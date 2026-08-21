//
//  SkyRows.swift
//  CloudCrown
//
//  Reusable rows for windows, plans, metrics and history entries.
//

import SwiftUI

// MARK: - Metric tile

struct MetricTile: View {
    let metric: MetricKind
    let value: Double?
    let settings: AppSettings
    var observation: ObservationKind?
    var confidence: Confidence = .unknown
    var updatedAt: Date?
    var isCompact: Bool = false
    var action: (() -> Void)?

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: metric.icon)
                    .font(.system(size: isCompact ? 10 : 12, weight: .semibold))
                    .foregroundColor(metric.accentColor)
                Text(metric.shortTitle)
                    .font(SkyFont.micro(isCompact ? 10 : 11))
                    .foregroundColor(SkyPalette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(SkyPalette.hairline)
                }
            }

            if let value = value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(SkyFormat.number(settings.display(value, for: metric), decimals: metric.decimals))
                        .font(SkyFont.metric(isCompact ? 18 : 22))
                        .foregroundColor(SkyPalette.textPrimary)
                    Text(settings.unitSymbol(for: metric))
                        .font(SkyFont.micro(isCompact ? 9 : 10))
                        .foregroundColor(SkyPalette.textTertiary)
                }
            } else {
                UnknownTag()
            }

            if !isCompact {
                HStack(spacing: 4) {
                    if let observation = observation, value != nil {
                        Image(systemName: observation.icon).font(.system(size: 7))
                        Text(observation.label).font(SkyFont.micro(9))
                    }
                    if value != nil {
                        Circle().fill(confidence.color).frame(width: 4, height: 4)
                        Text(confidence.shortLabel).font(SkyFont.micro(9))
                    }
                }
                .foregroundColor(SkyPalette.textTertiary)
                .lineLimit(1)
            }
        }
        .padding(isCompact ? SkySpacing.s : SkySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(SkyPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .strokeBorder(value == nil ? SkyPalette.unknown.opacity(0.25) : SkyPalette.hairline, lineWidth: 1)
        )

        if let action = action {
            Button(action: action) { content }.buttonStyle(SkyPressStyle())
        } else {
            content
        }
    }
}

// MARK: - Window row

struct WindowRow: View {
    let window: WindowCandidate
    var showsDay: Bool = true
    var isSuperseded: Bool = false
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: SkySpacing.m) {
            VStack(spacing: 2) {
                Text(SkyFormat.weekday(window.start, timeZone: window.timeZone).uppercased())
                    .font(SkyFont.micro(9).weight(.bold))
                    .foregroundColor(SkyPalette.textTertiary)
                Text(SkyFormat.dayNumber(window.start, timeZone: window.timeZone))
                    .font(SkyFont.metric(20))
                    .foregroundColor(SkyPalette.textPrimary)
            }
            .frame(width: 38)
            .opacity(showsDay ? 1 : 0)
            .frame(width: showsDay ? 38 : 0)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: SkySpacing.s) {
                    Text(window.timeRangeText())
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                    VerdictPill(verdict: window.verdict, compact: true)
                    if isSuperseded {
                        SkyChip(title: "Superseded", icon: "clock.arrow.circlepath", color: SkyPalette.warning)
                    }
                }
                Text(window.headline)
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SkySpacing.s) {
                    if !window.isComplete {
                        SkyChip(title: "\(SkyFormat.percent(window.completeness)) data", icon: "questionmark.circle", color: SkyPalette.unknown)
                    }
                    if let stability = window.stability {
                        SkyChip(title: "Stability \(SkyFormat.percent(stability))", icon: "waveform.path.ecg", color: SkyPalette.lightBlue)
                    }
                }
            }

            Spacer(minLength: 0)

            GlowRing(score: window.score, verdictColor: window.verdict.color, size: 50)
        }
        .padding(SkySpacing.m)
        .background(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(SkyPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .strokeBorder(window.verdict.color.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: window.verdict.color.opacity(0.08), radius: 10, y: 4)

        if let action = action {
            Button(action: action) { content }.buttonStyle(SkyPressStyle())
        } else {
            content
        }
    }
}

// MARK: - Plan row

