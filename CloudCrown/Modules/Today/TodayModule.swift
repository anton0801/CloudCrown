//
//  TodayModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol TodayInteractorInput: AnyObject {
    func loadSnapshot(for place: Place, forceRefresh: Bool) async -> SnapshotLoadResult
    func nextGoodWindow(place: Place, snapshot: ConditionSnapshot) -> (window: WindowCandidate, activity: ActivityTemplate)?
    func assessRisks(snapshot: ConditionSnapshot, place: Place)
    var defaultPlace: Place? { get }
    var setupGaps: [SetupGap] { get }
}

/// Explicitly distinguishes fresh network data from a stored local snapshot.
enum SnapshotLoadResult {
    case fresh(ConditionSnapshot)
    case cached(ConditionSnapshot, reason: String)
    case unavailable(reason: String, isOffline: Bool)
}

// MARK: - Router

enum TodayRoute: Identifiable, Equatable {
    case conditions(placeID: UUID)
    case comfortProfile
    case activities
    case activityEditor
    case places
    case plan(UUID)
    case planRisk(UUID)
    case settings
    case alerts
    case explanation(WindowCandidate)

    var id: String {
        switch self {
        case .conditions(let id): return "conditions-\(id)"
        case .comfortProfile: return "profile"
        case .activities: return "activities"
        case .activityEditor: return "activity-editor"
        case .places: return "places"
        case .plan(let id): return "plan-\(id)"
        case .planRisk(let id): return "risk-\(id)"
        case .settings: return "settings"
        case .alerts: return "alerts"
        case .explanation(let w): return "explanation-\(w.id)"
        }
    }
}

@MainActor
final class TodayRouter: ObservableObject {
    @Published var route: TodayRoute?
    private let environment: AppEnvironment
    private let coordinator: AppCoordinator

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.environment = environment
        self.coordinator = coordinator
    }

    func go(_ route: TodayRoute) { self.route = route }

    func openFinder(activityID: UUID?, placeID: UUID?) {
        coordinator.openFinder(activityID: activityID, placeID: placeID)
    }

    @ViewBuilder
    func destination(for route: TodayRoute) -> some View {
        switch route {
        case .conditions(let placeID):
            ConditionDetailsModule.build(environment: environment, placeID: placeID)
        case .comfortProfile:
            ComfortProfileModule.build(environment: environment)
        case .activities:
            ActivityTemplatesModule.build(environment: environment, openEditorImmediately: false)
        case .activityEditor:
            ActivityTemplatesModule.build(environment: environment, openEditorImmediately: true)
        case .places:
            PlaceLibraryModule.build(environment: environment, coordinator: coordinator)
        case .plan(let id):
            PlanDetailModule.build(environment: environment, coordinator: coordinator, planID: id)
        case .planRisk(let id):
            PlanRiskModule.build(environment: environment, coordinator: coordinator, planID: id)
        case .settings:
            SettingsModule.build(environment: environment)
        case .alerts:
            AlertRulesModule.build(environment: environment)
        case .explanation(let window):
            WindowExplanationModule.build(environment: environment, coordinator: coordinator, window: window)
        }
    }
}

// MARK: - Builder

enum TodayModule {
    @MainActor
    static func build(environment: AppEnvironment, coordinator: AppCoordinator) -> some View {
        let interactor = TodayInteractor(repository: environment.repository, weather: environment.weather)
        let router = TodayRouter(environment: environment, coordinator: coordinator)
        let presenter = TodayPresenter(interactor: interactor, router: router, repository: environment.repository)
        return TodayView(presenter: presenter, router: router)
    }
}
