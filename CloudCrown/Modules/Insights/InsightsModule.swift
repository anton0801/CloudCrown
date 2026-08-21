//
//  InsightsModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol InsightsInteractorInput: AnyObject {
    var activities: [ActivityTemplate] { get }
    func buildReport(activityID: UUID?) -> InsightsEngine.Report
    func plan(id: UUID) -> Plan?
    func place(id: UUID) -> Place?
    func activity(id: UUID) -> ActivityTemplate?
    var totalRated: Int { get }
}

// MARK: - Router

enum InsightsRoute: Identifiable, Equatable {
    case sourcePlans([UUID], String)
    case plan(UUID)

    var id: String {
        switch self {
        case .sourcePlans(_, let title): return "plans-\(title)"
        case .plan(let id): return "plan-\(id)"
        }
    }
}

@MainActor
final class InsightsRouter: ObservableObject {
    @Published var route: InsightsRoute?
    @Published var showsActivityPicker = false

    private let environment: AppEnvironment
    private let coordinator: AppCoordinator

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.environment = environment
        self.coordinator = coordinator
    }

    @ViewBuilder
    func destination(for route: InsightsRoute) -> some View {
        switch route {
        case .sourcePlans(let ids, let title):
            SourcePlansView(planIDs: ids, title: title, environment: environment, coordinator: coordinator)
        case .plan(let id):
            PlanDetailModule.build(environment: environment, coordinator: coordinator, planID: id)
        }
    }
}

// MARK: - Builder

enum InsightsModule {
    @MainActor
    static func build(environment: AppEnvironment, coordinator: AppCoordinator) -> some View {
        let interactor = InsightsInteractor(repository: environment.repository)
        let router = InsightsRouter(environment: environment, coordinator: coordinator)
        let presenter = InsightsPresenter(interactor: interactor, router: router)
        return InsightsView(presenter: presenter, router: router)
    }
}
