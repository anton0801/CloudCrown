//
//  DayComparisonPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class DayComparisonPresenter: ObservableObject {

    enum ViewState: Equatable {
        case loading
        case ready
        case unavailable(reason: String, isOffline: Bool)
        case missingEntity(String)
    }

    @Published private(set) var state: ViewState = .loading
    @Published private(set) var result: ComparisonEngine.Result?
    @Published private(set) var snapshot: ConditionSnapshot?
    @Published private(set) var isCached = false
    @Published var dayCount: Int = 5
    @Published var highlight: ComparisonEngine.Highlight = .bestOverall
    @Published var activityID: UUID
    @Published var toast: ToastPayload?

    private let interactor: DayComparisonInteractorInput
    private let router: DayComparisonRouter
    private let placeID: UUID
    private var didLoad = false

    init(interactor: DayComparisonInteractorInput,
         router: DayComparisonRouter,
         activityID: UUID,
         placeID: UUID) {
        self.interactor = interactor
        self.router = router
        self.activityID = activityID
        self.placeID = placeID
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var activity: ActivityTemplate? { interactor.activity(id: activityID) }
    var place: Place? { interactor.place(id: placeID) }
    var activities: [ActivityTemplate] { interactor.activities }
    var timeZone: TimeZone { snapshot?.timeZone ?? place?.timeZone ?? .current }

    var days: [ComparisonEngine.DaySummary] { result?.days ?? [] }

    var winnerID: UUID? { result?.winners[highlight] }
    var incompleteWarning: String? { result?.incompleteWarnings[highlight] }

    var hasAnyUsableDay: Bool { days.contains(where: \.hasUsableWindow) }

    func isWinner(_ day: ComparisonEngine.DaySummary) -> Bool { day.id == winnerID }

    func highlightValue(_ day: ComparisonEngine.DaySummary) -> String {
        switch highlight {
        case .bestOverall:
            return day.score.map { "\(Int($0.rounded()))" } ?? "—"
        case .mostStable:
            return day.stability.map { SkyFormat.percent($0) } ?? "—"
        case .lowestUV:
            return day.maxUV.map { SkyFormat.number($0, decimals: 1) } ?? "—"
        case .lowestRain:
            return day.maxRainProbability.map { "\(Int($0.rounded()))%" } ?? "—"
        }
    }

    func highlightCaption() -> String {
        switch highlight {
        case .bestOverall: return "Best window score for the day"
        case .mostStable: return "Least variation inside the usable windows"
        case .lowestUV: return "Highest UV reached during the day"
        case .lowestRain: return "Highest rain probability during the day"
        }
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !didLoad else { return }
        didLoad = true
        load()
    }

    func load(forceRefresh: Bool = false) {
        guard let activity = activity else {
            state = .missingEntity("This activity no longer exists.")
            return
        }
        guard let place = place else {
            state = .missingEntity("This place no longer exists.")
            return
        }

        if let cached = interactor.snapshot(for: placeID), !cached.isStale, !forceRefresh {
            apply(snapshot: cached, activity: activity, place: place, cached: false)
            return
        }

        state = .loading
        Task { [weak self] in
            guard let self = self else { return }
            let outcome = await self.interactor.refresh(place: place)
            switch outcome {
            case .fresh(let snapshot):
                self.apply(snapshot: snapshot, activity: activity, place: place, cached: false)
            case .cached(let snapshot, _):
                self.apply(snapshot: snapshot, activity: activity, place: place, cached: true)
            case .unavailable(let reason, let isOffline):
                self.state = .unavailable(reason: reason, isOffline: isOffline)
            }
        }
    }

    private func apply(snapshot: ConditionSnapshot, activity: ActivityTemplate, place: Place, cached: Bool) {
        self.snapshot = snapshot
        self.isCached = cached
        self.result = interactor.compare(activity: activity,
                                         place: place,
                                         snapshot: snapshot,
                                         startDate: Date(),
                                         dayCount: dayCount)
        self.state = .ready
    }

    func changeDayCount(_ count: Int) {
        dayCount = min(ComparisonEngine.maxDays, max(2, count))
        load()
    }

    func changeActivity(_ activity: ActivityTemplate) {
        activityID = activity.id
        router.showsActivityPicker = false
        load()
        toast = ToastPayload(title: "Comparing \(activity.name)",
                             changes: ["Same place and time zone throughout"])
    }

    func openDay(_ day: ComparisonEngine.DaySummary) {
        guard let window = day.bestWindow else { return }
        router.route = .explanation(window)
    }
}
