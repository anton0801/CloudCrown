//
//  DayComparisonView.swift
//  CloudCrown
//
//  Compares up to five days for ONE activity at ONE place. Days from different
//  places or time zones are never mixed, and an incomplete day never leads
//  without a visible warning.
//

import SwiftUI

struct DayComparisonView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: DayComparisonPresenter
    @StateObject private var router: DayComparisonRouter

    init(presenter: @autoclosure @escaping () -> DayComparisonPresenter,
         router: @autoclosure @escaping () -> DayComparisonRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            content
        }
        .navigationTitle("Compare Days")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { router.showsActivityPicker = true } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(SkyPalette.azure)
            }
        }
        .onAppear { presenter.onAppear() }
        .routed($router.route) { router.destination(for: $0) }
        .skyToast($presenter.toast)
        .sheet(isPresented: $router.showsActivityPicker) {
            ActivityPickerSheet(activities: presenter.activities,
                                selectedID: presenter.activityID) { activity in
                presenter.changeActivity(activity)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.state {
        case .loading:
            ScrollView(showsIndicators: false) { LoadingCardsView(count: 3).padding(SkySpacing.l) }
        case .missingEntity(let message):
            EmptyStateView(icon: "questionmark.folder", title: "Cannot compare", message: message)
        case .unavailable(let reason, let isOffline):
            ScrollView(showsIndicators: false) {
                ErrorStateView(
                    message: isOffline ? "Offline and no stored conditions" : "Conditions unavailable",
                    detail: reason,
                    onRetry: { presenter.load(forceRefresh: true) }
                )
                .padding(SkySpacing.l)
            }
        case .ready:
            readyContent
        }
    }

    private var readyContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SkySpacing.l) {
                scopeCard
                if presenter.isCached {
                    CachedBanner(updatedAt: presenter.snapshot?.capturedAt) {
                        presenter.load(forceRefresh: true)
                    }
                }
                highlightPicker
                if let warning = presenter.incompleteWarning {
                    WarningBanner(level: .warning, title: "The leading day is incomplete", message: warning)
                }
                chart
                dayCards
                if !presenter.hasAnyUsableDay { noUsableDayCard }
                Spacer(minLength: SkySpacing.xxl)
            }
            .padding(SkySpacing.l)
        }
    }

    // MARK: - Scope

    private var scopeCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: SkySpacing.s) {
                    Image(systemName: presenter.activity?.kind.icon ?? "figure.walk")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(presenter.activity?.kind.accent ?? SkyPalette.azure)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(presenter.activity?.name ?? "Activity")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text("\(presenter.place?.name ?? "Place") · \(presenter.timeZone.identifier)")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                Text("All days below use this one place and time zone. Different places are never compared in the same table.")
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Days")
                        .font(SkyFont.micro(11).weight(.semibold))
                        .foregroundColor(SkyPalette.textTertiary)
                    Spacer()
                    ForEach(2...ComparisonEngine.maxDays, id: \.self) { count in
                        Button { presenter.changeDayCount(count) } label: {
                            Text("\(count)")
                                .font(SkyFont.micro(12).weight(.bold))
                                .foregroundColor(presenter.dayCount == count ? .white : SkyPalette.textSecondary)
                                .frame(width: 30, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                        .fill(presenter.dayCount == count
                                              ? AnyShapeStyle(SkyPalette.azure)
                                              : AnyShapeStyle(SkyPalette.surfaceSunken))
                                )
                        }
                    }
                }

                if let snapshot = presenter.snapshot {
                    SourceStamp(source: snapshot.sourceSummary,
                                updatedAt: snapshot.capturedAt,
                                confidence: .high,
                                isStale: snapshot.isStale,
                                compact: true)
                }
            }
        }
    }

    // MARK: - Highlight

    private var highlightPicker: some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SkySpacing.s) {
                    ForEach(ComparisonEngine.Highlight.allCases) { highlight in
                        SkyChip(title: highlight.title,
                                icon: highlight.icon,
                                color: SkyPalette.gold,
                                isSelected: presenter.highlight == highlight) {
                            withAnimation(.easeOut(duration: 0.2)) { presenter.highlight = highlight }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            Text(presenter.highlightCaption())
                .font(SkyFont.micro(11))
                .foregroundColor(SkyPalette.textTertiary)
        }
    }

    // MARK: - Chart

    private var chart: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: presenter.highlight.title)
                HStack(alignment: .bottom, spacing: SkySpacing.s) {
                    ForEach(presenter.days) { day in
                        VStack(spacing: 6) {
                            Text(presenter.highlightValue(day))
                                .font(SkyFont.metric(14))
                                .foregroundColor(presenter.isWinner(day) ? SkyPalette.gold : SkyPalette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(SkyPalette.surfaceSunken)
                                    .frame(height: 110)
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(presenter.isWinner(day)
                                          ? AnyShapeStyle(LinearGradient(colors: [SkyPalette.gold, Color(hex: 0xE8B33A)],
                                                                         startPoint: .top, endPoint: .bottom))
                                          : AnyShapeStyle(SkyPalette.azure.opacity(0.55)))
                                    .frame(height: max(6, 110 * barFraction(day)))
                                if !day.isComplete {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(SkyPalette.unknown,
                                                      style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                        .frame(height: 110)
                                }
                            }

                            Text(SkyFormat.weekday(day.date, timeZone: day.timeZone))
                                .font(SkyFont.micro(10).weight(.semibold))
                                .foregroundColor(SkyPalette.textSecondary)
                            if presenter.isWinner(day) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(SkyPalette.gold)
                            } else {
                                Spacer().frame(height: 12)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: SkySpacing.m) {
                    legendItem(SkyPalette.gold, "Leads on this measure")
                    legendItem(SkyPalette.unknown, "Dashed = incomplete day")
                }
            }
        }
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 6)
            Text(text).font(SkyFont.micro(9)).foregroundColor(SkyPalette.textTertiary)
        }
    }

    private func barFraction(_ day: ComparisonEngine.DaySummary) -> Double {
        switch presenter.highlight {
        case .bestOverall:
            return (day.score ?? 0) / 100
        case .mostStable:
            return day.stability ?? 0
        case .lowestUV:
            guard let uv = day.maxUV else { return 0 }
            // Inverted: a lower reading fills more of the bar.
            return max(0.05, 1 - min(1, uv / 11))
        case .lowestRain:
            guard let rain = day.maxRainProbability else { return 0 }
            return max(0.05, 1 - min(1, rain / 100))
        }
    }

    // MARK: - Day cards

    private var dayCards: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Day by day")
            ForEach(presenter.days) { day in
                CloudCard(tint: presenter.isWinner(day) ? SkyPalette.gold : SkyPalette.azure) {
                    VStack(alignment: .leading, spacing: SkySpacing.m) {
                        HStack(spacing: SkySpacing.m) {
                            VStack(spacing: 2) {
                                Text(SkyFormat.weekday(day.date, timeZone: day.timeZone).uppercased())
                                    .font(SkyFont.micro(9).weight(.bold))
                                    .foregroundColor(SkyPalette.textTertiary)
                                Text(SkyFormat.dayNumber(day.date, timeZone: day.timeZone))
                                    .font(SkyFont.metric(22))
                                    .foregroundColor(SkyPalette.textPrimary)
                            }
                            .frame(width: 40)

                            VStack(alignment: .leading, spacing: 3) {
                                if let window = day.bestWindow {
                                    Text(window.timeRangeText())
                                        .font(SkyFont.headline(15))
                                        .foregroundColor(SkyPalette.textPrimary)
                                    Text("\(day.usableWindowCount) usable · \(day.blockedWindowCount) blocked")
                                        .font(SkyFont.micro(11))
                                        .foregroundColor(SkyPalette.textSecondary)
                                } else {
                                    Text("No usable window")
                                        .font(SkyFont.headline(15))
                                        .foregroundColor(SkyPalette.textSecondary)
                                    Text("\(day.blockedWindowCount) interval\(day.blockedWindowCount == 1 ? "" : "s") blocked by required conditions")
                                        .font(SkyFont.micro(11))
                                        .foregroundColor(SkyPalette.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                            GlowRing(score: day.score,
                                     verdictColor: day.bestWindow?.verdict.color ?? SkyPalette.unknown,
                                     size: 48)
                        }

                        HStack(spacing: SkySpacing.s) {
                            metricChip("UV", day.maxUV.map { SkyFormat.number($0, decimals: 1) }, SkyPalette.gold)
                            metricChip("Rain", day.maxRainProbability.map { "\(Int($0.rounded()))%" }, SkyPalette.azure)
                            metricChip("Stability", day.stability.map { SkyFormat.percent($0) }, SkyPalette.lightBlue)
                        }

                        if !day.isComplete {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(SkyPalette.warning)
                                Text(incompleteMessage(day))
                                    .font(SkyFont.micro(10))
                                    .foregroundColor(SkyPalette.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if day.bestWindow != nil {
                            Button { presenter.openDay(day) } label: {
                                HStack(spacing: 5) {
                                    Text("Why this window?")
                                        .font(SkyFont.caption(12).weight(.semibold))
                                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                                }
                                .foregroundColor(SkyPalette.azure)
                            }
                        }
                    }
                }
            }
        }
    }

    private func incompleteMessage(_ day: ComparisonEngine.DaySummary) -> String {
        var parts: [String] = []
        if day.hourCoverage < 0.999 {
            parts.append("only \(SkyFormat.percent(day.hourCoverage)) of the day is covered by the forecast")
        }
        if !day.missingMetrics.isEmpty {
            parts.append("missing \(day.missingMetrics.map(\.title).joined(separator: ", "))")
        }
        return "Incomplete day — " + parts.joined(separator: "; ") + "."
    }

    private func metricChip(_ title: String, _ value: String?, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title).font(SkyFont.micro(9)).foregroundColor(SkyPalette.textTertiary)
            if let value = value {
                Text(value).font(SkyFont.micro(11).weight(.bold)).foregroundColor(color)
            } else {
                Text("Unknown").font(SkyFont.micro(10).weight(.semibold)).foregroundColor(SkyPalette.unknown)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.10)))
    }

    private var noUsableDayCard: some View {
        WarningBanner(
            level: .warning,
            title: "No day has a usable window",
            message: "Every interval on every compared day broke a required condition or lacked the data to check one. The bars above still show how the days differ, so you can decide which limit to revisit."
        )
    }
}

