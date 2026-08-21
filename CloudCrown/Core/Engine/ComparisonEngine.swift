//
//  ComparisonEngine.swift
//  CloudCrown
//
//  Compares up to five days for one activity at ONE place. Days from different
//  places or time zones are never mixed into the same comparison.
//

import Foundation

struct ComparisonEngine {

    static let maxDays = 5

    struct DaySummary: Identifiable {
        let id = UUID()
        let date: Date
        let timeZone: TimeZone
        let bestWindow: WindowCandidate?
        let usableWindowCount: Int
        let blockedWindowCount: Int
        /// 0...1 across the day's evaluated windows.
        let stability: Double?
        let maxUV: Double?
        let maxRainProbability: Double?
        let hourCoverage: Double
        let missingMetrics: [MetricKind]

        var score: Double? { bestWindow?.score }
        var isComplete: Bool { hourCoverage >= 0.999 && missingMetrics.isEmpty }
        var hasUsableWindow: Bool { usableWindowCount > 0 }
    }

    enum Highlight: String, CaseIterable, Identifiable {
        case bestOverall, mostStable, lowestUV, lowestRain
        var id: String { rawValue }

        var title: String {
            switch self {
            case .bestOverall: return "Best Overall"
            case .mostStable: return "Most Stable"
            case .lowestUV: return "Lowest UV"
            case .lowestRain: return "Lowest Rain Risk"
            }
        }

        var icon: String {
            switch self {
            case .bestOverall: return "crown.fill"
            case .mostStable: return "waveform.path.ecg"
            case .lowestUV: return "sun.min"
            case .lowestRain: return "umbrella"
            }
        }
    }

    struct Result {
        let placeID: UUID
        let activityID: UUID
        let days: [DaySummary]
        let snapshotID: UUID
        let snapshotCapturedAt: Date
        let rulesVersion: String
        /// Winner per highlight, plus a note when the winner is incomplete.
        let winners: [Highlight: UUID]
        let incompleteWarnings: [Highlight: String]
    }

    static func compare(activity: ActivityTemplate,
                        profile: ComfortProfile?,
                        place: Place,
                        snapshot: ConditionSnapshot,
                        startDate: Date,
                        dayCount: Int) -> Result {

        let timeZone = snapshot.timeZone
        let count = min(max(dayCount, 1), maxDays)
        var summaries: [DaySummary] = []

        for offset in 0..<count {
            let day = startDate.startOfDay(in: timeZone).adding(days: offset, in: timeZone)
            let query = WindowQuery(activityID: activity.id,
                                    placeID: place.id,
                                    startDate: day,
                                    endDate: day,
                                    earliestMinute: activity.earliestMinute,
                                    latestMinute: activity.latestMinute,
                                    durationMinutes: activity.durationMinutes)

            let result = WindowEngine.findWindows(query: query,
                                                  activity: activity,
                                                  profile: profile,
                                                  place: place,
                                                  snapshot: snapshot,
                                                  usedCachedSnapshot: false,
                                                  limit: 60)

            let usable = result.candidates.filter { $0.verdict.isUsable }
            let best = usable.max(by: { ($0.score ?? -1) < ($1.score ?? -1) })

            let dayHours = snapshot.hours.filter { $0.date.isSameDay(as: day, in: timeZone) }
            let coverage = dayHours.isEmpty ? 0 : Double(dayHours.count) / 24.0

            let stabilities = usable.compactMap(\.stability)
            let dayStability = stabilities.isEmpty ? nil : stabilities.reduce(0, +) / Double(stabilities.count)

            let uvValues = dayHours.compactMap { $0.value(.uvIndex) }
            let rainValues = dayHours.compactMap { $0.value(.precipitationProbability) }

            var missing: Set<MetricKind> = Set(snapshot.unavailableMetrics)
            for metric in activity.allMetrics where dayHours.allSatisfy({ $0.value(metric) == nil }) {
                missing.insert(metric)
            }

            summaries.append(DaySummary(
                date: day,
                timeZone: timeZone,
                bestWindow: best,
                usableWindowCount: usable.count,
                blockedWindowCount: result.candidates.count - usable.count,
                stability: dayStability,
                maxUV: uvValues.max(),
                maxRainProbability: rainValues.max(),
                hourCoverage: min(1, coverage),
                missingMetrics: missing.sorted { $0.rawValue < $1.rawValue }
            ))
        }

        var winners: [Highlight: UUID] = [:]
        var warnings: [Highlight: String] = [:]

        func pick(_ highlight: Highlight, from candidates: [DaySummary], by better: (DaySummary, DaySummary) -> Bool) {
            guard let winner = candidates.max(by: { better($1, $0) }) else { return }
            winners[highlight] = winner.id
            if !winner.isComplete {
                let missing = winner.missingMetrics.map(\.title).joined(separator: ", ")
                warnings[highlight] = missing.isEmpty
                    ? "This day has incomplete hourly coverage — the comparison is partial."
                    : "This day is missing \(missing), so it leads on partial data."
            }
        }

        pick(.bestOverall, from: summaries.filter { $0.score != nil }) { ($0.score ?? -1) > ($1.score ?? -1) }
        pick(.mostStable, from: summaries.filter { $0.stability != nil }) { ($0.stability ?? -1) > ($1.stability ?? -1) }
        pick(.lowestUV, from: summaries.filter { $0.maxUV != nil }) { ($0.maxUV ?? .infinity) < ($1.maxUV ?? .infinity) }
        pick(.lowestRain, from: summaries.filter { $0.maxRainProbability != nil }) {
            ($0.maxRainProbability ?? .infinity) < ($1.maxRainProbability ?? .infinity)
        }

        return Result(placeID: place.id,
                      activityID: activity.id,
                      days: summaries,
                      snapshotID: snapshot.id,
                      snapshotCapturedAt: snapshot.capturedAt,
                      rulesVersion: WindowEngine.rulesVersion,
                      winners: winners,
                      incompleteWarnings: warnings)
    }
}
