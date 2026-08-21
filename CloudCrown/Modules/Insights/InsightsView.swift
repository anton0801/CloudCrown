//
//  InsightsView.swift
//  CloudCrown
//
//  Every insight names the plans it came from. No medical conclusions.
//

import SwiftUI

struct InsightsView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: InsightsPresenter
    @StateObject private var router: InsightsRouter

    init(presenter: @autoclosure @escaping () -> InsightsPresenter,
         router: @autoclosure @escaping () -> InsightsRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SkySpacing.l) {
                    scopeCard
                    if presenter.isUnlocked {
                        if presenter.insights.isEmpty { noPatternsCard } else { insightCards }
                        disclaimerCard
                    } else {
                        lockedState
                    }
                    Spacer(minLength: SkySpacing.xxl)
                }
                .padding(SkySpacing.l)
            }
        }
        .navigationTitle("Personal Insights")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presenter.onAppear() }
        .routed($router.route) { router.destination(for: $0) }
        .skyToast($presenter.toast)
        .sheet(isPresented: $router.showsActivityPicker) {
            InsightsActivityPicker(activities: presenter.activities,
                                   selectedID: presenter.selectedActivityID) { activity in
                presenter.selectActivity(activity)
            }
        }
    }

    // MARK: - Scope

    private var scopeCard: some View {
        Button(action: presenter.openActivityPicker) {
            CloudCard {
                HStack(spacing: SkySpacing.m) {
                    ZStack {
                        Circle().fill(SkyPalette.violet.opacity(0.13)).frame(width: 36, height: 36)
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(SkyPalette.violet)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(presenter.selectedActivityName)
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text("\(presenter.ratedCount) rated activit\(presenter.ratedCount == 1 ? "y" : "ies") in scope")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text("Change Activity")
                        .font(SkyFont.micro(11).weight(.semibold))
                        .foregroundColor(SkyPalette.azure)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SkyPalette.azure)
                }
            }
        }
        .buttonStyle(SkyPressStyle())
    }

    // MARK: - Locked

    private var lockedState: some View {
        VStack(spacing: SkySpacing.l) {
            CloudCard(tint: SkyPalette.violet) {
                VStack(spacing: SkySpacing.m) {
                    ZStack {
                        Circle()
                            .stroke(SkyPalette.surfaceSunken, lineWidth: 10)
                            .frame(width: 110, height: 110)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1, Double(presenter.ratedCount) / Double(presenter.requiredCount))))
                            .stroke(SkyPalette.violetGradient,
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 110, height: 110)
                        VStack(spacing: 0) {
                            Text("\(presenter.ratedCount)")
                                .font(SkyFont.metric(30))
                                .foregroundColor(SkyPalette.textPrimary)
                            Text("of \(presenter.requiredCount)")
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.textTertiary)
                        }
                    }

                    Text("\(presenter.remaining) more rated activit\(presenter.remaining == 1 ? "y" : "ies") needed")
                        .font(SkyFont.title(18))
                        .foregroundColor(SkyPalette.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Insights are drawn only from activities you actually rated. Below \(presenter.requiredCount) entries, any pattern would be noise dressed up as a finding — so CloudCrown shows nothing instead.")
                        .font(SkyFont.caption(13))
                        .foregroundColor(SkyPalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }

            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text("What you will get")
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                    previewRow("clock.fill", "Most Reliable Hours", "Which starting hours actually felt best.")
                    previewRow("exclamationmark.triangle.fill", "Common Mismatches", "Where the forecast and your experience diverged most often.")
                    previewRow("mappin.and.ellipse", "Preferred Places", "Which place you rate highest for this activity.")
                }
            }
        }
    }

    private func previewRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: SkySpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(SkyPalette.violet)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(SkyFont.caption(13).weight(.medium)).foregroundColor(SkyPalette.textPrimary)
                Text(detail).font(SkyFont.micro(11)).foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Insights

    private var insightCards: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "What your history shows",
                          subtitle: "From \(presenter.ratedCount) rated activities")
            ForEach(presenter.insights) { insight in
                CloudCard(tint: SkyPalette.violet) {
                    VStack(alignment: .leading, spacing: SkySpacing.m) {
                        HStack(spacing: SkySpacing.s) {
                            ZStack {
                                Circle().fill(SkyPalette.violet.opacity(0.13)).frame(width: 34, height: 34)
                                Image(systemName: icon(for: insight.kind))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(SkyPalette.violet)
                            }
                            Text(insight.title)
                                .font(SkyFont.headline(15))
                                .foregroundColor(SkyPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }

                        Text(insight.detail)
                            .font(SkyFont.caption(13))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 5) {
                            Image(systemName: "info.circle").font(.system(size: 9))
                            Text(insight.confidenceNote).font(SkyFont.micro(10))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundColor(SkyPalette.textTertiary)

                        Button { presenter.openSourcePlans(insight) } label: {
                            HStack(spacing: 5) {
                                Text("View Source Plans (\(Set(insight.supportingPlanIDs).count))")
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

    private func icon(for kind: InsightsEngine.Insight.Kind) -> String {
        switch kind {
        case .reliableHours: return "clock.fill"
        case .commonMismatch: return "exclamationmark.triangle.fill"
        case .preferredPlace: return "mappin.and.ellipse"
        case .forecastAccuracy: return "chart.line.uptrend.xyaxis"
        }
    }

    private var noPatternsCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                Text("No clear pattern yet")
                    .font(SkyFont.headline(15))
                    .foregroundColor(SkyPalette.textPrimary)
                Text("You have enough rated activities, but they are spread too evenly across hours, places and tags for any single finding to stand out. CloudCrown reports nothing rather than inventing a pattern.")
                    .font(SkyFont.caption(13))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var disclaimerCard: some View {
        CloudCard {
            HStack(alignment: .top, spacing: SkySpacing.s) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(SkyPalette.textTertiary)
                Text("These are patterns in your own recorded ratings, nothing more. They are not health findings, and CloudCrown does not draw medical conclusions from weather, air quality or pollen.")
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Source plans

struct SourcePlansView: View {
    let planIDs: [UUID]
    let title: String
    let environment: AppEnvironment
    let coordinator: AppCoordinator

    @EnvironmentObject private var repository: DataRepository
    @State private var selected: IdentifiableID?

    private var plans: [Plan] {
        planIDs.compactMap { repository.plan(id: $0) }.sorted { $0.window.start > $1.window.start }
    }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    Text(title)
                        .font(SkyFont.headline(16))
                        .foregroundColor(SkyPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This finding was computed from the plans below and nothing else.")
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if plans.isEmpty {
                        CloudCard {
                            Text("The supporting plans were deleted. The finding above was computed before they were removed.")
                                .font(SkyFont.caption(13))
                                .foregroundColor(SkyPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        ForEach(plans) { plan in
                            PlanRow(plan: plan,
                                    activityName: repository.activity(id: plan.activityID)?.name ?? "Removed activity",
                                    placeName: repository.place(id: plan.placeID)?.name ?? "Removed place") {
                                selected = IdentifiableID(id: plan.id)
                            }
                        }
                    }
                    Spacer(minLength: SkySpacing.xxl)
                }
                .padding(SkySpacing.l)
            }
        }
        .navigationTitle("Source Plans")
        .navigationBarTitleDisplayMode(.inline)
        .routed($selected) { item in
            PlanDetailModule.build(environment: environment, coordinator: coordinator, planID: item.id)
        }
    }
}

// MARK: - Activity picker

struct InsightsActivityPicker: View {
    let activities: [ActivityTemplate]
    let selectedID: UUID?
    let onPick: (ActivityTemplate?) -> Void

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SkySpacing.s) {
                        row(title: "All activities", icon: "square.stack.3d.up",
                            accent: SkyPalette.violet, isSelected: selectedID == nil) {
                            onPick(nil)
                            presentationMode.wrappedValue.dismiss()
                        }
                        ForEach(activities) { activity in
                            row(title: activity.name, icon: activity.kind.icon,
                                accent: activity.kind.accent, isSelected: selectedID == activity.id) {
                                onPick(activity)
                                presentationMode.wrappedValue.dismiss()
                            }
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

    private func row(title: String, icon: String, accent: Color, isSelected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SkySpacing.m) {
                ZStack {
                    Circle().fill(accent.opacity(0.13)).frame(width: 34, height: 34)
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(accent)
                }
                Text(title)
                    .font(SkyFont.caption(14).weight(.medium))
                    .foregroundColor(SkyPalette.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(SkyPalette.success)
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
