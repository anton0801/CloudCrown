//
//  DayComparisonModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol DayComparisonInteractorInput: AnyObject {
    var settings: AppSettings { get }
    func activity(id: UUID) -> ActivityTemplate?
    func place(id: UUID) -> Place?
    func snapshot(for placeID: UUID) -> ConditionSnapshot?
    func refresh(place: Place) async -> SnapshotLoadResult
    func compare(activity: ActivityTemplate, place: Place, snapshot: ConditionSnapshot,
                 startDate: Date, dayCount: Int) -> ComparisonEngine.Result
    var activities: [ActivityTemplate] { get }
}

// MARK: - Router

enum DayComparisonRoute: Identifiable, Equatable {
    case explanation(WindowCandidate)
    var id: String { switch self { case .explanation(let w): return "explain-\(w.id)" } }
}

@MainActor
final class DayComparisonRouter: ObservableObject {
    @Published var route: DayComparisonRoute?
    @Published var showsActivityPicker = false

    private let environment: AppEnvironment
    private let coordinator: AppCoordinator

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.environment = environment
        self.coordinator = coordinator
    }

    @ViewBuilder
    func destination(for route: DayComparisonRoute) -> some View {
        switch route {
        case .explanation(let window):
            WindowExplanationModule.build(environment: environment, coordinator: coordinator, window: window)
        }
    }
}

// MARK: - Builder

enum DayComparisonModule {
    @MainActor
    static func build(environment: AppEnvironment,
                      coordinator: AppCoordinator,
                      activityID: UUID,
                      placeID: UUID) -> some View {
        let interactor = DayComparisonInteractor(repository: environment.repository, weather: environment.weather)
        let router = DayComparisonRouter(environment: environment, coordinator: coordinator)
        let presenter = DayComparisonPresenter(interactor: interactor, router: router,
                                               activityID: activityID, placeID: placeID)
        return DayComparisonView(presenter: presenter, router: router)
    }
}
