//
//  TodayView.swift
//  CloudCrown
//

import SwiftUI

struct TodayView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: TodayPresenter
    @StateObject private var router: TodayRouter

    init(presenter: @autoclosure @escaping () -> TodayPresenter,
         router: @autoclosure @escaping () -> TodayRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }
    @EnvironmentObject private var repository: DataRepository

    var body: some View {
        ZStack {
            SkyBackground()
            content
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: SkySpacing.m) {
                    Button(action: presenter.openAlerts) {
                        Image(systemName: "bell.badge").font(.system(size: 15, weight: .medium))
                    }
                    Button(action: presenter.openSettings) {
                        Image(systemName: "gearshape.fill").font(.system(size: 15, weight: .medium))
                    }
                }
                .foregroundColor(SkyPalette.azure)
            }
        }
        .onAppear { presenter.onAppear() }
        .routed($router.route) { router.destination(for: $0) }
        .skyToast($presenter.toast)
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.state {
        case .loading:
            ScrollView(showsIndicators: false) {
                VStack(spacing: SkySpacing.m) {
                    LoadingCardsView(count: 3)
                }
                .padding(SkySpacing.l)
            }
        case .noPlace:
            ScrollView(showsIndicators: false) {
                EmptyStateView(
                    icon: "mappin.and.ellipse",
                    title: "No place yet",
                    message: "CloudCrown fetches conditions for a specific place, with its own coordinates and time zone. Nothing is shown until you add one.",
                    primaryTitle: "Add Place",
                    primaryAction: presenter.openPlaces,
                    firstStepHint: "Add a place, then set your comfort limits."
                )
                .padding(SkySpacing.l)
            }
        case .unavailable(let reason, let isOffline):
            ScrollView(showsIndicators: false) {
                VStack(spacing: SkySpacing.m) {
                    placeHeader
                    ErrorStateView(
                        message: isOffline ? "No connection and no local snapshot" : "Conditions could not be loaded",
                        detail: reason + " Nothing is shown rather than an estimate that could be wrong.",
                        onRetry: presenter.refresh
                    )
                    setupSection
                }
                .padding(SkySpacing.l)
            }
        case .ready:
            readyContent
        }
    }

    private var readyContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SkySpacing.l) {
                placeHeader

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        HStack(spacing: SkySpacing.s) {
                            OlympusAccent(kind: .laurel, size: 38)
                            OlympusAccent(kind: .lightning, size: 24)
                            OlympusAccent(kind: .clouds, size: 24)
                        }
                        HStack(spacing: SkySpacing.s) {
                            OlympusAccent(kind: .gem, size: 22)
                            OlympusAccent(kind: .calendar, size: 22)
                            OlympusAccent(kind: .timer, size: 22)
                        }
                    }
                    Spacer(minLength: 0)
                    OlympusAccent(kind: .zeus, size: 108)
                }
                .frame(height: 104)

                if presenter.isCached {
                    CachedBanner(updatedAt: presenter.snapshot?.capturedAt, onRetry: presenter.refresh)
                } else if presenter.snapshotIsStale {
                    CachedBanner(updatedAt: presenter.snapshot?.capturedAt, onRetry: presenter.refresh)
                }

                setupSection
                riskSection
                conditionsSection
                nextWindowSection
                feedbackSection
                plansSection
                quickLinks

                Spacer(minLength: SkySpacing.xl)
            }
            .padding(SkySpacing.l)
        }
        .refreshable { await presenter.load(forceRefresh: true) }
    }

    // MARK: - Header

    private var placeHeader: some View {
        HStack(spacing: SkySpacing.s) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 15))
                .foregroundColor(SkyPalette.azure)
            VStack(alignment: .leading, spacing: 1) {
                Text(presenter.place?.name ?? "No place")
                    .font(SkyFont.headline(15))
                    .foregroundColor(SkyPalette.textPrimary)
                if let snapshot = presenter.snapshot {
                    SourceStamp(source: snapshot.sourceSummary,
                                updatedAt: snapshot.capturedAt,
                                confidence: .high,
                                isStale: snapshot.isStale,
                                compact: true)
                } else {
                    Text("No conditions loaded")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Button(action: presenter.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SkyPalette.azure)
                    .rotationEffect(.degrees(presenter.isRefreshing ? 360 : 0))
                    .animation(presenter.isRefreshing
                               ? .linear(duration: 1).repeatForever(autoreverses: false)
                               : .default,
                               value: presenter.isRefreshing)
            }
        }
    }

    // MARK: - Setup gaps

    @ViewBuilder
    private var setupSection: some View {
        if !presenter.setupGaps.isEmpty {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Before results can be trusted",
                              subtitle: "CloudCrown will not score a window on missing inputs")
                ForEach(presenter.setupGaps) { gap in
                    SetupGapCard(gap: gap) { presenter.resolve(gap) }
                }
            }
        }
    }

    // MARK: - Risks

    @ViewBuilder
    private var riskSection: some View {
        if !presenter.plansAtRisk.isEmpty {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Plans at Risk",
                              subtitle: "Detected by comparing two forecast snapshots")
                ForEach(presenter.plansAtRisk) { plan in
                    WarningBanner(
                        level: .warning,
                        title: plan.title,
                        message: plan.openRisks.last?.summary ?? "Conditions changed for this window.",
                        actionTitle: "Review and decide",
                        action: { presenter.openRisk(plan.id) }
                    )
                }
            }
        }
    }

    // MARK: - Conditions

    @ViewBuilder
    private var conditionsSection: some View {
        if let snapshot = presenter.snapshot, let hour = presenter.currentHour {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(
                    title: "Current Conditions",
                    subtitle: "Nearest hour: \(SkyFormat.clock(hour.date, timeZone: snapshot.timeZone))",
                    actionTitle: "View Conditions",
                    action: presenter.openConditions
                )

                LazyVGrid(columns: [GridItem(.flexible(), spacing: SkySpacing.s),
                                    GridItem(.flexible(), spacing: SkySpacing.s),
                                    GridItem(.flexible(), spacing: SkySpacing.s)],
                          spacing: SkySpacing.s) {
                    ForEach(presenter.headlineMetrics, id: \.self) { metric in
                        let sample = hour.sample(metric)
                        MetricTile(
                            metric: metric,
                            value: sample?.value,
                            settings: presenter.settings,
                            observation: sample?.observation,
                            confidence: sample?.confidence ?? .unknown,
                            updatedAt: sample?.updatedAt,
                            isCompact: true,
                            action: { presenter.openMetric(metric) }
                        )
                    }
                }

                if !snapshot.unavailableMetrics.isEmpty {
                    WarningBanner(
                        level: .unknown,
                        title: "Some measurements are unavailable here",
                        message: snapshot.unavailableMetrics.map(\.title).joined(separator: ", ")
                            + " were not returned for this place. They stay Unknown and cannot satisfy a required condition."
                    )
                }
            }
        }
    }

    // MARK: - Next good window

    @ViewBuilder
    private var nextWindowSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Next Good Window",
                          subtitle: presenter.nextWindowActivity.map { "For \($0.name)" })

            if let window = presenter.nextWindow, let activity = presenter.nextWindowActivity {
                Button(action: presenter.openNextWindow) {
                    CelestialCard(gradient: window.verdict == .bestMatch
                                  ? LinearGradient(colors: [SkyPalette.verdictBest, SkyPalette.lightBlue],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                  : SkyPalette.azureGradient) {
                        VStack(alignment: .leading, spacing: SkySpacing.m) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(window.dayText())
                                        .font(SkyFont.micro(11).weight(.semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                    Text(window.timeRangeText())
                                        .font(SkyFont.display(26))
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                OlympusAccent(kind: .microphone, size: 42)
                                ZStack {
                                    Circle().fill(Color.white.opacity(0.18)).frame(width: 62, height: 62)
                                    VStack(spacing: 0) {
                                        Text(window.score.map { "\(Int($0.rounded()))" } ?? "?")
                                            .font(SkyFont.metric(22))
                                            .foregroundColor(.white)
                                        Text("score")
                                            .font(SkyFont.micro(9))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                            }

                            HStack(spacing: SkySpacing.s) {
                                SkyChip(title: activity.name, icon: activity.kind.icon, color: .white, isSelected: false)
                                    .colorMultiply(.white)
                                Text(SkyFormat.duration(minutes: window.durationMinutes))
                                    .font(SkyFont.micro(11).weight(.semibold))
                                    .foregroundColor(.white.opacity(0.9))
                            }

                            Text(window.headline)
                                .font(SkyFont.caption(13))
                                .foregroundColor(.white.opacity(0.94))
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 5) {
                                Text("Why this window?")
                                    .font(SkyFont.caption(13).weight(.semibold))
                                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(SkyPressStyle())
            } else if presenter.isReady {
                MissingPrerequisiteView(
                    title: "No window meets your conditions in the next 2 days",
                    reason: "Every interval checked broke at least one required condition, or the data needed to check it was missing. Open Find Window to see the closest interval and exactly what blocked it.",
                    actionTitle: "Open Find Window",
                    action: presenter.openFinder
                )
            } else {
                MissingPrerequisiteView(
                    title: "Not enough set up to find a window",
                    reason: "A window is only shown when your limits, an activity and a place all exist. Nothing is estimated in the meantime.",
                    actionTitle: presenter.setupGaps.first?.actionTitle ?? "Continue setup",
                    action: { if let gap = presenter.setupGaps.first { presenter.resolve(gap) } }
                )
            }
        }
    }

    // MARK: - Awaiting feedback

    @ViewBuilder
    private var feedbackSection: some View {
        if !presenter.plansAwaitingFeedback.isEmpty {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "How did it go?",
                              subtitle: "Rating is optional, but Insights needs it")
                ForEach(presenter.plansAwaitingFeedback.prefix(2)) { plan in
                    PlanRow(plan: plan,
                            activityName: presenter.activityName(plan.activityID),
                            placeName: presenter.placeName(plan.placeID),
                            awaitsFeedback: true) {
                        presenter.openPlan(plan.id)
                    }
                }
            }
        }
    }

    // MARK: - Plans

    @ViewBuilder
    private var plansSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Saved Plans", subtitle: presenter.upcomingPlans.isEmpty ? nil : "Next \(presenter.upcomingPlans.count)")
            if presenter.upcomingPlans.isEmpty {
                CloudCard {
                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        Text("No saved plans")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text("When you save a window as a plan, it appears here and CloudCrown starts watching the conditions it depends on.")
                            .font(SkyFont.caption(13))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ForEach(presenter.upcomingPlans) { plan in
                    PlanRow(plan: plan,
                            activityName: presenter.activityName(plan.activityID),
                            placeName: presenter.placeName(plan.placeID)) {
                        presenter.openPlan(plan.id)
                    }
                }
            }
        }
    }

    // MARK: - Quick links

    private var quickLinks: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Your Setup", subtitle: "Change any of these and every window is re-scored")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SkySpacing.s),
                                GridItem(.flexible(), spacing: SkySpacing.s)],
                      spacing: SkySpacing.s) {
                quickLink("Add Activity", "figure.walk", SkyPalette.azure,
                          "\(repository.activeActivities.count) saved", presenter.addActivity)
                quickLink("Places", "mappin.and.ellipse", SkyPalette.lightBlue,
                          "\(repository.activePlaces.count) saved", presenter.openPlaces)
                quickLink("Comfort Profile", "slider.horizontal.below.square.filled.and.square", SkyPalette.gold,
                          repository.profile.map { "\($0.definedCount) limits" } ?? "Not set",
                          { presenter.resolve(.profile(missing: [])) })
                quickLink("Alert Rules", "bell.badge.fill", SkyPalette.violet,
                          "\(repository.alerts.count) rules", presenter.openAlerts)
            }
        }
    }

    private func quickLink(_ title: String, _ icon: String, _ color: Color,
                           _ subtitle: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                ZStack {
                    Circle().fill(color.opacity(0.13)).frame(width: 32, height: 32)
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
                }
                Text(title)
                    .font(SkyFont.caption(13).weight(.semibold))
                    .foregroundColor(SkyPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(SkyFont.micro(10))
                    .foregroundColor(SkyPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SkySpacing.m)
            .background(
                RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                    .fill(SkyPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                    .strokeBorder(SkyPalette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(SkyPressStyle())
    }
}
