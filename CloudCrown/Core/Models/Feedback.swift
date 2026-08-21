//
//  Feedback.swift
//  CloudCrown
//
//  Feedback never rewrites a forecast. It stores the forecast snapshot the
//  plan relied on alongside the user's real-world assessment.
//

import SwiftUI

enum FeedbackTag: String, Codable, CaseIterable, Identifiable {
    case conditionsMatched, tooHot, tooCold, tooWindy, tooWet, tooBright, airFeltBad, pollenFeltBad, crowded, betterThanExpected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conditionsMatched: return "Conditions Matched"
        case .tooHot: return "Too Hot"
        case .tooCold: return "Too Cold"
        case .tooWindy: return "Too Windy"
        case .tooWet: return "Too Wet"
        case .tooBright: return "Too Bright"
        case .airFeltBad: return "Air Felt Bad"
        case .pollenFeltBad: return "Pollen Felt Bad"
        case .crowded: return "Crowded"
        case .betterThanExpected: return "Better Than Expected"
        }
    }

    var icon: String {
        switch self {
        case .conditionsMatched: return "checkmark.circle"
        case .tooHot: return "thermometer.sun.fill"
        case .tooCold: return "thermometer.snowflake"
        case .tooWindy: return "wind"
        case .tooWet: return "cloud.rain.fill"
        case .tooBright: return "sun.max.fill"
        case .airFeltBad: return "aqi.high"
        case .pollenFeltBad: return "leaf.fill"
        case .crowded: return "person.3.fill"
        case .betterThanExpected: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .conditionsMatched, .betterThanExpected: return SkyPalette.success
        default: return SkyPalette.warning
        }
    }

    /// The metric a mismatch points at, used by Insights to find patterns.
    var relatedMetric: MetricKind? {
        switch self {
        case .tooHot, .tooCold: return .temperature
        case .tooWindy: return .windSpeed
        case .tooWet: return .precipitationProbability
        case .tooBright: return .uvIndex
        case .airFeltBad: return .airQuality
        case .pollenFeltBad: return .pollen
        default: return nil
        }
    }
}

struct FeedbackEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var planID: UUID
    var activityID: UUID
    var placeID: UUID
    /// What the user actually observed, entered by hand. Optional throughout.
    var actualConditions: [MetricSample]
    /// 1...5, nil when the user closed the plan without rating it.
    var comfortRating: Int?
    var wouldRepeat: Bool?
    var tags: [FeedbackTag]
    var note: String
    /// The forecast this plan was built on — preserved, never overwritten.
    var forecastSnapshotID: UUID
    var forecastCapturedAt: Date
    var forecastScore: Double?
    var windowStart: Date
    var windowEnd: Date
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         planID: UUID,
         activityID: UUID,
         placeID: UUID,
         actualConditions: [MetricSample] = [],
         comfortRating: Int? = nil,
         wouldRepeat: Bool? = nil,
         tags: [FeedbackTag] = [],
         note: String = "",
         forecastSnapshotID: UUID,
         forecastCapturedAt: Date,
         forecastScore: Double?,
         windowStart: Date,
         windowEnd: Date,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.planID = planID
        self.activityID = activityID
        self.placeID = placeID
        self.actualConditions = actualConditions
        self.comfortRating = comfortRating
        self.wouldRepeat = wouldRepeat
        self.tags = tags
        self.note = note
        self.forecastSnapshotID = forecastSnapshotID
        self.forecastCapturedAt = forecastCapturedAt
        self.forecastScore = forecastScore
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Rated entries are the only ones that can feed Personal Insights.
    var isRated: Bool { comfortRating != nil }

    var mismatchTags: [FeedbackTag] {
        tags.filter { $0 != .conditionsMatched && $0 != .betterThanExpected }
    }
}

// MARK: - History records

