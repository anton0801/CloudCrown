//
//  DataRepository.swift
//  CloudCrown
//
//  The single source of truth. Every section reads from these collections, so
//  changing an entity in one place recomputes dependents everywhere and writes
//  one readable history record — never a parallel copy of the same data.
//

import SwiftUI
import Combine

/// Consequences of removing an entity, listed before anything is destroyed.
struct DeletionImpact {
    struct Dependent: Identifiable {
        let id: UUID
        let type: EntityType
        let title: String
        let detail: String
    }

    let entityType: EntityType
    let entityTitle: String
    let dependents: [Dependent]
    /// True when deletion is allowed at all.
    let canDelete: Bool
    let blockingReason: String?

    var isEmpty: Bool { dependents.isEmpty }

    var summary: String {
        if dependents.isEmpty {
            return "Nothing else references this \(entityType.title.lowercased())."
        }
        var counts: [EntityType: Int] = [:]
        for d in dependents { counts[d.type, default: 0] += 1 }
        let parts = counts.map { "\($0.value) \($0.key.title.lowercased())\($0.value == 1 ? "" : "s")" }
        return "This will affect \(parts.sorted().joined(separator: ", "))."
    }
}

/// The result of a persisted mutation. `.failure` means nothing was written
/// and the in-memory state was rolled back, so no screen may report success.
enum SaveOutcome: Equatable {
    case success(changes: [String])
    case failure(message: String)

    var isSuccess: Bool { if case .success = self { return true }; return false }
    var changes: [String] { if case .success(let c) = self { return c }; return [] }
    var errorMessage: String? { if case .failure(let m) = self { return m }; return nil }
}

enum DeletionStrategy {
    case cancel
    case archive
    /// Removes the entity and safely detaches dependents (archiving them).
    case deleteAndDetach
}

@MainActor
final class DataRepository: ObservableObject {

    // MARK: - Published state

    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var profile: ComfortProfile?
    @Published private(set) var activities: [ActivityTemplate] = []
    @Published private(set) var places: [Place] = []
    @Published private(set) var plans: [Plan] = []
    @Published private(set) var alerts: [AlertRule] = []
    @Published private(set) var alertEvents: [AlertEvent] = []
    @Published private(set) var feedback: [FeedbackEntry] = []
    @Published private(set) var history: [HistoryRecord] = []
    /// Most recent snapshot per place id.
    @Published private(set) var snapshots: [UUID: ConditionSnapshot] = [:]
    @Published private(set) var lastStoreError: String?

    private let store: LocalStoring
    private var drafts: [String: Data] = [:]
    /// Cancels a plan's system reminder when the plan stops being actionable.
    private weak var notificationCanceller: PlanNotificationCancelling?

    init(store: LocalStoring) {
        self.store = store
        loadAll()
    }

    func attach(notificationCanceller: PlanNotificationCancelling) {
        self.notificationCanceller = notificationCanceller
    }

    /// Cancels the system reminder belonging to a plan, so no notification
    /// outlives the plan that justified it.
    private func cancelReminder(for plan: Plan) {
        if let identifier = plan.reminderNotificationID {
            notificationCanceller?.cancel(identifier: identifier)
        }
        notificationCanceller?.cancel(identifier: "plan-\(plan.id.uuidString)")
    }

    // MARK: - Loading

    private func loadAll() {
        do {
            settings = try store.load(AppSettings.self, from: .settings) ?? .default
            profile = try store.load(ComfortProfile.self, from: .profile)
            activities = try store.load([ActivityTemplate].self, from: .activities) ?? []
            places = try store.load([Place].self, from: .places) ?? []
            plans = try store.load([Plan].self, from: .plans) ?? []
            alerts = try store.load([AlertRule].self, from: .alerts) ?? []
            alertEvents = try store.load([AlertEvent].self, from: .alertEvents) ?? []
            feedback = try store.load([FeedbackEntry].self, from: .feedback) ?? []
            history = try store.load([HistoryRecord].self, from: .history) ?? []
            let stored = try store.load([ConditionSnapshot].self, from: .snapshots) ?? []
            snapshots = Dictionary(uniqueKeysWithValues: stored.map { ($0.placeID, $0) })
            drafts = try store.load([String: Data].self, from: .drafts) ?? [:]
        } catch {
            lastStoreError = error.localizedDescription
        }
    }

    /// Publishes `newValue` only if it was written. On failure the previous
    /// value is restored and the error message returned.
    private func commit<T>(_ keyPath: ReferenceWritableKeyPath<DataRepository, T>,
                           _ newValue: T,
                           to file: StoreFile) -> String? {
        let previous = self[keyPath: keyPath]
        self[keyPath: keyPath] = newValue
        if let error = persistResult(file) {
            self[keyPath: keyPath] = previous
            lastStoreError = error
            return error
        }
        lastStoreError = nil
        return nil
    }

    private func persist(_ file: StoreFile) {
        lastStoreError = persistResult(file)
    }

