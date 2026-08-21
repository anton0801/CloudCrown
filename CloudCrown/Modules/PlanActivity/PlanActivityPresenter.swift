//
//  PlanActivityPresenter.swift
//  CloudCrown
//

import SwiftUI
import EventKit

@MainActor
final class PlanActivityPresenter: ObservableObject {

    @Published var title: String = ""
    @Published var notes: String = ""
    @Published var reminderMinutes: Int? = 60
    @Published private(set) var backupWindow: WindowCandidate?
    @Published private(set) var backupOptions: [WindowCandidate] = []
    @Published private(set) var isSaving = false
    @Published var saveError: String?
    @Published private(set) var savedPlan: Plan?
    @Published private(set) var reminderStatusMessage: String?
    @Published private(set) var calendarStatusMessage: String?
    @Published private(set) var calendarIsConfirmed = false
    @Published var toast: ToastPayload?
    @Published private(set) var duplicatePlan: Plan?

    let window: WindowCandidate

    private let interactor: PlanActivityInteractorInput
    private let router: PlanActivityRouter
    private let coordinator: AppCoordinator
    private var didAppear = false

    init(interactor: PlanActivityInteractorInput,
         router: PlanActivityRouter,
         coordinator: AppCoordinator,
         window: WindowCandidate) {
        self.interactor = interactor
        self.router = router
        self.coordinator = coordinator
        self.window = window
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var activity: ActivityTemplate? { interactor.activity(id: window.activityID) }
    var place: Place? { interactor.place(id: window.placeID) }
    var placeName: String { place?.name ?? "Unknown place" }

    var isUpdatingExisting: Bool { duplicatePlan != nil }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var reminderOptions: [Int] { [15, 30, 60, 120, 180] }

    var notificationAuthorization: NotificationAuthorization { interactor.notificationAuthorization }

    var reminderFireTime: Date? {
        guard let minutes = reminderMinutes else { return nil }
        return window.start.addingTimeInterval(TimeInterval(-minutes * 60))
    }

    var reminderIsInPast: Bool {
        guard let fireAt = reminderFireTime else { return false }
        return fireAt <= Date()
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !didAppear else { return }
        didAppear = true
        duplicatePlan = interactor.existingPlan(activityID: window.activityID,
                                                placeID: window.placeID,
                                                start: window.start)
        if let existing = duplicatePlan {
            title = existing.title
            notes = existing.preparationNotes
            reminderMinutes = existing.reminderMinutesBefore
            backupWindow = existing.backupWindow
            calendarIsConfirmed = existing.isCalendarConfirmed
            savedPlan = existing
        } else {
            title = activity.map { "\($0.name) · \(window.dayText())" } ?? "Planned activity"
        }
        backupOptions = interactor.backupCandidates(for: window)
        Task { await interactor.refreshNotificationAuthorization() }
    }

    // MARK: - Backup

    func openBackupPicker() { router.showsBackupPicker = true }

    func selectBackup(_ candidate: WindowCandidate) {
        backupWindow = candidate
        router.showsBackupPicker = false
        toast = ToastPayload(title: "Backup window set",
                             changes: ["\(candidate.dayText()) \(candidate.timeRangeText())",
                                       "Offered first if this plan comes under risk"])
    }

    func clearBackup() { backupWindow = nil }

    // MARK: - Save

    func save() {
        guard canSave else { return }
        isSaving = true
        saveError = nil

        var plan = duplicatePlan ?? Plan(
            title: title,
            activityID: window.activityID,
            placeID: window.placeID,
            window: window
        )
        plan.title = title.trimmingCharacters(in: .whitespaces)
        plan.window = window
        plan.backupWindow = backupWindow
        plan.preparationNotes = notes
        plan.reminderMinutesBefore = reminderMinutes
        plan.status = .scheduled

        Task { [weak self] in
            guard let self = self else { return }

            if self.reminderMinutes != nil {
                if self.interactor.notificationAuthorization == .notDetermined {
                    _ = await self.interactor.requestNotificationAuthorization()
                }
                await self.interactor.refreshNotificationAuthorization()
            }

            // Reconcile the system reminder against the plan being saved: the
            // previous request is always cancelled, and a new one is only
            // claimed when iOS accepted it.
            let identifier = await self.interactor.syncReminder(plan: plan, placeName: self.placeName)
            plan.reminderNotificationID = identifier

            if self.reminderMinutes == nil {
                self.reminderStatusMessage = nil
            } else if self.reminderIsInPast {
                self.reminderStatusMessage = "That reminder time has already passed, so no notification was scheduled."
            } else if identifier == nil {
                self.reminderStatusMessage = "iOS did not schedule a reminder. \(self.interactor.notificationAuthorization.explanation)"
            } else {
                self.reminderStatusMessage = nil
            }

            let outcome = self.interactor.save(plan)
            self.isSaving = false

            switch outcome {
            case .failure(let message):
                // The plan was not stored, so its reminder must not survive either.
                var rollback = plan
                rollback.reminderMinutesBefore = nil
                _ = await self.interactor.syncReminder(plan: rollback, placeName: self.placeName)
                self.saveError = message
            case .success(let changes):
                self.saveError = nil
                self.savedPlan = plan
                self.duplicatePlan = plan
                self.toast = ToastPayload(
                    title: self.isUpdatingExisting ? "Plan updated" : "Plan saved",
                    changes: Array(changes.prefix(4))
                )
            }
        }
    }

    func dismissSaveError() { saveError = nil }

    // MARK: - Calendar

    func addToCalendar() {
        guard savedPlan != nil else {
            calendarStatusMessage = "Save the plan first — CloudCrown only offers the calendar for a stored plan."
            return
        }
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await self.interactor.requestCalendarAccess()
            if granted {
                self.calendarStatusMessage = nil
                self.router.showsCalendarEditor = true
            } else {
                self.calendarStatusMessage = "Calendar access was not granted, so the system event editor cannot open. The plan itself is unaffected."
            }
        }
    }

