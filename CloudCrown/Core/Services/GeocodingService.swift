//
//  GeocodingService.swift
//  CloudCrown
//
//  Manual place search — always available, even when location access is denied.
//

import Foundation

protocol GeocodingServicing {
    func search(_ query: String) async throws -> [PlaceSearchResult]
    func reverse(latitude: Double, longitude: Double) async -> String?
}

final class GeocodingService: GeocodingServicing {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ query: String) async throws -> [PlaceSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "12"),
            URLQueryItem(name: "language", value: Locale.current.languageCode ?? "en"),
            URLQueryItem(name: "format", value: "json")
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw WeatherServiceError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let decoded = try JSONDecoder().decode(GeocodingResponse.self, from: data)
            return (decoded.results ?? []).map {
                PlaceSearchResult(
                    id: String($0.id),
                    name: $0.name,
                    admin: $0.admin1,
                    country: $0.country,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    timeZoneIdentifier: $0.timezone ?? TimeZone.current.identifier
                )
            }
        } catch let error as URLError {
            throw error.code == .cancelled ? WeatherServiceError.cancelled : WeatherServiceError.offline
        } catch let error as WeatherServiceError {
            throw error
        } catch {
            throw WeatherServiceError.decoding(error.localizedDescription)
        }
    }

    /// Best-effort label for a coordinate. Returns nil rather than a guess.
    func reverse(latitude: Double, longitude: Double) async -> String? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let decoded = try? JSONDecoder().decode(GeocodingResponse.self, from: data) else { return nil }
        return decoded.results?.first?.name
    }
}

private struct GeocodingResponse: Decodable {
    var results: [Result]?

    struct Result: Decodable {
        var id: Int
        var name: String
        var latitude: Double
        var longitude: Double
        var country: String?
        var admin1: String?
        var timezone: String?
    }
}