    /// Returns nil on success, or a human-readable failure message.
    private func persistResult(_ file: StoreFile) -> String? {
        do {
            switch file {
            case .settings: try store.save(settings, to: .settings)
            case .profile:
                if let profile = profile { try store.save(profile, to: .profile) }
                else { try store.delete(.profile) }
            case .activities: try store.save(activities, to: .activities)
            case .places: try store.save(places, to: .places)
            case .plans: try store.save(plans, to: .plans)
            case .alerts: try store.save(alerts, to: .alerts)
            case .alertEvents: try store.save(alertEvents, to: .alertEvents)
            case .feedback: try store.save(feedback, to: .feedback)
            case .history: try store.save(history, to: .history)
            case .snapshots: try store.save(Array(snapshots.values), to: .snapshots)
            case .drafts: try store.save(drafts, to: .drafts)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - History

    @discardableResult
    func record(_ kind: HistoryKind,
                _ entityType: EntityType,
                id: UUID? = nil,
                title: String,
                detail: String = "",
                changes: [String] = []) -> HistoryRecord {
        let entry = HistoryRecord(kind: kind, entityType: entityType, entityID: id,
                                  title: title, detail: detail, changes: changes)
        history.insert(entry, at: 0)
        if history.count > 500 { history = Array(history.prefix(500)) }
        persist(.history)
        return entry
    }

    func history(for entityID: UUID) -> [HistoryRecord] {
        history.filter { $0.entityID == entityID }
    }

    // MARK: - Settings

    @discardableResult
    func updateSettings(_ transform: (inout AppSettings) -> Void) -> SaveOutcome {
        let before = settings
        var copy = settings
        transform(&copy)
        copy.updatedAt = Date()
        if let error = commit(\.settings, copy, to: .settings) {
            return .failure(message: error)
        }
        let changes = Self.settingsChanges(before: before, after: copy)
        if !changes.isEmpty {
            record(.updated, .settings, title: "Settings updated", changes: changes)
        }
        return .success(changes: changes)
    }

    private static func settingsChanges(before: AppSettings, after: AppSettings) -> [String] {
        var changes: [String] = []
        if before.temperatureUnit != after.temperatureUnit { changes.append("Temperature shown in \(after.temperatureUnit.title)") }
        if before.speedUnit != after.speedUnit { changes.append("Wind shown in \(after.speedUnit.title)") }
        if before.distanceUnit != after.distanceUnit { changes.append("Distance shown in \(after.distanceUnit.title)") }
        if before.precipitationUnit != after.precipitationUnit { changes.append("Rain shown in \(after.precipitationUnit.title)") }
        if before.aqiStandard != after.aqiStandard { changes.append("Air quality scale: \(after.aqiStandard.title)") }
        if before.locationPrecision != after.locationPrecision { changes.append("Location precision: \(after.locationPrecision.title)") }
        if before.backgroundRefreshEnabled != after.backgroundRefreshEnabled {
            changes.append("Background refresh \(after.backgroundRefreshEnabled ? "enabled" : "disabled")")
        }
        if before.notificationsEnabled != after.notificationsEnabled {
            changes.append("Notifications \(after.notificationsEnabled ? "enabled" : "disabled")")
        }
        return changes
    }

    // MARK: - Comfort profile

    @discardableResult
    func saveProfile(_ newProfile: ComfortProfile, appliedDefaults: Bool = false) -> SaveOutcome {
        let before = profile
        var copy = newProfile
        copy.updatedAt = Date()
        if let error = commit(\.profile, copy, to: .profile) {
            return .failure(message: error)
        }

        var changes: [String] = []
        if let before = before {
            for metric in MetricKind.allCases {
                let old = before.threshold(for: metric)
                let new = copy.threshold(for: metric)
                if old?.minValue != new?.minValue || old?.maxValue != new?.maxValue {
                    changes.append("\(metric.title): \(new?.summary ?? "Not set")")
                }
            }
            for kind in SensitivityKind.allCases where before.level(for: kind) != copy.level(for: kind) {
                changes.append("\(kind.title) sensitivity: \(copy.level(for: kind).title)")
            }
        } else {
            changes.append("\(copy.definedCount) limit\(copy.definedCount == 1 ? "" : "s") defined")
        }

        record(appliedDefaults ? .defaultsApplied : (before == nil ? .created : .updated),
               .profile, id: copy.id,
               title: before == nil ? "Comfort Profile created" : "Comfort Profile updated",
               detail: appliedDefaults ? ComfortProfile.generalDefaultsDisclaimer : "",
               changes: changes)
        return .success(changes: changes)
    }

    @discardableResult
    func resetProfile() -> SaveOutcome {
        guard profile != nil else { return .success(changes: []) }
        if let error = commit(\.profile, nil, to: .profile) {
            return .failure(message: error)
        }
        record(.profileReset, .profile, title: "Comfort Profile reset",
               detail: "All personal limits were cleared. Window results are unavailable until limits are defined again.")
        return .success(changes: ["All limits cleared"])
    }

    // MARK: - Activities

    func activity(id: UUID?) -> ActivityTemplate? {
        guard let id = id else { return nil }
        return activities.first(where: { $0.id == id })
    }

    var activeActivities: [ActivityTemplate] { activities.filter { !$0.isArchived } }

    @discardableResult
    func saveActivity(_ template: ActivityTemplate) -> SaveOutcome {
        var copy = template
        copy.updatedAt = Date()
        let existing = activities.firstIndex(where: { $0.id == copy.id })
        var changes: [String] = []
        var candidate = activities
        var isUpdate = false

        if let index = existing {
            isUpdate = true
            let before = activities[index]
            if before.name != copy.name { changes.append("Renamed to “\(copy.name)”") }
            if before.durationMinutes != copy.durationMinutes {
                changes.append("Duration \(SkyFormat.duration(minutes: copy.durationMinutes))")
            }
            if before.requiredConditions.count != copy.requiredConditions.count {
                changes.append("\(copy.requiredConditions.count) required condition\(copy.requiredConditions.count == 1 ? "" : "s")")
            }
            if before.preferredConditions != copy.preferredConditions {
                changes.append("\(copy.preferredConditions.count) preferred condition\(copy.preferredConditions.count == 1 ? "" : "s"), weights total \(copy.totalWeight)%")
            }
            if before.earliestMinute != copy.earliestMinute || before.latestMinute != copy.latestMinute {
                changes.append("Time range \(QuietHours.text(copy.earliestMinute))–\(QuietHours.text(copy.latestMinute))")
            }
            candidate[index] = copy
        } else {
            candidate.append(copy)
            changes = [
                "\(copy.requiredConditions.count) required condition\(copy.requiredConditions.count == 1 ? "" : "s")",
                "\(copy.preferredConditions.count) preferred condition\(copy.preferredConditions.count == 1 ? "" : "s")",
                "Duration \(SkyFormat.duration(minutes: copy.durationMinutes))"
            ]
        }

        if let error = commit(\.activities, candidate, to: .activities) {
            return .failure(message: error)
        }
        record(isUpdate ? .updated : .created, .activity, id: copy.id,
               title: "“\(copy.name)” \(isUpdate ? "updated" : "created")", changes: changes)
        return .success(changes: changes)
    }

    @discardableResult
    func setActivityArchived(_ id: UUID, archived: Bool) -> SaveOutcome {
        guard let index = activities.firstIndex(where: { $0.id == id }) else {
            return .failure(message: "That activity no longer exists.")
        }
        var candidate = activities
        candidate[index].isArchived = archived
        candidate[index].updatedAt = Date()
        if let error = commit(\.activities, candidate, to: .activities) {
            return .failure(message: error)
        }
        record(archived ? .archived : .restored, .activity, id: id,
               title: "“\(activities[index].name)” \(archived ? "archived" : "restored")",
               detail: archived ? "It stays available in History and existing plans keep working." : "")
        return .success(changes: [archived ? "Archived" : "Restored"])
    }

    // MARK: - Places

    func place(id: UUID?) -> Place? {
        guard let id = id else { return nil }
        return places.first(where: { $0.id == id })
    }

    var activePlaces: [Place] { places.filter { !$0.isArchived } }

    var defaultPlace: Place? {
        activePlaces.first(where: { $0.isDefault }) ?? activePlaces.first
    }

    @discardableResult
    func savePlace(_ place: Place) -> SaveOutcome {
        var copy = place
        copy.updatedAt = Date()
        var changes: [String] = []
        var candidate = places
        var isUpdate = false
        var clearsSnapshot = false

        if let index = candidate.firstIndex(where: { $0.id == copy.id }) {
            isUpdate = true
            let before = candidate[index]
            if before.name != copy.name { changes.append("Renamed to “\(copy.name)”") }
            if before.note != copy.note { changes.append("Note updated") }
            if before.latitude != copy.latitude || before.longitude != copy.longitude {
                changes.append("Coordinates updated — stored conditions were cleared")
                clearsSnapshot = true
            }
            if before.timeZoneIdentifier != copy.timeZoneIdentifier { changes.append("Time zone \(copy.timeZoneIdentifier)") }
            candidate[index] = copy
        } else {
            if candidate.isEmpty { copy.isDefault = true }
            candidate.append(copy)
            changes = ["Saved from \(copy.source.title.lowercased())", "Time zone \(copy.timeZoneIdentifier)"]
        }

        if copy.isDefault {
            for i in candidate.indices where candidate[i].id != copy.id { candidate[i].isDefault = false }
        }

        if let error = commit(\.places, candidate, to: .places) {
            return .failure(message: error)
        }
        // Only drop the stale snapshot once the new coordinates are stored.
        if clearsSnapshot {
            var snaps = snapshots
            snaps[copy.id] = nil
            _ = commit(\.snapshots, snaps, to: .snapshots)
        }
        record(isUpdate ? .updated : .created, .place, id: copy.id,
               title: "“\(copy.name)” \(isUpdate ? "updated" : "added")", changes: changes)
        return .success(changes: changes)
    }

    @discardableResult
    func setDefaultPlace(_ id: UUID) -> SaveOutcome {
        guard let target = places.first(where: { $0.id == id }) else {
            return .failure(message: "That place no longer exists.")
        }
        var candidate = places
        for i in candidate.indices { candidate[i].isDefault = candidate[i].id == id }
        if let error = commit(\.places, candidate, to: .places) {
            return .failure(message: error)
        }
        record(.updated, .place, id: id, title: "“\(target.name)” is now the default place",
               detail: "Today and new searches start from this place.")
        return .success(changes: ["Default place"])
    }

    @discardableResult
    func setPlaceArchived(_ id: UUID, archived: Bool) -> SaveOutcome {
        guard let index = places.firstIndex(where: { $0.id == id }) else {
            return .failure(message: "That place no longer exists.")
        }
        var candidate = places
        candidate[index].isArchived = archived
        candidate[index].updatedAt = Date()
        if archived && candidate[index].isDefault {
            candidate[index].isDefault = false
            if let next = candidate.firstIndex(where: { !$0.isArchived }) { candidate[next].isDefault = true }
        }
        if let error = commit(\.places, candidate, to: .places) {
            return .failure(message: error)
        }
        record(archived ? .archived : .restored, .place, id: id,
               title: "“\(places[index].name)” \(archived ? "archived" : "restored")")
        return .success(changes: [archived ? "Archived" : "Restored"])
    }

    // MARK: - Snapshots

    func snapshot(for placeID: UUID) -> ConditionSnapshot? { snapshots[placeID] }

    func storeSnapshot(_ snapshot: ConditionSnapshot) {
        snapshots[snapshot.placeID] = snapshot
        persist(.snapshots)
        record(.snapshotRefreshed, .snapshot, id: snapshot.placeID,
               title: "Conditions refreshed for \(place(id: snapshot.placeID)?.name ?? "a place")",
               detail: snapshot.sourceSummary,
               changes: ["\(snapshot.hours.count) hourly points", "Captured \(RelativeTime.string(for: snapshot.capturedAt))"])
    }

    // MARK: - Plans

    func plan(id: UUID?) -> Plan? {
        guard let id = id else { return nil }
        return plans.first(where: { $0.id == id })
    }

    var activePlans: [Plan] {
        plans.filter { $0.status == .scheduled || $0.status == .atRisk }
            .sorted { $0.window.start < $1.window.start }
    }

    var upcomingPlans: [Plan] {
        activePlans.filter { $0.window.end >= Date() }
    }

    var plansAtRisk: [Plan] { plans.filter { $0.hasOpenRisk } }

    func plans(forPlace placeID: UUID) -> [Plan] { plans.filter { $0.placeID == placeID } }
    func plans(forActivity activityID: UUID) -> [Plan] { plans.filter { $0.activityID == activityID } }

    /// Finds an existing plan covering the same window, so the user can update
    /// instead of silently creating a duplicate.
    func duplicatePlan(activityID: UUID, placeID: UUID, start: Date) -> Plan? {
        plans.first {
            $0.activityID == activityID && $0.placeID == placeID
                && abs($0.window.start.timeIntervalSince(start)) < 60
                && ($0.status == .scheduled || $0.status == .atRisk)
        }
    }

    @discardableResult
    func savePlan(_ plan: Plan) -> SaveOutcome {
        var copy = plan
        copy.updatedAt = Date()
        var changes: [String] = []
        var candidate = plans
        var isUpdate = false

        if let index = candidate.firstIndex(where: { $0.id == copy.id }) {
            isUpdate = true
            let before = candidate[index]
            if before.window.start != copy.window.start {
                changes.append("Moved to \(copy.window.dayText()) \(copy.window.timeRangeText())")
            }
            if before.reminderMinutesBefore != copy.reminderMinutesBefore {
                changes.append(copy.reminderMinutesBefore.map { "Reminder \($0) min before" } ?? "Reminder removed")
            }
            if before.backupWindow?.id != copy.backupWindow?.id {
                changes.append(copy.backupWindow == nil ? "Backup window removed" : "Backup window set")
            }
            if before.preparationNotes != copy.preparationNotes { changes.append("Notes updated") }
            if before.status != copy.status { changes.append("Status: \(copy.status.title)") }
            candidate[index] = copy
        } else {
            candidate.append(copy)
            changes = [
                "\(copy.window.dayText()), \(copy.window.timeRangeText())",
                copy.window.score.map { "Score \(Int($0.rounded()))" } ?? "Score unavailable",
                copy.reminderMinutesBefore.map { "Reminder \($0) min before" } ?? "No reminder"
            ]
        }

        if let error = commit(\.plans, candidate, to: .plans) {
            return .failure(message: error)
        }
        record(isUpdate ? .updated : .planSaved, .plan, id: copy.id,
               title: "“\(copy.title)” \(isUpdate ? "updated" : "planned")", changes: changes)
        return .success(changes: changes)
    }

    @discardableResult
    func updatePlan(_ id: UUID, _ transform: (inout Plan) -> Void) -> SaveOutcome {
        guard let index = plans.firstIndex(where: { $0.id == id }) else {
            return .failure(message: "That plan no longer exists.")
        }
        var candidate = plans
        transform(&candidate[index])
        candidate[index].updatedAt = Date()
        if let error = commit(\.plans, candidate, to: .plans) {
            return .failure(message: error)
        }
        return .success(changes: [])
    }

    /// Changing status also retires the system reminder when the plan stops
    /// being actionable, so no notification outlives the plan it belongs to.
    @discardableResult
    func setPlanStatus(_ id: UUID, _ status: PlanStatus, note: String = "") -> SaveOutcome {
        guard let index = plans.firstIndex(where: { $0.id == id }) else {
            return .failure(message: "That plan no longer exists.")
        }
        let retiresReminder = (status != .scheduled && status != .atRisk)
        let previous = plans[index]
        var candidate = plans
        candidate[index].status = status
        candidate[index].updatedAt = Date()
        if retiresReminder { candidate[index].reminderNotificationID = nil }

        if let error = commit(\.plans, candidate, to: .plans) {
            return .failure(message: error)
        }
        if retiresReminder {
            cancelReminder(for: previous)
        }
        let kind: HistoryKind
        switch status {
        case .completed: kind = .planCompleted
        case .cancelled: kind = .planCancelled
        case .archived: kind = .archived
        default: kind = .updated
        }
        record(kind, .plan, id: id, title: "“\(plans[index].title)” — \(status.title)", detail: note)
        return .success(changes: ["Status: \(status.title)"]
                        + (retiresReminder && previous.reminderNotificationID != nil ? ["Reminder cancelled"] : []))
    }

    @discardableResult
    func addRiskEvent(_ event: RiskEvent, to planID: UUID) -> SaveOutcome {
        guard let index = plans.firstIndex(where: { $0.id == planID }) else {
            return .failure(message: "That plan no longer exists.")
        }
        guard !plans[index].riskEvents.contains(where: { $0.newSnapshotID == event.newSnapshotID }) else {
            return .success(changes: [])
        }
        var candidate = plans
        candidate[index].riskEvents.append(event)
        candidate[index].status = .atRisk
        candidate[index].updatedAt = Date()
        if let error = commit(\.plans, candidate, to: .plans) {
            return .failure(message: error)
        }
        record(.riskDetected, .plan, id: planID,
               title: "“\(plans[index].title)” is at risk",
               detail: event.summary,
               changes: ["Compared snapshot captured \(RelativeTime.string(for: event.previousCapturedAt)) with the newest one"])
        return .success(changes: [event.summary])
    }

    /// Resolving a risk can move the window, which invalidates the reminder that
    /// was scheduled for the old start time. The identifier is cleared here and
    /// the caller reschedules from the new window.
    @discardableResult
    func resolveRisk(planID: UUID, eventID: UUID, resolution: RiskResolution,
                     newWindow: WindowCandidate? = nil) -> SaveOutcome {
        guard let pIndex = plans.firstIndex(where: { $0.id == planID }),
              let eIndex = plans[pIndex].riskEvents.firstIndex(where: { $0.id == eventID }) else {
            return .failure(message: "That plan or risk entry no longer exists.")
        }
        let previous = plans[pIndex]
        var candidate = plans
        candidate[pIndex].riskEvents[eIndex].resolution = resolution
        candidate[pIndex].riskEvents[eIndex].resolvedAt = Date()
        if let newWindow = newWindow {
            candidate[pIndex].window = newWindow
            if resolution == .movedToBackup { candidate[pIndex].backupWindow = nil }
        }
        candidate[pIndex].status = resolution == .cancelled
            ? .cancelled
            : (candidate[pIndex].hasOpenRisk ? .atRisk : .scheduled)
        candidate[pIndex].updatedAt = Date()

        let invalidatesReminder = newWindow != nil || resolution == .cancelled
        if invalidatesReminder { candidate[pIndex].reminderNotificationID = nil }

        if let error = commit(\.plans, candidate, to: .plans) {
            return .failure(message: error)
        }
        if invalidatesReminder { cancelReminder(for: previous) }

        record(resolution == .kept ? .planKept : .planMoved, .plan, id: planID,
               title: "“\(plans[pIndex].title)” — \(resolution.title)",
               changes: newWindow.map { ["New window \($0.dayText()) \($0.timeRangeText())"] } ?? [])
        record(.riskResolved, .plan, id: planID, title: "Risk resolved", detail: resolution.title)
        return .success(changes: [resolution.title])
    }

    // MARK: - Alerts

    func alert(id: UUID?) -> AlertRule? {
        guard let id = id else { return nil }
        return alerts.first(where: { $0.id == id })
    }

    @discardableResult
    func saveAlert(_ rule: AlertRule) -> SaveOutcome {
        var copy = rule
        copy.updatedAt = Date()
        var changes: [String] = []
        var candidate = alerts
        var isUpdate = false
        if let index = candidate.firstIndex(where: { $0.id == copy.id }) {
            isUpdate = true
            let before = candidate[index]
            if before.isPaused != copy.isPaused { changes.append(copy.isPaused ? "Paused" : "Resumed") }
            if before.threshold != copy.threshold, let t = copy.threshold, let m = copy.metric {
                changes.append("Threshold \(SkyFormat.number(t, decimals: m.decimals)) \(m.canonicalUnit)")
            }
            if before.quietHours != copy.quietHours { changes.append("Quiet hours \(copy.quietHours.summary)") }
            if before.horizonDays != copy.horizonDays { changes.append("Looks \(copy.horizonDays) day\(copy.horizonDays == 1 ? "" : "s") ahead") }
            candidate[index] = copy
        } else {
            candidate.append(copy)
            changes = [copy.summary, "Quiet hours \(copy.quietHours.summary)", "Cooldown \(copy.cooldownSummary)"]
        }
        if let error = commit(\.alerts, candidate, to: .alerts) {
            return .failure(message: error)
        }
        record(isUpdate ? .updated : .created, .alert, id: copy.id,
               title: "“\(copy.name)” \(isUpdate ? "updated" : "created")", changes: changes)
        return .success(changes: changes)
    }

    @discardableResult
    func setAlertPaused(_ id: UUID, paused: Bool) -> SaveOutcome {
        guard let index = alerts.firstIndex(where: { $0.id == id }) else {
            return .failure(message: "That alert rule no longer exists.")
        }
        var candidate = alerts
        candidate[index].isPaused = paused
        candidate[index].updatedAt = Date()
        if let error = commit(\.alerts, candidate, to: .alerts) {
            return .failure(message: error)
        }
        record(.updated, .alert, id: id, title: "“\(alerts[index].name)” \(paused ? "paused" : "resumed")")
        return .success(changes: [paused ? "Paused" : "Resumed"])
    }

    @discardableResult
    func deleteAlert(_ id: UUID) -> SaveOutcome {
        guard let index = alerts.firstIndex(where: { $0.id == id }) else {
            return .failure(message: "That alert rule no longer exists.")
        }
        let name = alerts[index].name
        var candidate = alerts
        candidate.remove(at: index)
        if let error = commit(\.alerts, candidate, to: .alerts) {
            return .failure(message: error)
        }
        record(.deleted, .alert, id: id, title: "“\(name)” deleted",
               detail: "No further notifications will be scheduled for this rule.")
        return .success(changes: ["Rule removed"])
    }

    /// Records a delivered alert and advances the rule's cooldown/dedup state.
    func markAlertFired(_ id: UUID, fingerprint: String, event: AlertEvent) {
        if let index = alerts.firstIndex(where: { $0.id == id }) {
            var candidate = alerts
            candidate[index].lastFiredAt = Date()
            candidate[index].lastFingerprint = fingerprint
            _ = commit(\.alerts, candidate, to: .alerts)
        }
        appendAlertEvent(event)
        record(.alertFired, .alert, id: id, title: event.title, detail: event.body)
    }

    /// Records a match that was deliberately not delivered. The rule's cooldown
    /// and fingerprint are left untouched so a real send is still possible.
    func recordSuppressedAlert(_ id: UUID, event: AlertEvent) {
        appendAlertEvent(event)
        record(.alertSuppressed, .alert, id: id,
               title: event.title, detail: event.suppressionReason ?? "")
    }

    private func appendAlertEvent(_ event: AlertEvent) {
        var candidate = alertEvents
        candidate.insert(event, at: 0)
        if candidate.count > 200 { candidate = Array(candidate.prefix(200)) }
        _ = commit(\.alertEvents, candidate, to: .alertEvents)
    }

    // MARK: - Feedback

    func feedback(forPlan planID: UUID) -> FeedbackEntry? {
        feedback.first(where: { $0.planID == planID })
    }

    var ratedFeedback: [FeedbackEntry] { feedback.filter(\.isRated) }

    @discardableResult
    func saveFeedback(_ entry: FeedbackEntry) -> SaveOutcome {
        var copy = entry
        copy.updatedAt = Date()
        var changes: [String] = []
        var candidate = feedback
        if let index = candidate.firstIndex(where: { $0.id == copy.id }) {
            candidate[index] = copy
            changes = ["Feedback updated"]
        } else {
            candidate.append(copy)
            changes = [
                copy.comfortRating.map { "Comfort \($0)/5" } ?? "No rating given",
                copy.wouldRepeat.map { $0 ? "Would repeat" : "Would not repeat" } ?? "Repeat not answered",
                copy.tags.isEmpty ? "No tags" : copy.tags.map(\.title).joined(separator: ", ")
            ]
        }
        if let error = commit(\.feedback, candidate, to: .feedback) {
            return .failure(message: error)
        }
        // A reviewed plan is finished: close it and retire its reminder.
        if let planIndex = plans.firstIndex(where: { $0.id == copy.planID }), plans[planIndex].status != .completed {
            _ = setPlanStatus(plans[planIndex].id, .completed)
        }
        record(.feedbackSaved, .feedback, id: copy.id,
               title: "Feedback saved for “\(plan(id: copy.planID)?.title ?? "a plan")”",
               detail: "The original forecast snapshot was preserved unchanged.",
               changes: changes)
        return .success(changes: changes)
    }

    // MARK: - Drafts

    func saveDraft<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        drafts[key] = data
        persist(.drafts)
    }

    func loadDraft<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = drafts[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func clearDraft(key: String) {
        guard drafts[key] != nil else { return }
        drafts[key] = nil
        persist(.drafts)
    }

    func hasDraft(key: String) -> Bool { drafts[key] != nil }

    // MARK: - Deletion impact

    func deletionImpact(place id: UUID) -> DeletionImpact {
        guard let place = place(id: id) else {
            return DeletionImpact(entityType: .place, entityTitle: "", dependents: [], canDelete: false,
                                  blockingReason: "This place no longer exists.")
        }
        var dependents: [DeletionImpact.Dependent] = []
        for plan in plans where plan.placeID == id && plan.status != .archived {
            dependents.append(.init(id: plan.id, type: .plan, title: plan.title,
                                    detail: "\(plan.window.dayText()) · \(plan.status.title)"))
        }
        for alert in alerts where alert.placeID == id {
            dependents.append(.init(id: alert.id, type: .alert, title: alert.name, detail: alert.kind.shortTitle))
        }
        for entry in feedback where entry.placeID == id {
            dependents.append(.init(id: entry.id, type: .feedback, title: "Feedback entry",
                                    detail: SkyFormat.dayShort(entry.windowStart, timeZone: place.timeZone)))
        }
        return DeletionImpact(entityType: .place, entityTitle: place.name, dependents: dependents,
                              canDelete: true, blockingReason: nil)
    }

    func deletionImpact(activity id: UUID) -> DeletionImpact {
        guard let activity = activity(id: id) else {
            return DeletionImpact(entityType: .activity, entityTitle: "", dependents: [], canDelete: false,
                                  blockingReason: "This activity no longer exists.")
        }
        var dependents: [DeletionImpact.Dependent] = []
        for plan in plans where plan.activityID == id && plan.status != .archived {
            dependents.append(.init(id: plan.id, type: .plan, title: plan.title,
                                    detail: "\(plan.window.dayText()) · \(plan.status.title)"))
        }
        for alert in alerts where alert.activityID == id {
            dependents.append(.init(id: alert.id, type: .alert, title: alert.name, detail: alert.kind.shortTitle))
        }
        for entry in feedback where entry.activityID == id {
            dependents.append(.init(id: entry.id, type: .feedback, title: "Feedback entry", detail: ""))
        }
        return DeletionImpact(entityType: .activity, entityTitle: activity.name, dependents: dependents,
                              canDelete: true, blockingReason: nil)
    }

    func deletionImpact(plan id: UUID) -> DeletionImpact {
        guard let plan = plan(id: id) else {
            return DeletionImpact(entityType: .plan, entityTitle: "", dependents: [], canDelete: false,
                                  blockingReason: "This plan no longer exists.")
        }
        var dependents: [DeletionImpact.Dependent] = []
        if let entry = feedback(forPlan: id) {
            dependents.append(.init(id: entry.id, type: .feedback, title: "Feedback entry",
                                    detail: entry.comfortRating.map { "Comfort \($0)/5" } ?? "No rating"))
        }
        if plan.isCalendarConfirmed {
            dependents.append(.init(id: plan.id, type: .plan, title: "Calendar event",
                                    detail: "Remains in your calendar — remove it there if you want it gone."))
        }
        return DeletionImpact(entityType: .plan, entityTitle: plan.title, dependents: dependents,
                              canDelete: true, blockingReason: nil)
    }

    /// Executes the strategy the user picked after reading the consequences.
    @discardableResult
    func deletePlace(_ id: UUID, strategy: DeletionStrategy) -> SaveOutcome {
        guard strategy != .cancel else { return .success(changes: []) }
        guard let place = place(id: id) else { return .failure(message: "That place no longer exists.") }
        if strategy == .archive { return setPlaceArchived(id, archived: true) }

        var detached: [String] = []
        var planCandidate = plans
        // Archiving a dependent plan also retires its reminder.
        var reminderOwners: [Plan] = []
        for index in planCandidate.indices where planCandidate[index].placeID == id {
            planCandidate[index].status = .archived
            if planCandidate[index].reminderNotificationID != nil { reminderOwners.append(plans[index]) }
            planCandidate[index].reminderNotificationID = nil
            detached.append("Plan “\(planCandidate[index].title)” archived")
        }
        let removedAlerts = alerts.filter { $0.placeID == id }
        var alertCandidate = alerts
        alertCandidate.removeAll { $0.placeID == id }
        for a in removedAlerts { detached.append("Alert “\(a.name)” removed") }

        var placeCandidate = places
        placeCandidate.removeAll { $0.id == id }
        if !placeCandidate.isEmpty && !placeCandidate.contains(where: { $0.isDefault && !$0.isArchived }) {
            if let next = placeCandidate.firstIndex(where: { !$0.isArchived }) { placeCandidate[next].isDefault = true }
        }
        var snapshotCandidate = snapshots
        snapshotCandidate[id] = nil

        if let error = commit(\.plans, planCandidate, to: .plans) { return .failure(message: error) }
        if let error = commit(\.alerts, alertCandidate, to: .alerts) { return .failure(message: error) }
        if let error = commit(\.places, placeCandidate, to: .places) { return .failure(message: error) }
        if let error = commit(\.snapshots, snapshotCandidate, to: .snapshots) { return .failure(message: error) }

        for plan in reminderOwners { cancelReminder(for: plan) }
        record(.deleted, .place, id: id, title: "“\(place.name)” deleted",
               detail: "Feedback history was kept so past results stay verifiable.",
               changes: detached.isEmpty ? ["Nothing else referenced this place"] : detached)
        return .success(changes: detached)
    }

    @discardableResult
    func deleteActivity(_ id: UUID, strategy: DeletionStrategy) -> SaveOutcome {
        guard strategy != .cancel else { return .success(changes: []) }
        guard let activity = activity(id: id) else { return .failure(message: "That activity no longer exists.") }
        if strategy == .archive { return setActivityArchived(id, archived: true) }

        var detached: [String] = []
        var planCandidate = plans
        var reminderOwners: [Plan] = []
        for index in planCandidate.indices where planCandidate[index].activityID == id {
            planCandidate[index].status = .archived
            if planCandidate[index].reminderNotificationID != nil { reminderOwners.append(plans[index]) }
            planCandidate[index].reminderNotificationID = nil
            detached.append("Plan “\(planCandidate[index].title)” archived")
        }
        let removedAlerts = alerts.filter { $0.activityID == id }
        var alertCandidate = alerts
        alertCandidate.removeAll { $0.activityID == id }
        for a in removedAlerts { detached.append("Alert “\(a.name)” removed") }

        var activityCandidate = activities
        activityCandidate.removeAll { $0.id == id }

        if let error = commit(\.plans, planCandidate, to: .plans) { return .failure(message: error) }
        if let error = commit(\.alerts, alertCandidate, to: .alerts) { return .failure(message: error) }
        if let error = commit(\.activities, activityCandidate, to: .activities) { return .failure(message: error) }

        for plan in reminderOwners { cancelReminder(for: plan) }
        record(.deleted, .activity, id: id, title: "“\(activity.name)” deleted",
               detail: "Feedback history was kept so past results stay verifiable.",
               changes: detached.isEmpty ? ["Nothing else referenced this activity"] : detached)
        return .success(changes: detached)
    }

    @discardableResult
    func deletePlan(_ id: UUID, strategy: DeletionStrategy) -> SaveOutcome {
        guard strategy != .cancel else { return .success(changes: []) }
        guard let plan = plan(id: id) else { return .failure(message: "That plan no longer exists.") }
        if strategy == .archive { return setPlanStatus(id, .archived) }

        var candidate = plans
        candidate.removeAll { $0.id == id }
        if let error = commit(\.plans, candidate, to: .plans) {
            return .failure(message: error)
        }
        // The plan is gone, so its reminder must be gone too.
        cancelReminder(for: plan)
        record(.deleted, .plan, id: id, title: "“\(plan.title)” deleted",
               detail: plan.isCalendarConfirmed
                   ? "The calendar event was not removed — CloudCrown does not delete events it did not confirm creating."
                   : "")
        return .success(changes: plan.reminderNotificationID != nil ? ["Reminder cancelled"] : [])
    }

    // MARK: - Export / erase

    func exportData() throws -> Data {
        let data = try store.exportBundle()
        record(.dataExported, .settings, title: "Data exported",
               changes: ["\(places.count) places", "\(activities.count) activities", "\(plans.count) plans", "\(feedback.count) feedback entries"])
        return data
    }

    func eraseAllData() {
        for plan in plans { cancelReminder(for: plan) }
        try? store.deleteAll()
        settings = .default
        profile = nil
        activities = []
        places = []
        plans = []
        alerts = []
        alertEvents = []
        feedback = []
        snapshots = [:]
        drafts = [:]
        history = []
        record(.dataDeleted, .settings, title: "All local data deleted",
               detail: "Every place, activity, plan, alert and feedback entry was removed from this device.")
    }

    // MARK: - Readiness

    /// What is still missing before window results can be trusted.
    var setupGaps: [SetupGap] {
        var gaps: [SetupGap] = []
        if profile == nil || profile?.isUsable != true {
            gaps.append(.profile(missing: profile?.missingCoreMetrics ?? ComfortProfile.coreMetrics))
        }
        if activeActivities.isEmpty { gaps.append(.activity) }
        if activePlaces.isEmpty { gaps.append(.place) }
        return gaps
    }

    var isReadyForWindows: Bool { setupGaps.isEmpty }
}

enum SetupGap: Identifiable, Equatable {
    case profile(missing: [MetricKind])
    case activity
    case place

    var id: String {
        switch self {
        case .profile: return "profile"
        case .activity: return "activity"
        case .place: return "place"
        }
    }

    var title: String {
        switch self {
        case .profile: return "Comfort limits are incomplete"
        case .activity: return "No activity template yet"
        case .place: return "No place saved yet"
        }
    }

    var reason: String {
        switch self {
        case .profile(let missing):
            let names = missing.map(\.title).joined(separator: ", ")
            return "Windows are scored against your own limits. Still missing: \(names)."
        case .activity:
            return "An activity defines which conditions block a window and which only shape the score."
        case .place:
            return "Conditions are fetched per place, with its own coordinates and time zone."
        }
    }

    var actionTitle: String {
        switch self {
        case .profile: return "Set My Limits"
        case .activity: return "Add Activity"
        case .place: return "Add Place"
        }
    }

    var icon: String {
        switch self {
        case .profile: return "slider.horizontal.below.square.filled.and.square"
        case .activity: return "figure.walk"
        case .place: return "mappin.and.ellipse"
        }
    }
}
