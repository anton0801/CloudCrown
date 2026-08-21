//
//  ComfortProfile.swift
//  CloudCrown
//
//  The user's personal thresholds. General defaults are explicitly labelled
//  as general — never as medical guidance.
//

import Foundation

enum SensitivityKind: String, Codable, CaseIterable, Identifiable {
    case air, pollen, uv, heat, cold, wind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .air: return "Air quality"
        case .pollen: return "Pollen"
        case .uv: return "UV"
        case .heat: return "Heat"
        case .cold: return "Cold"
        case .wind: return "Wind"
        }
    }

    var icon: String {
        switch self {
        case .air: return "aqi.medium"
        case .pollen: return "leaf.fill"
        case .uv: return "sun.max.fill"
        case .heat: return "thermometer.sun.fill"
        case .cold: return "thermometer.snowflake"
        case .wind: return "wind"
        }
    }
}

enum SensitivityLevel: String, Codable, CaseIterable, Identifiable {
    case notSet, low, normal, high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notSet: return "Not set"
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    /// Multiplier applied to the user's own threshold. Never a medical rule.
    var thresholdMultiplier: Double {
        switch self {
        case .notSet, .normal: return 1.0
        case .low: return 1.2
        case .high: return 0.75
        }
    }
}

struct SensitivityEntry: Codable, Hashable, Identifiable {
    var kind: SensitivityKind
    var level: SensitivityLevel
    var id: String { kind.rawValue }
}

/// A single threshold. `value == nil` means the user has not defined it, which
/// is a distinct state from "zero".
struct ComfortThreshold: Codable, Hashable, Identifiable {
    var metric: MetricKind
    var minValue: Double?
    var maxValue: Double?

    var id: String { metric.rawValue }

    var isDefined: Bool { minValue != nil || maxValue != nil }

    var summary: String {
        switch (minValue, maxValue) {
        case let (min?, max?):
            return "\(SkyFormat.number(min, decimals: metric.decimals))–\(SkyFormat.number(max, decimals: metric.decimals)) \(metric.canonicalUnit)"
        case let (min?, nil):
            return "≥ \(SkyFormat.number(min, decimals: metric.decimals)) \(metric.canonicalUnit)"
        case let (nil, max?):
            return "≤ \(SkyFormat.number(max, decimals: metric.decimals)) \(metric.canonicalUnit)"
        default:
            return "Not set"
        }
    }
}

struct ComfortProfile: Codable, Hashable, Identifiable {
    var id: UUID
    var thresholds: [ComfortThreshold]
    var sensitivities: [SensitivityEntry]
    var usesGeneralDefaults: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         thresholds: [ComfortThreshold] = [],
         sensitivities: [SensitivityEntry] = SensitivityKind.allCases.map { SensitivityEntry(kind: $0, level: .notSet) },
         usesGeneralDefaults: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.thresholds = thresholds
        self.sensitivities = sensitivities
        self.usesGeneralDefaults = usesGeneralDefaults
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func threshold(for metric: MetricKind) -> ComfortThreshold? {
        thresholds.first(where: { $0.metric == metric })
    }

    func level(for kind: SensitivityKind) -> SensitivityLevel {
        sensitivities.first(where: { $0.kind == kind })?.level ?? .notSet
    }

    var definedCount: Int { thresholds.filter(\.isDefined).count }

    /// The profile is usable once the user has defined at least these.
    static let coreMetrics: [MetricKind] = [.temperature, .precipitationProbability, .windSpeed, .uvIndex]

    var isUsable: Bool {
        Self.coreMetrics.allSatisfy { threshold(for: $0)?.isDefined == true }
    }

    var missingCoreMetrics: [MetricKind] {
        Self.coreMetrics.filter { threshold(for: $0)?.isDefined != true }
    }

    /// Effective bound after applying the user's declared sensitivity.
    func effectiveMax(for metric: MetricKind) -> Double? {
        guard let raw = threshold(for: metric)?.maxValue else { return nil }
        guard let kind = Self.sensitivityKind(for: metric) else { return raw }
        return raw * level(for: kind).thresholdMultiplier
    }

    func effectiveMin(for metric: MetricKind) -> Double? {
        guard let raw = threshold(for: metric)?.minValue else { return nil }
        guard metric == .temperature else { return raw }
        // Cold sensitivity raises the acceptable floor.
        let multiplier = level(for: .cold).thresholdMultiplier
        return multiplier == 1.0 ? raw : raw + (1.0 - multiplier) * 10
    }

    static func sensitivityKind(for metric: MetricKind) -> SensitivityKind? {
        switch metric {
        case .airQuality: return .air
        case .pollen: return .pollen
        case .uvIndex: return .uv
        case .temperature, .apparentTemperature: return .heat
        case .windSpeed, .windGust: return .wind
        default: return nil
        }
    }

    /// General starting points — clearly labelled as general, not medical.
    static func generalDefaults() -> ComfortProfile {
        ComfortProfile(
            thresholds: [
                ComfortThreshold(metric: .temperature, minValue: 8, maxValue: 27),
                ComfortThreshold(metric: .apparentTemperature, minValue: 5, maxValue: 29),
                ComfortThreshold(metric: .precipitationProbability, minValue: nil, maxValue: 30),
                ComfortThreshold(metric: .precipitationAmount, minValue: nil, maxValue: 0.5),
                ComfortThreshold(metric: .windSpeed, minValue: nil, maxValue: 25),
                ComfortThreshold(metric: .windGust, minValue: nil, maxValue: 40),
                ComfortThreshold(metric: .uvIndex, minValue: nil, maxValue: 6),
                ComfortThreshold(metric: .airQuality, minValue: nil, maxValue: 100),
                ComfortThreshold(metric: .pollen, minValue: nil, maxValue: 50),
                ComfortThreshold(metric: .visibility, minValue: 2, maxValue: nil)
            ],
            usesGeneralDefaults: true
        )
    }

    static let generalDefaultsDisclaimer =
        "These are general starting points, not medical guidance. Adjust every limit to your own experience."
}
