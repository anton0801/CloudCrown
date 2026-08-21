//
//  ActivityTemplate.swift
//  CloudCrown
//
//  Required conditions block a window outright; preferred conditions only
//  shape the score, and their weights must total 100%.
//

import SwiftUI

enum ActivityKind: String, Codable, CaseIterable, Identifiable {
    case walking, running, photography, outdoorWork, plantCare, commute, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walking: return "Walking"
        case .running: return "Running"
        case .photography: return "Photography"
        case .outdoorWork: return "Outdoor Work"
        case .plantCare: return "Plant Care"
        case .commute: return "Commute"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .photography: return "camera.fill"
        case .outdoorWork: return "hammer.fill"
        case .plantCare: return "leaf.fill"
        case .commute: return "bicycle"
        case .custom: return "slider.horizontal.3"
        }
    }

    var accent: Color {
        switch self {
        case .walking: return SkyPalette.azure
        case .running: return Color(hex: 0xE0623D)
        case .photography: return SkyPalette.violet
        case .outdoorWork: return SkyPalette.gold
        case .plantCare: return SkyPalette.success
        case .commute: return SkyPalette.lightBlue
        case .custom: return SkyPalette.textSecondary
        }
    }

    var defaultDurationMinutes: Int {
        switch self {
        case .walking: return 60
        case .running: return 45
        case .photography: return 90
        case .outdoorWork: return 120
        case .plantCare: return 30
        case .commute: return 30
        case .custom: return 60
        }
    }

    /// Starting suggestions the user can accept or change — never applied silently.
    var suggestedRequiredMetrics: [MetricKind] {
        switch self {
        case .walking: return [.precipitationProbability, .windSpeed]
        case .running: return [.temperature, .airQuality, .precipitationProbability]
        case .photography: return [.precipitationProbability, .visibility]
        case .outdoorWork: return [.uvIndex, .windGust, .precipitationProbability]
        case .plantCare: return [.temperature, .windSpeed]
        case .commute: return [.precipitationAmount, .windGust]
        case .custom: return []
        }
    }

    var suggestedPreferredMetrics: [MetricKind] {
        switch self {
        case .walking: return [.temperature, .uvIndex, .airQuality]
        case .running: return [.apparentTemperature, .humidity, .windSpeed]
        case .photography: return [.cloudCover, .visibility, .windSpeed]
        case .outdoorWork: return [.temperature, .humidity]
        case .plantCare: return [.uvIndex, .precipitationProbability]
        case .commute: return [.temperature, .windSpeed]
        case .custom: return []
        }
    }
}

enum Comparison: String, Codable, CaseIterable, Identifiable {
    case atMost, atLeast, between

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atMost: return "At most"
        case .atLeast: return "At least"
        case .between: return "Between"
        }
    }

    var symbol: String {
        switch self {
        case .atMost: return "≤"
        case .atLeast: return "≥"
        case .between: return "↔"
        }
    }
}

/// A hard constraint. If it fails, the window cannot be recommended.
struct ConditionRule: Codable, Hashable, Identifiable {
    var id: UUID
    var metric: MetricKind
    var comparison: Comparison
    var value: Double
    var upperValue: Double?

    init(id: UUID = UUID(), metric: MetricKind, comparison: Comparison, value: Double, upperValue: Double? = nil) {
        self.id = id
        self.metric = metric
        self.comparison = comparison
        self.value = value
        self.upperValue = upperValue
    }

    var summary: String {
        let unit = metric.canonicalUnit
        let d = metric.decimals
        switch comparison {
        case .atMost: return "\(metric.title) ≤ \(SkyFormat.number(value, decimals: d)) \(unit)"
        case .atLeast: return "\(metric.title) ≥ \(SkyFormat.number(value, decimals: d)) \(unit)"
        case .between:
            let upper = upperValue ?? value
            return "\(metric.title) \(SkyFormat.number(value, decimals: d))–\(SkyFormat.number(upper, decimals: d)) \(unit)"
        }
    }

