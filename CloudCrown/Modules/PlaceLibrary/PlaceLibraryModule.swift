//
//  PlaceLibraryModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol PlaceLibraryInteractorInput: AnyObject {
    var places: [Place] { get }
    var settings: AppSettings { get }
    var locationAuthorization: LocationAuthorization { get }
    func search(_ query: String) async throws -> [PlaceSearchResult]
    func resolveCurrentPlace() async throws -> Place
    func save(_ place: Place) -> SaveOutcome
    func setDefault(_ id: UUID) -> SaveOutcome
    func setArchived(_ id: UUID, archived: Bool) -> SaveOutcome
    func deletionImpact(_ id: UUID) -> DeletionImpact
    func delete(_ id: UUID, strategy: DeletionStrategy) -> SaveOutcome
    func snapshot(for placeID: UUID) -> ConditionSnapshot?
    func planCount(for placeID: UUID) -> Int
}

// MARK: - Router

enum PlaceLibraryRoute: Identifiable, Equatable {
    case conditions(UUID)
    var id: String { switch self { case .conditions(let id): return "conditions-\(id)" } }
}

@MainActor
final class PlaceLibraryRouter: ObservableObject {
    @Published var route: PlaceLibraryRoute?
    @Published var editing: Place?
    @Published var isAdding = false
    @Published var deletionTarget: DeletionImpact?
    @Published var showsArchived = false

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    @ViewBuilder
    func destination(for route: PlaceLibraryRoute) -> some View {
        switch route {
        case .conditions(let id):
            ConditionDetailsModule.build(environment: environment, placeID: id)
        }
    }
}

// MARK: - Builder

enum PlaceLibraryModule {
    @MainActor
    static func build(environment: AppEnvironment, coordinator: AppCoordinator) -> some View {
        let interactor = PlaceLibraryInteractor(repository: environment.repository,
                                                geocoding: environment.geocoding,
                                                location: environment.location)
        let router = PlaceLibraryRouter(environment: environment)
        let presenter = PlaceLibraryPresenter(interactor: interactor, router: router)
        return PlaceLibraryView(presenter: presenter, router: router)
    }
}
