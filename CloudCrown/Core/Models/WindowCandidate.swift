//
//  WindowCandidate.swift
//  CloudCrown
//
//  A concrete time interval evaluated against one activity template.
//  Every candidate carries the inputs it was derived from so the score can be
//  reproduced (rulesVersion + snapshotID) and later marked Superseded.
//

import SwiftUI

enum RuleOutcome: String, Codable {
    case pass, fail, unknown

    var title: String {
        switch self {
        case .pass: return "Meets"
        case .fail: return "Does not meet"
        case .unknown: return "Needs verification"
        }
    }

    var icon: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pass: return SkyPalette.success
        case .fail: return SkyPalette.danger
        case .unknown: return SkyPalette.unknown
        }
    }
}

/// Result of one required rule against the aggregated window measurement.
struct RuleEvaluation: Codable, Hashable, Identifiable {
    var id: UUID
    var rule: ConditionRule
    var outcome: RuleOutcome
    /// The aggregated value actually compared (worst case inside the window).
    var measuredValue: Double?
    /// When and where that value came from.
    var measuredAt: Date?
    var observation: ObservationKind?
    var confidence: Confidence
    var sourceID: String?

    init(id: UUID = UUID(),
         rule: ConditionRule,
         outcome: RuleOutcome,
         measuredValue: Double?,
         measuredAt: Date? = nil,
         observation: ObservationKind? = nil,
         confidence: Confidence = .unknown,
         sourceID: String? = nil) {
        self.id = id
        self.rule = rule
        self.outcome = outcome
        self.measuredValue = measuredValue
        self.measuredAt = measuredAt
        self.observation = observation
        self.confidence = confidence
        self.sourceID = sourceID
    }

    var readableMeasurement: String {
        guard let v = measuredValue else { return "Unknown" }
        return "\(SkyFormat.number(v, decimals: rule.metric.decimals)) \(rule.metric.canonicalUnit)"
    }

    /// Plain-language reason, always naming the raw figure behind the verdict.
    var reason: String {
        switch outcome {
        case .pass:
            return "\(rule.metric.title) is \(readableMeasurement), within your limit of \(rule.summary.replacingOccurrences(of: "\(rule.metric.title) ", with: ""))."
        case .fail:
            return "\(rule.metric.title) reaches \(readableMeasurement) inside this window, breaking \(rule.summary)."
        case .unknown:
            return "\(rule.metric.title) is not available for this window, so this requirement could not be checked."
        }
    }
}

/// Result of one preferred rule, including its contribution to the score.
struct PreferredEvaluation: Codable, Hashable, Identifiable {
    var id: UUID
    var rule: PreferredRule
    var measuredValue: Double?
    var satisfaction: Double?     // 0...1, nil when unknown
    var pointsEarned: Double      // 0...weight
    var confidence: Confidence
    var sourceID: String?

    init(id: UUID = UUID(),
         rule: PreferredRule,
         measuredValue: Double?,
         satisfaction: Double?,
         pointsEarned: Double,
         confidence: Confidence = .unknown,
         sourceID: String? = nil) {
        self.id = id
        self.rule = rule
        self.measuredValue = measuredValue
        self.satisfaction = satisfaction
        self.pointsEarned = pointsEarned
        self.confidence = confidence
        self.sourceID = sourceID
    }

    var readableMeasurement: String {
        guard let v = measuredValue else { return "Unknown" }
        return "\(SkyFormat.number(v, decimals: rule.metric.decimals)) \(rule.metric.canonicalUnit)"
    }

    var reason: String {
        guard let s = satisfaction else {
            return "\(rule.metric.title) is unknown, so it contributed 0 of \(rule.weight) points."
        }
        return "\(rule.metric.title) at \(readableMeasurement) satisfies this preference \(SkyFormat.percent(s)), contributing \(String(format: "%.1f", pointsEarned)) of \(rule.weight) points."
    }
}

enum WindowVerdict: String, Codable {
    case bestMatch, acceptable, notRecommended, needsVerification

    var title: String {
        switch self {
        case .bestMatch: return "Best Match"
        case .acceptable: return "Acceptable"
        case .notRecommended: return "Not Recommended"
        case .needsVerification: return "Needs Verification"
        }
    }

