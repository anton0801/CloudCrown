//
//  OnboardingModule.swift
//  CloudCrown
//
//  VIPER contract + router + builder for the explaining onboarding.
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol OnboardingInteractorInput: AnyObject {
    func makeGeneralDefaults() -> ComfortProfile
    func saveProfile(_ profile: ComfortProfile, appliedDefaults: Bool)
    func saveActivity(_ template: ActivityTemplate)
    func savePlace(_ place: Place) -> Place?
    func searchPlaces(_ query: String) async throws -> [PlaceSearchResult]
    func resolveCurrentPlace() async throws -> Place
    func completeOnboarding()
    var locationAuthorization: LocationAuthorization { get }
}

@MainActor
protocol OnboardingPresenterInput: AnyObject {
    func onAppear()
    func advance()
    func goBack()
    func applyGeneralDefaults()
    func chooseCustomLimits()
    func saveCustomLimits()
    func selectActivityKind(_ kind: ActivityKind)
    func search(_ query: String)
    func useCurrentLocation()
    func selectSearchResult(_ result: PlaceSearchResult)
    func finish()
}

enum OnboardingStep: Int, CaseIterable {
    case problem, limits, explanation, firstActivity

    var title: String {
        switch self {
        case .problem: return "Plan Around Real Conditions"
        case .limits: return "Set Your Comfort Limits"
        case .explanation: return "See Why a Window Works"
        case .firstActivity: return "Add Your First Activity"
        }
    }

    var subtitle: String {
        switch self {
        case .problem:
            return "A forecast tells you the weather. CloudCrown tells you when your own conditions are actually met."
        case .limits:
            return "Windows are judged against your limits, not a generic idea of good weather."
        case .explanation:
            return "Every window opens up to show the measurements behind it, with source and update time."
        case .firstActivity:
            return "Create one real activity and one real place. CloudCrown starts empty on purpose."
        }
    }
}

// MARK: - Router

@MainActor
final class OnboardingRouter: ObservableObject {
    @Published var showsLimitsEditor = false
    @Published var showsDefaultsDisclaimer = false
}

// MARK: - Builder

enum OnboardingModule {
    @MainActor
    static func build(environment: AppEnvironment) -> some View {
        let interactor = OnboardingInteractor(repository: environment.repository,
                                              geocoding: environment.geocoding,
                                              location: environment.location)
        let router = OnboardingRouter()
        let presenter = OnboardingPresenter(interactor: interactor, router: router)
        return OnboardingView(presenter: presenter, router: router)
    }
}
