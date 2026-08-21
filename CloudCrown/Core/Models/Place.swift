//
//  Place.swift
//  CloudCrown
//

import Foundation

enum LocationPrecision: String, Codable, CaseIterable, Identifiable {
    case exact          // full precision
    case neighbourhood  // ~1 km
    case city           // ~10 km

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exact: return "Exact"
        case .neighbourhood: return "Neighbourhood (~1 km)"
        case .city: return "City area (~10 km)"
        }
    }

    var shortTitle: String {
        switch self {
        case .exact: return "Exact"
        case .neighbourhood: return "~1 km"
        case .city: return "~10 km"
        }
    }

    var decimals: Int {
        switch self {
        case .exact: return 4
        case .neighbourhood: return 2
        case .city: return 1
        }
    }

    var explanation: String {
        switch self {
        case .exact: return "Coordinates are sent at full precision for the most accurate forecast."
        case .neighbourhood: return "Coordinates are rounded to about 1 km before any request leaves the device."
        case .city: return "Coordinates are rounded to about 10 km before any request leaves the device."
        }
    }

    func round(_ value: Double) -> Double {
        let factor = pow(10.0, Double(decimals))
        return (value * factor).rounded() / factor
    }
}

enum PlaceSource: String, Codable {
    case currentLocation, search, manual

    var title: String {
        switch self {
        case .currentLocation: return "Current location"
        case .search: return "Search result"
        case .manual: return "Entered manually"
        }
    }

    var icon: String {
        switch self {
        case .currentLocation: return "location.fill"
        case .search: return "magnifyingglass"
        case .manual: return "pencil"
        }
    }
}

struct Place: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var note: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var isDefault: Bool
    var source: PlaceSource
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         name: String,
         note: String = "",
         latitude: Double,
         longitude: Double,
         timeZoneIdentifier: String = TimeZone.current.identifier,
         isDefault: Bool = false,
         source: PlaceSource = .manual,
         isArchived: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.note = note
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isDefault = isDefault
        self.source = source
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    func coordinateSummary(precision: LocationPrecision) -> String {
        "\(SkyFormat.coordinate(latitude, precision: precision)), \(SkyFormat.coordinate(longitude, precision: precision))"
    }

    /// Coordinates actually transmitted, honouring the user's precision setting.
    func transmittedCoordinate(precision: LocationPrecision) -> (lat: Double, lon: Double) {
        (precision.round(latitude), precision.round(longitude))
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}

/// A geocoding search result, before the user saves it as a Place.
struct PlaceSearchResult: Identifiable, Hashable {
    var id: String
    var name: String
    var admin: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String

    var subtitle: String {
        [admin, country].compactMap { $0 }.joined(separator: ", ")
    }

    func makePlace() -> Place {
        Place(name: name,
              note: subtitle,
              latitude: latitude,
              longitude: longitude,
              timeZoneIdentifier: timeZoneIdentifier,
              source: .search)
    }
}
