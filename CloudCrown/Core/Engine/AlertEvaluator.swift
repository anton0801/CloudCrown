//
//  AlertEvaluator.swift
//  CloudCrown
//
//  Applies cooldown, quiet hours and fingerprint deduplication before any
//  notification is delivered — and records suppressed attempts so History can
//  explain why a rule stayed silent.
//

import Foundation

struct AlertEvaluator {

    struct Candidate {
        let rule: AlertRule
        let title: String
        let body: String
        let fingerprint: String
        let snapshotID: UUID
    }

    enum Decision {
        case deliver(Candidate)
        case suppress(Candidate, reason: String)
        case noMatch
    }

    static func evaluate(rule: AlertRule,
                         activity: ActivityTemplate?,
                         profile: ComfortProfile?,
                         place: Place,
                         snapshot: ConditionSnapshot,
                         plans: [Plan],
                         now: Date = Date()) -> Decision {

        guard !rule.isPaused else { return .noMatch }

        guard let candidate = match(rule: rule,
                                    activity: activity,
                                    profile: profile,
                                    place: place,
                                    snapshot: snapshot,
                                    plans: plans,
                                    now: now) else { return .noMatch }

        if candidate.fingerprint == rule.lastFingerprint {
            return .suppress(candidate, reason: "The same result was already sent for this rule.")
        }
        if rule.isInCooldown(now: now) {
            let remaining = Int((Double(rule.cooldownMinutes) * 60 - now.timeIntervalSince(rule.lastFiredAt ?? now)) / 60)
            return .suppress(candidate, reason: "Cooldown active — \(max(1, remaining)) min remaining.")
        }
        let minute = now.minutesFromMidnight(in: place.timeZone)
        if rule.quietHours.contains(minuteOfDay: minute) {
            return .suppress(candidate, reason: "Quiet hours \(rule.quietHours.summary) at \(place.name).")
        }
        return .deliver(candidate)
    }

    private static func match(rule: AlertRule,
                              activity: ActivityTemplate?,
                              profile: ComfortProfile?,
                              place: Place,
                              snapshot: ConditionSnapshot,
                              plans: [Plan],
                              now: Date) -> Candidate? {

        switch rule.kind {

        case .windowAppears:
            guard let activity = activity else { return nil }
            let query = WindowQuery(activityID: activity.id,
                                    placeID: place.id,
                                    startDate: now,
                                    endDate: now.adding(days: rule.horizonDays, in: place.timeZone),
                                    earliestMinute: activity.earliestMinute,
                                    latestMinute: activity.latestMinute,
                                    durationMinutes: activity.durationMinutes)
            let result = WindowEngine.findWindows(query: query,
                                                  activity: activity,
                                                  profile: profile,
                                                  place: place,
                                                  snapshot: snapshot,
                                                  usedCachedSnapshot: false,
                                                  limit: 5)
            guard let best = result.best.first ?? result.acceptable.first else { return nil }
            return Candidate(
                rule: rule,
                title: "Window found for \(activity.name)",
                // Minimal payload: place, day, time. No coordinates, no health data.
                body: "\(best.dayText()), \(best.timeRangeText()) at \(place.name).",
                fingerprint: "window-\(activity.id.uuidString)-\(Int(best.start.timeIntervalSince1970))",
                snapshotID: snapshot.id
            )

        case .planDegrades:
            let relevant = plans.filter { $0.placeID == place.id && $0.hasOpenRisk }
            guard let plan = relevant.sorted(by: { $0.window.start < $1.window.start }).first,
                  let risk = plan.openRisks.last else { return nil }
            return Candidate(
                rule: rule,
                title: "\(plan.title) needs a decision",
                body: "Conditions changed for \(plan.window.dayText()), \(plan.window.timeRangeText()).",
                fingerprint: "risk-\(plan.id.uuidString)-\(risk.newSnapshotID.uuidString)",
                snapshotID: snapshot.id
            )

        case .metricThreshold:
            guard let metric = rule.metric, let threshold = rule.threshold else { return nil }
            let horizonEnd = now.adding(days: rule.horizonDays, in: place.timeZone)
            let hours = snapshot.hours.filter { $0.date >= now && $0.date <= horizonEnd }
            let probe = ConditionRule(metric: metric, comparison: rule.comparison, value: threshold)

            // The rule fires when the threshold is crossed, i.e. the rule fails.
            guard let hit = hours.first(where: { hour in
                guard let value = hour.value(metric) else { return false }
                return probe.evaluate(value) == .fail
            }), let value = hit.value(metric) else { return nil }

            return Candidate(
                rule: rule,
                title: "\(metric.title) crosses your threshold",
                body: "\(SkyFormat.number(value, decimals: metric.decimals)) \(metric.canonicalUnit) at \(SkyFormat.clock(hit.date, timeZone: place.timeZone)), \(place.name).",
                fingerprint: "metric-\(metric.rawValue)-\(Int(hit.date.timeIntervalSince1970))",
                snapshotID: snapshot.id
            )
        }
    }
}
