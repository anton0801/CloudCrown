//
//  WindowEngine.swift
//  CloudCrown
//
//  The evaluation authority. Views never recompute a score themselves — they
//  render the RuleEvaluation / PreferredEvaluation objects produced here.
//  A result is reproducible from (rulesVersion, snapshotID, template, profile).
//

import Foundation

struct WindowEngine {

    /// Bump when the aggregation or scoring semantics change. Stored on every
    /// candidate so an old explanation can be identified as Superseded.
    static let rulesVersion = "1.0.0"

    /// Candidate windows start on this grid.
    private static let stepMinutes = 30
    /// A window with less coverage than this is never called Best Match.
    private static let completenessFloor = 0.999
    /// Minimum score for Best Match once all required rules pass.
    private static let bestMatchScore: Double = 75

    // MARK: - Public entry point

    static func findWindows(query: WindowQuery,
                            activity: ActivityTemplate,
                            profile: ComfortProfile?,
                            place: Place,
                            snapshot: ConditionSnapshot,
                            usedCachedSnapshot: Bool,
                            limit: Int = 40) -> WindowSearchResult {

        let timeZone = snapshot.timeZone
        let rules = effectiveRequiredRules(activity: activity, profile: profile)
        let now = Date()

        var candidates: [WindowCandidate] = []
        var day = query.startDate.startOfDay(in: timeZone)
        let lastDay = query.endDate.startOfDay(in: timeZone)

        while day <= lastDay {
            var minute = query.earliestMinute
            while minute + query.durationMinutes <= query.latestMinute {
                let start = day.addingTimeInterval(TimeInterval(minute * 60))
                let end = start.addingTimeInterval(TimeInterval(query.durationMinutes * 60))

                // Only evaluate windows that still lie ahead and are covered.
                if end > now, let candidate = evaluate(start: start,
                                                      end: end,
                                                      rules: rules,
                                                      preferred: activity.preferredConditions,
                                                      requiresDaylight: activity.requiresDaylight,
                                                      activity: activity,
                                                      place: place,
                                                      snapshot: snapshot) {
                    candidates.append(candidate)
                }
                minute += stepMinutes
            }
            day = day.adding(days: 1, in: timeZone)
        }

        // Collapse overlapping windows, keeping the strongest of each cluster.
        let deduped = dedupe(candidates)
        let usable = deduped.filter { $0.verdict.isUsable }

        var ranked = usable.sorted { lhs, rhs in
            let l = lhs.score ?? -1, r = rhs.score ?? -1
            if abs(l - r) > 0.01 { return l > r }
            return lhs.start < rhs.start
        }

        // Promote the single strongest usable window to Best Match.
        if let topIndex = ranked.firstIndex(where: { ($0.score ?? 0) >= bestMatchScore && $0.isComplete }) {
            ranked[topIndex].verdict = .bestMatch
        } else if let firstIndex = ranked.indices.first, ranked[firstIndex].isComplete {
            ranked[firstIndex].verdict = .bestMatch
        }

        let rejected = deduped.filter { !$0.verdict.isUsable }
            .sorted { closenessScore($0) > closenessScore($1) }

        let finalCandidates = Array((ranked + rejected).prefix(limit))
        let closest: WindowCandidate? = ranked.isEmpty ? rejected.first : nil

        return WindowSearchResult(
            id: UUID(),
            query: query,
            candidates: finalCandidates,
            closestAlternative: closest,
            rulesVersion: rulesVersion,
            snapshotID: snapshot.id,
            snapshotCapturedAt: snapshot.capturedAt,
            evaluatedAt: now,
            usedCachedSnapshot: usedCachedSnapshot
        )
    }

    /// Re-evaluates one existing window against a newer snapshot. Used by the
    /// risk engine so "before" and "after" are computed identically.
    static func reevaluate(window: WindowCandidate,
                           activity: ActivityTemplate,
                           profile: ComfortProfile?,
                           place: Place,
                           snapshot: ConditionSnapshot) -> WindowCandidate? {
        evaluate(start: window.start,
                 end: window.end,
                 rules: effectiveRequiredRules(activity: activity, profile: profile),
                 preferred: activity.preferredConditions,
                 requiresDaylight: activity.requiresDaylight,
                 activity: activity,
                 place: place,
                 snapshot: snapshot)
    }

