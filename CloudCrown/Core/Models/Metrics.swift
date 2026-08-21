//
//  Metrics.swift
//  CloudCrown
//
//  The measurable dimensions the app reasons about, and the envelope that
//  carries a value together with its unit, origin, freshness and confidence.
//

import SwiftUI

// MARK: - Metric kinds

enum MetricKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case temperature
    case apparentTemperature
    case precipitationProbability
    case precipitationAmount
    case windSpeed
    case windGust
    case uvIndex
    case airQuality
    case pollen
    case visibility
    case humidity
    case cloudCover
    case daylight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperature: return "Temperature"
        case .apparentTemperature: return "Feels like"
        case .precipitationProbability: return "Rain chance"
        case .precipitationAmount: return "Rain amount"
        case .windSpeed: return "Wind"
        case .windGust: return "Gusts"
        case .uvIndex: return "UV index"
        case .airQuality: return "Air quality"
        case .pollen: return "Pollen"
        case .visibility: return "Visibility"
        case .humidity: return "Humidity"
        case .cloudCover: return "Cloud cover"
        case .daylight: return "Daylight"
        }
    }

    var shortTitle: String {
        switch self {
        case .apparentTemperature: return "Feels"
        case .precipitationProbability: return "Rain %"
        case .precipitationAmount: return "Rain mm"
        case .windGust: return "Gust"
        case .airQuality: return "AQI"
        case .cloudCover: return "Cloud"
        default: return title
        }
    }

    var icon: String {
        switch self {
        case .temperature: return "thermometer"
        case .apparentTemperature: return "thermometer.sun"
        case .precipitationProbability: return "umbrella"
        case .precipitationAmount: return "drop.fill"
        case .windSpeed: return "wind"
        case .windGust: return "wind.circle"
        case .uvIndex: return "sun.max.fill"
        case .airQuality: return "aqi.medium"
        case .pollen: return "leaf.fill"
        case .visibility: return "eye"
        case .humidity: return "humidity"
        case .cloudCover: return "cloud.fill"
        case .daylight: return "sunrise.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .temperature, .apparentTemperature: return Color(hex: 0xE0623D)
        case .precipitationProbability, .precipitationAmount: return SkyPalette.azure
        case .windSpeed, .windGust: return SkyPalette.lightBlue
        case .uvIndex: return SkyPalette.gold
        case .airQuality: return SkyPalette.violet
        case .pollen: return SkyPalette.success
        case .visibility: return Color(hex: 0x4A9AD4)
        case .humidity: return Color(hex: 0x2FB0C8)
        case .cloudCover: return SkyPalette.textTertiary
        case .daylight: return Color(hex: 0xF0A32C)
        }
    }

    /// Canonical storage unit. Display units are converted at presentation time.
    var canonicalUnit: String {
        switch self {
        case .temperature, .apparentTemperature: return "°C"
        case .precipitationProbability, .humidity, .cloudCover: return "%"
        case .precipitationAmount: return "mm"
        case .windSpeed, .windGust: return "km/h"
        case .uvIndex: return "index"
        case .airQuality: return "AQI"
        case .pollen: return "grains/m³"
        case .visibility: return "km"
        case .daylight: return "min"
        }
    }

    /// Sensible bounds for dials and normalisation.
    var uiRange: ClosedRange<Double> {
        switch self {
        case .temperature, .apparentTemperature: return -30...45
        case .precipitationProbability, .humidity, .cloudCover: return 0...100
        case .precipitationAmount: return 0...20
        case .windSpeed: return 0...80
        case .windGust: return 0...120
        case .uvIndex: return 0...12
        case .airQuality: return 0...300
        case .pollen: return 0...150
        case .visibility: return 0...30
        case .daylight: return 0...1440
        }
    }

    var decimals: Int {
        switch self {
        case .precipitationAmount, .uvIndex, .visibility: return 1
        default: return 0
        }
    }

    /// For most metrics "less is better"; for a few, more is better.
    var higherIsBetter: Bool {
        switch self {
        case .visibility, .daylight: return true
        default: return false
        }
    }

    /// Metrics the user typically constrains in an activity template.
    static var constrainable: [MetricKind] {
        [.temperature, .apparentTemperature, .precipitationProbability, .precipitationAmount,
         .windSpeed, .windGust, .uvIndex, .airQuality, .pollen, .visibility, .cloudCover, .humidity]
    }
}

// MARK: - Confidence

enum Confidence: String, Codable, CaseIterable {
    case high, medium, low, unknown

    var label: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        case .unknown: return "Confidence unknown"
        }
    }

    var shortLabel: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .high: return SkyPalette.success
        case .medium: return SkyPalette.warning
        case .low: return SkyPalette.danger
        case .unknown: return SkyPalette.unknown
        }
    }

    /// Forecast confidence decays with lead time. This is an explicit,
    /// documented assumption — surfaced to the user, never hidden.
    static func forForecast(leadTime: TimeInterval) -> Confidence {
        let hours = leadTime / 3600
        switch hours {
        case ..<24: return .high
        case ..<72: return .medium
        default: return .low
        }
    }
}

enum ObservationKind: String, Codable {
    case observed
    case forecast

    var label: String { self == .observed ? "Observed" : "Forecast" }
    var icon: String { self == .observed ? "dot.radiowaves.up.forward" : "chart.line.uptrend.xyaxis" }
}

// MARK: - Data source

struct DataSource: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var attribution: String
    var url: String
    var fetchedAt: Date

    static func openMeteoForecast(fetchedAt: Date) -> DataSource {
        DataSource(id: "open-meteo-forecast",
                   name: "Open-Meteo Forecast",
                   attribution: "Open-Meteo.com, CC BY 4.0",
                   url: "https://open-meteo.com/",
                   fetchedAt: fetchedAt)
    }

    static func openMeteoAir(fetchedAt: Date) -> DataSource {
        DataSource(id: "open-meteo-air-quality",
                   name: "Open-Meteo Air Quality",
                   attribution: "Open-Meteo.com / CAMS, CC BY 4.0",
                   url: "https://open-meteo.com/en/docs/air-quality-api",
                   fetchedAt: fetchedAt)
    }

    static func openMeteoGeocoding(fetchedAt: Date) -> DataSource {
        DataSource(id: "open-meteo-geocoding",
                   name: "Open-Meteo Geocoding",
                   attribution: "Open-Meteo.com, CC BY 4.0",
                   url: "https://open-meteo.com/en/docs/geocoding-api",
                   fetchedAt: fetchedAt)
    }

    static func device(_ name: String, fetchedAt: Date) -> DataSource {
        DataSource(id: "device-\(name.lowercased())",
                   name: name,
                   attribution: "On-device",
                   url: "",
                   fetchedAt: fetchedAt)
    }
}

// MARK: - Metric value envelope

/// A single measurement. `value == nil` means genuinely unknown — it is never
/// substituted with zero anywhere in the app.
struct MetricValue: Codable, Hashable {
    var value: Double?
    var unit: String
    var observation: ObservationKind
    var updatedAt: Date
    var confidence: Confidence
    var sourceID: String

    var isKnown: Bool { value != nil }

    static func unknown(unit: String, sourceID: String, updatedAt: Date = Date()) -> MetricValue {
        MetricValue(value: nil, unit: unit, observation: .forecast,
                    updatedAt: updatedAt, confidence: .unknown, sourceID: sourceID)
    }
}

struct MetricSample: Codable, Hashable, Identifiable {
    var kind: MetricKind
    var value: MetricValue
    var id: String { kind.rawValue }
}
