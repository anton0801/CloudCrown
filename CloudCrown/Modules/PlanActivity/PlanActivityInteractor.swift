//
//  PlanActivityInteractor.swift
//  CloudCrown
//

import Foundation
import EventKit

@MainActor
final class PlanActivityInteractor: PlanActivityInteractorInput {

    private let repository: DataRepository
    private let notifications: NotificationService
    private let calendar: CalendarService
    private let draftKey = "plan-draft"

    init(repository: DataRepository, notifications: NotificationService, calendar: CalendarService) {
        self.repository = repository
        self.notifications = notifications
        self.calendar = calendar
    }

    var settings: AppSettings { repository.settings }
    var eventStore: EKEventStore { calendar.store }
    var notificationAuthorization: NotificationAuthorization { notifications.authorization }

    func activity(id: UUID) -> ActivityTemplate? { repository.activity(id: id) }
    func place(id: UUID) -> Place? { repository.place(id: id) }

    func existingPlan(activityID: UUID, placeID: UUID, start: Date) -> Plan? {
        repository.duplicatePlan(activityID: activityID, placeID: placeID, start: start)
    }

    /// Other usable windows on the same day, offered as a backup.
    func backupCandidates(for window: WindowCandidate) -> [WindowCandidate] {
        guard let activity = repository.activity(id: window.activityID),
              let place = repository.place(id: window.placeID),
              let snapshot = repository.snapshot(for: window.placeID) else { return [] }

        let day = window.start.startOfDay(in: snapshot.timeZone)
        let query = WindowQuery(activityID: activity.id,
                                placeID: place.id,
                                startDate: day,
                                endDate: day.adding(days: 1, in: snapshot.timeZone),
                                earliestMinute: activity.earliestMinute,
                                latestMinute: activity.latestMinute,
                                durationMinutes: window.durationMinutes)

        let result = WindowEngine.findWindows(query: query,
                                              activity: activity,
                                              profile: repository.profile,
                                              place: place,
                                              snapshot: snapshot,
                                              usedCachedSnapshot: false,
                                              limit: 12)
        return Array(result.candidates
            .filter { $0.verdict.isUsable && abs($0.start.timeIntervalSince(window.start)) > 1800 }
            .prefix(6))
    }

    func save(_ plan: Plan) -> SaveOutcome {
        let outcome = repository.savePlan(plan)
        if outcome.isSuccess { clearDraft() }
        return outcome
    }

    func syncReminder(plan: Plan, placeName: String) async -> String? {
        await notifications.syncReminder(for: plan, placeName: placeName)
    }

    func requestNotificationAuthorization() async -> Bool { await notifications.requestAuthorization() }
    func refreshNotificationAuthorization() async { await notifications.refreshAuthorization() }

    func requestCalendarAccess() async -> Bool { await calendar.requestAccess() }

    func makeCalendarEvent(plan: Plan, placeName: String) -> EKEvent {
        let notes = [
            plan.preparationNotes,
            "Window \(plan.window.timeRangeText()) · score \(plan.window.score.map { String(Int($0.rounded())) } ?? "unavailable")",
            "Planned with CloudCrown from a forecast captured \(SkyFormat.fullDateTime(plan.window.snapshotCapturedAt, timeZone: plan.window.timeZone))."
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")

        return calendar.makeEvent(title: plan.title,
                                  notes: notes,
                                  start: plan.window.start,
                                  end: plan.window.end,
                                  timeZone: plan.window.timeZone,
                                  location: placeName)
    }

    func saveDraft(_ plan: Plan) { repository.saveDraft(plan, key: draftKey) }
    func loadDraft() -> Plan? { repository.loadDraft(Plan.self, key: draftKey) }
    func clearDraft() { repository.clearDraft(key: draftKey) }
}
