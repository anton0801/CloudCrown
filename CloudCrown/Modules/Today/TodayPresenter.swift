//
//  TodayPresenter.swift
//  CloudCrown
//

import SwiftUI
import Combine

@MainActor
final class TodayPresenter: ObservableObject {

    enum ViewState: Equatable {
        case loading
        case ready
        case noPlace
        case unavailable(reason: String, isOffline: Bool)
    }

    @Published private(set) var state: ViewState = .loading
    @Published private(set) var place: Place?
    @Published private(set) var snapshot: ConditionSnapshot?
    @Published private(set) var isCached = false
    @Published private(set) var cachedReason: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var nextWindow: WindowCandidate?
    @Published private(set) var nextWindowActivity: ActivityTemplate?
    @Published var toast: ToastPayload?

    private let interactor: TodayInteractorInput
    private let router: TodayRouter
    private let repository: DataRepository
    private var hasLoadedOnce = false

    init(interactor: TodayInteractorInput, router: TodayRouter, repository: DataRepository) {
        self.interactor = interactor
        self.router = router
        self.repository = repository
    }

    // MARK: - Derived

    var setupGaps: [SetupGap] { interactor.setupGaps }
    var isReady: Bool { setupGaps.isEmpty }

    var currentHour: HourlyConditions? {
        snapshot?.hour(nearest: Date())
    }

    var plansAtRisk: [Plan] { repository.plansAtRisk }

    var upcomingPlans: [Plan] {
        Array(repository.upcomingPlans.prefix(4))
    }

    var plansAwaitingFeedback: [Plan] {
        repository.plans.filter { $0.awaitsFeedback(hasFeedback: repository.feedback(forPlan: $0.id) != nil) }
    }

    var settings: AppSettings { repository.settings }

    var headlineMetrics: [MetricKind] {
        [.temperature, .apparentTemperature, .precipitationProbability, .windSpeed, .uvIndex, .airQuality]
    }

    var snapshotIsStale: Bool { snapshot?.isStale ?? false }

    func activityName(_ id: UUID) -> String { repository.activity(id: id)?.name ?? "Removed activity" }
    func placeName(_ id: UUID) -> String { repository.place(id: id)?.name ?? "Removed place" }

    // MARK: - Loading

    func onAppear() {
        guard !hasLoadedOnce else {
            refreshDerived()
            return
        }
        hasLoadedOnce = true
        Task { await load(forceRefresh: false) }
    }

    func refresh() {
        Task { await load(forceRefresh: true) }
    }

    func load(forceRefresh: Bool) async {
        guard let place = interactor.defaultPlace else {
            state = .noPlace
            self.place = nil
            return
        }
        self.place = place

        if snapshot == nil { state = .loading }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await interactor.loadSnapshot(for: place, forceRefresh: forceRefresh)
        switch result {
        case .fresh(let snapshot):
            self.snapshot = snapshot
            isCached = false
            cachedReason = nil
            state = .ready
            interactor.assessRisks(snapshot: snapshot, place: place)
        case .cached(let snapshot, let reason):
            self.snapshot = snapshot
            isCached = true
            cachedReason = reason
            state = .ready
        case .unavailable(let reason, let isOffline):
            state = .unavailable(reason: reason, isOffline: isOffline)
        }
        refreshDerived()
    }

    private func refreshDerived() {
        guard let place = place, let snapshot = snapshot else {
            nextWindow = nil
            nextWindowActivity = nil
            return
        }
        if let found = interactor.nextGoodWindow(place: place, snapshot: snapshot) {
            nextWindow = found.window
            nextWindowActivity = found.activity
        } else {
            nextWindow = nil
            nextWindowActivity = nil
        }
    }

    // MARK: - Actions

    func openConditions() {
        guard let place = place else { return }
        router.go(.conditions(placeID: place.id))
    }

    func openMetric(_ metric: MetricKind) {
        guard let place = place else { return }
        router.go(.conditions(placeID: place.id))
    }

    func openNextWindow() {
        guard let window = nextWindow else {
            router.openFinder(activityID: nil, placeID: place?.id)
            return
        }
        router.go(.explanation(window))
    }

    func addActivity() { router.go(.activityEditor) }
    func openPlaces() { router.go(.places) }
    func openSettings() { router.go(.settings) }
    func openAlerts() { router.go(.alerts) }
    func openPlan(_ id: UUID) { router.go(.plan(id)) }
    func openRisk(_ id: UUID) { router.go(.planRisk(id)) }
    func openFinder() { router.openFinder(activityID: nil, placeID: place?.id) }

    func resolve(_ gap: SetupGap) {
        switch gap {
        case .profile: router.go(.comfortProfile)
        case .activity: router.go(.activityEditor)
        case .place: router.go(.places)
        }
    }
}
