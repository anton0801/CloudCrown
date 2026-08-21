//
//  DayComparisonInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class DayComparisonInteractor: DayComparisonInteractorInput {

    private let repository: DataRepository
    private let weather: WeatherFetching

    init(repository: DataRepository, weather: WeatherFetching) {
        self.repository = repository
        self.weather = weather
    }

    var settings: AppSettings { repository.settings }
    var activities: [ActivityTemplate] { repository.activeActivities }

    func activity(id: UUID) -> ActivityTemplate? { repository.activity(id: id) }
    func place(id: UUID) -> Place? { repository.place(id: id) }
    func snapshot(for placeID: UUID) -> ConditionSnapshot? { repository.snapshot(for: placeID) }

    func refresh(place: Place) async -> SnapshotLoadResult {
        do {
            let snapshot = try await weather.fetchSnapshot(for: place,
                                                           precision: repository.settings.locationPrecision,
                                                           forecastDays: 7)
            repository.storeSnapshot(snapshot)
            return .fresh(snapshot)
        } catch {
            let isOffline = (error as? WeatherServiceError)?.isOffline ?? false
            if let cached = repository.snapshot(for: place.id) {
                return .cached(cached, reason: error.localizedDescription)
            }
            return .unavailable(reason: error.localizedDescription, isOffline: isOffline)
        }
    }

    func compare(activity: ActivityTemplate, place: Place, snapshot: ConditionSnapshot,
                 startDate: Date, dayCount: Int) -> ComparisonEngine.Result {
        ComparisonEngine.compare(activity: activity,
                                 profile: repository.profile,
                                 place: place,
                                 snapshot: snapshot,
                                 startDate: startDate,
                                 dayCount: dayCount)
    }
}
