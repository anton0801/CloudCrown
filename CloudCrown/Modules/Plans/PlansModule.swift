//
//  PlansModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol PlansInteractorInput: AnyObject {
    var plans: [Plan] { get }
    func activity(id: UUID) -> ActivityTemplate?
    func place(id: UUID) -> Place?
    func feedback(forPlan id: UUID) -> FeedbackEntry?
    func setStatus(_ id: UUID, _ status: PlanStatus) -> SaveOutcome
    func deletionImpact(_ id: UUID) -> DeletionImpact
    func delete(_ id: UUID, strategy: DeletionStrategy) -> SaveOutcome
}

// MARK: - Router

enum PlansRoute: Identifiable, Equatable {
    case detail(UUID)
    case risk(UUID)
    case feedback(UUID)

    var id: String {
        switch self {
        case .detail(let id): return "detail-\(id)"
        case .risk(let id): return "risk-\(id)"
        case .feedback(let id): return "feedback-\(id)"
        }
    }
}

@MainActor
final class PlansRouter: ObservableObject {
    @Published var route: PlansRoute?
    @Published var deletionTarget: DeletionImpact?

    private let environment: AppEnvironment
    private let coordinator: AppCoordinator

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.environment = environment
        self.coordinator = coordinator
    }

    @ViewBuilder
    func destination(for route: PlansRoute) -> some View {
        switch route {
        case .detail(let id):
            PlanDetailModule.build(environment: environment, coordinator: coordinator, planID: id)
        case .risk(let id):
            PlanRiskModule.build(environment: environment, coordinator: coordinator, planID: id)
        case .feedback(let id):
            FeedbackModule.build(environment: environment, planID: id)
        }
    }
}

// MARK: - Builder

enum PlansModule {
    @MainActor
    static func build(environment: AppEnvironment, coordinator: AppCoordinator) -> some View {
        let interactor = PlansInteractor(repository: environment.repository)
        let router = PlansRouter(environment: environment, coordinator: coordinator)
        let presenter = PlansPresenter(interactor: interactor, router: router, coordinator: coordinator)
        return PlansView(presenter: presenter, router: router)
    }
}
