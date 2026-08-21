//
//  TodayInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class TodayInteractor: TodayInteractorInput {

    private let repository: DataRepository
    private let weather: WeatherFetching

    init(repository: DataRepository, weather: WeatherFetching) {
        self.repository = repository
        self.weather = weather
    }

    var defaultPlace: Place? { repository.defaultPlace }
    var setupGaps: [SetupGap] { repository.setupGaps }

    /// Never silently substitutes a stale snapshot for a fresh one — the caller
    /// is told exactly which it received.
    func loadSnapshot(for place: Place, forceRefresh: Bool) async -> SnapshotLoadResult {
        let existing = repository.snapshot(for: place.id)

        if !forceRefresh, let existing = existing, !existing.isStale {
            return .fresh(existing)
        }

        do {
            let snapshot = try await weather.fetchSnapshot(
                for: place,
                precision: repository.settings.locationPrecision,
                forecastDays: 7
            )
            repository.storeSnapshot(snapshot)
            return .fresh(snapshot)
        } catch {
            let isOffline = (error as? WeatherServiceError)?.isOffline ?? false
            if let existing = existing {
                return .cached(existing, reason: error.localizedDescription)
            }
            return .unavailable(reason: error.localizedDescription, isOffline: isOffline)
        }
    }

    /// The soonest usable window across all active activities.
    func nextGoodWindow(place: Place, snapshot: ConditionSnapshot) -> (window: WindowCandidate, activity: ActivityTemplate)? {
        let profile = repository.profile
        guard profile?.isUsable == true else { return nil }

        var best: (WindowCandidate, ActivityTemplate)?

        for activity in repository.activeActivities {
            let query = WindowQuery(
                activityID: activity.id,
                placeID: place.id,
                startDate: Date(),
                endDate: Date().adding(days: 2, in: snapshot.timeZone),
                earliestMinute: activity.earliestMinute,
                latestMinute: activity.latestMinute,
                durationMinutes: activity.durationMinutes
            )
            let result = WindowEngine.findWindows(query: query,
                                                  activity: activity,
                                                  profile: profile,
                                                  place: place,
                                                  snapshot: snapshot,
                                                  usedCachedSnapshot: snapshot.isStale,
                                                  limit: 8)
            guard let candidate = (result.best + result.acceptable).min(by: { $0.start < $1.start }) else { continue }
            if let current = best {
                if candidate.start < current.0.start { best = (candidate, activity) }
            } else {
                best = (candidate, activity)
            }
        }
        return best
    }

    /// Compares the newest snapshot with the one each plan was saved from.
    func assessRisks(snapshot: ConditionSnapshot, place: Place) {
        let profile = repository.profile
        for plan in repository.upcomingPlans where plan.placeID == place.id {
            guard let activity = repository.activity(id: plan.activityID) else { continue }
            guard let assessment = RiskEngine.assess(plan: plan,
                                                     activity: activity,
                                                     profile: profile,
                                                     place: place,
                                                     snapshot: snapshot) else { continue }
            guard assessment.isMaterial else { continue }
            repository.addRiskEvent(RiskEngine.makeEvent(from: assessment, snapshot: snapshot), to: plan.id)
        }
    }
}
