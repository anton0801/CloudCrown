//
//  AlertRulesInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class AlertRulesInteractor: AlertRulesInteractorInput {

    private let repository: DataRepository
    private let notifications: NotificationService
    private let refreshCoordinator: RefreshCoordinator
    private let backgroundScheduler: BackgroundRefreshScheduler
    private let draftKey = "alert-rule-draft"

    init(repository: DataRepository,
         notifications: NotificationService,
         refreshCoordinator: RefreshCoordinator,
         backgroundScheduler: BackgroundRefreshScheduler) {
        self.repository = repository
        self.notifications = notifications
        self.refreshCoordinator = refreshCoordinator
        self.backgroundScheduler = backgroundScheduler
    }

    func runCheckNow() async -> RefreshReport {
        await refreshCoordinator.run(trigger: .manual)
    }

    var lastCheck: Date? { repository.settings.lastRefreshCheck }
    var lastReport: RefreshReport? { refreshCoordinator.lastReport }
    var backgroundStatus: BackgroundRefreshScheduler.Status { backgroundScheduler.status }
    var isBackgroundRefreshEnabled: Bool { repository.settings.backgroundRefreshEnabled }

    var rules: [AlertRule] { repository.alerts }
    var events: [AlertEvent] { repository.alertEvents }
    var places: [Place] { repository.activePlaces }
    var activities: [ActivityTemplate] { repository.activeActivities }
    var settings: AppSettings { repository.settings }
    var notificationAuthorization: NotificationAuthorization { notifications.authorization }

    func refreshNotificationAuthorization() async { await notifications.refreshAuthorization() }
    func requestNotificationAuthorization() async -> Bool { await notifications.requestAuthorization() }

    func save(_ rule: AlertRule) -> SaveOutcome {
        let outcome = repository.saveAlert(rule)
        if outcome.isSuccess { clearDraft() }
        return outcome
    }

    func setPaused(_ id: UUID, paused: Bool) -> SaveOutcome { repository.setAlertPaused(id, paused: paused) }
    func delete(_ id: UUID) -> SaveOutcome { repository.deleteAlert(id) }

    /// Evaluates the rule now, applying cooldown, quiet hours and deduplication,
    /// so the user can see exactly what would happen — and why it might not.
    func testRun(_ rule: AlertRule) -> AlertEvaluator.Decision {
        guard let place = repository.place(id: rule.placeID),
              let snapshot = repository.snapshot(for: rule.placeID) else {
            return .noMatch
        }
        return AlertEvaluator.evaluate(
            rule: rule,
            activity: repository.activity(id: rule.activityID),
            profile: repository.profile,
            place: place,
            snapshot: snapshot,
            plans: repository.plans
        )
    }

    func saveDraft(_ rule: AlertRule) { repository.saveDraft(rule, key: draftKey) }
    func loadDraft() -> AlertRule? { repository.loadDraft(AlertRule.self, key: draftKey) }
    func clearDraft() { repository.clearDraft(key: draftKey) }
    func hasDraft() -> Bool { repository.hasDraft(key: draftKey) }
}
