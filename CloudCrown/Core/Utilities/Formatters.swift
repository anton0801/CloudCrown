//
//  Formatters.swift
//  CloudCrown
//

import Foundation

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func string(for date: Date, relativeTo now: Date = Date()) -> String {
        let delta = now.timeIntervalSince(date)
        if abs(delta) < 60 { return "just now" }
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// True when a snapshot is older than the freshness budget for its kind.
    static func isStale(_ date: Date?, maxAge: TimeInterval, now: Date = Date()) -> Bool {
        guard let date = date else { return true }
        return now.timeIntervalSince(date) > maxAge
    }
}

enum SkyFormat {

    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f.string(from: date)
    }

    static func dayShort(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: date)
    }

    static func weekday(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }

    static func dayNumber(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("d")
        return f.string(from: date)
    }

    static func fullDateTime(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func range(_ start: Date, _ end: Date, timeZone: TimeZone) -> String {
        "\(clock(start, timeZone: timeZone)) – \(clock(end, timeZone: timeZone))"
    }

    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Formats a numeric metric, or the explicit Unknown marker when absent.
    static func number(_ value: Double?, decimals: Int = 0, unknown: String = "—") -> String {
        guard let value = value else { return unknown }
        return String(format: "%.\(decimals)f", value)
    }

    static func signed(_ value: Double, decimals: Int = 0) -> String {
        let s = String(format: "%.\(decimals)f", abs(value))
        return value >= 0 ? "+\(s)" : "−\(s)"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func coordinate(_ value: Double, precision: LocationPrecision) -> String {
        String(format: "%.\(precision.decimals)f", value)
    }
}

extension Date {
    func startOfDay(in timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.startOfDay(for: self)
    }

    func adding(days: Int, in timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(byAdding: .day, value: days, to: self) ?? self
    }

    func minutesFromMidnight(in timeZone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: self)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    func isSameDay(as other: Date, in timeZone: TimeZone) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.isDate(self, inSameDayAs: other)
    }
}
