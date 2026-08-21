//
//  PlanRiskView.swift
//  CloudCrown
//
//  A risk is only shown after two snapshot versions have been compared, and
//  the user always confirms any replacement.
//

import SwiftUI

struct PlanRiskView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: PlanRiskPresenter
    @StateObject private var router: PlanRiskRouter

    init(presenter: @autoclosure @escaping () -> PlanRiskPresenter,
         router: @autoclosure @escaping () -> PlanRiskRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            content
        }
        .navigationTitle("Plan at Risk")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presenter.onAppear() }
        .routed($router.route) { router.destination(for: $0) }
        .skyToast($presenter.toast)
        .sheet(isPresented: $router.showsAlternatives) {
            AlternativeWindowPicker(options: presenter.alternatives) { presenter.selectAlternative($0) }
        }
        .alert(item: $router.pendingConfirmation) { pending in
            Alert(
                title: Text(pending.title),
                message: Text(pending.message),
                primaryButton: .default(Text("Confirm")) { presenter.confirm(pending) },
                secondaryButton: .cancel(Text("Not now"))
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.state {
        case .loading:
            ScrollView(showsIndicators: false) { LoadingCardsView(count: 3).padding(SkySpacing.l) }
        case .missingPlan:
            EmptyStateView(icon: "calendar.badge.exclamationmark",
                           title: "Plan unavailable",
                           message: "This plan or its place no longer exists, so no comparison can be made.")
        case .unavailable(let reason, let isOffline):
            ScrollView(showsIndicators: false) {
                VStack(spacing: SkySpacing.m) {
                    WarningBanner(
                        level: .unknown,
                        title: "No comparison possible right now",
                        message: "A risk is only raised after two forecast snapshots have been compared. Without a newer snapshot, CloudCrown will not guess."
                    )
                    ErrorStateView(
                        message: isOffline ? "Offline" : "Could not load a newer forecast",
                        detail: reason,
                        onRetry: presenter.load
                    )
                }
                .padding(SkySpacing.l)
            }
        case .noRisk:
            ScrollView(showsIndicators: false) {
                VStack(spacing: SkySpacing.l) {
                    CloudCard(tint: SkyPalette.success) {
                        VStack(alignment: .leading, spacing: SkySpacing.s) {
                            HStack(spacing: SkySpacing.s) {
                                Image(systemName: "checkmark.shield.fill").foregroundColor(SkyPalette.success)
                                Text("No risk detected")
                                    .font(SkyFont.headline(16))
                                    .foregroundColor(SkyPalette.textPrimary)
                            }
                            Text("The newest forecast was compared with the snapshot this plan was saved from. Every required condition still holds and the score did not drop materially.")
                                .font(SkyFont.caption(13))
                                .foregroundColor(SkyPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let snapshot = presenter.snapshot {
                                SourceStamp(source: snapshot.sourceSummary,
                                            updatedAt: snapshot.capturedAt,
                                            confidence: .high, compact: true)
                            }
                        }
                    }
                    resolvedHistory
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
                headerCard
                if let message = presenter.saveError {
                    SaveErrorBanner(message: message, onDismiss: presenter.dismissSaveError)
                }
                if presenter.isCached {
                    CachedBanner(updatedAt: presenter.snapshot?.capturedAt, onRetry: presenter.load)
                }
                comparisonCard
                brokenCard
                decisionsCard
                resolvedHistory
                Spacer(minLength: SkySpacing.xxl)
            }
            .padding(SkySpacing.l)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        CloudCard(tint: SkyPalette.warning) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: SkySpacing.s) {
                    ZStack {
                        Circle().fill(SkyPalette.warning.opacity(0.15)).frame(width: 40, height: 40)
                        Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(SkyPalette.warning)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presenter.plan?.title ?? "Plan")
                            .font(SkyFont.headline(16))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text("\(presenter.plan?.window.dayText() ?? "") · \(presenter.plan?.window.timeRangeText() ?? "")")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                LightningLine()
                    .stroke(SkyPalette.warning.opacity(0.75),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(height: 8)

                Text(presenter.assessment?.reason ?? presenter.openRisk?.summary ?? "Conditions changed for this window.")
                    .font(SkyFont.caption(13))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Comparison

    private var comparisonCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "What changed",
                              subtitle: "Two snapshots compared, not a guess")

                HStack(spacing: SkySpacing.m) {
                    snapshotColumn(
                        "Saved with",
                        presenter.scoreBefore,
                        presenter.plan?.window.snapshotCapturedAt,
                        presenter.plan?.window.verdict ?? .acceptable
                    )
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(SkyPalette.textTertiary)
                    snapshotColumn(
                        "Newest",
                        presenter.scoreAfter,
                        presenter.snapshot?.capturedAt,
                        presenter.assessment?.updatedWindow.verdict ?? .notRecommended
                    )
                }

                if let delta = presenter.scoreDelta {
                    HStack(spacing: 5) {
                        Image(systemName: delta < 0 ? "arrow.down.right" : "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(SkyFormat.signed(delta, decimals: 0)) points")
                            .font(SkyFont.caption(13).weight(.semibold))
                    }
                    .foregroundColor(delta < 0 ? SkyPalette.danger : SkyPalette.success)
                } else {
                    Text("The score could not be compared — one of the two evaluations had nothing scoreable.")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.unknown)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if presenter.assessment?.updatedWindow != nil {
                    Button(action: presenter.openUpdatedExplanation) {
                        HStack(spacing: 5) {
                            Text("Open the new explanation")
                                .font(SkyFont.caption(12).weight(.semibold))
                            Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(SkyPalette.azure)
                    }
                }
            }
        }
    }

    private func snapshotColumn(_ title: String, _ score: Double?, _ capturedAt: Date?, _ verdict: WindowVerdict) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(SkyFont.micro(10)).foregroundColor(SkyPalette.textTertiary)
            GlowRing(score: score, verdictColor: verdict.color, size: 56)
            Text(capturedAt.map { RelativeTime.string(for: $0) } ?? "Unknown")
                .font(SkyFont.micro(10))
                .foregroundColor(SkyPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Broken conditions

    @ViewBuilder
    private var brokenCard: some View {
        if !presenter.brokenRequired.isEmpty || !presenter.newlyUnknown.isEmpty {
            CloudCard(tint: SkyPalette.danger) {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    SectionHeader(title: "Requirements that no longer hold")
                    ForEach(presenter.brokenRequired) { evaluation in
                        ruleRow(evaluation)
                    }
                    ForEach(presenter.newlyUnknown) { evaluation in
                        ruleRow(evaluation)
                    }
                }
            }
        }
    }

    private func ruleRow(_ evaluation: RuleEvaluation) -> some View {
        HStack(alignment: .top, spacing: SkySpacing.s) {
            Image(systemName: evaluation.outcome.icon)
                .font(.system(size: 13))
                .foregroundColor(evaluation.outcome.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(evaluation.rule.summary)
                    .font(SkyFont.caption(13).weight(.medium))
                    .foregroundColor(SkyPalette.textPrimary)
                Text(evaluation.reason)
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Decisions

    private var decisionsCard: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Your decision",
                          subtitle: "Nothing is replaced until you confirm")

            SkyButton(title: "Keep Plan", icon: "hand.raised.fill", kind: .secondary,
                      action: presenter.requestKeep)

            if let backup = presenter.backupWindow {
                CloudCard(tint: SkyPalette.gold) {
                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        Text("Backup window available")
                            .font(SkyFont.headline(14))
                            .foregroundColor(SkyPalette.textPrimary)
                        WindowRow(window: backup) { presenter.openExplanation(backup) }
                        SkyButton(title: "Use Backup", icon: "arrow.triangle.2.circlepath",
                                  kind: .gold, action: presenter.requestUseBackup)
                    }
                }
            }

            if presenter.alternatives.isEmpty {
                CloudCard {
                    Text("No replacement window meets your required conditions in the next two days, so there is nothing to offer instead.")
                        .font(SkyFont.caption(13))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                SkyButton(title: "Choose Another Window (\(presenter.alternatives.count))",
                          icon: "square.stack.3d.up", kind: .primary,
                          action: presenter.requestChooseAnother)
            }

            SkyButton(title: "Cancel this plan", icon: "slash.circle",
                      kind: .destructive, action: presenter.requestCancelPlan)
        }
    }

    // MARK: - Resolved history

    @ViewBuilder
    private var resolvedHistory: some View {
        if !presenter.resolvedRisks.isEmpty {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Earlier decisions", subtitle: "\(presenter.resolvedRisks.count) resolved")
                ForEach(presenter.resolvedRisks) { risk in
                    CloudCard {
                        VStack(alignment: .leading, spacing: SkySpacing.s) {
                            HStack {
                                Text(risk.resolution?.title ?? "Resolved")
                                    .font(SkyFont.caption(13).weight(.semibold))
                                    .foregroundColor(SkyPalette.textPrimary)
                                Spacer()
                                Text(RelativeTime.string(for: risk.resolvedAt ?? risk.detectedAt))
                                    .font(SkyFont.micro(10))
                                    .foregroundColor(SkyPalette.textTertiary)
                            }
                            Text(risk.summary)
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Alternative picker

struct AlternativeWindowPicker: View {
    let options: [WindowCandidate]
    let onPick: (WindowCandidate) -> Void

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SkySpacing.m) {
                        Text("These were evaluated against the newest forecast snapshot. Choosing one replaces the plan's window and its explanation.")
                            .font(SkyFont.caption(12))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(options) { candidate in
                            WindowRow(window: candidate) {
                                onPick(candidate)
                                presentationMode.wrappedValue.dismiss()
                            }
                        }
                    }
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle("Choose Another Window")
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
