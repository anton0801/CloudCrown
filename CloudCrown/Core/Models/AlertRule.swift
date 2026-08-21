//
//  AlertRule.swift
//  CloudCrown
//

import SwiftUI

enum AlertKind: String, Codable, CaseIterable, Identifiable {
    case windowAppears, planDegrades, metricThreshold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowAppears: return "A good window appears"
        case .planDegrades: return "A saved plan gets worse"
        case .metricThreshold: return "A condition crosses my threshold"
        }
    }

    var shortTitle: String {
        switch self {
        case .windowAppears: return "Window found"
        case .planDegrades: return "Plan at risk"
        case .metricThreshold: return "Threshold"
        }
    }

    var icon: String {
        switch self {
        case .windowAppears: return "sparkles"
        case .planDegrades: return "bolt.trianglebadge.exclamationmark.fill"
        case .metricThreshold: return "gauge.with.dots.needle.33percent"
        }
    }

    var color: Color {
        switch self {
        case .windowAppears: return SkyPalette.success
        case .planDegrades: return SkyPalette.warning
        case .metricThreshold: return SkyPalette.violet
        }
    }

    var explanation: String {
        switch self {
        case .windowAppears:
            return "Checks the chosen activity at the chosen place and notifies you when a window that meets all required conditions appears."
        case .planDegrades:
            return "Compares each new forecast snapshot with the one your plan was saved from, and notifies you only when a required condition breaks or the score drops sharply."
        case .metricThreshold:
            return "Notifies you when a single measurement crosses the threshold you set — for example UV above 6."
        }
    }
}

struct QuietHours: Codable, Hashable {
    var isEnabled: Bool
    var startMinute: Int   // minutes from midnight
    var endMinute: Int

    static let `default` = QuietHours(isEnabled: true, startMinute: 22 * 60, endMinute: 7 * 60)

    /// Handles ranges that wrap past midnight.
    func contains(minuteOfDay: Int) -> Bool {
        guard isEnabled else { return false }
        if startMinute <= endMinute {
            return minuteOfDay >= startMinute && minuteOfDay < endMinute
        }
        return minuteOfDay >= startMinute || minuteOfDay < endMinute
    }

    var summary: String {
        guard isEnabled else { return "Off" }
        return "\(QuietHours.text(startMinute)) – \(QuietHours.text(endMinute))"
    }

    static func text(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

struct AlertRule: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var kind: AlertKind
    var placeID: UUID
    var activityID: UUID?
    var metric: MetricKind?
    var comparison: Comparison
    var threshold: Double?
    /// Days ahead the rule looks at.
    var horizonDays: Int
    var quietHours: QuietHours
    var cooldownMinutes: Int
    var isPaused: Bool
    var lastFiredAt: Date?
    /// Deduplication key of the last delivered notification.
    var lastFingerprint: String?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         name: String,
         kind: AlertKind,
         placeID: UUID,
         activityID: UUID? = nil,
         metric: MetricKind? = nil,
         comparison: Comparison = .atMost,
         threshold: Double? = nil,
         horizonDays: Int = 3,
         quietHours: QuietHours = .default,
         cooldownMinutes: Int = 360,
         isPaused: Bool = false,
         lastFiredAt: Date? = nil,
         lastFingerprint: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.placeID = placeID
        self.activityID = activityID
        self.metric = metric
        self.comparison = comparison
        self.threshold = threshold
        self.horizonDays = horizonDays
        self.quietHours = quietHours
        self.cooldownMinutes = cooldownMinutes
        self.isPaused = isPaused
        self.lastFiredAt = lastFiredAt
        self.lastFingerprint = lastFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// A rule cannot exist without a place, a period and a threshold/target.
    var validationErrors: [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Give the rule a name so you can recognise it later.")
        }
        if horizonDays < 1 || horizonDays > 7 {
            errors.append("The period must be between 1 and 7 days.")
        }
        switch kind {
        case .metricThreshold:
            if metric == nil { errors.append("Choose which condition to watch.") }
            if threshold == nil { errors.append("Set the threshold value.") }
        case .windowAppears:
            if activityID == nil { errors.append("Choose the activity whose required conditions define the window.") }
        case .planDegrades:
            break
        }
        return errors
    }

    var isValid: Bool { validationErrors.isEmpty }

    var summary: String {
        switch kind {
        case .windowAppears:
            return "When a window meeting all required conditions appears within \(horizonDays) day\(horizonDays == 1 ? "" : "s")."
        case .planDegrades:
            return "When a saved plan's required conditions break or its score drops."
        case .metricThreshold:
            guard let metric = metric, let threshold = threshold else { return "Incomplete rule." }
            return "When \(metric.title.lowercased()) is \(comparison.symbol) \(SkyFormat.number(threshold, decimals: metric.decimals)) \(metric.canonicalUnit) within \(horizonDays) day\(horizonDays == 1 ? "" : "s")."
        }
    }

    func isInCooldown(now: Date = Date()) -> Bool {
        guard let last = lastFiredAt else { return false }
        return now.timeIntervalSince(last) < Double(cooldownMinutes) * 60
    }

    var cooldownSummary: String {
        cooldownMinutes % 60 == 0 ? "\(cooldownMinutes / 60) h" : "\(cooldownMinutes) min"
    }
}

/// A delivered notification, kept so History can explain what fired and why.
struct AlertEvent: Codable, Hashable, Identifiable {
    var id: UUID
    var ruleID: UUID
    var ruleName: String
    var firedAt: Date
    var title: String
    var body: String
    var fingerprint: String
    var snapshotID: UUID?
    var wasSuppressed: Bool
    var suppressionReason: String?
}
