//
//  ConditionDetailsView.swift
//  CloudCrown
//
//  Every value shows unit, observed/forecast, updated_at and confidence.
//  A missing parameter is Unknown — never 0.
//

import SwiftUI

struct ConditionDetailsView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: ConditionDetailsPresenter
    @StateObject private var router: ConditionDetailsRouter

    init(presenter: @autoclosure @escaping () -> ConditionDetailsPresenter,
         router: @autoclosure @escaping () -> ConditionDetailsRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            content
        }
        .navigationTitle(presenter.place?.name ?? "Conditions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: presenter.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(SkyPalette.azure)
                .disabled(presenter.isRefreshing)
            }
        }
        .onAppear { presenter.onAppear() }
        .skyToast($presenter.toast)
        .sheet(isPresented: $router.showsSources) {
            SourceDetailsSheet(sources: presenter.sources,
                               snapshot: presenter.snapshot,
                               unavailable: presenter.unavailableMetrics)
        }
        .sheet(item: Binding(
            get: { router.inspectedMetric.map { MetricInspection(metric: $0) } },
            set: { if $0 == nil { router.inspectedMetric = nil } }
        )) { inspection in
            MetricTimelineSheet(metric: inspection.metric, presenter: presenter)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.state {
        case .loading:
            ScrollView(showsIndicators: false) {
                LoadingCardsView(count: 4).padding(SkySpacing.l)
            }
        case .missingPlace:
            EmptyStateView(
                icon: "mappin.slash",
                title: "This place no longer exists",
                message: "It was deleted or archived. Conditions cannot be shown for a place that is not saved."
            )
        case .unavailable(let reason, let isOffline):
            ScrollView(showsIndicators: false) {
                ErrorStateView(
                    message: isOffline ? "Offline and no local snapshot" : "Conditions unavailable",
                    detail: reason + " Nothing is estimated in place of real measurements.",
                    onRetry: presenter.refresh
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
                sourceBar
                if presenter.isCached {
                    CachedBanner(updatedAt: presenter.snapshot?.capturedAt, onRetry: presenter.refresh)
                }
                dayPicker
                hourStrip
                metricsGrid
                daylightCard
                unavailableCard
                Spacer(minLength: SkySpacing.xxl)
            }
            .padding(SkySpacing.l)
        }
        .refreshable { presenter.refresh() }
    }

    // MARK: - Source bar

    private var sourceBar: some View {
        Button(action: presenter.openSources) {
            HStack(spacing: SkySpacing.s) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13))
                    .foregroundColor(SkyPalette.violet)
                VStack(alignment: .leading, spacing: 1) {
                    Text(presenter.snapshot?.sourceSummary ?? "Unknown source")
                        .font(SkyFont.caption(13).weight(.semibold))
                        .foregroundColor(SkyPalette.textPrimary)
                        .lineLimit(1)
                    if let captured = presenter.snapshot?.capturedAt {
                        Text("Data time: \(SkyFormat.fullDateTime(captured, timeZone: presenter.timeZone)) · \(RelativeTime.string(for: captured))")
                            .font(SkyFont.micro(10))
                            .foregroundColor(presenter.snapshot?.isStale == true ? SkyPalette.warning : SkyPalette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("Source Details")
                    .font(SkyFont.micro(11).weight(.semibold))
                    .foregroundColor(SkyPalette.violet)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SkyPalette.violet)
            }
            .padding(SkySpacing.m)
            .background(RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(SkyPalette.violet.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .strokeBorder(SkyPalette.violet.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(SkyPressStyle())
    }

    // MARK: - Day picker

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SkySpacing.s) {
                ForEach(presenter.availableDays, id: \.self) { day in
                    let isSelected = day.isSameDay(as: presenter.selectedDate, in: presenter.timeZone)
                    Button { presenter.selectDay(day) } label: {
                        VStack(spacing: 3) {
                            Text(SkyFormat.weekday(day, timeZone: presenter.timeZone).uppercased())
                                .font(SkyFont.micro(9).weight(.bold))
                            Text(SkyFormat.dayNumber(day, timeZone: presenter.timeZone))
                                .font(SkyFont.metric(18))
                        }
                        .foregroundColor(isSelected ? .white : SkyPalette.textSecondary)
                        .frame(width: 50, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                                .fill(isSelected ? AnyShapeStyle(SkyPalette.azureGradient) : AnyShapeStyle(SkyPalette.surface))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                                .strokeBorder(isSelected ? Color.clear : SkyPalette.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(SkyPressStyle())
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Hour strip

    private var hourStrip: some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            SectionHeader(title: "Hours", subtitle: "Tap an hour to read its exact values")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presenter.hoursForSelectedDay) { hour in
                        let isSelected = presenter.selectedHour?.date == hour.date
                        let temp = hour.value(.temperature)
                        Button { presenter.selectHour(hour) } label: {
                            VStack(spacing: 4) {
                                Text(SkyFormat.clock(hour.date, timeZone: presenter.timeZone))
                                    .font(SkyFont.micro(9).weight(.semibold))
                                if let temp = temp {
                                    Text(SkyFormat.number(presenter.settings.display(temp, for: .temperature), decimals: 0))
                                        .font(SkyFont.metric(15))
                                } else {
                                    Image(systemName: "questionmark")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                Circle()
                                    .fill(coverageColor(hour))
                                    .frame(width: 4, height: 4)
                            }
                            .foregroundColor(isSelected ? .white : SkyPalette.textPrimary)
                            .frame(width: 46, height: 62)
                            .background(
                                RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                    .fill(isSelected ? AnyShapeStyle(SkyPalette.azure) : AnyShapeStyle(SkyPalette.surface))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                    .strokeBorder(isSelected ? Color.clear : SkyPalette.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(SkyPressStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func coverageColor(_ hour: HourlyConditions) -> Color {
        let ratio = Double(hour.knownCount) / Double(max(1, hour.samples.count))
        if ratio > 0.9 { return SkyPalette.success }
        if ratio > 0.6 { return SkyPalette.warning }
        return SkyPalette.unknown
    }

    // MARK: - Metrics

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            if let hour = presenter.selectedHour {
                SectionHeader(
                    title: "Measurements",
                    subtitle: "\(SkyFormat.dayShort(hour.date, timeZone: presenter.timeZone)) at \(SkyFormat.clock(hour.date, timeZone: presenter.timeZone))"
                )
                LazyVGrid(columns: [GridItem(.flexible(), spacing: SkySpacing.s),
                                    GridItem(.flexible(), spacing: SkySpacing.s)],
                          spacing: SkySpacing.s) {
                    ForEach(presenter.detailMetrics, id: \.self) { metric in
                        let sample = hour.sample(metric)
                        MetricTile(
                            metric: metric,
                            value: sample?.value,
                            settings: presenter.settings,
                            observation: sample?.observation,
                            confidence: sample?.confidence ?? .unknown,
                            updatedAt: sample?.updatedAt,
                            action: { presenter.inspect(metric) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Daylight

    @ViewBuilder
    private var daylightCard: some View {
        if let day = presenter.selectedDay {
            CloudCard(tint: SkyPalette.gold) {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    SectionHeader(title: "Daylight")
                    HStack(spacing: SkySpacing.l) {
                        daylightItem("Sunrise", "sunrise.fill",
                                     day.sunrise.map { SkyFormat.clock($0, timeZone: presenter.timeZone) })
                        daylightItem("Sunset", "sunset.fill",
                                     day.sunset.map { SkyFormat.clock($0, timeZone: presenter.timeZone) })
                        daylightItem("Length", "clock.fill",
                                     day.daylightMinutes.map { SkyFormat.duration(minutes: Int($0)) })
                    }
                    if day.sunrise == nil || day.sunset == nil {
                        Text("Sunrise or sunset was not returned for this day. Activities that require daylight cannot be verified here.")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.unknown)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func daylightItem(_ title: String, _ icon: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10)).foregroundColor(SkyPalette.gold)
                Text(title).font(SkyFont.micro(10)).foregroundColor(SkyPalette.textTertiary)
            }
            if let value = value {
                Text(value).font(SkyFont.metric(16)).foregroundColor(SkyPalette.textPrimary)
            } else {
                UnknownTag()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Unavailable

    @ViewBuilder
    private var unavailableCard: some View {
        if !presenter.unavailableMetrics.isEmpty {
            WarningBanner(
                level: .unknown,
                title: "Not available for this place",
                message: presenter.unavailableMetrics.map(\.title).joined(separator: ", ")
                    + ". These stay Unknown. A required condition on them can never pass, and a window depending on them is marked Needs Verification."
            )
        }
    }
}

struct MetricInspection: Identifiable {
    let metric: MetricKind
    var id: String { metric.rawValue }
}

// MARK: - Metric timeline sheet

struct MetricTimelineSheet: View {

    let metric: MetricKind
    @ObservedObject var presenter: ConditionDetailsPresenter
    @Environment(\.presentationMode) private var presentationMode

    private var hours: [HourlyConditions] { presenter.hoursForSelectedDay }

    private var values: [Double] { hours.compactMap { $0.value(metric) } }

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        summaryCard
                        chartCard
                        rowsCard
                        Spacer(minLength: SkySpacing.xl)
                    }
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                        .font(SkyFont.headline(15))
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var summaryCard: some View {
        CloudCard(tint: metric.accentColor) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: SkySpacing.m) {
                    ZStack {
                        Circle().fill(metric.accentColor.opacity(0.14)).frame(width: 44, height: 44)
                        Image(systemName: metric.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(metric.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Measured in \(presenter.settings.unitSymbol(for: metric))")
                            .font(SkyFont.caption(13))
                            .foregroundColor(SkyPalette.textSecondary)
                        Text("Coverage \(SkyFormat.percent(presenter.coverage(of: metric))) of the snapshot")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }

                if values.isEmpty {
                    WarningBanner(level: .unknown, title: "No values for this day",
                                  message: "The provider returned nothing for \(metric.title.lowercased()) here. It is recorded as Unknown, not as zero.")
                } else {
                    HStack(spacing: SkySpacing.l) {
                        statItem("Min", values.min())
                        statItem("Max", values.max())
                        statItem("Mean", values.reduce(0, +) / Double(values.count))
                    }
                }
            }
        }
    }

    private func statItem(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(SkyFont.micro(10)).foregroundColor(SkyPalette.textTertiary)
            Text(presenter.settings.format(value, for: metric))
                .font(SkyFont.metric(16))
                .foregroundColor(SkyPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Hand-drawn chart: Swift Charts requires iOS 16, this app targets 15.
    private var chartCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Through the day",
                              subtitle: "Gaps mean Unknown, not zero")
                GeometryReader { geo in
                    let known = hours.compactMap { hour -> (Int, Double)? in
                        guard let index = hours.firstIndex(where: { $0.date == hour.date }),
                              let value = hour.value(metric) else { return nil }
                        return (index, value)
                    }
                    let minValue = values.min() ?? 0
                    let maxValue = values.max() ?? 1
                    let span = max(0.001, maxValue - minValue)

                    ZStack(alignment: .bottomLeading) {
                        ForEach(0..<3) { i in
                            Rectangle()
                                .fill(SkyPalette.divider)
                                .frame(height: 1)
                                .offset(y: -geo.size.height * Double(i) / 2)
                        }
                        ForEach(known, id: \.0) { index, value in
                            let x = hours.count > 1
                                ? geo.size.width * Double(index) / Double(hours.count - 1)
                                : geo.size.width / 2
                            let h = max(3, geo.size.height * (value - minValue) / span)
                            Capsule()
                                .fill(metric.accentColor.opacity(0.75))
                                .frame(width: max(2, geo.size.width / Double(max(1, hours.count)) - 3), height: h)
                                .offset(x: x - 3)
                        }
                    }
                }
                .frame(height: 110)

                if values.isEmpty {
                    Text("Nothing to draw — every hour is Unknown.")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.unknown)
                }
            }
        }
    }

    private var rowsCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                SectionHeader(title: "Hour by hour", subtitle: "Each with its own source and confidence")
                ForEach(hours) { hour in
                    let sample = hour.sample(metric)
                    HStack(spacing: SkySpacing.s) {
                        Text(SkyFormat.clock(hour.date, timeZone: presenter.timeZone))
                            .font(SkyFont.micro(11).weight(.semibold))
                            .foregroundColor(SkyPalette.textSecondary)
                            .frame(width: 52, alignment: .leading)

                        if let value = sample?.value {
                            Text(presenter.settings.format(value, for: metric))
                                .font(SkyFont.metric(14))
                                .foregroundColor(SkyPalette.textPrimary)
                                .frame(width: 78, alignment: .leading)
                        } else {
                            UnknownTag().frame(width: 78, alignment: .leading)
                        }

                        Spacer(minLength: 0)

                        if let sample = sample {
                            HStack(spacing: 4) {
                                Image(systemName: sample.observation.icon).font(.system(size: 8))
                                Text(sample.observation.label).font(SkyFont.micro(9))
                                Circle().fill(sample.confidence.color).frame(width: 4, height: 4)
                            }
                            .foregroundColor(SkyPalette.textTertiary)
                        }
                    }
                    .padding(.vertical, 3)
                    Divider().background(SkyPalette.divider)
                }
            }
        }
    }
}

// MARK: - Source details sheet

struct SourceDetailsSheet: View {

    let sources: [DataSource]
    let snapshot: ConditionSnapshot?
    let unavailable: [MetricKind]

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        if let snapshot = snapshot {
                            CloudCard {
                                VStack(alignment: .leading, spacing: SkySpacing.s) {
                                    SectionHeader(title: "This snapshot")
                                    detailRow("Snapshot ID", String(snapshot.id.uuidString.prefix(8)))
                                    detailRow("Captured", SkyFormat.fullDateTime(snapshot.capturedAt, timeZone: snapshot.timeZone))
                                    detailRow("Age", RelativeTime.string(for: snapshot.capturedAt))
                                    detailRow("Time zone", snapshot.timeZoneIdentifier)
                                    detailRow("Hourly points", "\(snapshot.hours.count)")
                                    detailRow("Daily points", "\(snapshot.days.count)")
                                    detailRow("Freshness budget", "\(Int(ConditionSnapshot.freshnessBudget / 60)) min")
                                    if snapshot.isStale {
                                        WarningBanner(level: .warning, title: "Older than the freshness budget",
                                                      message: "It is shown as a local snapshot and marked as possibly outdated everywhere it appears.")
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: SkySpacing.m) {
                            SectionHeader(title: "Sources", subtitle: "\(sources.count) provider\(sources.count == 1 ? "" : "s")")
                            ForEach(sources) { source in
                                CloudCard(tint: SkyPalette.violet) {
                                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                                        Text(source.name)
                                            .font(SkyFont.headline(15))
                                            .foregroundColor(SkyPalette.textPrimary)
                                        Text(source.attribution)
                                            .font(SkyFont.caption(12))
                                            .foregroundColor(SkyPalette.textSecondary)
                                        detailRow("Fetched", SkyFormat.fullDateTime(source.fetchedAt, timeZone: .current))
                                        if !source.url.isEmpty {
                                            Text(source.url)
                                                .font(SkyFont.micro(10))
                                                .foregroundColor(SkyPalette.azure)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }

                        if !unavailable.isEmpty {
                            WarningBanner(
                                level: .unknown,
                                title: "Metrics this source did not return",
                                message: unavailable.map(\.title).joined(separator: ", ")
                                    + ". CloudCrown records them as Unknown rather than filling in a substitute."
                            )
                        }

                        CloudCard {
                            VStack(alignment: .leading, spacing: SkySpacing.s) {
                                SectionHeader(title: "How confidence is assigned")
                                confidenceRow(.high, "Observed values, or forecasts less than 24 hours ahead.")
                                confidenceRow(.medium, "Forecasts 24 to 72 hours ahead.")
                                confidenceRow(.low, "Forecasts more than 72 hours ahead.")
                                confidenceRow(.unknown, "No value was returned at all.")
                                Text("This is CloudCrown's own stated assumption about lead time, not a figure published by the provider.")
                                    .font(SkyFont.micro(10))
                                    .foregroundColor(SkyPalette.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 2)
                            }
                        }

                        Spacer(minLength: SkySpacing.xl)
                    }
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle("Source Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                        .font(SkyFont.headline(15))
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(SkyFont.caption(12)).foregroundColor(SkyPalette.textSecondary)
            Spacer()
            Text(value).font(SkyFont.micro(12).weight(.semibold)).foregroundColor(SkyPalette.textPrimary)
        }
    }

    private func confidenceRow(_ confidence: Confidence, _ text: String) -> some View {
        HStack(alignment: .top, spacing: SkySpacing.s) {
            Circle().fill(confidence.color).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(confidence.shortLabel)
                    .font(SkyFont.caption(12).weight(.semibold))
                    .foregroundColor(SkyPalette.textPrimary)
                Text(text)
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
