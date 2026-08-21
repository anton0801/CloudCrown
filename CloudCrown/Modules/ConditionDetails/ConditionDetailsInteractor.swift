//
//  ConditionDetailsInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class ConditionDetailsInteractor: ConditionDetailsInteractorInput {

    private let repository: DataRepository
    private let weather: WeatherFetching

    init(repository: DataRepository, weather: WeatherFetching) {
        self.repository = repository
        self.weather = weather
    }

    var settings: AppSettings { repository.settings }

    func place(id: UUID) -> Place? { repository.place(id: id) }
    func cachedSnapshot(for placeID: UUID) -> ConditionSnapshot? { repository.snapshot(for: placeID) }

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
}
