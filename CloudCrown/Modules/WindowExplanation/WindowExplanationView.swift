//
//  WindowExplanationView.swift
//  CloudCrown
//
//  Opens the reasoning: which required conditions passed or failed, what each
//  preferred condition contributed, and which snapshot it all came from.
//

import SwiftUI

struct WindowExplanationView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: WindowExplanationPresenter
    @StateObject private var router: WindowExplanationRouter

    init(presenter: @autoclosure @escaping () -> WindowExplanationPresenter,
         router: @autoclosure @escaping () -> WindowExplanationRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SkySpacing.l) {
                    headerCard
                    if presenter.isSuperseded { supersededCard }
                    reproducibilityCard
                    requiredSection
                    preferredSection
                    tradeOffSection
                    alternativesSection
                    Spacer(minLength: 110)
                }
                .padding(SkySpacing.l)
            }

            VStack {
                Spacer()
                actionBar
            }
        }
        .navigationTitle("Why This Window?")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presenter.onAppear() }
        .skyToast($presenter.toast)
    }

    // MARK: - Header

    private var headerCard: some View {
        CelestialCard(gradient: LinearGradient(
            colors: [presenter.window.verdict.color, presenter.window.verdict.color.opacity(0.7)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(presenter.window.dayText())
                            .font(SkyFont.micro(11).weight(.semibold))
                            .foregroundColor(.white.opacity(0.86))
                        Text(presenter.window.timeRangeText())
                            .font(SkyFont.display(26))
                            .foregroundColor(.white)
                        Text("\(presenter.activity?.name ?? "Activity") · \(presenter.place?.name ?? "Place")")
                            .font(SkyFont.caption(13))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer()
                    VStack(spacing: 3) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.18)).frame(width: 64, height: 64)
                            VStack(spacing: 0) {
                                Text(presenter.window.score.map { "\(Int($0.rounded()))" } ?? "?")
                                    .font(SkyFont.metric(24))
                                    .foregroundColor(.white)
                                Text("/ 100")
                                    .font(SkyFont.micro(9))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }

                HStack(spacing: SkySpacing.s) {
                    Text(presenter.window.verdict.title)
                        .font(SkyFont.micro(11).weight(.bold))
                        .foregroundColor(presenter.window.verdict.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white))
                    if let stability = presenter.window.stability {
                        Text("Stability \(SkyFormat.percent(stability))")
                            .font(SkyFont.micro(11).weight(.semibold))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    Text("Data \(SkyFormat.percent(presenter.window.completeness))")
                        .font(SkyFont.micro(11).weight(.semibold))
                        .foregroundColor(.white.opacity(0.92))
                }

                Text(presenter.window.headline)
                    .font(SkyFont.caption(13))
                    .foregroundColor(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Superseded

    @ViewBuilder
    private var supersededCard: some View {
        if let current = presenter.currentVersion {
            CloudCard(tint: SkyPalette.warning) {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    HStack(spacing: SkySpacing.s) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(SkyPalette.warning)
                        Text("This explanation is Superseded")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                    }
                    Text("A newer forecast snapshot exists. The explanation above is kept exactly as it was produced — it is not silently rewritten.")
                        .font(SkyFont.caption(13))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LightningLine()
                        .stroke(SkyPalette.warning.opacity(0.7),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(height: 8)

                    HStack(spacing: SkySpacing.l) {
                        versionColumn("Saved with", presenter.window.score,
                                      presenter.window.snapshotCapturedAt, presenter.window.verdict)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(SkyPalette.textTertiary)
                        versionColumn("Newest", current.score, current.snapshotCapturedAt, current.verdict)
                    }

                    if let delta = presenter.scoreDelta {
                        Text("Score change: \(SkyFormat.signed(delta, decimals: 0)) points")
                            .font(SkyFont.caption(13).weight(.semibold))
                            .foregroundColor(delta < 0 ? SkyPalette.danger : SkyPalette.success)
                    }

                    SkyButton(title: "Use the newest evaluation", icon: "arrow.clockwise",
                              kind: .secondary, action: presenter.adoptCurrentVersion)
                }
            }
        }
    }

    private func versionColumn(_ title: String, _ score: Double?, _ capturedAt: Date, _ verdict: WindowVerdict) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(SkyFont.micro(10)).foregroundColor(SkyPalette.textTertiary)
            GlowRing(score: score, verdictColor: verdict.color, size: 52)
            Text(RelativeTime.string(for: capturedAt))
                .font(SkyFont.micro(10))
                .foregroundColor(SkyPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Reproducibility

    private var reproducibilityCard: some View {
        CloudCard(tint: SkyPalette.violet) {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                HStack(spacing: SkySpacing.s) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(SkyPalette.violet)
                    Text("How this score can be reproduced")
                        .font(SkyFont.headline(14))
                        .foregroundColor(SkyPalette.textPrimary)
                }
                metaRow("Rules version", presenter.window.rulesVersion)
                metaRow("Snapshot ID", String(presenter.window.snapshotID.uuidString.prefix(8)))
                metaRow("Snapshot captured", SkyFormat.fullDateTime(presenter.window.snapshotCapturedAt, timeZone: presenter.window.timeZone))
                metaRow("Evaluated", SkyFormat.fullDateTime(presenter.window.evaluatedAt, timeZone: presenter.window.timeZone))
                metaRow("Time zone", presenter.window.timeZoneIdentifier)

                Button(action: presenter.openConditions) {
                    HStack(spacing: 5) {
                        Text("Open the source measurements")
                            .font(SkyFont.caption(12).weight(.semibold))
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(SkyPalette.violet)
                }
                .padding(.top, 2)
            }
        }
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(SkyFont.caption(12)).foregroundColor(SkyPalette.textSecondary)
            Spacer()
            Text(value).font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: - Required

    private var requiredSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Required Conditions",
                          subtitle: "A single failure blocks the window")

            if presenter.window.requiredResults.isEmpty {
                CloudCard {
                    Text("This activity has no required conditions and your Comfort Profile defines no hard limits, so nothing could block this window.")
                        .font(SkyFont.caption(13))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if !presenter.failed.isEmpty {
                    groupCard("Does Not Meet", presenter.failed, SkyPalette.danger)
                }
                if !presenter.unknown.isEmpty {
                    groupCard("Needs Verification", presenter.unknown, SkyPalette.unknown)
                }
                if !presenter.passed.isEmpty {
                    groupCard("Meets", presenter.passed, SkyPalette.success)
                }
            }
        }
    }

    private func groupCard(_ title: String, _ evaluations: [RuleEvaluation], _ accent: Color) -> some View {
        CloudCard(tint: accent) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(SkyFont.headline(14))
                        .foregroundColor(accent)
                    Text("\(evaluations.count)")
                        .font(SkyFont.micro(10).weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(accent))
                }
                ForEach(evaluations) { evaluation in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: SkySpacing.s) {
                            Image(systemName: evaluation.rule.metric.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(evaluation.rule.metric.accentColor)
                                .frame(width: 18)
                            Text(evaluation.rule.summary)
                                .font(SkyFont.caption(13).weight(.medium))
                                .foregroundColor(SkyPalette.textPrimary)
                            Spacer(minLength: 0)
                            if let value = evaluation.measuredValue {
                                Text(presenter.settings.format(value, for: evaluation.rule.metric))
                                    .font(SkyFont.metric(14))
                                    .foregroundColor(evaluation.outcome.color)
                            } else {
                                UnknownTag()
                            }
                        }
                        Text(evaluation.reason)
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 26)

                        HStack(spacing: 8) {
                            if let observation = evaluation.observation {
                                HStack(spacing: 3) {
                                    Image(systemName: observation.icon).font(.system(size: 8))
                                    Text(observation.label).font(SkyFont.micro(9))
                                }
                            }
                            if let measuredAt = evaluation.measuredAt {
                                Text("worst at \(SkyFormat.clock(measuredAt, timeZone: presenter.window.timeZone))")
                                    .font(SkyFont.micro(9))
                            }
                            HStack(spacing: 3) {
                                Circle().fill(evaluation.confidence.color).frame(width: 4, height: 4)
                                Text(evaluation.confidence.shortLabel).font(SkyFont.micro(9))
                            }
                            if let source = presenter.source(for: evaluation) {
                                Text("· \(source.name)").font(SkyFont.micro(9)).lineLimit(1)
                            }
                        }
                        .foregroundColor(SkyPalette.textTertiary)
                        .padding(.leading, 26)
                    }
                    if evaluation.id != evaluations.last?.id {
                        Divider().background(SkyPalette.divider)
                    }
                }
            }
        }
    }

    // MARK: - Preferred

    private var preferredSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Preferred Conditions",
                          subtitle: "Each one's contribution to the score")

            if presenter.window.preferredResults.isEmpty {
                CloudCard {
                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        Text("This activity has no preferred conditions")
                            .font(SkyFont.headline(14))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text("Without them a window can pass or fail its requirements, but there is nothing to score. That is why no number is shown above.")
                            .font(SkyFont.caption(12))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                CloudCard {
                    VStack(alignment: .leading, spacing: SkySpacing.m) {
                        HStack {
                            Text("Total")
                                .font(SkyFont.caption(13).weight(.semibold))
                                .foregroundColor(SkyPalette.textPrimary)
                            Spacer()
                            Text("\(String(format: "%.1f", presenter.totalPointsEarned)) of \(presenter.totalWeight) points")
                                .font(SkyFont.metric(15))
                                .foregroundColor(SkyPalette.azure)
                        }

                        ForEach(presenter.preferredSorted) { evaluation in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: SkySpacing.s) {
                                    Image(systemName: evaluation.rule.metric.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(evaluation.rule.metric.accentColor)
                                        .frame(width: 16)
                                    Text(evaluation.rule.summary)
                                        .font(SkyFont.caption(12).weight(.medium))
                                        .foregroundColor(SkyPalette.textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text("\(String(format: "%.1f", evaluation.pointsEarned)) / \(evaluation.rule.weight)")
                                        .font(SkyFont.micro(11).weight(.bold))
                                        .foregroundColor(evaluation.satisfaction == nil ? SkyPalette.unknown : SkyPalette.textPrimary)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(SkyPalette.surfaceSunken)
                                        if let satisfaction = evaluation.satisfaction {
                                            Capsule()
                                                .fill(evaluation.rule.metric.accentColor)
                                                .frame(width: geo.size.width * min(1, max(0, satisfaction)))
                                        } else {
                                            Capsule()
                                                .strokeBorder(SkyPalette.unknown.opacity(0.5),
                                                              style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                                        }
                                    }
                                }
                                .frame(height: 6)

                                Text(evaluation.reason)
                                    .font(SkyFont.micro(10))
                                    .foregroundColor(SkyPalette.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }

                        if presenter.window.preferredResults.contains(where: { $0.satisfaction == nil }) {
                            Text("Unknown preferences contribute zero points, and the score is expressed over the weight that could actually be assessed.")
                                .font(SkyFont.micro(10))
                                .foregroundColor(SkyPalette.unknown)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Trade-off

    @ViewBuilder
    private var tradeOffSection: some View {
        if let tradeOff = presenter.tradeOff {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Trade-Off", subtitle: "What a nearby window would give you instead")
                CloudCard(tint: SkyPalette.gold) {
                    VStack(alignment: .leading, spacing: SkySpacing.m) {
                        HStack(spacing: SkySpacing.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tradeOff.better.timeRangeText())
                                    .font(SkyFont.headline(15))
                                    .foregroundColor(SkyPalette.textPrimary)
                                Text(tradeOff.better.dayText())
                                    .font(SkyFont.micro(11))
                                    .foregroundColor(SkyPalette.textSecondary)
                            }
                            Spacer()
                            GlowRing(score: tradeOff.better.score,
                                     verdictColor: tradeOff.better.verdict.color, size: 48)
                        }
                        ForEach(tradeOff.gains, id: \.self) { gain in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(SkyPalette.success)
                                    .padding(.top, 2)
                                Text(gain)
                                    .font(SkyFont.micro(11))
                                    .foregroundColor(SkyPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        SkyButton(title: "Explain that window instead", icon: "arrow.right",
                                  kind: .secondary) {
                            presenter.selectAlternative(tradeOff.better)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Alternatives

    @ViewBuilder
    private var alternativesSection: some View {
        if !presenter.alternatives.isEmpty {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                Button { withAnimation { presenter.showsAlternatives.toggle() } } label: {
                    HStack {
                        Text("Compare Windows (\(presenter.alternatives.count))")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                        Spacer()
                        Image(systemName: presenter.showsAlternatives ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(SkyPalette.textTertiary)
                    }
                }
                if presenter.showsAlternatives {
                    ForEach(presenter.alternatives) { candidate in
                        WindowRow(window: candidate, showsDay: false) {
                            presenter.selectAlternative(candidate)
                        }
                    }
                    SkyButton(title: "Compare whole days", icon: "square.split.2x1",
                              kind: .ghost, action: presenter.openComparison)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        VStack(spacing: SkySpacing.s) {
            if let existing = presenter.existingPlan {
                Text("A plan already exists for this window: “\(existing.title)”.")
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.warning)
                    .multilineTextAlignment(.center)
            }
            SkyButton(
                title: presenter.existingPlan != nil ? "Update Existing Plan" : "Save as Plan",
                icon: presenter.existingPlan != nil ? "arrow.triangle.2.circlepath" : "calendar.badge.plus",
                kind: presenter.window.verdict.isUsable ? .primary : .secondary,
                action: presenter.savePlan
            )
            if !presenter.window.verdict.isUsable {
                Text("This window does not meet all required conditions. You can still plan it deliberately.")
                    .font(SkyFont.micro(10))
                    .foregroundColor(SkyPalette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, SkySpacing.l)
        .padding(.top, SkySpacing.m)
        .padding(.bottom, SkySpacing.l)
        .background(
            LinearGradient(colors: [SkyPalette.cloudWhite.opacity(0), SkyPalette.cloudWhite],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}
