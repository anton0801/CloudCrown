//
//  ConditionDetailsModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol ConditionDetailsInteractorInput: AnyObject {
    var settings: AppSettings { get }
    func place(id: UUID) -> Place?
    func cachedSnapshot(for placeID: UUID) -> ConditionSnapshot?
    func refresh(place: Place) async -> SnapshotLoadResult
}

// MARK: - Router

@MainActor
final class ConditionDetailsRouter: ObservableObject {
    @Published var inspectedMetric: MetricKind?
    @Published var showsSources = false
}

// MARK: - Builder

enum ConditionDetailsModule {
    @MainActor
    static func build(environment: AppEnvironment, placeID: UUID) -> some View {
        let interactor = ConditionDetailsInteractor(repository: environment.repository,
                                                    weather: environment.weather)
        let router = ConditionDetailsRouter()
        let presenter = ConditionDetailsPresenter(interactor: interactor, router: router, placeID: placeID)
        return ConditionDetailsView(presenter: presenter, router: router)
    }
}
