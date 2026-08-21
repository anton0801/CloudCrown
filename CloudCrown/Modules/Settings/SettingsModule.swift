//
//  SettingsModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol SettingsInteractorInput: AnyObject {
    var settings: AppSettings { get }
    var sources: [DataSource] { get }
    var counts: SettingsCounts { get }
    var locationAuthorization: LocationAuthorization { get }
    var notificationAuthorization: NotificationAuthorization { get }
    var calendarSummary: String { get }
    func refreshAuthorizations() async
    func requestNotificationAuthorization() async -> Bool
    func update(_ transform: (inout AppSettings) -> Void) -> SaveOutcome
    func runManualCheck() async -> RefreshReport
    var backgroundStatus: BackgroundRefreshScheduler.Status { get }
    var lastRefreshReport: RefreshReport? { get }
    var lastRefreshCheck: Date? { get }
    func exportData() throws -> Data
    func eraseAll()
    func cancelAllNotifications()
}

struct SettingsCounts {
    let places: Int
    let activities: Int
    let plans: Int
    let alerts: Int
    let feedback: Int
    let historyRecords: Int
    let snapshots: Int
}

// MARK: - Router

enum SettingsRoute: Identifiable, Equatable {
    case comfortProfile, activities, places, alerts

    var id: String {
        switch self {
        case .comfortProfile: return "profile"
        case .activities: return "activities"
        case .places: return "places"
        case .alerts: return "alerts"
        }
    }
}

@MainActor
final class SettingsRouter: ObservableObject {
    @Published var route: SettingsRoute?
    @Published var showsEraseConfirmation = false
    @Published var showsExportSheet = false
    @Published var exportURL: URL?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) { self.environment = environment }

    @ViewBuilder
    func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .comfortProfile:
            ComfortProfileModule.build(environment: environment)
        case .activities:
            ActivityTemplatesModule.build(environment: environment, openEditorImmediately: false)
        case .places:
            PlaceLibraryModule.build(environment: environment, coordinator: AppCoordinator())
        case .alerts:
            AlertRulesModule.build(environment: environment)
        }
    }
}

// MARK: - Builder

enum SettingsModule {
    @MainActor
    static func build(environment: AppEnvironment) -> some View {
        let interactor = SettingsInteractor(repository: environment.repository,
                                            location: environment.location,
                                            notifications: environment.notifications,
                                            calendar: environment.calendar,
                                            refreshCoordinator: environment.refreshCoordinator,
                                            backgroundScheduler: environment.backgroundScheduler)
        let router = SettingsRouter(environment: environment)
        let presenter = SettingsPresenter(interactor: interactor, router: router)
        return SettingsView(presenter: presenter, router: router)
    }
}
