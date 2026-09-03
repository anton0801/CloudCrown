//
//  SyncModels.swift
//  CloudCrown
//

import Foundation

/// Marks a record deleted locally so the deletion can reach the server, and
/// other devices, instead of the record simply reappearing on the next pull.
struct Tombstone: Codable, Hashable, Identifiable {
    var entityType: EntityType
    var entityID: UUID
    var deletedAt: Date

    var id: String { "\(entityType.rawValue)-\(entityID.uuidString)" }
}

struct SyncState: Codable, Equatable {
    /// Server clock at the end of the last successful sync.
    var lastSyncedAt: Date?
    var lastSuccessAt: Date?
    var lastError: String?
    /// The account the local data currently belongs to.
    var ownerUserID: String?

    static let empty = SyncState()
}

/// Everything the client sends up. History and condition snapshots are not
/// synced: history is a local audit log and snapshots are re-fetchable data.
struct SyncPushRequest: Encodable {
    let clientTime: Date
    let profile: ComfortProfile?
    let places: [Place]
    let activities: [ActivityTemplate]
    let plans: [Plan]
    let alerts: [AlertRule]
    let feedback: [FeedbackEntry]
    let tombstones: [Tombstone]

    var isEmpty: Bool {
        profile == nil && places.isEmpty && activities.isEmpty && plans.isEmpty
            && alerts.isEmpty && feedback.isEmpty && tombstones.isEmpty
    }

    var totalCount: Int {
        (profile == nil ? 0 : 1) + places.count + activities.count
            + plans.count + alerts.count + feedback.count + tombstones.count
    }
}

struct SyncPullResponse: Decodable {
    let serverTime: Date
    let profile: ComfortProfile?
    let places: [Place]
    let activities: [ActivityTemplate]
    let plans: [Plan]
    let alerts: [AlertRule]
    let feedback: [FeedbackEntry]
    let tombstones: [Tombstone]

    var totalCount: Int {
        (profile == nil ? 0 : 1) + places.count + activities.count
            + plans.count + alerts.count + feedback.count + tombstones.count
    }
}

struct SyncPushResponse: Decodable {
    let serverTime: Date
    let accepted: Int?
}

/// What the client holds that is newer than the last successful sync.
struct LocalChanges {
    var profile: ComfortProfile?
    var places: [Place] = []
    var activities: [ActivityTemplate] = []
    var plans: [Plan] = []
    var alerts: [AlertRule] = []
    var feedback: [FeedbackEntry] = []
    var tombstones: [Tombstone] = []

    var isEmpty: Bool {
        profile == nil && places.isEmpty && activities.isEmpty && plans.isEmpty
            && alerts.isEmpty && feedback.isEmpty && tombstones.isEmpty
    }
}

/// Result of merging a pull into local storage.
struct MergeReport: Equatable {
    var updated: Int = 0
    var deleted: Int = 0
    var keptLocal: Int = 0

    var isEmpty: Bool { updated == 0 && deleted == 0 }

    var summary: String {
        var parts: [String] = []
        if updated > 0 { parts.append("\(updated) updated") }
        if deleted > 0 { parts.append("\(deleted) removed") }
        if keptLocal > 0 { parts.append("\(keptLocal) kept from this device") }
        return parts.isEmpty ? "Already up to date" : parts.joined(separator: ", ")
    }
}
