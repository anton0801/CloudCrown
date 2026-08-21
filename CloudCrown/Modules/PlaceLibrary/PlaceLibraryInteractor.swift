//
//  PlaceLibraryInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class PlaceLibraryInteractor: PlaceLibraryInteractorInput {

    private let repository: DataRepository
    private let geocoding: GeocodingServicing
    private let location: LocationService

    init(repository: DataRepository, geocoding: GeocodingServicing, location: LocationService) {
        self.repository = repository
        self.geocoding = geocoding
        self.location = location
    }

    var places: [Place] { repository.places }
    var settings: AppSettings { repository.settings }
    var locationAuthorization: LocationAuthorization {
        location.refreshAuthorization()
        return location.authorization
    }

    func search(_ query: String) async throws -> [PlaceSearchResult] {
        try await geocoding.search(query)
    }

    /// Precise location is only read here — the one action that asks for it.
    func resolveCurrentPlace() async throws -> Place {
        let fix = try await location.requestCurrentLocation()
        let precision = repository.settings.locationPrecision
        let lat = precision.round(fix.coordinate.latitude)
        let lon = precision.round(fix.coordinate.longitude)
        let name = await geocoding.reverse(latitude: lat, longitude: lon)
        return Place(
            name: name ?? "My location",
            note: precision == .exact ? "" : "Coordinates rounded to \(precision.shortTitle) before leaving the device",
            latitude: lat,
            longitude: lon,
            timeZoneIdentifier: TimeZone.current.identifier,
            source: .currentLocation
        )
    }

    func save(_ place: Place) -> SaveOutcome { repository.savePlace(place) }
    func setDefault(_ id: UUID) -> SaveOutcome { repository.setDefaultPlace(id) }
    func setArchived(_ id: UUID, archived: Bool) -> SaveOutcome { repository.setPlaceArchived(id, archived: archived) }
    func deletionImpact(_ id: UUID) -> DeletionImpact { repository.deletionImpact(place: id) }
    func delete(_ id: UUID, strategy: DeletionStrategy) -> SaveOutcome { repository.deletePlace(id, strategy: strategy) }
    func snapshot(for placeID: UUID) -> ConditionSnapshot? { repository.snapshot(for: placeID) }
    func planCount(for placeID: UUID) -> Int {
        repository.plans(forPlace: placeID).filter { $0.status == .scheduled || $0.status == .atRisk }.count
    }
}