    // MARK: - Rule composition

    /// The template's own required rules, plus any hard limit from the comfort
    /// profile that the template does not already constrain. Sensitivity is
    /// applied here — once — so it can be explained rather than hidden.
    static func effectiveRequiredRules(activity: ActivityTemplate, profile: ComfortProfile?) -> [ConditionRule] {
        var rules = activity.requiredConditions
        guard let profile = profile else { return rules }

        for metric in MetricKind.constrainable {
            guard !rules.contains(where: { $0.metric == metric }) else { continue }
            let maxValue = profile.effectiveMax(for: metric)
            let minValue = profile.effectiveMin(for: metric)
            switch (minValue, maxValue) {
            case let (min?, max?):
                rules.append(ConditionRule(metric: metric, comparison: .between, value: min, upperValue: max))
            case let (nil, max?):
                rules.append(ConditionRule(metric: metric, comparison: .atMost, value: max))
            case let (min?, nil):
                rules.append(ConditionRule(metric: metric, comparison: .atLeast, value: min))
            default:
                continue
            }
        }
        return rules
    }

    // MARK: - Single window evaluation

    private static func evaluate(start: Date,
                                 end: Date,
                                 rules: [ConditionRule],
                                 preferred: [PreferredRule],
                                 requiresDaylight: Bool,
                                 activity: ActivityTemplate,
                                 place: Place,
                                 snapshot: ConditionSnapshot) -> WindowCandidate? {

        let hours = snapshot.hours(from: start, to: end)
        guard !hours.isEmpty else { return nil }

        // MARK: Required rules — aggregated to the worst case in the window.
        var requiredResults: [RuleEvaluation] = []
        var missing: Set<MetricKind> = []

        for rule in rules {
            let readings = hours.compactMap { hour -> (Double, HourlyConditions)? in
                guard let v = hour.value(rule.metric) else { return nil }
                return (v, hour)
            }

            guard let worst = worstCase(for: rule, readings: readings) else {
                missing.insert(rule.metric)
                requiredResults.append(RuleEvaluation(rule: rule, outcome: .unknown, measuredValue: nil))
                continue
            }

            let sample = worst.hour.sample(rule.metric)
            requiredResults.append(
                RuleEvaluation(rule: rule,
                               outcome: rule.evaluate(worst.value),
                               measuredValue: worst.value,
                               measuredAt: worst.hour.date,
                               observation: sample?.observation,
                               confidence: sample?.confidence ?? .unknown,
                               sourceID: sample?.sourceID)
            )
        }

        // MARK: Daylight, when the activity demands it.
        if requiresDaylight {
            if let day = snapshot.day(containing: start), let sunrise = day.sunrise, let sunset = day.sunset {
                let insideDaylight = start >= sunrise && end <= sunset
                let rule = ConditionRule(metric: .daylight, comparison: .atLeast, value: 1)
                requiredResults.append(
                    RuleEvaluation(rule: rule,
                                   outcome: insideDaylight ? .pass : .fail,
                                   measuredValue: insideDaylight ? 1 : 0,
                                   measuredAt: sunrise,
                                   observation: .forecast,
                                   confidence: .high,
                                   sourceID: snapshot.sources.first?.id)
                )
            } else {
                missing.insert(.daylight)
                requiredResults.append(
                    RuleEvaluation(rule: ConditionRule(metric: .daylight, comparison: .atLeast, value: 1),
                                   outcome: .unknown, measuredValue: nil)
                )
            }
        }

        // MARK: Preferred rules — averaged across the window.
        var preferredResults: [PreferredEvaluation] = []
        var earnedPoints: Double = 0
        var availableWeight: Double = 0

        for rule in preferred {
            let values = hours.compactMap { $0.value(rule.metric) }
            guard !values.isEmpty else {
                missing.insert(rule.metric)
                preferredResults.append(
                    PreferredEvaluation(rule: rule, measuredValue: nil, satisfaction: nil, pointsEarned: 0)
                )
                continue
            }
            let mean = values.reduce(0, +) / Double(values.count)
            let satisfaction = rule.satisfaction(mean) ?? 0
            let points = satisfaction * Double(rule.weight)
            earnedPoints += points
            availableWeight += Double(rule.weight)

            let sample = hours.first(where: { $0.value(rule.metric) != nil })?.sample(rule.metric)
            preferredResults.append(
                PreferredEvaluation(rule: rule,
                                    measuredValue: mean,
                                    satisfaction: satisfaction,
                                    pointsEarned: points,
                                    confidence: sample?.confidence ?? .unknown,
                                    sourceID: sample?.sourceID)
            )
        }

        // Score is expressed over the weight that could actually be assessed,
        // and completeness reports how much of the intent was measurable.
        let score: Double? = availableWeight > 0 ? (earnedPoints / availableWeight) * 100 : nil

        let neededMetrics = Set(rules.map(\.metric) + preferred.map(\.metric))
        let completeness = neededMetrics.isEmpty
            ? 1.0
            : Double(neededMetrics.subtracting(missing).count) / Double(neededMetrics.count)

        // MARK: Verdict.
        let hasFail = requiredResults.contains { $0.outcome == .fail }
        let hasUnknown = requiredResults.contains { $0.outcome == .unknown }
        let verdict: WindowVerdict
        if hasFail { verdict = .notRecommended }
        else if hasUnknown { verdict = .needsVerification }
        else { verdict = .acceptable }

        return WindowCandidate(
            id: UUID(),
            start: start,
            end: end,
            placeID: place.id,
            activityID: activity.id,
            verdict: verdict,
            score: score,
            requiredResults: requiredResults,
            preferredResults: preferredResults,
            stability: stability(hours: hours, metrics: neededMetrics),
            completeness: completeness,
            missingMetrics: missing.sorted { $0.rawValue < $1.rawValue },
            rulesVersion: rulesVersion,
            snapshotID: snapshot.id,
            snapshotCapturedAt: snapshot.capturedAt,
            evaluatedAt: Date(),
            timeZoneIdentifier: snapshot.timeZoneIdentifier
        )
    }

