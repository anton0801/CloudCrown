//
//  ConditionDetailsPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class ConditionDetailsPresenter: ObservableObject {

    enum ViewState: Equatable {
        case loading
        case ready
        case missingPlace
        case unavailable(reason: String, isOffline: Bool)
    }

    @Published private(set) var state: ViewState = .loading
    @Published private(set) var snapshot: ConditionSnapshot?
    @Published private(set) var isCached = false
    @Published private(set) var isRefreshing = false
    @Published var selectedDate: Date = Date()
    @Published var selectedHourDate: Date?
    @Published var toast: ToastPayload?

    private let interactor: ConditionDetailsInteractorInput
    private let router: ConditionDetailsRouter
    private let placeID: UUID
    private var didLoad = false

    init(interactor: ConditionDetailsInteractorInput, router: ConditionDetailsRouter, placeID: UUID) {
        self.interactor = interactor
        self.router = router
        self.placeID = placeID
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var place: Place? { interactor.place(id: placeID) }
    var timeZone: TimeZone { snapshot?.timeZone ?? place?.timeZone ?? .current }

    var availableDays: [Date] {
        guard let snapshot = snapshot else { return [] }
        var seen: [Date] = []
        for hour in snapshot.hours {
            let day = hour.date.startOfDay(in: snapshot.timeZone)
            if !seen.contains(where: { $0 == day }) { seen.append(day) }
        }
        return seen
    }

    var hoursForSelectedDay: [HourlyConditions] {
        guard let snapshot = snapshot else { return [] }
        return snapshot.hours.filter { $0.date.isSameDay(as: selectedDate, in: snapshot.timeZone) }
    }

    var selectedHour: HourlyConditions? {
        guard let snapshot = snapshot else { return nil }
        if let date = selectedHourDate,
           let match = snapshot.hours.first(where: { $0.date == date }) {
            return match
        }
        return hoursForSelectedDay.first(where: { $0.date >= Date() }) ?? hoursForSelectedDay.first
    }

    var selectedDay: DailyConditions? {
        snapshot?.day(containing: selectedDate)
    }

    var detailMetrics: [MetricKind] {
        [.temperature, .apparentTemperature, .precipitationProbability, .precipitationAmount,
         .windSpeed, .windGust, .uvIndex, .airQuality, .pollen, .visibility, .humidity, .cloudCover]
    }

    var sources: [DataSource] { snapshot?.sources ?? [] }

    /// Metrics with no value anywhere in the snapshot.
    var unavailableMetrics: [MetricKind] { snapshot?.unavailableMetrics ?? [] }

    func coverage(of metric: MetricKind) -> Double { snapshot?.coverage(of: metric) ?? 0 }

    func source(for sourceID: String?) -> DataSource? {
        guard let sourceID = sourceID else { return nil }
        return snapshot?.source(id: sourceID)
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !didLoad else { return }
        didLoad = true
        guard let place = place else {
            state = .missingPlace
            return
        }
        if let cached = interactor.cachedSnapshot(for: placeID) {
            snapshot = cached
            isCached = cached.isStale
            selectedDate = cached.hours.first?.date ?? Date()
            state = .ready
            if cached.isStale { refresh() }
        } else {
            refresh()
        }
        _ = place
    }

    func refresh() {
        guard let place = place else {
            state = .missingPlace
            return
        }
        if snapshot == nil { state = .loading }
        isRefreshing = true
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.interactor.refresh(place: place)
            switch result {
            case .fresh(let snapshot):
                self.snapshot = snapshot
                self.isCached = false
                if !self.availableDays.contains(where: { $0.isSameDay(as: self.selectedDate, in: snapshot.timeZone) }) {
                    self.selectedDate = snapshot.hours.first?.date ?? Date()
                }
                self.selectedHourDate = nil
                self.state = .ready
                self.toast = ToastPayload(title: "Conditions refreshed",
                                          changes: ["\(snapshot.hours.count) hourly points",
                                                    "Source: \(snapshot.sourceSummary)"])
            case .cached(let snapshot, let reason):
                self.snapshot = snapshot
                self.isCached = true
                self.state = .ready
                self.toast = ToastPayload(title: "Showing local snapshot", changes: [reason])
            case .unavailable(let reason, let isOffline):
                self.state = .unavailable(reason: reason, isOffline: isOffline)
            }
            self.isRefreshing = false
        }
    }

    func selectDay(_ date: Date) {
        selectedDate = date
        selectedHourDate = nil
    }

    func selectHour(_ hour: HourlyConditions) {
        selectedHourDate = hour.date
    }

    func inspect(_ metric: MetricKind) {
        router.inspectedMetric = metric
    }

    func openSources() { router.showsSources = true }
}
