//
//  WindowExplanationInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class WindowExplanationInteractor: WindowExplanationInteractorInput {

    private let repository: DataRepository

    init(repository: DataRepository) {
        self.repository = repository
    }

    var settings: AppSettings { repository.settings }

    func activity(id: UUID) -> ActivityTemplate? { repository.activity(id: id) }
    func place(id: UUID) -> Place? { repository.place(id: id) }
    func currentSnapshot(for placeID: UUID) -> ConditionSnapshot? { repository.snapshot(for: placeID) }

    func reevaluate(_ window: WindowCandidate) -> WindowCandidate? {
        guard let activity = repository.activity(id: window.activityID),
              let place = repository.place(id: window.placeID),
              let snapshot = repository.snapshot(for: window.placeID),
              snapshot.id != window.snapshotID else { return nil }
        return WindowEngine.reevaluate(window: window,
                                       activity: activity,
                                       profile: repository.profile,
                                       place: place,
                                       snapshot: snapshot)
    }

    /// Nearby alternatives on the same day, for the trade-off comparison.
    func alternatives(for window: WindowCandidate, count: Int) -> [WindowCandidate] {
        guard let activity = repository.activity(id: window.activityID),
              let place = repository.place(id: window.placeID),
              let snapshot = repository.snapshot(for: window.placeID) else { return [] }

        let day = window.start.startOfDay(in: snapshot.timeZone)
        let query = WindowQuery(activityID: activity.id,
                                placeID: place.id,
                                startDate: day,
                                endDate: day,
                                earliestMinute: activity.earliestMinute,
                                latestMinute: activity.latestMinute,
                                durationMinutes: window.durationMinutes)

        let result = WindowEngine.findWindows(query: query,
                                              activity: activity,
                                              profile: repository.profile,
                                              place: place,
                                              snapshot: snapshot,
                                              usedCachedSnapshot: false,
                                              limit: 20)
        return Array(result.candidates
            .filter { abs($0.start.timeIntervalSince(window.start)) > 60 }
            .sorted { ($0.score ?? -1) > ($1.score ?? -1) }
            .prefix(count))
    }

    func existingPlan(activityID: UUID, placeID: UUID, start: Date) -> Plan? {
        repository.duplicatePlan(activityID: activityID, placeID: placeID, start: start)
    }
}
