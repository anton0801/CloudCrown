//
//  HistoryModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol HistoryInteractorInput: AnyObject {
    var records: [HistoryRecord] { get }
    var feedback: [FeedbackEntry] { get }
    var plans: [Plan] { get }
    func plan(id: UUID?) -> Plan?
    func activity(id: UUID) -> ActivityTemplate?
    func place(id: UUID) -> Place?
    var ratedCount: Int { get }
}

// MARK: - Router

enum HistoryRoute: Identifiable, Equatable {
    case plan(UUID)
    case feedback(UUID)
    case insights

    var id: String {
        switch self {
        case .plan(let id): return "plan-\(id)"
        case .feedback(let id): return "feedback-\(id)"
        case .insights: return "insights"
        }
    }
}

@MainActor
final class HistoryRouter: ObservableObject {
    @Published var route: HistoryRoute?

    private let environment: AppEnvironment
    private let coordinator: AppCoordinator

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.environment = environment
        self.coordinator = coordinator
    }

    @ViewBuilder
    func destination(for route: HistoryRoute) -> some View {
        switch route {
        case .plan(let id):
            PlanDetailModule.build(environment: environment, coordinator: coordinator, planID: id)
        case .feedback(let id):
            FeedbackModule.build(environment: environment, planID: id)
        case .insights:
            InsightsModule.build(environment: environment, coordinator: coordinator)
        }
    }
}

// MARK: - Builder

enum HistoryModule {
    @MainActor
    static func build(environment: AppEnvironment, coordinator: AppCoordinator) -> some View {
        let interactor = HistoryInteractor(repository: environment.repository)
        let router = HistoryRouter(environment: environment, coordinator: coordinator)
        let presenter = HistoryPresenter(interactor: interactor, router: router)
        return HistoryView(presenter: presenter, router: router)
    }
}
