//
//  RefreshCoordinator.swift
//  CloudCrown
//
//  The one place where saved work is actually re-checked: snapshots are
//  refreshed, saved plans are compared against the newer snapshot, and alert
//  rules are evaluated and delivered. Runs on launch, on foreground, from a
//  background task, and on manual request.
//

import Foundation

enum RefreshTrigger: String {
    case launch, foreground, background, manual

    var title: String {
        switch self {
        case .launch: return "App opened"
        case .foreground: return "Returned to the app"
        case .background: return "Background refresh"
        case .manual: return "Manual check"
        }
    }

    /// Only a manual check ignores the Background Refresh preference.
    var respectsPreference: Bool { self != .manual }
}

struct RefreshReport: Equatable {
    var trigger: RefreshTrigger
    var startedAt: Date
    var finishedAt: Date
    var placesRefreshed: Int
    var placesFailed: Int
    var risksRaised: Int
    var alertsDelivered: Int
    var alertsSuppressed: Int
    var skippedReason: String?

    var didWork: Bool {
        placesRefreshed > 0 || risksRaised > 0 || alertsDelivered > 0
    }

    var summary: String {
        if let reason = skippedReason { return reason }
        var parts: [String] = []
        if placesRefreshed > 0 { parts.append("\(placesRefreshed) place\(placesRefreshed == 1 ? "" : "s") refreshed") }
        if placesFailed > 0 { parts.append("\(placesFailed) could not be reached") }
        if risksRaised > 0 { parts.append("\(risksRaised) plan\(risksRaised == 1 ? "" : "s") flagged at risk") }
        if alertsDelivered > 0 { parts.append("\(alertsDelivered) alert\(alertsDelivered == 1 ? "" : "s") sent") }
        if alertsSuppressed > 0 { parts.append("\(alertsSuppressed) held back") }
        return parts.isEmpty ? "Nothing changed" : parts.joined(separator: ", ")
    }
}