    /// The reading that most endangers the rule inside the window.
    private static func worstCase(for rule: ConditionRule,
                                  readings: [(value: Double, hour: HourlyConditions)]) -> (value: Double, hour: HourlyConditions)? {
        guard !readings.isEmpty else { return nil }
        switch rule.comparison {
        case .atMost:
            return readings.max(by: { $0.value < $1.value })
        case .atLeast:
            return readings.min(by: { $0.value < $1.value })
        case .between:
            let mid = (rule.value + (rule.upperValue ?? rule.value)) / 2
            return readings.max(by: { abs($0.value - mid) < abs($1.value - mid) })
        }
    }

    /// 0...1, where 1 means the conditions barely move inside the window.
    private static func stability(hours: [HourlyConditions], metrics: Set<MetricKind>) -> Double? {
        guard hours.count > 1, !metrics.isEmpty else { return nil }
        var spreads: [Double] = []
        for metric in metrics {
            let values = hours.compactMap { $0.value(metric) }
            guard values.count > 1 else { continue }
            let range = metric.uiRange
            let span = range.upperBound - range.lowerBound
            guard span > 0, let min = values.min(), let max = values.max() else { continue }
            spreads.append((max - min) / span)
        }
        guard !spreads.isEmpty else { return nil }
        let meanSpread = spreads.reduce(0, +) / Double(spreads.count)
        return Swift.max(0, Swift.min(1, 1 - meanSpread * 2.5))
    }

    /// Ranks rejected windows so the "closest" one can be shown honestly.
    private static func closenessScore(_ candidate: WindowCandidate) -> Double {
        let failures = Double(candidate.failedRequired.count)
        let unknowns = Double(candidate.unknownRequired.count)
        return -(failures * 10 + unknowns * 4) + (candidate.score ?? 0) / 100
    }

    /// Keeps the best candidate among overlapping windows so the list shows
    /// distinct options rather than 30-minute shifts of the same interval.
    private static func dedupe(_ candidates: [WindowCandidate]) -> [WindowCandidate] {
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return (lhs.score ?? 0) > (rhs.score ?? 0)
        }
        var kept: [WindowCandidate] = []
        for candidate in sorted {
            if let last = kept.last,
               last.verdict == candidate.verdict,
               candidate.start < last.end {
                if (candidate.score ?? 0) > (last.score ?? 0) {
                    kept[kept.count - 1] = candidate
                }
                continue
            }
            kept.append(candidate)
        }
        return kept
    }
}