enum HistoryKind: String, Codable, CaseIterable {
    case created, updated, archived, restored, deleted
    case planSaved, planMoved, planKept, planCompleted, planCancelled
    case riskDetected, riskResolved
    case feedbackSaved
    case snapshotRefreshed
    case alertFired, alertSuppressed
    case profileReset, defaultsApplied
    case dataExported, dataDeleted

    var title: String {
        switch self {
        case .created: return "Created"
        case .updated: return "Updated"
        case .archived: return "Archived"
        case .restored: return "Restored"
        case .deleted: return "Deleted"
        case .planSaved: return "Plan saved"
        case .planMoved: return "Plan moved"
        case .planKept: return "Plan kept"
        case .planCompleted: return "Plan completed"
        case .planCancelled: return "Plan cancelled"
        case .riskDetected: return "Risk detected"
        case .riskResolved: return "Risk resolved"
        case .feedbackSaved: return "Feedback saved"
        case .snapshotRefreshed: return "Conditions refreshed"
        case .alertFired: return "Alert sent"
        case .alertSuppressed: return "Alert suppressed"
        case .profileReset: return "Profile reset"
        case .defaultsApplied: return "General defaults applied"
        case .dataExported: return "Data exported"
        case .dataDeleted: return "Data deleted"
        }
    }

    var icon: String {
        switch self {
        case .created: return "plus.circle.fill"
        case .updated: return "pencil.circle.fill"
        case .archived: return "archivebox.fill"
        case .restored: return "arrow.uturn.backward.circle.fill"
        case .deleted: return "trash.fill"
        case .planSaved: return "calendar.badge.plus"
        case .planMoved: return "arrow.left.arrow.right.circle.fill"
        case .planKept: return "hand.raised.fill"
        case .planCompleted: return "checkmark.seal.fill"
        case .planCancelled: return "slash.circle"
        case .riskDetected: return "bolt.trianglebadge.exclamationmark.fill"
        case .riskResolved: return "checkmark.shield.fill"
        case .feedbackSaved: return "star.bubble.fill"
        case .snapshotRefreshed: return "arrow.clockwise.circle.fill"
        case .alertFired: return "bell.fill"
        case .alertSuppressed: return "bell.slash.fill"
        case .profileReset: return "arrow.counterclockwise.circle.fill"
        case .defaultsApplied: return "wand.and.stars"
        case .dataExported: return "square.and.arrow.up.fill"
        case .dataDeleted: return "trash.slash.fill"
        }
    }

    var color: Color {
        switch self {
        case .created, .planSaved, .restored, .riskResolved, .planCompleted: return SkyPalette.success
        case .deleted, .planCancelled, .dataDeleted: return SkyPalette.danger
        case .riskDetected, .alertFired, .alertSuppressed: return SkyPalette.warning
        case .feedbackSaved: return SkyPalette.violet
        default: return SkyPalette.azure
        }
    }
}

enum EntityType: String, Codable {
    case profile, activity, place, plan, alert, feedback, snapshot, settings

    var title: String {
        switch self {
        case .profile: return "Comfort Profile"
        case .activity: return "Activity"
        case .place: return "Place"
        case .plan: return "Plan"
        case .alert: return "Alert Rule"
        case .feedback: return "Feedback"
        case .snapshot: return "Conditions"
        case .settings: return "Settings"
        }
    }
}

/// A readable audit entry. Every mutation in the app writes one of these,
/// which is what makes the sections feel connected rather than separate.
struct HistoryRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var timestamp: Date
    var kind: HistoryKind
    var entityType: EntityType
    var entityID: UUID?
    var title: String
    var detail: String
    /// Human-readable list of what changed, shown after a successful save.
    var changes: [String]

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         kind: HistoryKind,
         entityType: EntityType,
         entityID: UUID? = nil,
         title: String,
         detail: String = "",
         changes: [String] = []) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.entityType = entityType
        self.entityID = entityID
        self.title = title
        self.detail = detail
        self.changes = changes
    }
}