@MainActor
final class RefreshCoordinator: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var lastReport: RefreshReport?

    private let repository: DataRepository
    private let weather: WeatherFetching
    private let notifications: AlertNotifying

    /// Guards against two cycles overlapping (launch + foreground can coincide).
    private var runningTask: Task<RefreshReport, Never>?

    init(repository: DataRepository, weather: WeatherFetching, notifications: AlertNotifying) {
        self.repository = repository
        self.weather = weather
        self.notifications = notifications
    }

    @discardableResult
    func run(trigger: RefreshTrigger) async -> RefreshReport {
        if let existing = runningTask {
            return await existing.value
        }
        let task = Task { await performCycle(trigger: trigger) }
        runningTask = task
        isRunning = true
        let report = await task.value
        runningTask = nil
        isRunning = false
        lastReport = report
        return report
    }

    // MARK: - Cycle

    private func performCycle(trigger: RefreshTrigger) async -> RefreshReport {
        let startedAt = Date()

        func report(_ placesRefreshed: Int = 0, _ placesFailed: Int = 0,
                    _ risks: Int = 0, _ delivered: Int = 0, _ suppressed: Int = 0,
                    skipped: String? = nil) -> RefreshReport {
            RefreshReport(trigger: trigger, startedAt: startedAt, finishedAt: Date(),
                          placesRefreshed: placesRefreshed, placesFailed: placesFailed,
                          risksRaised: risks, alertsDelivered: delivered,
                          alertsSuppressed: suppressed, skippedReason: skipped)
        }

        if trigger.respectsPreference && !repository.settings.backgroundRefreshEnabled {
            return report(skipped: "Background Refresh is off, so nothing was re-checked automatically.")
        }

        // Only places that something actually depends on are fetched.
        let placeIDs = watchedPlaceIDs()
        guard !placeIDs.isEmpty else {
            return report(skipped: "No plan, alert rule or default place to check yet.")
        }

        var refreshed = 0
        var failed = 0

        for placeID in placeIDs {
            guard let place = repository.place(id: placeID), !place.isArchived else { continue }
            let existing = repository.snapshot(for: placeID)
            // A snapshot inside its freshness budget is reused rather than refetched.
            if let existing = existing, !existing.isStale, trigger != .manual { continue }
            do {
                let snapshot = try await weather.fetchSnapshot(
                    for: place,
                    precision: repository.settings.locationPrecision,
                    forecastDays: 7
                )
                repository.storeSnapshot(snapshot)
                refreshed += 1
            } catch {
                failed += 1
            }
        }

        let risks = assessPlanRisks()
        let alertResult = await evaluateAlertRules()

        _ = repository.updateSettings { $0.lastRefreshCheck = Date() }

        return report(refreshed, failed, risks, alertResult.delivered, alertResult.suppressed)
    }

    /// Places referenced by an upcoming plan, an active alert rule, or the default.
    private func watchedPlaceIDs() -> [UUID] {
        var ids: [UUID] = []
        func add(_ id: UUID) { if !ids.contains(id) { ids.append(id) } }
        if let defaultPlace = repository.defaultPlace { add(defaultPlace.id) }
        for plan in repository.upcomingPlans { add(plan.placeID) }
        for rule in repository.alerts where !rule.isPaused { add(rule.placeID) }
        return ids
    }

    // MARK: - Plan risk

    private func assessPlanRisks() -> Int {
        var raised = 0
        let profile = repository.profile
        for plan in repository.upcomingPlans {
            guard let activity = repository.activity(id: plan.activityID),
                  let place = repository.place(id: plan.placeID),
                  let snapshot = repository.snapshot(for: plan.placeID) else { continue }
            guard let assessment = RiskEngine.assess(plan: plan,
                                                     activity: activity,
                                                     profile: profile,
                                                     place: place,
                                                     snapshot: snapshot),
                  assessment.isMaterial else { continue }
            let before = repository.plan(id: plan.id)?.riskEvents.count ?? 0
            repository.addRiskEvent(RiskEngine.makeEvent(from: assessment, snapshot: snapshot), to: plan.id)
            if (repository.plan(id: plan.id)?.riskEvents.count ?? 0) > before { raised += 1 }
        }
        return raised
    }

    // MARK: - Alert rules

    private func evaluateAlertRules() async -> (delivered: Int, suppressed: Int) {
        var delivered = 0
        var suppressed = 0

        await notifications.refreshAuthorization()
        let isAuthorized = notifications.authorization.isAuthorized

        for rule in repository.alerts where !rule.isPaused {
            guard let place = repository.place(id: rule.placeID), !place.isArchived,
                  let snapshot = repository.snapshot(for: rule.placeID) else { continue }

            let decision = AlertEvaluator.evaluate(
                rule: rule,
                activity: repository.activity(id: rule.activityID),
                profile: repository.profile,
                place: place,
                snapshot: snapshot,
                plans: repository.plans
            )

            switch decision {
            case .noMatch:
                continue

            case .suppress(let candidate, let reason):
                if recordSuppression(rule: rule, candidate: candidate, reason: reason) {
                    suppressed += 1
                }

            case .deliver(let candidate):
                guard isAuthorized else {
                    // The rule matched but iOS cannot deliver it. That is recorded
                    // as a suppression with the real reason, never as a send.
                    if recordSuppression(rule: rule, candidate: candidate,
                                         reason: notifications.authorization.explanation) {
                        suppressed += 1
                    }
                    continue
                }
                let identifier = "alert-\(rule.id.uuidString)-\(candidate.fingerprint)"
                let sent = await notifications.deliver(title: candidate.title,
                                                       body: candidate.body,
                                                       identifier: identifier)
                if sent {
                    let event = AlertEvent(id: UUID(), ruleID: rule.id, ruleName: rule.name,
                                           firedAt: Date(), title: candidate.title,
                                           body: candidate.body, fingerprint: candidate.fingerprint,
                                           snapshotID: candidate.snapshotID,
                                           wasSuppressed: false, suppressionReason: nil)
                    repository.markAlertFired(rule.id, fingerprint: candidate.fingerprint, event: event)
                    delivered += 1
                } else if recordSuppression(rule: rule, candidate: candidate,
                                            reason: "iOS declined to schedule the notification.") {
                    suppressed += 1
                }
            }
        }
        return (delivered, suppressed)
    }

    /// Records a suppressed match once. Returns false when the identical
    /// suppression was already logged, so History does not fill up on relaunch.
    private func recordSuppression(rule: AlertRule,
                                   candidate: AlertEvaluator.Candidate,
                                   reason: String) -> Bool {
        let alreadyLogged = repository.alertEvents.contains {
            $0.ruleID == rule.id && $0.fingerprint == candidate.fingerprint && $0.wasSuppressed
        }
        guard !alreadyLogged else { return false }
        let event = AlertEvent(id: UUID(), ruleID: rule.id, ruleName: rule.name,
                               firedAt: Date(), title: candidate.title,
                               body: candidate.body, fingerprint: candidate.fingerprint,
                               snapshotID: candidate.snapshotID,
                               wasSuppressed: true, suppressionReason: reason)
        repository.recordSuppressedAlert(rule.id, event: event)
        return true
    }
}
