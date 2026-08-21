//
//  LocationService.swift
//  CloudCrown
//
//  Precise location is requested only when the user taps "Use Current Location".
//  Denial never blocks the manual path.
//

import CoreLocation
import Combine

enum LocationAuthorization {
    case notDetermined, denied, restricted, authorized

    var canRequest: Bool { self == .notDetermined }
    var isDenied: Bool { self == .denied || self == .restricted }

    var explanation: String {
        switch self {
        case .notDetermined: return "CloudCrown has not asked for location yet."
        case .denied: return "Location access is off. You can still search for a place or enter one manually."
        case .restricted: return "Location access is restricted on this device. Manual search still works."
        case .authorized: return "Location access is on. It is only used when you tap Use Current Location."
        }
    }
}

enum LocationError: LocalizedError {
    case denied
    case unavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .denied: return "Location access was declined. Search for the place instead."
        case .unavailable: return "The device could not determine a location right now."
        case .timeout: return "Getting a location took too long."
        }
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject {

    @Published private(set) var authorization: LocationAuthorization = .notDetermined
    @Published private(set) var isResolving = false

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = Self.map(manager.authorizationStatus)
    }

    func refreshAuthorization() {
        authorization = Self.map(manager.authorizationStatus)
    }

    /// Requests a single fix. Throws instead of silently returning a stale value.
    func requestCurrentLocation() async throws -> CLLocation {
        refreshAuthorization()
        if authorization.isDenied { throw LocationError.denied }

        if authorization.canRequest {
            manager.requestWhenInUseAuthorization()
            // Give the system prompt a moment to resolve before requesting a fix.
            try? await Task.sleep(nanoseconds: 600_000_000)
            refreshAuthorization()
            if authorization.isDenied { throw LocationError.denied }
        }

        isResolving = true
        defer { isResolving = false }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard let self = self, !Task.isCancelled else { return }
                self.finish(.failure(LocationError.timeout))
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation = continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let location): continuation.resume(returning: location)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        @unknown default: return .notDetermined
        }
    }
}

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if (error as? CLError)?.code == .denied {
                self.authorization = .denied
                self.finish(.failure(LocationError.denied))
            } else {
                self.finish(.failure(LocationError.unavailable))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refreshAuthorization() }
    }
}
