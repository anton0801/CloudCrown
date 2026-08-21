//
//  ConditionSnapshot.swift
//  CloudCrown
//
//  An immutable, identifiable capture of external conditions for one place.
//  Every window evaluation records the snapshot id it was computed from, so
//  any score can be reproduced or marked Superseded later.
//

import Foundation

struct HourlyConditions: Codable, Hashable, Identifiable {
    var date: Date
    var samples: [MetricSample]

    var id: Date { date }

    func sample(_ kind: MetricKind) -> MetricValue? {
        samples.first(where: { $0.kind == kind })?.value
    }

    func value(_ kind: MetricKind) -> Double? {
        sample(kind)?.value
    }

    var knownCount: Int { samples.filter { $0.value.isKnown }.count }
}

struct DailyConditions: Codable, Hashable, Identifiable {
    var date: Date
    var sunrise: Date?
    var sunset: Date?
    var daylightMinutes: Double?
    var maxUV: Double?
    var precipitationSum: Double?

    var id: Date { date }
}

struct ConditionSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var placeID: UUID
    var capturedAt: Date
    var timeZoneIdentifier: String
    var sources: [DataSource]
    var hours: [HourlyConditions]
    var days: [DailyConditions]
    /// Metrics the provider did not return at all for this place.
    var unavailableMetrics: [MetricKind]

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    init(id: UUID = UUID(),
         placeID: UUID,
         capturedAt: Date,
         timeZoneIdentifier: String,
         sources: [DataSource],
         hours: [HourlyConditions],
         days: [DailyConditions],
         unavailableMetrics: [MetricKind] = []) {
        self.id = id
        self.placeID = placeID
        self.capturedAt = capturedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sources = sources
        self.hours = hours
        self.days = days
        self.unavailableMetrics = unavailableMetrics
    }

    /// Snapshots older than this are shown as "may be outdated", never as current.
    static let freshnessBudget: TimeInterval = 60 * 60

    var isStale: Bool {
        Date().timeIntervalSince(capturedAt) > Self.freshnessBudget
    }

    func hour(nearest date: Date) -> HourlyConditions? {
        hours.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    func hours(from start: Date, to end: Date) -> [HourlyConditions] {
        hours.filter { $0.date >= start.addingTimeInterval(-1800) && $0.date < end }
    }

    func day(containing date: Date) -> DailyConditions? {
        days.first(where: { $0.date.isSameDay(as: date, in: timeZone) })
    }

    var sourceSummary: String {
        sources.map(\.name).joined(separator: " + ")
    }

    func source(id: String) -> DataSource? {
        sources.first(where: { $0.id == id })
    }

    /// Coverage of a metric across the snapshot, 0...1. Used to warn about
    /// incomplete days rather than silently treating gaps as acceptable.
    func coverage(of kind: MetricKind) -> Double {
        guard !hours.isEmpty else { return 0 }
        let known = hours.filter { $0.value(kind) != nil }.count
        return Double(known) / Double(hours.count)
    }
}
