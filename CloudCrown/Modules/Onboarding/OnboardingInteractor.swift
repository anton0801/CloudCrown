//
//  OnboardingInteractor.swift
//  CloudCrown
//

import Foundation
import CoreLocation

@MainActor
final class OnboardingInteractor: OnboardingInteractorInput {

    private let repository: DataRepository
    private let geocoding: GeocodingServicing
    private let location: LocationService

    init(repository: DataRepository, geocoding: GeocodingServicing, location: LocationService) {
        self.repository = repository
        self.geocoding = geocoding
        self.location = location
    }

    var locationAuthorization: LocationAuthorization { location.authorization }

    func makeGeneralDefaults() -> ComfortProfile {
        ComfortProfile.generalDefaults()
    }

    func saveProfile(_ profile: ComfortProfile, appliedDefaults: Bool) {
        repository.saveProfile(profile, appliedDefaults: appliedDefaults)
    }

    func saveActivity(_ template: ActivityTemplate) {
        repository.saveActivity(template)
    }

    @discardableResult
    func savePlace(_ place: Place) -> Place? {
        repository.savePlace(place)
        return repository.place(id: place.id)
    }

    func searchPlaces(_ query: String) async throws -> [PlaceSearchResult] {
        try await geocoding.search(query)
    }

    /// Resolves the device location into a named place. The name falls back to
    /// coordinates rather than inventing a label.
    func resolveCurrentPlace() async throws -> Place {
        let fix = try await location.requestCurrentLocation()
        let precision = repository.settings.locationPrecision
        let lat = precision.round(fix.coordinate.latitude)
        let lon = precision.round(fix.coordinate.longitude)
        let name = await geocoding.reverse(latitude: lat, longitude: lon)
        return Place(
            name: name ?? "My location",
            note: name == nil ? "Saved from device location" : "",
            latitude: lat,
            longitude: lon,
            timeZoneIdentifier: TimeZone.current.identifier,
            isDefault: true,
            source: .currentLocation
        )
    }

    func completeOnboarding() {
        _ = repository.updateSettings { $0.hasCompletedOnboarding = true }
    }
}
