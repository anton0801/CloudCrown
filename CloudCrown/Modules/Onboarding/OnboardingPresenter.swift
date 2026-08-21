//
//  OnboardingPresenter.swift
//  CloudCrown
//

import SwiftUI
import Combine

@MainActor
final class OnboardingPresenter: ObservableObject, OnboardingPresenterInput {

    // MARK: - View state

    @Published private(set) var step: OnboardingStep = .problem
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    // Limits step
    @Published var profileDraft: ComfortProfile = ComfortProfile()
    @Published private(set) var limitsChoice: LimitsChoice?

    // Activity step
    @Published var activityName: String = ""
    @Published var activityKind: ActivityKind = .walking
    @Published var durationMinutes: Double = 60

    // Place step
    @Published var searchQuery: String = ""
    @Published private(set) var searchResults: [PlaceSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchError: String?
    @Published private(set) var chosenPlace: Place?
    @Published private(set) var isResolvingLocation = false
    @Published private(set) var locationMessage: String?

    enum LimitsChoice: Equatable { case generalDefaults, custom }

    private let interactor: OnboardingInteractorInput
    private let router: OnboardingRouter
    private var searchTask: Task<Void, Never>?

    init(interactor: OnboardingInteractorInput, router: OnboardingRouter) {
        self.interactor = interactor
        self.router = router
    }

    // MARK: - Derived state

    var progress: Double {
        Double(step.rawValue + 1) / Double(OnboardingStep.allCases.count)
    }

    var canAdvance: Bool {
        switch step {
        case .problem, .explanation: return true
        case .limits: return limitsChoice != nil
        case .firstActivity: return isActivityValid && chosenPlace != nil
        }
    }

    var isActivityValid: Bool {
        !activityName.trimmingCharacters(in: .whitespaces).isEmpty && durationMinutes >= 15
    }

    var advanceTitle: String {
        step == .firstActivity ? "Create and Continue" : "Continue"
    }

    var locationAuthorization: LocationAuthorization { interactor.locationAuthorization }

    // MARK: - Input

    func onAppear() {
        if activityName.isEmpty { activityName = activityKind.title }
    }

    func advance() {
        guard canAdvance else { return }
        if step == .firstActivity {
            finish()
            return
        }
        if step == .limits { persistLimits() }
        withAnimation(.easeInOut(duration: 0.28)) {
            step = OnboardingStep(rawValue: step.rawValue + 1) ?? step
        }
    }

    func goBack() {
        guard step.rawValue > 0 else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            step = OnboardingStep(rawValue: step.rawValue - 1) ?? step
        }
    }

    // MARK: - Limits

    func applyGeneralDefaults() {
        profileDraft = interactor.makeGeneralDefaults()
        limitsChoice = .generalDefaults
        router.showsDefaultsDisclaimer = true
    }

    func chooseCustomLimits() {
        if profileDraft.thresholds.isEmpty {
            // Start from empty thresholds so nothing is assumed on the user's behalf.
            profileDraft = ComfortProfile(
                thresholds: ComfortProfile.coreMetrics.map { ComfortThreshold(metric: $0, minValue: nil, maxValue: nil) },
                usesGeneralDefaults: false
            )
        }
        profileDraft.usesGeneralDefaults = false
        limitsChoice = .custom
        router.showsLimitsEditor = true
    }

    func saveCustomLimits() {
        limitsChoice = .custom
        router.showsLimitsEditor = false
    }

    func setThreshold(_ metric: MetricKind, min: Double?, max: Double?) {
        if let index = profileDraft.thresholds.firstIndex(where: { $0.metric == metric }) {
            profileDraft.thresholds[index].minValue = min
            profileDraft.thresholds[index].maxValue = max
        } else {
            profileDraft.thresholds.append(ComfortThreshold(metric: metric, minValue: min, maxValue: max))
        }
    }

    private func persistLimits() {
        interactor.saveProfile(profileDraft, appliedDefaults: limitsChoice == .generalDefaults)
    }

    // MARK: - Activity

    func selectActivityKind(_ kind: ActivityKind) {
        let previousDefault = activityKind.title
        activityKind = kind
        if activityName.isEmpty || activityName == previousDefault {
            activityName = kind.title
        }
        durationMinutes = Double(kind.defaultDurationMinutes)
    }

    // MARK: - Place

    func search(_ query: String) {
        searchTask?.cancel()
        searchError = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await self.interactor.searchPlaces(trimmed)
                guard !Task.isCancelled else { return }
                self.searchResults = results
                self.searchError = results.isEmpty ? "No place matched “\(trimmed)”. Try a different spelling." : nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if case WeatherServiceError.cancelled = error { return }
                self.searchError = error.localizedDescription
                self.searchResults = []
            }
            self.isSearching = false
        }
    }

    func useCurrentLocation() {
        guard !isResolvingLocation else { return }
        isResolvingLocation = true
        locationMessage = nil
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let place = try await self.interactor.resolveCurrentPlace()
                self.chosenPlace = place
                self.locationMessage = nil
            } catch {
                self.locationMessage = error.localizedDescription
            }
            self.isResolvingLocation = false
        }
    }

    func selectSearchResult(_ result: PlaceSearchResult) {
        var place = result.makePlace()
        place.isDefault = true
        chosenPlace = place
        searchResults = []
        searchQuery = ""
    }

    func clearChosenPlace() {
        chosenPlace = nil
    }

    // MARK: - Finish

    func finish() {
        guard canAdvance, !isSaving, let place = chosenPlace else { return }
        isSaving = true
        errorMessage = nil

        // Required conditions stay empty until the user defines them; the
        // comfort profile already supplies personal limits.
        let template = ActivityTemplate(
            name: activityName.trimmingCharacters(in: .whitespaces),
            kind: activityKind,
            requiredConditions: [],
            preferredConditions: [],
            durationMinutes: Int(durationMinutes),
            earliestMinute: 6 * 60,
            latestMinute: 21 * 60,
            requiresDaylight: activityKind == .photography,
            note: ""
        )

        _ = interactor.savePlace(place)
        interactor.saveActivity(template)
        interactor.completeOnboarding()
        isSaving = false
    }
}
