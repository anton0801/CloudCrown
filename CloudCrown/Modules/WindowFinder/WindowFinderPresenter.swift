//
//  WindowFinderPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class WindowFinderPresenter: ObservableObject {

    enum ResultState: Equatable {
        case idle
        case searching
        case results
        case noWindow
        case unavailable(reason: String, isOffline: Bool)
        case invalid(String)
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, bestMatch, acceptable, notRecommended
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .bestMatch: return "Best Match"
            case .acceptable: return "Acceptable"
            case .notRecommended: return "Not Recommended"
            }
        }
    }

    @Published var form: WindowFinderForm
    @Published private(set) var state: ResultState = .idle
    @Published private(set) var result: WindowSearchResult?
    @Published private(set) var snapshot: ConditionSnapshot?
    @Published private(set) var usedCache = false
    @Published var filter: Filter = .all
    @Published var toast: ToastPayload?

    private let interactor: WindowFinderInteractorInput
    private let router: WindowFinderRouter
    private let coordinator: AppCoordinator
    private var didAppear = false

    init(interactor: WindowFinderInteractorInput, router: WindowFinderRouter, coordinator: AppCoordinator) {
        self.interactor = interactor
        self.router = router
        self.coordinator = coordinator
        let activity = interactor.activities.first
        let place = interactor.places.first(where: { $0.isDefault }) ?? interactor.places.first
        self.form = interactor.loadDraft() ?? WindowFinderForm.makeDefault(activity: activity, place: place)
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var activities: [ActivityTemplate] { interactor.activities }
    var places: [Place] { interactor.places }
    var setupGaps: [SetupGap] { interactor.setupGaps }
    var isReady: Bool { setupGaps.isEmpty }

    var selectedActivity: ActivityTemplate? {
        interactor.activities.first(where: { $0.id == form.activityID })
    }
    var selectedPlace: Place? {
        interactor.places.first(where: { $0.id == form.placeID })
    }
    var timeZone: TimeZone { selectedPlace?.timeZone ?? .current }

    var validationMessage: String? {
        if form.activityID == nil { return "Choose an activity — it defines which conditions block a window." }
        if form.placeID == nil { return "Choose a place — conditions are fetched per place." }
        return form.makeQuery()?.validationMessage
    }

    var canSearch: Bool {
        validationMessage == nil && state != .searching
    }

    var visibleCandidates: [WindowCandidate] {
        guard let result = result else { return [] }
        switch filter {
        case .all: return result.candidates
        case .bestMatch: return result.best
        case .acceptable: return result.acceptable
        case .notRecommended: return result.notRecommended + result.needsVerification
        }
    }

    func count(for filter: Filter) -> Int {
        guard let result = result else { return 0 }
        switch filter {
        case .all: return result.candidates.count
        case .bestMatch: return result.best.count
        case .acceptable: return result.acceptable.count
        case .notRecommended: return result.notRecommended.count + result.needsVerification.count
        }
    }

    /// True when the stored explanation predates the newest snapshot.
    func isSuperseded(_ window: WindowCandidate) -> Bool {
        guard let snapshot = snapshot else { return false }
        return window.snapshotID != snapshot.id
    }

    // MARK: - Lifecycle

    func onAppear() {
        applyPendingCoordinatorSelection()
        guard !didAppear else { return }
        didAppear = true
        if form.activityID == nil { form.activityID = interactor.activities.first?.id }
        if form.placeID == nil {
            form.placeID = (interactor.places.first(where: { $0.isDefault }) ?? interactor.places.first)?.id
        }
    }

    private func applyPendingCoordinatorSelection() {
        if let activityID = coordinator.pendingFinderActivityID {
            form.activityID = activityID
            coordinator.pendingFinderActivityID = nil
        }
        if let placeID = coordinator.pendingFinderPlaceID {
            form.placeID = placeID
            coordinator.pendingFinderPlaceID = nil
        }
    }

    // MARK: - Form

    func selectActivity(_ activity: ActivityTemplate) {
        form.activityID = activity.id
        form.durationMinutes = activity.durationMinutes
        form.earliestMinute = activity.earliestMinute
        form.latestMinute = activity.latestMinute
        interactor.saveDraft(form)
    }

    func selectPlace(_ place: Place) {
        form.placeID = place.id
        interactor.saveDraft(form)
    }

    func persistDraft() { interactor.saveDraft(form) }

    func resetForm() {
        form = WindowFinderForm.makeDefault(activity: selectedActivity, place: selectedPlace)
        interactor.clearDraft()
        state = .idle
        result = nil
    }

    // MARK: - Search

    func search() {
        guard let query = form.makeQuery() else {
            state = .invalid(validationMessage ?? "Complete the form first.")
            return
        }
        if let message = query.validationMessage {
            state = .invalid(message)
            return
        }
        interactor.saveDraft(form)
        state = .searching

        Task { [weak self] in
            guard let self = self else { return }
            let outcome = await self.interactor.find(query: query)
            switch outcome {
            case .success(let result, let usedCache, let snapshot):
                self.result = result
                self.snapshot = snapshot
                self.usedCache = usedCache
                self.state = result.hasUsableWindow ? .results : .noWindow
                self.filter = .all
                if result.hasUsableWindow {
                    self.toast = ToastPayload(
                        title: "\(result.best.count + result.acceptable.count) window\(result.best.count + result.acceptable.count == 1 ? "" : "s") found",
                        changes: ["Rules version \(result.rulesVersion)",
                                  "From snapshot captured \(RelativeTime.string(for: result.snapshotCapturedAt))"]
                    )
                }
            case .missingSnapshot(let reason, let isOffline):
                self.state = .unavailable(reason: reason, isOffline: isOffline)
            case .invalidQuery(let message):
                self.state = .invalid(message)
            }
        }
    }

    // MARK: - Navigation

    func openExplanation(_ window: WindowCandidate) {
        router.route = .explanation(window)
    }

    func openComparison() {
        guard let activity = selectedActivity, let place = selectedPlace else { return }
        router.route = .comparison(activityID: activity.id, placeID: place.id)
    }

    func resolve(_ gap: SetupGap) {
        switch gap {
        case .profile: router.route = .profile
        case .activity: router.route = .activities
        case .place: router.route = .places
        }
    }
}
