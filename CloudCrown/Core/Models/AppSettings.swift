//
//  AppSettings.swift
//  CloudCrown
//

import Foundation

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var title: String { self == .celsius ? "Celsius" : "Fahrenheit" }
    var symbol: String { self == .celsius ? "°C" : "°F" }

    func fromCanonical(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }
    func toCanonical(_ value: Double) -> Double {
        self == .celsius ? value : (value - 32) * 5 / 9
    }
}

enum SpeedUnit: String, Codable, CaseIterable, Identifiable {
    case kmh, mph, ms
    var id: String { rawValue }
    var title: String {
        switch self {
        case .kmh: return "km/h"
        case .mph: return "mph"
        case .ms: return "m/s"
        }
    }
    var symbol: String { title }

    func fromCanonical(_ kmh: Double) -> Double {
        switch self {
        case .kmh: return kmh
        case .mph: return kmh * 0.621371
        case .ms: return kmh / 3.6
        }
    }
    func toCanonical(_ value: Double) -> Double {
        switch self {
        case .kmh: return value
        case .mph: return value / 0.621371
        case .ms: return value * 3.6
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Identifiable {
    case kilometres, miles
    var id: String { rawValue }
    var title: String { self == .kilometres ? "Kilometres" : "Miles" }
    var symbol: String { self == .kilometres ? "km" : "mi" }

    func fromCanonical(_ km: Double) -> Double {
        self == .kilometres ? km : km * 0.621371
    }
}

enum PrecipitationUnit: String, Codable, CaseIterable, Identifiable {
    case millimetres, inches
    var id: String { rawValue }
    var title: String { self == .millimetres ? "Millimetres" : "Inches" }
    var symbol: String { self == .millimetres ? "mm" : "in" }

    func fromCanonical(_ mm: Double) -> Double {
        self == .millimetres ? mm : mm / 25.4
    }
}

enum AQIStandard: String, Codable, CaseIterable, Identifiable {
    case us, european
    var id: String { rawValue }
    var title: String { self == .us ? "US AQI" : "European AQI" }
    var explanation: String {
        self == .us
            ? "US EPA scale, 0–500. Higher is worse."
            : "European scale, 0–100+. Higher is worse."
    }
}

struct AppSettings: Codable, Hashable {
    var temperatureUnit: TemperatureUnit
    var speedUnit: SpeedUnit
    var distanceUnit: DistanceUnit
    var precipitationUnit: PrecipitationUnit
    var aqiStandard: AQIStandard
    var locationPrecision: LocationPrecision
    var backgroundRefreshEnabled: Bool
    var notificationsEnabled: Bool
    var hasCompletedOnboarding: Bool
    var lastRefreshCheck: Date?
    var updatedAt: Date

    static let `default` = AppSettings(
        temperatureUnit: .celsius,
        speedUnit: .kmh,
        distanceUnit: .kilometres,
        precipitationUnit: .millimetres,
        aqiStandard: .us,
        locationPrecision: .neighbourhood,
        backgroundRefreshEnabled: true,
        notificationsEnabled: false,
        hasCompletedOnboarding: false,
        lastRefreshCheck: nil,
        updatedAt: Date()
    )

    /// Converts a canonical (metric) value into the user's chosen unit.
    func display(_ value: Double, for metric: MetricKind) -> Double {
        switch metric {
        case .temperature, .apparentTemperature: return temperatureUnit.fromCanonical(value)
        case .windSpeed, .windGust: return speedUnit.fromCanonical(value)
        case .visibility: return distanceUnit.fromCanonical(value)
        case .precipitationAmount: return precipitationUnit.fromCanonical(value)
        default: return value
        }
    }

    func unitSymbol(for metric: MetricKind) -> String {
        switch metric {
        case .temperature, .apparentTemperature: return temperatureUnit.symbol
        case .windSpeed, .windGust: return speedUnit.symbol
        case .visibility: return distanceUnit.symbol
        case .precipitationAmount: return precipitationUnit.symbol
        default: return metric.canonicalUnit
        }
    }

    /// Formats a value for display, or the explicit unknown marker.
    func format(_ value: Double?, for metric: MetricKind, includeUnit: Bool = true) -> String {
        guard let value = value else { return "Unknown" }
        let converted = display(value, for: metric)
        let text = SkyFormat.number(converted, decimals: metric.decimals)
        return includeUnit ? "\(text) \(unitSymbol(for: metric))" : text
    }
}
