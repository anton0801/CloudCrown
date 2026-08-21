//
//  PlanRiskModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol PlanRiskInteractorInput: AnyObject {
    var settings: AppSettings { get }
    func plan(id: UUID) -> Plan?
    func activity(id: UUID) -> ActivityTemplate?
    func place(id: UUID) -> Place?
    func snapshot(for placeID: UUID) -> ConditionSnapshot?
    func refresh(place: Place) async -> SnapshotLoadResult
    func assess(plan: Plan, snapshot: ConditionSnapshot) -> RiskEngine.Assessment?
    func alternatives(for plan: Plan, snapshot: ConditionSnapshot) -> [WindowCandidate]
    func resolve(planID: UUID, eventID: UUID, resolution: RiskResolution, newWindow: WindowCandidate?) -> SaveOutcome
    func recordRisk(_ event: RiskEvent, planID: UUID)
    /// Reschedules the plan's reminder after its window moved.
    func syncReminder(planID: UUID) async
}

// MARK: - Router

enum PlanRiskRoute: Identifiable, Equatable {
    case explanation(WindowCandidate)
    var id: String { switch self { case .explanation(let w): return "explain-\(w.id)" } }
}

@MainActor
final class PlanRiskRouter: ObservableObject {
    @Published var route: PlanRiskRoute?
    @Published var showsAlternatives = false
    @Published var pendingConfirmation: PendingResolution?

    struct PendingResolution: Identifiable, Equatable {
        let id = UUID()
        let resolution: RiskResolution
        let window: WindowCandidate?
        let title: String
        let message: String
    }

    private let environment: AppEnvironment
    private let coordinator: AppCoordinator

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.environment = environment
        self.coordinator = coordinator
    }

    @ViewBuilder
    func destination(for route: PlanRiskRoute) -> some View {
        switch route {
        case .explanation(let window):
            WindowExplanationModule.build(environment: environment, coordinator: coordinator, window: window)
        }
    }
}

// MARK: - Builder

enum PlanRiskModule {
    @MainActor
    static func build(environment: AppEnvironment, coordinator: AppCoordinator, planID: UUID) -> some View {
        let interactor = PlanRiskInteractor(repository: environment.repository,
                                            weather: environment.weather,
                                            notifications: environment.notifications)
        let router = PlanRiskRouter(environment: environment, coordinator: coordinator)
        let presenter = PlanRiskPresenter(interactor: interactor, router: router, planID: planID)
        return PlanRiskView(presenter: presenter, router: router)
    }
}
