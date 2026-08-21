//
//  PlanDetailView.swift
//  CloudCrown
//

import SwiftUI

struct PlanDetailView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: PlanDetailPresenter
    @StateObject private var router: PlanDetailRouter

    init(presenter: @autoclosure @escaping () -> PlanDetailPresenter,
         router: @autoclosure @escaping () -> PlanDetailRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            if let plan = presenter.plan {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        headerCard(plan)
                        if let message = presenter.saveError {
                            SaveErrorBanner(message: message, onDismiss: presenter.dismissSaveError)
                        }
                        if plan.hasOpenRisk { riskCard(plan) }
                        if presenter.awaitsFeedback { feedbackPromptCard }
                        if let entry = presenter.feedback { feedbackCard(entry) }
                        detailsCard(plan)
                        if let backup = plan.backupWindow { backupCard(backup) }
                        historyCard
                        actionsCard(plan)
                        Spacer(minLength: SkySpacing.xxl)
                    }
                    .padding(SkySpacing.l)
                }
            } else {
                EmptyStateView(
                    icon: "calendar.badge.exclamationmark",
                    title: "This plan no longer exists",
                    message: "It was deleted. Its history entries remain in the History section."
                )
            }
        }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .routed($router.route) { router.destination(for: $0) }
        .skyToast($presenter.toast)
    }

    // MARK: - Header

    private func headerCard(_ plan: Plan) -> some View {
        CelestialCard(gradient: LinearGradient(
            colors: [plan.status.color, plan.status.color.opacity(0.72)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plan.title)
                            .font(SkyFont.title(21))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(presenter.activity?.name ?? "Removed activity") · \(presenter.place?.name ?? "Removed place")")
                            .font(SkyFont.caption(13))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().fill(Color.white.opacity(0.18)).frame(width: 54, height: 54)
                        Text(plan.window.score.map { "\(Int($0.rounded()))" } ?? "?")
                            .font(SkyFont.metric(20))
                            .foregroundColor(.white)
                    }
                }
                HStack(spacing: SkySpacing.s) {
                    Text(plan.status.title)
                        .font(SkyFont.micro(11).weight(.bold))
                        .foregroundColor(plan.status.color)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white))
                    Text("\(plan.window.dayText()) · \(plan.window.timeRangeText())")
                        .font(SkyFont.caption(13).weight(.semibold))
                        .foregroundColor(.white.opacity(0.94))
                }
            }
        }
    }

    // MARK: - Risk

    private func riskCard(_ plan: Plan) -> some View {
        WarningBanner(
            level: .warning,
            title: "This plan is at risk",
            message: plan.openRisks.last?.summary ?? "Conditions changed.",
            actionTitle: "Review and decide",
            action: presenter.openRisk
        )
    }

    // MARK: - Feedback

    private var feedbackPromptCard: some View {
        CloudCard(tint: SkyPalette.violet) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: SkySpacing.s) {
                    Image(systemName: "star.bubble.fill").foregroundColor(SkyPalette.violet)
                    Text("How did it go?")
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                }
                Text("Recording what actually happened does not change the forecast — the original snapshot is kept. It is what makes Personal Insights possible.")
                    .font(SkyFont.caption(12))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SkyButton(title: "Record how it went", icon: "star", kind: .secondary,
                          action: presenter.openFeedback)
            }
        }
    }

    private func feedbackCard(_ entry: FeedbackEntry) -> some View {
        CloudCard(tint: SkyPalette.violet) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Your review",
                              subtitle: "Recorded \(RelativeTime.string(for: entry.createdAt))",
                              actionTitle: "Edit",
                              action: presenter.openFeedback)
                HStack(spacing: SkySpacing.m) {
                    if let rating = entry.comfortRating {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { index in
                                Image(systemName: index <= rating ? "star.fill" : "star")
                                    .font(.system(size: 13))
                                    .foregroundColor(SkyPalette.gold)
                            }
                        }
                    } else {
                        UnknownTag(text: "Not rated")
                    }
                    if let repeatIt = entry.wouldRepeat {
                        SkyChip(title: repeatIt ? "Would repeat" : "Would not repeat",
                                icon: repeatIt ? "hand.thumbsup.fill" : "hand.thumbsdown.fill",
                                color: repeatIt ? SkyPalette.success : SkyPalette.danger)
                    }
                }
                if !entry.tags.isEmpty {
                    SkyWrapRow(items: entry.tags.map { FeedbackTagItem(tag: $0) }) { item in
                        SkyChip(title: item.tag.title, icon: item.tag.icon, color: item.tag.color)
                    }
                }
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Details

    private func detailsCard(_ plan: Plan) -> some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "The window you saved",
                              subtitle: "Frozen with its explanation",
                              actionTitle: "Why?",
                              action: presenter.openExplanation)

                WindowRow(window: plan.window, action: presenter.openExplanation)

                Divider().background(SkyPalette.divider)

                detailRow("Reminder", plan.reminderMinutesBefore.map { "\($0) min before" } ?? "None",
                          icon: "bell")
                if plan.reminderMinutesBefore != nil && plan.reminderNotificationID == nil {
                    Text("No notification is scheduled — iOS did not accept it. The plan itself is unaffected.")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                detailRow("Calendar",
                          plan.isCalendarConfirmed
                            ? "Confirmed \(RelativeTime.string(for: plan.calendarConfirmedAt ?? Date()))"
                            : "Not added",
                          icon: "calendar")
                detailRow("Snapshot", SkyFormat.fullDateTime(plan.window.snapshotCapturedAt, timeZone: plan.timeZone),
                          icon: "cube.box")
                detailRow("Rules version", plan.window.rulesVersion, icon: "function")

                if !plan.preparationNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preparation notes")
                            .font(SkyFont.micro(11).weight(.semibold))
                            .foregroundColor(SkyPalette.textTertiary)
                        Text(plan.preparationNotes)
                            .font(SkyFont.caption(13))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(action: presenter.openConditions) {
                    HStack(spacing: 5) {
                        Text("Open the conditions for this place")
                            .font(SkyFont.caption(12).weight(.semibold))
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(SkyPalette.azure)
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: SkySpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(SkyPalette.textTertiary)
                .frame(width: 16)
            Text(title).font(SkyFont.caption(12)).foregroundColor(SkyPalette.textSecondary)
            Spacer()
            Text(value)
                .font(SkyFont.micro(12).weight(.semibold))
                .foregroundColor(SkyPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: - Backup

    private func backupCard(_ backup: WindowCandidate) -> some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Backup window", subtitle: "Offered first if this plan comes under risk")
            WindowRow(window: backup, action: presenter.openBackupExplanation)
        }
    }

    // MARK: - History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "History", subtitle: "\(presenter.history.count) entr\(presenter.history.count == 1 ? "y" : "ies")")
            if presenter.history.isEmpty {
                CloudCard {
                    Text("No history entries yet for this plan.")
                        .font(SkyFont.caption(13))
                        .foregroundColor(SkyPalette.textSecondary)
                }
            } else {
                ForEach(presenter.history.prefix(8)) { record in
                    HistoryRow(record: record)
                }
            }
        }
    }

    // MARK: - Actions

    private func actionsCard(_ plan: Plan) -> some View {
        VStack(spacing: SkySpacing.s) {
            if plan.status == .scheduled || plan.status == .atRisk {
                if plan.isPast {
                    SkyButton(title: "Mark as completed", icon: "checkmark.seal",
                              kind: .secondary, action: presenter.markCompleted)
                }
                SkyButton(title: "Cancel this plan", icon: "slash.circle",
                          kind: .destructive, action: presenter.cancelPlan)
            }
        }
    }
}

struct FeedbackTagItem: Identifiable {
    let tag: FeedbackTag
    var id: String { tag.rawValue }
}
