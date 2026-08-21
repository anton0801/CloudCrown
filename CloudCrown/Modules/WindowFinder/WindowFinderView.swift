//
//  WindowFinderView.swift
//  CloudCrown
//

import SwiftUI

struct WindowFinderView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: WindowFinderPresenter
    @StateObject private var router: WindowFinderRouter

    init(presenter: @autoclosure @escaping () -> WindowFinderPresenter,
         router: @autoclosure @escaping () -> WindowFinderRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SkySpacing.l) {
                    if !presenter.isReady {
                        setupSection
                    } else {
                        queryCard
                        searchButton
                        resultsSection
                    }
                    Spacer(minLength: SkySpacing.xxl)
                }
                .padding(SkySpacing.l)
            }
        }
        .navigationTitle("Find Window")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { presenter.onAppear() }
        .routed($router.route) { router.destination(for: $0) }
        .skyToast($presenter.toast)
    }

    // MARK: - Setup

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            EmptyStateView(
                icon: "square.stack.3d.up.slash",
                title: "Not enough set up to search",
                message: "A window is only produced when your comfort limits, an activity and a place all exist. CloudCrown will not estimate around missing inputs.",
                firstStepHint: "Complete the steps below in any order."
            )
            ForEach(presenter.setupGaps) { gap in
                SetupGapCard(gap: gap) { presenter.resolve(gap) }
            }
        }
    }

    // MARK: - Query form

    private var queryCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.l) {
                SectionHeader(title: "Search", subtitle: "These inputs are saved as a draft automatically")

                pickerRow(
                    title: "Activity",
                    icon: "figure.walk",
                    value: presenter.selectedActivity?.name ?? "Choose an activity",
                    isPlaceholder: presenter.selectedActivity == nil
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SkySpacing.s) {
                            ForEach(presenter.activities) { activity in
                                SkyChip(title: activity.name,
                                        icon: activity.kind.icon,
                                        color: activity.kind.accent,
                                        isSelected: presenter.form.activityID == activity.id) {
                                    presenter.selectActivity(activity)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                pickerRow(
                    title: "Place",
                    icon: "mappin.and.ellipse",
                    value: presenter.selectedPlace?.name ?? "Choose a place",
                    isPlaceholder: presenter.selectedPlace == nil
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SkySpacing.s) {
                            ForEach(presenter.places) { place in
                                SkyChip(title: place.name,
                                        icon: place.isDefault ? "crown.fill" : "mappin",
                                        color: SkyPalette.azure,
                                        isSelected: presenter.form.placeID == place.id) {
                                    presenter.selectPlace(place)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                Divider().background(SkyPalette.divider)

                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text("Date range")
                        .font(SkyFont.micro(11).weight(.semibold))
                        .foregroundColor(SkyPalette.textTertiary)
                    DatePicker("From", selection: $presenter.form.startDate, displayedComponents: .date)
                        .font(SkyFont.caption(13))
                        .onChange(of: presenter.form.startDate) { _ in presenter.persistDraft() }
                    DatePicker("To", selection: $presenter.form.endDate,
                               in: presenter.form.startDate...,
                               displayedComponents: .date)
                        .font(SkyFont.caption(13))
                        .onChange(of: presenter.form.endDate) { _ in presenter.persistDraft() }
                }

                Divider().background(SkyPalette.divider)

                timeRow("Earliest", $presenter.form.earliestMinute,
                        upperBound: presenter.form.latestMinute - 15)
                timeRow("Latest", $presenter.form.latestMinute,
                        lowerBound: presenter.form.earliestMinute + 15)

                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    HStack {
                        Text("Duration")
                            .font(SkyFont.micro(11).weight(.semibold))
                            .foregroundColor(SkyPalette.textTertiary)
                        Spacer()
                        Text(SkyFormat.duration(minutes: presenter.form.durationMinutes))
                            .font(SkyFont.metric(16))
                            .foregroundColor(SkyPalette.textPrimary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(presenter.form.durationMinutes) },
                            set: { presenter.form.durationMinutes = Int($0) }
                        ),
                        in: 15...300, step: 15
                    )
                    .tint(SkyPalette.azure)
                    .onChange(of: presenter.form.durationMinutes) { _ in presenter.persistDraft() }
                }

                if let message = presenter.validationMessage {
                    WarningBanner(level: .warning, title: "Cannot search yet", message: message)
                }
            }
        }
    }

    private func pickerRow<Content: View>(title: String, icon: String, value: String,
                                          isPlaceholder: Bool,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(SkyPalette.textTertiary)
                Text(title).font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                Spacer()
                Text(value)
                    .font(SkyFont.caption(13).weight(.semibold))
                    .foregroundColor(isPlaceholder ? SkyPalette.unknown : SkyPalette.textPrimary)
                    .lineLimit(1)
            }
            content()
        }
    }

    private func timeRow(_ title: String, _ binding: Binding<Int>,
                         lowerBound: Int = 0, upperBound: Int = 24 * 60 - 15) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                Spacer()
                Text(QuietHours.text(binding.wrappedValue))
                    .font(SkyFont.metric(15))
                    .foregroundColor(SkyPalette.textPrimary)
            }
            Slider(
                value: Binding(
                    get: { Double(binding.wrappedValue) },
                    set: {
                        binding.wrappedValue = min(upperBound, max(lowerBound, Int($0 / 15) * 15))
                        presenter.persistDraft()
                    }
                ),
                in: 0...Double(24 * 60 - 15), step: 15
            )
            .tint(SkyPalette.lightBlue)
        }
    }

    private var searchButton: some View {
        VStack(spacing: SkySpacing.s) {
            SkyButton(
                title: "Find Windows",
                icon: "sparkle.magnifyingglass",
                kind: .primary,
                isLoading: presenter.state == .searching,
                isEnabled: presenter.canSearch,
                action: presenter.search
            )
            if presenter.selectedActivity != nil && presenter.selectedPlace != nil {
                SkyButton(title: "Compare Days", icon: "square.split.2x1",
                          kind: .ghost, action: presenter.openComparison)
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        switch presenter.state {
        case .idle:
            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text("No search run yet")
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                    Text("Results appear only after a search. Nothing is shown from a previous session, because the forecast it came from may already be superseded.")
                        .font(SkyFont.caption(13))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .searching:
            LoadingCardsView(count: 3)
        case .invalid(let message):
            WarningBanner(level: .danger, title: "Search not run", message: message)
        case .unavailable(let reason, let isOffline):
            ErrorStateView(
                message: isOffline ? "Offline and no stored conditions" : "Conditions could not be loaded",
                detail: reason + " Your search inputs were kept.",
                onRetry: presenter.search
            )
        case .noWindow:
            noWindowSection
        case .results:
            resultsList
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            resultMeta

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SkySpacing.s) {
                    ForEach(WindowFinderPresenter.Filter.allCases) { filter in
                        SkyChip(
                            title: "\(filter.title) (\(presenter.count(for: filter)))",
                            color: color(for: filter),
                            isSelected: presenter.filter == filter
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) { presenter.filter = filter }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            if presenter.visibleCandidates.isEmpty {
                CloudCard {
                    Text("No window in this category.")
                        .font(SkyFont.caption(13))
                        .foregroundColor(SkyPalette.textSecondary)
                }
            } else {
                ForEach(presenter.visibleCandidates) { window in
                    WindowRow(window: window, isSuperseded: presenter.isSuperseded(window)) {
                        presenter.openExplanation(window)
                    }
                }
            }
        }
    }

    private func color(for filter: WindowFinderPresenter.Filter) -> Color {
        switch filter {
        case .all: return SkyPalette.textSecondary
        case .bestMatch: return SkyPalette.verdictBest
        case .acceptable: return SkyPalette.verdictAcceptable
        case .notRecommended: return SkyPalette.verdictNotRecommended
        }
    }

    @ViewBuilder
    private var resultMeta: some View {
        if let result = presenter.result {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                if presenter.usedCache {
                    CachedBanner(updatedAt: result.snapshotCapturedAt, onRetry: presenter.search)
                }
                HStack(spacing: SkySpacing.s) {
                    SkyChip(title: "Rules v\(result.rulesVersion)", icon: "function", color: SkyPalette.violet)
                    SkyChip(title: "Snapshot \(String(result.snapshotID.uuidString.prefix(6)))",
                            icon: "cube.box", color: SkyPalette.textSecondary)
                }
                Text("Every window below was scored from this snapshot with these rules, so the same inputs always produce the same result.")
                    .font(SkyFont.micro(10))
                    .foregroundColor(SkyPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - No window

    @ViewBuilder
    private var noWindowSection: some View {
        if let result = presenter.result {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                WarningBanner(
                    level: .warning,
                    title: "No window meets all required conditions",
                    message: "Every interval in this range broke at least one requirement, or the data needed to check it was missing. The closest interval is shown below with exactly what blocked it."
                )

                if let closest = result.closestAlternative {
                    SectionHeader(title: "Closest interval", subtitle: "Shown so you can decide, not recommended")
                    WindowRow(window: closest, isSuperseded: presenter.isSuperseded(closest)) {
                        presenter.openExplanation(closest)
                    }

                    CloudCard(tint: SkyPalette.danger) {
                        VStack(alignment: .leading, spacing: SkySpacing.s) {
                            Text("What blocked it")
                                .font(SkyFont.headline(14))
                                .foregroundColor(SkyPalette.textPrimary)
                            ForEach(closest.failedRequired) { evaluation in
                                ruleReason(evaluation)
                            }
                            ForEach(closest.unknownRequired) { evaluation in
                                ruleReason(evaluation)
                            }
                        }
                    }
                }

                CloudCard {
                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        Text("What you can change")
                            .font(SkyFont.headline(14))
                            .foregroundColor(SkyPalette.textPrimary)
                        suggestion("Widen the date range or the earliest/latest hours.")
                        suggestion("Shorten the duration — a shorter window has fewer hours that can break a rule.")
                        suggestion("Revisit the limits that blocked it in your Comfort Profile or the activity's required conditions.")
                    }
                }

                if !result.notRecommended.isEmpty {
                    SectionHeader(title: "All evaluated intervals", subtitle: "\(result.notRecommended.count) not recommended")
                    ForEach(result.notRecommended.prefix(6)) { window in
                        WindowRow(window: window) { presenter.openExplanation(window) }
                    }
                }
            }
        }
    }

    private func ruleReason(_ evaluation: RuleEvaluation) -> some View {
        HStack(alignment: .top, spacing: SkySpacing.s) {
            Image(systemName: evaluation.outcome.icon)
                .font(.system(size: 12))
                .foregroundColor(evaluation.outcome.color)
            Text(evaluation.reason)
                .font(SkyFont.caption(12))
                .foregroundColor(SkyPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func suggestion(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(SkyPalette.azure).frame(width: 4, height: 4).padding(.top, 6)
            Text(text)
                .font(SkyFont.caption(12))
                .foregroundColor(SkyPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
