//
//  HistoryView.swift
//  CloudCrown
//

import SwiftUI

struct HistoryView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: HistoryPresenter
    @StateObject private var router: HistoryRouter

    init(presenter: @autoclosure @escaping () -> HistoryPresenter,
         router: @autoclosure @escaping () -> HistoryRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SkySpacing.l) {
                    insightsCard
                    SkySegmented(options: HistoryPresenter.Tab.allCases,
                                 titleFor: { $0.title },
                                 selection: $presenter.tab)
                    if presenter.tab == .reviews { reviewsTab } else { activityLogTab }
                    Spacer(minLength: SkySpacing.xxl)
                }
                .padding(SkySpacing.l)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .routed($router.route) { router.destination(for: $0) }
        .skyToast($presenter.toast)
    }

    // MARK: - Insights entry

    private var insightsCard: some View {
        Button(action: presenter.openInsights) {
            CloudCard(tint: SkyPalette.violet) {
                HStack(spacing: SkySpacing.m) {
                    CrownBadge(progress: Double(presenter.ratedCount) / Double(presenter.insightsRequired),
                               tint: SkyPalette.violet,
                               size: 48,
                               label: "\(presenter.ratedCount)")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personal Insights")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text(presenter.insightsUnlocked
                             ? "Unlocked from \(presenter.ratedCount) rated activities"
                             : "\(presenter.insightsRemaining) more rated activit\(presenter.insightsRemaining == 1 ? "y" : "ies") needed")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(SkyPalette.hairline)
                }
            }
        }
        .buttonStyle(SkyPressStyle())
    }

    // MARK: - Reviews

    @ViewBuilder
    private var reviewsTab: some View {
        VStack(alignment: .leading, spacing: SkySpacing.l) {
            if !presenter.pendingReviews.isEmpty {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    SectionHeader(title: "Waiting for your review",
                                  subtitle: "Rating is optional, but Insights needs it")
                    ForEach(presenter.pendingReviews) { plan in
                        PlanRow(plan: plan,
                                activityName: presenter.activityName(plan.activityID),
                                placeName: presenter.placeName(plan.placeID),
                                awaitsFeedback: true) {
                            presenter.openReview(plan)
                        }
                    }
                }
            }

            if presenter.feedbackEntries.isEmpty {
                EmptyStateView(
                    icon: "star.bubble",
                    title: "No reviews yet",
                    message: "After a planned window ends, record what actually happened. CloudCrown keeps the original forecast alongside your assessment — the forecast is never rewritten.",
                    firstStepHint: presenter.pendingReviews.isEmpty
                        ? "Save a plan first, then review it once it has passed."
                        : "Start with the plan waiting above."
                )
            } else {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    SectionHeader(title: "Recorded reviews", subtitle: "\(presenter.feedbackEntries.count) total")
                    ForEach(presenter.feedbackEntries) { entry in
                        feedbackCard(entry)
                    }
                }
            }
        }
    }

    private func feedbackCard(_ entry: FeedbackEntry) -> some View {
        Button { presenter.openFeedback(entry) } label: {
            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    HStack(spacing: SkySpacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(presenter.planTitle(entry.planID))
                                .font(SkyFont.headline(15))
                                .foregroundColor(SkyPalette.textPrimary)
                                .lineLimit(1)
                            Text("\(SkyFormat.dayShort(entry.windowStart, timeZone: presenter.timeZone(entry.placeID))) · \(presenter.placeName(entry.placeID))")
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if let rating = entry.comfortRating {
                            HStack(spacing: 1) {
                                ForEach(1...5, id: \.self) { index in
                                    Image(systemName: index <= rating ? "star.fill" : "star")
                                        .font(.system(size: 10))
                                        .foregroundColor(SkyPalette.gold)
                                }
                            }
                        } else {
                            UnknownTag(text: "Not rated")
                        }
                    }

                    HStack(spacing: SkySpacing.m) {
                        forecastVsActual(entry)
                    }

                    if !entry.tags.isEmpty {
                        SkyWrapRow(items: entry.tags.map { FeedbackTagItem(tag: $0) }) { item in
                            SkyChip(title: item.tag.title, icon: item.tag.icon, color: item.tag.color)
                        }
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "cube.box").font(.system(size: 8))
                        Text("Forecast snapshot \(String(entry.forecastSnapshotID.uuidString.prefix(6))) preserved unchanged")
                            .font(SkyFont.micro(9))
                    }
                    .foregroundColor(SkyPalette.textTertiary)
                }
            }
        }
        .buttonStyle(SkyPressStyle())
    }

    private func forecastVsActual(_ entry: FeedbackEntry) -> some View {
        HStack(spacing: SkySpacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Forecast score").font(SkyFont.micro(9)).foregroundColor(SkyPalette.textTertiary)
                if let score = entry.forecastScore {
                    Text("\(Int(score.rounded()))")
                        .font(SkyFont.metric(16))
                        .foregroundColor(SkyPalette.azure)
                } else {
                    UnknownTag()
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Your comfort").font(SkyFont.micro(9)).foregroundColor(SkyPalette.textTertiary)
                if let rating = entry.comfortRating {
                    Text("\(rating)/5")
                        .font(SkyFont.metric(16))
                        .foregroundColor(SkyPalette.violet)
                } else {
                    UnknownTag(text: "—")
                }
            }
            if let repeatIt = entry.wouldRepeat {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat?").font(SkyFont.micro(9)).foregroundColor(SkyPalette.textTertiary)
                    Image(systemName: repeatIt ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .font(.system(size: 14))
                        .foregroundColor(repeatIt ? SkyPalette.success : SkyPalette.danger)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Activity log

    @ViewBuilder
    private var activityLogTab: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            if presenter.records.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "Nothing recorded yet",
                    message: "Every change you make — a limit, an activity, a place, a plan, a refresh — writes a readable entry here so you can always see what happened and when."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SkySpacing.s) {
                        SkyChip(title: "All", color: SkyPalette.textSecondary,
                                isSelected: presenter.entityFilter == nil) {
                            presenter.entityFilter = nil
                        }
                        ForEach(presenter.availableFilters, id: \.self) { type in
                            SkyChip(title: type.title, color: SkyPalette.azure,
                                    isSelected: presenter.entityFilter == type) {
                                presenter.entityFilter = type
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }

                SectionHeader(title: "Activity log", subtitle: "\(presenter.records.count) entr\(presenter.records.count == 1 ? "y" : "ies")")

                ForEach(presenter.records.prefix(80)) { record in
                    HistoryRow(record: record) { presenter.openRecord(record) }
                }

                if presenter.records.count > 80 {
                    Text("Showing the 80 most recent of \(presenter.records.count) entries.")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.textTertiary)
                }
            }
        }
    }
}