struct PlanRow: View {
    let plan: Plan
    let activityName: String
    let placeName: String
    var awaitsFeedback: Bool = false
    var action: (() -> Void)?

    var body: some View {
        let content = VStack(alignment: .leading, spacing: SkySpacing.s) {
            HStack(spacing: SkySpacing.s) {
                ZStack {
                    Circle().fill(plan.status.color.opacity(0.14)).frame(width: 34, height: 34)
                    Image(systemName: plan.status.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(plan.status.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                        .lineLimit(1)
                    Text("\(activityName) · \(placeName)")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let score = plan.window.score {
                    CrownBadge(progress: score / 100,
                               tint: plan.window.verdict.color,
                               size: 38,
                               label: "\(Int(score.rounded()))")
                } else {
                    UnknownTag(text: "No score")
                }
            }

            HStack(spacing: SkySpacing.s) {
                SkyChip(title: "\(plan.window.dayText()) · \(plan.window.timeRangeText())",
                        icon: "clock", color: SkyPalette.azure)
                if plan.isCalendarConfirmed {
                    SkyChip(title: "In calendar", icon: "checkmark.seal.fill", color: SkyPalette.success)
                }
                if plan.backupWindow != nil {
                    SkyChip(title: "Backup", icon: "arrow.triangle.2.circlepath", color: SkyPalette.violet)
                }
            }

            if plan.hasOpenRisk, let risk = plan.openRisks.last {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(SkyPalette.warning)
                    Text(risk.summary)
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if awaitsFeedback {
                HStack(spacing: 6) {
                    Image(systemName: "star.bubble.fill")
                        .font(.system(size: 10))
                        .foregroundColor(SkyPalette.violet)
                    Text("Finished — record how it actually went")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.violet)
                }
            }
        }
        .padding(SkySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(SkyPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .strokeBorder(plan.hasOpenRisk ? SkyPalette.warning.opacity(0.4) : SkyPalette.hairline, lineWidth: 1)
        )
        .shadow(color: SkyPalette.azure.opacity(0.07), radius: 10, y: 4)

        if let action = action {
            Button(action: action) { content }.buttonStyle(SkyPressStyle())
        } else {
            content
        }
    }
}

// MARK: - History row

struct HistoryRow: View {
    let record: HistoryRecord
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(alignment: .top, spacing: SkySpacing.m) {
            ZStack {
                Circle().fill(record.kind.color.opacity(0.13)).frame(width: 32, height: 32)
                Image(systemName: record.kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(record.kind.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(SkyFont.caption(14).weight(.medium))
                    .foregroundColor(SkyPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !record.detail.isEmpty {
                    Text(record.detail)
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(record.changes.prefix(3), id: \.self) { change in
                    HStack(spacing: 4) {
                        Circle().fill(SkyPalette.textTertiary).frame(width: 3, height: 3)
                        Text(change)
                            .font(SkyFont.micro(10))
                            .foregroundColor(SkyPalette.textTertiary)
                    }
                }
                HStack(spacing: 5) {
                    Text(record.entityType.title)
                        .font(SkyFont.micro(9).weight(.semibold))
                        .foregroundColor(SkyPalette.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(SkyPalette.surfaceSunken))
                    Text(RelativeTime.string(for: record.timestamp))
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                }
                .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .padding(SkySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(SkyPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .strokeBorder(SkyPalette.hairline, lineWidth: 1)
        )

        if let action = action {
            Button(action: action) { content }.buttonStyle(SkyPressStyle())
        } else {
            content
        }
    }
}

// MARK: - Setup gap card

struct SetupGapCard: View {
    let gap: SetupGap
    let action: () -> Void

    var body: some View {
        CloudCard(tint: SkyPalette.violet) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: SkySpacing.s) {
                    ZStack {
                        Circle().fill(SkyPalette.violet.opacity(0.13)).frame(width: 34, height: 34)
                        Image(systemName: gap.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SkyPalette.violet)
                    }
                    Text(gap.title)
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                    Spacer(minLength: 0)
                }
                Text(gap.reason)
                    .font(SkyFont.caption(13))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SkyButton(title: gap.actionTitle, icon: "arrow.right", kind: .secondary, action: action)
            }
        }
    }
}
