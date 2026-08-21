//
//  PlanDetailModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol PlanDetailInteractorInput: AnyObject {
    var settings: AppSettings { get }
    func plan(id: UUID) -> Plan?
    func activity(id: UUID) -> ActivityTemplate?
    func place(id: UUID) -> Place?
    func feedback(forPlan id: UUID) -> FeedbackEntry?
    func history(for id: UUID) -> [HistoryRecord]
    func setStatus(_ id: UUID, _ status: PlanStatus) -> SaveOutcome
}

// MARK: - Router

enum PlanDetailRoute: Identifiable, Equatable {
    case explanation(WindowCandidate)
    case risk(UUID)
    case feedback(UUID)
    case conditions(UUID)

    var id: String {
        switch self {
        case .explanation(let w): return "explain-\(w.id)"
        case .risk(let id): return "risk-\(id)"
        case .feedback(let id): return "feedback-\(id)"
        case .conditions(let id): return "conditions-\(id)"
        }
    }
}

@MainActor
final class PlanDetailRouter: ObservableObject {
    @Published var route: PlanDetailRoute?

    private let environment: AppEnvironment
    private let coordinator: AppCoordinator

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.environment = environment
        self.coordinator = coordinator
    }

    @ViewBuilder
    func destination(for route: PlanDetailRoute) -> some View {
        switch route {
        case .explanation(let window):
            WindowExplanationModule.build(environment: environment, coordinator: coordinator, window: window)
        case .risk(let id):
            PlanRiskModule.build(environment: environment, coordinator: coordinator, planID: id)
        case .feedback(let id):
            FeedbackModule.build(environment: environment, planID: id)
        case .conditions(let id):
            ConditionDetailsModule.build(environment: environment, placeID: id)
        }
    }
}

// MARK: - Builder

enum PlanDetailModule {
    @MainActor
    static func build(environment: AppEnvironment, coordinator: AppCoordinator, planID: UUID) -> some View {
        let interactor = PlanDetailInteractor(repository: environment.repository)
        let router = PlanDetailRouter(environment: environment, coordinator: coordinator)
        let presenter = PlanDetailPresenter(interactor: interactor, router: router, planID: planID)
        return PlanDetailView(presenter: presenter, router: router)
    }
}
