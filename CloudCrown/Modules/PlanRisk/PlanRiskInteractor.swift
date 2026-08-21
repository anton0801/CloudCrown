//
//  PlanRiskInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class PlanRiskInteractor: PlanRiskInteractorInput {

    private let repository: DataRepository
    private let weather: WeatherFetching
    private let notifications: NotificationService

    init(repository: DataRepository, weather: WeatherFetching, notifications: NotificationService) {
        self.repository = repository
        self.weather = weather
        self.notifications = notifications
    }

    var settings: AppSettings { repository.settings }

    func plan(id: UUID) -> Plan? { repository.plan(id: id) }
    func activity(id: UUID) -> ActivityTemplate? { repository.activity(id: id) }
    func place(id: UUID) -> Place? { repository.place(id: id) }
    func snapshot(for placeID: UUID) -> ConditionSnapshot? { repository.snapshot(for: placeID) }

    func refresh(place: Place) async -> SnapshotLoadResult {
        do {
            let snapshot = try await weather.fetchSnapshot(for: place,
                                                           precision: repository.settings.locationPrecision,
                                                           forecastDays: 7)
            repository.storeSnapshot(snapshot)
            return .fresh(snapshot)
        } catch {
            let isOffline = (error as? WeatherServiceError)?.isOffline ?? false
            if let cached = repository.snapshot(for: place.id) {
                return .cached(cached, reason: error.localizedDescription)
            }
            return .unavailable(reason: error.localizedDescription, isOffline: isOffline)
        }
    }

    func assess(plan: Plan, snapshot: ConditionSnapshot) -> RiskEngine.Assessment? {
        guard let activity = repository.activity(id: plan.activityID),
              let place = repository.place(id: plan.placeID) else { return nil }
        return RiskEngine.assess(plan: plan,
                                 activity: activity,
                                 profile: repository.profile,
                                 place: place,
                                 snapshot: snapshot)
    }

    /// Replacement windows evaluated against the newest snapshot.
    func alternatives(for plan: Plan, snapshot: ConditionSnapshot) -> [WindowCandidate] {
        guard let activity = repository.activity(id: plan.activityID),
              let place = repository.place(id: plan.placeID) else { return [] }

        let start = max(Date(), plan.window.start.startOfDay(in: snapshot.timeZone))
        let query = WindowQuery(activityID: activity.id,
                                placeID: place.id,
                                startDate: start,
                                endDate: plan.window.start.adding(days: 2, in: snapshot.timeZone),
                                earliestMinute: activity.earliestMinute,
                                latestMinute: activity.latestMinute,
                                durationMinutes: plan.window.durationMinutes)

        let result = WindowEngine.findWindows(query: query,
                                              activity: activity,
                                              profile: repository.profile,
                                              place: place,
                                              snapshot: snapshot,
                                              usedCachedSnapshot: false,
                                              limit: 12)
        return Array((result.best + result.acceptable)
            .filter { abs($0.start.timeIntervalSince(plan.window.start)) > 1800 }
            .prefix(6))
    }

    func resolve(planID: UUID, eventID: UUID, resolution: RiskResolution,
                 newWindow: WindowCandidate?) -> SaveOutcome {
        repository.resolveRisk(planID: planID, eventID: eventID, resolution: resolution, newWindow: newWindow)
    }

    /// Moving a plan invalidates the reminder scheduled for the old start time.
    func syncReminder(planID: UUID) async {
        guard let plan = repository.plan(id: planID) else { return }
        let placeName = repository.place(id: plan.placeID)?.name ?? "your place"
        let identifier = await notifications.syncReminder(for: plan, placeName: placeName)
        if identifier != plan.reminderNotificationID {
            _ = repository.updatePlan(planID) { $0.reminderNotificationID = identifier }
        }
    }

    func recordRisk(_ event: RiskEvent, planID: UUID) {
        repository.addRiskEvent(event, to: planID)
    }
}
