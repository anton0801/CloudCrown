//
//  ComfortProfileModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol ComfortProfileInteractorInput: AnyObject {
    var profile: ComfortProfile? { get }
    var settings: AppSettings { get }
    func generalDefaults() -> ComfortProfile
    func save(_ profile: ComfortProfile, appliedDefaults: Bool) -> SaveOutcome
    func reset() -> SaveOutcome
    func saveDraft(_ profile: ComfortProfile)
    func loadDraft() -> ComfortProfile?
    func clearDraft()
    func hasDraft() -> Bool
    func dependentSummary() -> String
    func updateUnits(_ transform: (inout AppSettings) -> Void) -> SaveOutcome
}

// MARK: - Router

enum ComfortProfileRoute: Identifiable, Equatable {
    case metricSources(MetricKind)
    var id: String {
        switch self { case .metricSources(let m): return "metric-\(m.rawValue)" }
    }
}

@MainActor
final class ComfortProfileRouter: ObservableObject {
    @Published var route: ComfortProfileRoute?
    @Published var showsResetConfirmation = false
    @Published var showsDraftPrompt = false
    @Published var showsUnitsSheet = false
}

// MARK: - Builder

enum ComfortProfileModule {
    @MainActor
    static func build(environment: AppEnvironment) -> some View {
        let interactor = ComfortProfileInteractor(repository: environment.repository)
        let router = ComfortProfileRouter()
        let presenter = ComfortProfilePresenter(interactor: interactor, router: router)
        return ComfortProfileView(presenter: presenter, router: router)
    }
}