// MARK: - Activity picker

struct ActivityPickerSheet: View {
    let activities: [ActivityTemplate]
    let selectedID: UUID
    let onPick: (ActivityTemplate) -> Void

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SkySpacing.s) {
                        ForEach(activities) { activity in
                            Button {
                                onPick(activity)
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                HStack(spacing: SkySpacing.m) {
                                    ZStack {
                                        Circle().fill(activity.kind.accent.opacity(0.13)).frame(width: 36, height: 36)
                                        Image(systemName: activity.kind.icon)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(activity.kind.accent)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(activity.name)
                                            .font(SkyFont.caption(14).weight(.medium))
                                            .foregroundColor(SkyPalette.textPrimary)
                                        Text("\(activity.requiredConditions.count) required · \(SkyFormat.duration(minutes: activity.durationMinutes))")
                                            .font(SkyFont.micro(10))
                                            .foregroundColor(SkyPalette.textSecondary)
                                    }
                                    Spacer()
                                    if activity.id == selectedID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(SkyPalette.success)
                                    }
                                }
                                .padding(SkySpacing.m)
                                .background(RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                                    .fill(SkyPalette.surface))
                                .overlay(RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                                    .strokeBorder(SkyPalette.hairline, lineWidth: 1))
                            }
                            .buttonStyle(SkyPressStyle())
                        }
                    }
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle("Change Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                        .foregroundColor(SkyPalette.textSecondary)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
