//
//  Plan.swift
//  CloudCrown
//

import SwiftUI

enum PlanStatus: String, Codable, CaseIterable {
    case scheduled, atRisk, completed, archived, cancelled

    var title: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .atRisk: return "At Risk"
        case .completed: return "Completed"
        case .archived: return "Archived"
        case .cancelled: return "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .scheduled: return SkyPalette.azure
        case .atRisk: return SkyPalette.warning
        case .completed: return SkyPalette.success
        case .archived: return SkyPalette.textTertiary
        case .cancelled: return SkyPalette.textTertiary
        }
    }

    var icon: String {
        switch self {
        case .scheduled: return "calendar"
        case .atRisk: return "bolt.trianglebadge.exclamationmark.fill"
        case .completed: return "checkmark.seal.fill"
        case .archived: return "archivebox.fill"
        case .cancelled: return "slash.circle"
        }
    }
}

enum RiskResolution: String, Codable {
    case kept, movedToBackup, movedToNewWindow, cancelled

    var title: String {
        switch self {
        case .kept: return "Kept original plan"
        case .movedToBackup: return "Moved to backup window"
        case .movedToNewWindow: return "Moved to a new window"
        case .cancelled: return "Plan cancelled"
        }
    }
}

/// Recorded only after two snapshot versions have actually been compared.
struct RiskEvent: Codable, Hashable, Identifiable {
    var id: UUID
    var detectedAt: Date
    var previousSnapshotID: UUID
    var previousCapturedAt: Date
    var newSnapshotID: UUID
    var newCapturedAt: Date
    var brokenRequired: [RuleEvaluation]
    var scoreBefore: Double?
    var scoreAfter: Double?
    var resolution: RiskResolution?
    var resolvedAt: Date?

    var scoreDelta: Double? {
        guard let a = scoreAfter, let b = scoreBefore else { return nil }
        return a - b
    }

    var isResolved: Bool { resolution != nil }

    var summary: String {
        if !brokenRequired.isEmpty {
            let names = brokenRequired.map { $0.rule.metric.title }.joined(separator: ", ")
            return "Required conditions broke: \(names)."
        }
        if let delta = scoreDelta, delta < 0 {
            return "Score dropped by \(Int(abs(delta).rounded())) points."
        }
        return "Forecast changed for this window."
    }
}

struct Plan: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var activityID: UUID
    var placeID: UUID
    /// Frozen at save time — the explanation the user actually agreed to.
    var window: WindowCandidate
    var backupWindow: WindowCandidate?
    var reminderMinutesBefore: Int?
    var reminderNotificationID: String?
    var preparationNotes: String
    /// Only true once EventKit confirmed the save. Never optimistic.
    var calendarEventIdentifier: String?
    var calendarConfirmedAt: Date?
    var status: PlanStatus
    var riskEvents: [RiskEvent]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         title: String,
         activityID: UUID,
         placeID: UUID,
         window: WindowCandidate,
         backupWindow: WindowCandidate? = nil,
         reminderMinutesBefore: Int? = nil,
         reminderNotificationID: String? = nil,
         preparationNotes: String = "",
         calendarEventIdentifier: String? = nil,
         calendarConfirmedAt: Date? = nil,
         status: PlanStatus = .scheduled,
         riskEvents: [RiskEvent] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.activityID = activityID
        self.placeID = placeID
        self.window = window
        self.backupWindow = backupWindow
        self.reminderMinutesBefore = reminderMinutesBefore
        self.reminderNotificationID = reminderNotificationID
        self.preparationNotes = preparationNotes
        self.calendarEventIdentifier = calendarEventIdentifier
        self.calendarConfirmedAt = calendarConfirmedAt
        self.status = status
        self.riskEvents = riskEvents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isCalendarConfirmed: Bool { calendarEventIdentifier != nil && calendarConfirmedAt != nil }

    var openRisks: [RiskEvent] { riskEvents.filter { !$0.isResolved } }
    var hasOpenRisk: Bool { !openRisks.isEmpty }

    var isPast: Bool { window.end < Date() }

    /// A plan awaiting feedback: finished but not yet reviewed.
    func awaitsFeedback(hasFeedback: Bool) -> Bool {
        isPast && !hasFeedback && (status == .scheduled || status == .atRisk || status == .completed)
    }

    var timeZone: TimeZone { window.timeZone }
}
