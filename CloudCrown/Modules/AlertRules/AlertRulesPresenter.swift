//
//  AlertRulesPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class AlertRulesPresenter: ObservableObject {

    @Published var editorDraft: AlertRule?
    @Published private(set) var isSaving = false
    @Published var saveError: String?
    @Published private(set) var isCheckingNow = false
    @Published private(set) var testResultMessage: String?
    @Published private(set) var testResultIsPositive = false
    @Published var toast: ToastPayload?

    private let interactor: AlertRulesInteractorInput
    private let router: AlertRulesRouter
    private var didAppear = false

    init(interactor: AlertRulesInteractorInput, router: AlertRulesRouter) {
        self.interactor = interactor
        self.router = router
    }

    // MARK: - Derived

    var rules: [AlertRule] { interactor.rules }
    var events: [AlertEvent] { interactor.events }
    var places: [Place] { interactor.places }
    var activities: [ActivityTemplate] { interactor.activities }
    var settings: AppSettings { interactor.settings }
    var notificationAuthorization: NotificationAuthorization { interactor.notificationAuthorization }
    var isEmpty: Bool { interactor.rules.isEmpty }
    var canCreate: Bool { !interactor.places.isEmpty }

    var draftValidationMessages: [String] {
        editorDraft?.validationErrors ?? []
    }

    var canSaveDraft: Bool {
        guard let draft = editorDraft else { return false }
        return draft.isValid && !isSaving
    }

    func placeName(_ id: UUID) -> String {
        interactor.places.first(where: { $0.id == id })?.name ?? "Removed place"
    }

    func activityName(_ id: UUID?) -> String? {
        guard let id = id else { return nil }
        return interactor.activities.first(where: { $0.id == id })?.name
    }

    // MARK: - Lifecycle

    func onAppear() {
        Task { await interactor.refreshNotificationAuthorization() }
        guard !didAppear else { return }
        didAppear = true
        if interactor.hasDraft() { router.showsDraftPrompt = true }
    }

    func restoreDraft() {
        if let draft = interactor.loadDraft() {
            editorDraft = draft
            router.isCreating = true
        }
        router.showsDraftPrompt = false
    }

    func discardDraft() {
        interactor.clearDraft()
        router.showsDraftPrompt = false
    }

    // MARK: - Automatic checking

    var lastCheck: Date? { interactor.lastCheck }
    var lastReport: RefreshReport? { interactor.lastReport }
    var backgroundStatus: BackgroundRefreshScheduler.Status { interactor.backgroundStatus }
    var isBackgroundRefreshEnabled: Bool { interactor.isBackgroundRefreshEnabled }

    var automaticCheckSummary: String {
        var lines = ["Rules are checked every time you open CloudCrown."]
        if isBackgroundRefreshEnabled {
            lines.append(backgroundStatus.summary)
        } else {
            lines.append("Background Refresh is off, so nothing is checked while the app is closed.")
        }
        return lines.joined(separator: " ")
    }

    /// Runs the real cycle — the same one launch, foreground and the background
    /// task use — so the user can confirm delivery rather than only simulate it.
    func runCheckNow() {
        guard !isCheckingNow else { return }
        isCheckingNow = true
        Task { [weak self] in
            guard let self = self else { return }
            let report = await self.interactor.runCheckNow()
            self.isCheckingNow = false
            self.toast = ToastPayload(title: "Rules checked", changes: [report.summary])
        }
    }

    func requestNotificationPermission() {
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await self.interactor.requestNotificationAuthorization()
            self.toast = ToastPayload(
                title: granted ? "Notifications enabled" : "Notifications not enabled",
                changes: granted
                    ? ["Alert rules can now reach you"]
                    : ["Rules still evaluate, but nothing will be delivered"]
            )
        }
    }

    // MARK: - Editing

    func startCreating() {
        guard let place = interactor.places.first(where: { $0.isDefault }) ?? interactor.places.first else { return }
        editorDraft = AlertRule(
            name: "",
            kind: .windowAppears,
            placeID: place.id,
            activityID: interactor.activities.first?.id
        )
        testResultMessage = nil
        router.isCreating = true
    }

    func startEditing(_ rule: AlertRule) {
        editorDraft = rule
        testResultMessage = nil
        router.editing = rule
    }

    func changeKind(_ kind: AlertKind) {
        guard var draft = editorDraft else { return }
        draft.kind = kind
        switch kind {
        case .metricThreshold:
            if draft.metric == nil { draft.metric = .uvIndex }
            if draft.threshold == nil { draft.threshold = 6 }
        case .windowAppears:
            if draft.activityID == nil { draft.activityID = interactor.activities.first?.id }
        case .planDegrades:
            break
        }
        editorDraft = draft
    }

    func save() {
        guard var draft = editorDraft, draft.isValid, !isSaving else { return }
        isSaving = true
        saveError = nil
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        let outcome = interactor.save(draft)
        isSaving = false

        switch outcome {
        case .failure(let message):
            editorDraft = draft
            saveError = message
        case .success(let changes):
            editorDraft = nil
            router.isCreating = false
            router.editing = nil
            toast = ToastPayload(title: "“\(draft.name)” saved", changes: Array(changes.prefix(3)))
        }
    }

    func dismissSaveError() { saveError = nil }

    func cancelEditing() {
        if let draft = editorDraft, !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            interactor.saveDraft(draft)
            toast = ToastPayload(title: "Draft kept", changes: ["No rule was created"])
        }
        editorDraft = nil
        router.isCreating = false
        router.editing = nil
    }

    /// Shows what the rule would do right now, including suppression reasons.
    func testRun() {
        guard let draft = editorDraft, draft.isValid else { return }
        switch interactor.testRun(draft) {
        case .deliver(let candidate):
            testResultIsPositive = true
            testResultMessage = "Would notify now: “\(candidate.title) — \(candidate.body)”"
        case .suppress(let candidate, let reason):
            testResultIsPositive = false
            testResultMessage = "Matched (“\(candidate.title)”) but would be held back: \(reason)"
        case .noMatch:
            testResultIsPositive = false
            testResultMessage = "Nothing matches right now. Either the condition is not met in the chosen period, or no conditions are stored for this place yet."
        }
    }

    // MARK: - Actions

    func togglePause(_ rule: AlertRule) {
        switch interactor.setPaused(rule.id, paused: !rule.isPaused) {
        case .failure(let message): saveError = message
        case .success:
            toast = ToastPayload(title: rule.isPaused ? "“\(rule.name)” resumed" : "“\(rule.name)” paused")
        }
    }

    func requestDelete(_ rule: AlertRule) { router.deletionTarget = rule }

    func confirmDelete() {
        guard let rule = router.deletionTarget else { return }
        let outcome = interactor.delete(rule.id)
        router.deletionTarget = nil
        switch outcome {
        case .failure(let message): saveError = message
        case .success:
            toast = ToastPayload(title: "“\(rule.name)” deleted",
                                 changes: ["No further notifications will be scheduled for it"])
        }
    }
}
