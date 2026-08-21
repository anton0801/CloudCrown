//
//  WindowExplanationModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol WindowExplanationInteractorInput: AnyObject {
    var settings: AppSettings { get }
    func activity(id: UUID) -> ActivityTemplate?
    func place(id: UUID) -> Place?
    func currentSnapshot(for placeID: UUID) -> ConditionSnapshot?
    /// Re-runs the same rules against the newest snapshot so a Superseded
    /// explanation can be compared with the current one side by side.
    func reevaluate(_ window: WindowCandidate) -> WindowCandidate?
    func alternatives(for window: WindowCandidate, count: Int) -> [WindowCandidate]
    func existingPlan(activityID: UUID, placeID: UUID, start: Date) -> Plan?
}

// MARK: - Router

enum WindowExplanationRoute: Identifiable, Equatable {
    case planActivity(WindowCandidate)
    case conditions(UUID)
    case comparison(activityID: UUID, placeID: UUID)

    var id: String {
        switch self {
        case .planActivity(let w): return "plan-\(w.id)"
        case .conditions(let id): return "conditions-\(id)"
        case .comparison(let a, let p): return "compare-\(a)-\(p)"
        }
    }
}

@MainActor
final class WindowExplanationRouter: ObservableObject {
    @Published var route: WindowExplanationRoute?

    private let environment: AppEnvironment
    private let coordinator: AppCoordinator

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.environment = environment
        self.coordinator = coordinator
    }

    @ViewBuilder
    func destination(for route: WindowExplanationRoute) -> some View {
        switch route {
        case .planActivity(let window):
            PlanActivityModule.build(environment: environment, coordinator: coordinator, window: window)
        case .conditions(let placeID):
            ConditionDetailsModule.build(environment: environment, placeID: placeID)
        case .comparison(let activityID, let placeID):
            DayComparisonModule.build(environment: environment, coordinator: coordinator,
                                      activityID: activityID, placeID: placeID)
        }
    }
}

// MARK: - Builder

enum WindowExplanationModule {
    @MainActor
    static func build(environment: AppEnvironment,
                      coordinator: AppCoordinator,
                      window: WindowCandidate) -> some View {
        let interactor = WindowExplanationInteractor(repository: environment.repository)
        let router = WindowExplanationRouter(environment: environment, coordinator: coordinator)
        let presenter = WindowExplanationPresenter(interactor: interactor, router: router, window: window)
        return WindowExplanationView(presenter: presenter, router: router)
    }
}