    /// Evaluates a concrete measurement. Unknown input yields `.unknown`,
    /// never a silent pass.
    func evaluate(_ measured: Double?) -> RuleOutcome {
        guard let m = measured else { return .unknown }
        switch comparison {
        case .atMost: return m <= value ? .pass : .fail
        case .atLeast: return m >= value ? .pass : .fail
        case .between:
            let upper = upperValue ?? value
            return (m >= value && m <= upper) ? .pass : .fail
        }
    }
}

enum PreferenceDirection: String, Codable, CaseIterable, Identifiable {
    case lower, higher, target

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lower: return "Prefer lower"
        case .higher: return "Prefer higher"
        case .target: return "Prefer near target"
        }
    }
}

/// A soft preference. Contributes `weight`% of the total score.
struct PreferredRule: Codable, Hashable, Identifiable {
    var id: UUID
    var metric: MetricKind
    var direction: PreferenceDirection
    var target: Double?
    var weight: Int

    init(id: UUID = UUID(), metric: MetricKind, direction: PreferenceDirection, target: Double? = nil, weight: Int) {
        self.id = id
        self.metric = metric
        self.direction = direction
        self.target = target
        self.weight = weight
    }

    var summary: String {
        switch direction {
        case .lower: return "Lower \(metric.title.lowercased()) is better"
        case .higher: return "Higher \(metric.title.lowercased()) is better"
        case .target:
            let t = SkyFormat.number(target ?? 0, decimals: metric.decimals)
            return "\(metric.title) near \(t) \(metric.canonicalUnit)"
        }
    }

    /// Returns 0...1 satisfaction, or nil when the measurement is unknown.
    func satisfaction(_ measured: Double?) -> Double? {
        guard let m = measured else { return nil }
        let range = metric.uiRange
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return nil }
        let clamped = min(range.upperBound, max(range.lowerBound, m))
        switch direction {
        case .lower:
            return 1 - (clamped - range.lowerBound) / span
        case .higher:
            return (clamped - range.lowerBound) / span
        case .target:
            guard let target = target else { return nil }
            let distance = abs(clamped - target)
            // Full credit within 10% of the range, decaying to zero at 50%.
            let normalized = distance / span
            if normalized <= 0.10 { return 1 }
            if normalized >= 0.50 { return 0 }
            return 1 - (normalized - 0.10) / 0.40
        }
    }
}

struct ActivityTemplate: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var kind: ActivityKind
    var requiredConditions: [ConditionRule]
    var preferredConditions: [PreferredRule]
    var durationMinutes: Int
    var earliestMinute: Int      // minutes from midnight
    var latestMinute: Int
    var requiresDaylight: Bool
    var note: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         name: String,
         kind: ActivityKind,
         requiredConditions: [ConditionRule] = [],
         preferredConditions: [PreferredRule] = [],
         durationMinutes: Int = 60,
         earliestMinute: Int = 6 * 60,
         latestMinute: Int = 21 * 60,
         requiresDaylight: Bool = false,
         note: String = "",
         isArchived: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.requiredConditions = requiredConditions
        self.preferredConditions = preferredConditions
        self.durationMinutes = durationMinutes
        self.earliestMinute = earliestMinute
        self.latestMinute = latestMinute
        self.requiresDaylight = requiresDaylight
        self.note = note
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var totalWeight: Int { preferredConditions.reduce(0) { $0 + $1.weight } }
    var weightRemaining: Int { 100 - totalWeight }
    var weightIsValid: Bool { preferredConditions.isEmpty || totalWeight == 100 }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && durationMinutes > 0
            && latestMinute > earliestMinute
            && weightIsValid
    }

    /// Metrics this template needs in order to be evaluated at all.
    var requiredMetrics: [MetricKind] {
        Array(Set(requiredConditions.map(\.metric))).sorted { $0.rawValue < $1.rawValue }
    }

    var allMetrics: [MetricKind] {
        Array(Set(requiredConditions.map(\.metric) + preferredConditions.map(\.metric)))
            .sorted { $0.rawValue < $1.rawValue }
    }
}
