//
//  InsightsEngine.swift
//  CloudCrown
//
//  Personal patterns derived only from rated feedback. Every insight names the
//  plans it came from. No medical or health conclusions are ever drawn.
//

import Foundation

struct InsightsEngine {

    /// Insights stay hidden until enough rated activities exist to mean anything.
    static let minimumRatedEntries = 10

    struct Insight: Identifiable {
        enum Kind { case reliableHours, commonMismatch, preferredPlace, forecastAccuracy }

        let id = UUID()
        let kind: Kind
        let title: String
        let detail: String
        let supportingPlanIDs: [UUID]
        let confidenceNote: String
    }

    struct Report {
        let ratedCount: Int
        let requiredCount: Int
        let activityID: UUID?
        let insights: [Insight]

        var isUnlocked: Bool { ratedCount >= requiredCount }
        var remaining: Int { max(0, requiredCount - ratedCount) }
    }

    static func build(feedback allFeedback: [FeedbackEntry],
                      plans: [Plan],
                      places: [Place],
                      activityID: UUID?) -> Report {

        let scoped = activityID.map { id in allFeedback.filter { $0.activityID == id && $0.isRated } }
            ?? allFeedback.filter(\.isRated)

        guard scoped.count >= minimumRatedEntries else {
            return Report(ratedCount: scoped.count,
                          requiredCount: minimumRatedEntries,
                          activityID: activityID,
                          insights: [])
        }

        var insights: [Insight] = []

        // MARK: Most reliable hours — buckets with the highest mean comfort.
        var hourBuckets: [Int: [FeedbackEntry]] = [:]
        for entry in scoped {
            let tz = places.first(where: { $0.id == entry.placeID })?.timeZone ?? .current
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            let hour = cal.component(.hour, from: entry.windowStart)
            hourBuckets[hour, default: []].append(entry)
        }
        let rankedHours = hourBuckets
            .filter { $0.value.count >= 2 }
            .map { (hour: $0.key, mean: meanRating($0.value), entries: $0.value) }
            .sorted { $0.mean > $1.mean }

        if let top = rankedHours.first, top.mean >= 3.5 {
            let window = "\(String(format: "%02d:00", top.hour))–\(String(format: "%02d:00", (top.hour + 1) % 24))"
            insights.append(Insight(
                kind: .reliableHours,
                title: "Most reliable hours: \(window)",
                detail: "Across \(top.entries.count) rated activities starting in this hour, your average comfort was \(String(format: "%.1f", top.mean)) out of 5.",
                supportingPlanIDs: top.entries.map(\.planID),
                confidenceNote: top.entries.count < 4
                    ? "Based on only \(top.entries.count) entries — treat as a weak signal."
                    : "Based on \(top.entries.count) entries."
            ))
        }

        // MARK: Common mismatches — where the forecast and reality diverged.
        var tagCounts: [FeedbackTag: [FeedbackEntry]] = [:]
        for entry in scoped {
            for tag in entry.mismatchTags { tagCounts[tag, default: []].append(entry) }
        }
        if let top = tagCounts.max(by: { $0.value.count < $1.value.count }), top.value.count >= 2 {
            let share = Double(top.value.count) / Double(scoped.count)
            let metricNote = top.key.relatedMetric.map {
                " Your \($0.title.lowercased()) limit may be worth revisiting."
            } ?? ""
            insights.append(Insight(
                kind: .commonMismatch,
                title: "Common mismatch: \(top.key.title)",
                detail: "You marked “\(top.key.title)” on \(top.value.count) of \(scoped.count) rated activities (\(SkyFormat.percent(share))).\(metricNote)",
                supportingPlanIDs: top.value.map(\.planID),
                confidenceNote: "Counted from your own feedback tags only."
            ))
        }

        // MARK: Preferred places — highest mean comfort per place.
        var placeBuckets: [UUID: [FeedbackEntry]] = [:]
        for entry in scoped { placeBuckets[entry.placeID, default: []].append(entry) }
        let rankedPlaces = placeBuckets
            .filter { $0.value.count >= 2 }
            .map { (id: $0.key, mean: meanRating($0.value), entries: $0.value) }
            .sorted { $0.mean > $1.mean }

        if let top = rankedPlaces.first, let place = places.first(where: { $0.id == top.id }) {
            insights.append(Insight(
                kind: .preferredPlace,
                title: "Preferred place: \(place.name)",
                detail: "Average comfort \(String(format: "%.1f", top.mean)) out of 5 across \(top.entries.count) rated activities here.",
                supportingPlanIDs: top.entries.map(\.planID),
                confidenceNote: rankedPlaces.count < 2
                    ? "Only one place has enough rated activities to compare."
                    : "Compared against \(rankedPlaces.count) places with at least two entries."
            ))
        }

        // MARK: Forecast agreement — how often a high score felt good.
        let withScores = scoped.filter { $0.forecastScore != nil }
        if withScores.count >= 4 {
            let agreed = withScores.filter { entry in
                guard let score = entry.forecastScore, let rating = entry.comfortRating else { return false }
                return (score >= 70 && rating >= 4) || (score < 70 && rating <= 3)
            }
            let share = Double(agreed.count) / Double(withScores.count)
            insights.append(Insight(
                kind: .forecastAccuracy,
                title: "Score matched your experience \(SkyFormat.percent(share)) of the time",
                detail: "On \(agreed.count) of \(withScores.count) rated activities, a score of 70+ came with a comfort rating of 4–5, or a lower score came with 3 or below.",
                supportingPlanIDs: withScores.map(\.planID),
                confidenceNote: "This measures agreement with your ratings, not forecast accuracy in general."
            ))
        }

        return Report(ratedCount: scoped.count,
                      requiredCount: minimumRatedEntries,
                      activityID: activityID,
                      insights: insights)
    }

    private static func meanRating(_ entries: [FeedbackEntry]) -> Double {
        let ratings = entries.compactMap { $0.comfortRating }.map(Double.init)
        guard !ratings.isEmpty else { return 0 }
        return ratings.reduce(0, +) / Double(ratings.count)
    }
}
