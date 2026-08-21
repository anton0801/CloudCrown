//
//  AlertRulesModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol AlertRulesInteractorInput: AnyObject {
    var rules: [AlertRule] { get }
    var events: [AlertEvent] { get }
    var places: [Place] { get }
    var activities: [ActivityTemplate] { get }
    var settings: AppSettings { get }
    var notificationAuthorization: NotificationAuthorization { get }
    func refreshNotificationAuthorization() async
    func requestNotificationAuthorization() async -> Bool
    func save(_ rule: AlertRule) -> SaveOutcome
    func setPaused(_ id: UUID, paused: Bool) -> SaveOutcome
    func delete(_ id: UUID) -> SaveOutcome
    /// Runs the rule against current data so the user can see what it would do.
    func testRun(_ rule: AlertRule) -> AlertEvaluator.Decision
    /// Runs the same automatic cycle that launch, foreground and background use.
    func runCheckNow() async -> RefreshReport
    var lastCheck: Date? { get }
    var lastReport: RefreshReport? { get }
    var backgroundStatus: BackgroundRefreshScheduler.Status { get }
    var isBackgroundRefreshEnabled: Bool { get }
    func saveDraft(_ rule: AlertRule)
    func loadDraft() -> AlertRule?
    func clearDraft()
    func hasDraft() -> Bool
}

// MARK: - Router

@MainActor
final class AlertRulesRouter: ObservableObject {
    @Published var editing: AlertRule?
    @Published var isCreating = false
    @Published var deletionTarget: AlertRule?
    @Published var showsDraftPrompt = false
    @Published var showsHistory = false
}

// MARK: - Builder

enum AlertRulesModule {
    @MainActor
    static func build(environment: AppEnvironment) -> some View {
        let interactor = AlertRulesInteractor(repository: environment.repository,
                                              notifications: environment.notifications,
                                              refreshCoordinator: environment.refreshCoordinator,
                                              backgroundScheduler: environment.backgroundScheduler)
        let router = AlertRulesRouter()
        let presenter = AlertRulesPresenter(interactor: interactor, router: router)
        return AlertRulesView(presenter: presenter, router: router)
    }
}