    var icon: String {
        switch self {
        case .bestMatch: return "crown.fill"
        case .acceptable: return "checkmark"
        case .notRecommended: return "xmark"
        case .needsVerification: return "questionmark"
        }
    }

    var color: Color {
        switch self {
        case .bestMatch: return SkyPalette.verdictBest
        case .acceptable: return SkyPalette.verdictAcceptable
        case .notRecommended: return SkyPalette.verdictNotRecommended
        case .needsVerification: return SkyPalette.verdictUnknown
        }
    }

    var isUsable: Bool { self == .bestMatch || self == .acceptable }
}

struct WindowCandidate: Codable, Hashable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    var placeID: UUID
    var activityID: UUID
    var verdict: WindowVerdict
    /// 0...100 from preferred rules only. nil when nothing could be scored.
    var score: Double?
    var requiredResults: [RuleEvaluation]
    var preferredResults: [PreferredEvaluation]
    /// 0...1, higher means less variation inside the window.
    var stability: Double?
    /// 0...1 fraction of needed metrics that were actually available.
    var completeness: Double
    var missingMetrics: [MetricKind]
    var rulesVersion: String
    var snapshotID: UUID
    var snapshotCapturedAt: Date
    var evaluatedAt: Date
    var timeZoneIdentifier: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }

    var failedRequired: [RuleEvaluation] { requiredResults.filter { $0.outcome == .fail } }
    var unknownRequired: [RuleEvaluation] { requiredResults.filter { $0.outcome == .unknown } }
    var passedRequired: [RuleEvaluation] { requiredResults.filter { $0.outcome == .pass } }

    var isComplete: Bool { completeness >= 0.999 }

    func timeRangeText() -> String {
        SkyFormat.range(start, end, timeZone: timeZone)
    }

    func dayText() -> String {
        SkyFormat.dayShort(start, timeZone: timeZone)
    }

    /// One-line headline reason, used in lists and notifications.
    var headline: String {
        switch verdict {
        case .bestMatch:
            return "All required conditions met with the strongest score in range."
        case .acceptable:
            return "All required conditions met."
        case .notRecommended:
            let names = failedRequired.map { $0.rule.metric.title }
            if names.isEmpty { return "Below your preferred conditions." }
            return "Blocked by \(names.joined(separator: ", "))."
        case .needsVerification:
            let names = unknownRequired.map { $0.rule.metric.title }
            return "Missing data for \(names.joined(separator: ", "))."
        }
    }
}

/// Search parameters used by Window Finder — kept so a result set can be re-run.
struct WindowQuery: Codable, Hashable {
    var activityID: UUID
    var placeID: UUID
    var startDate: Date
    var endDate: Date
    var earliestMinute: Int
    var latestMinute: Int
    var durationMinutes: Int

    var isValid: Bool {
        endDate >= startDate && latestMinute - earliestMinute >= durationMinutes && durationMinutes > 0
    }

    var validationMessage: String? {
        if endDate < startDate { return "The end date must be on or after the start date." }
        if durationMinutes <= 0 { return "Duration must be at least 15 minutes." }
        if latestMinute - earliestMinute < durationMinutes {
            return "The time range is shorter than the duration you asked for."
        }
        return nil
    }
}

/// The full outcome of one Window Finder run.
struct WindowSearchResult: Codable, Hashable, Identifiable {
    var id: UUID
    var query: WindowQuery
    var candidates: [WindowCandidate]
    /// Present when nothing qualified: the least-bad interval and what broke.
    var closestAlternative: WindowCandidate?
    var rulesVersion: String
    var snapshotID: UUID
    var snapshotCapturedAt: Date
    var evaluatedAt: Date
    var usedCachedSnapshot: Bool

    var best: [WindowCandidate] { candidates.filter { $0.verdict == .bestMatch } }
    var acceptable: [WindowCandidate] { candidates.filter { $0.verdict == .acceptable } }
    var notRecommended: [WindowCandidate] { candidates.filter { $0.verdict == .notRecommended } }
    var needsVerification: [WindowCandidate] { candidates.filter { $0.verdict == .needsVerification } }

    var hasUsableWindow: Bool { !best.isEmpty || !acceptable.isEmpty }
}