    func makeCalendarEvent() -> EKEvent? {
        guard let plan = savedPlan else { return nil }
        return interactor.makeCalendarEvent(plan: plan, placeName: placeName)
    }

    var eventStore: EKEventStore { interactor.eventStore }

    /// Records the calendar link only when iOS actually confirmed the save.
    func handleCalendarOutcome(_ outcome: CalendarOutcome) {
        router.showsCalendarEditor = false
        guard var plan = savedPlan else { return }

        switch outcome {
        case .saved(let identifier, let date):
            plan.calendarEventIdentifier = identifier
            plan.calendarConfirmedAt = date
            if case .failure(let message) = interactor.save(plan) {
                // iOS created the event but CloudCrown could not store the link.
                calendarStatusMessage = "The calendar event was created, but the link could not be saved to the plan: \(message)"
                saveError = message
                return
            }
            savedPlan = plan
            duplicatePlan = plan
            calendarIsConfirmed = true
            calendarStatusMessage = nil
            toast = ToastPayload(title: "Added to calendar",
                                 changes: ["Confirmed by iOS at \(SkyFormat.clock(date, timeZone: .current))",
                                           "Event ID stored with the plan"])
        case .cancelled:
            calendarStatusMessage = "You closed the calendar editor without saving, so no event was created."
        case .deleted:
            plan.calendarEventIdentifier = nil
            plan.calendarConfirmedAt = nil
            if case .failure(let message) = interactor.save(plan) {
                saveError = message
                return
            }
            savedPlan = plan
            calendarIsConfirmed = false
            calendarStatusMessage = "The calendar event was deleted. The plan itself is unchanged."
        case .denied:
            calendarStatusMessage = "Calendar access is not granted."
        case .failed(let reason):
            calendarStatusMessage = reason
        }
    }

    // MARK: - Cancel

    func cancel() {
        if savedPlan == nil, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            var draft = Plan(title: title, activityID: window.activityID, placeID: window.placeID, window: window)
            draft.preparationNotes = notes
            draft.reminderMinutesBefore = reminderMinutes
            draft.backupWindow = backupWindow
            interactor.saveDraft(draft)
            toast = ToastPayload(title: "Draft kept",
                                 changes: ["No plan was created", "Your notes were stored on this device"])
        }
        router.didFinish = true
    }

    func openPlans() {
        guard let plan = savedPlan else { return }
        coordinator.openPlan(plan.id)
    }
}
