//
//  PlansView.swift
//  CloudCrown
//

import SwiftUI

struct PlansView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: PlansPresenter
    @StateObject private var router: PlansRouter

    init(presenter: @autoclosure @escaping () -> PlansPresenter,
         router: @autoclosure @escaping () -> PlansRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SkySpacing.l) {
                    if let message = presenter.saveError {
                        SaveErrorBanner(message: message, onDismiss: presenter.dismissSaveError)
                    }
                    if presenter.isEmpty {
                        emptyState
                    } else {
                        scopePicker
                        planList
                    }
                    Spacer(minLength: SkySpacing.xxl)
                }
                .padding(SkySpacing.l)
            }
        }
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { presenter.onAppear() }
        .routed($router.route) { router.destination(for: $0) }
        .skyToast($presenter.toast)
        .sheet(item: Binding(
            get: { router.deletionTarget.map { DeletionSheetPayload(impact: $0) } },
            set: { if $0 == nil { router.deletionTarget = nil } }
        )) { payload in
            DeletionConsequencesSheet(impact: payload.impact) { strategy in
                presenter.performDelete(payload.impact, strategy: strategy)
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "calendar.badge.plus",
            title: "No plans yet",
            message: "A plan is a window you decided to keep. CloudCrown stores the explanation it was saved with, then tells you when the forecast it relied on changes.",
            firstStepHint: "Run Find Window, open a result, then save it as a plan."
        )
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SkySpacing.s) {
                ForEach(PlansPresenter.Scope.allCases) { scope in
                    SkyChip(
                        title: "\(scope.title) (\(presenter.count(for: scope)))",
                        color: color(for: scope),
                        isSelected: presenter.scope == scope
                    ) {
                        withAnimation(.easeOut(duration: 0.18)) { presenter.scope = scope }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func color(for scope: PlansPresenter.Scope) -> Color {
        switch scope {
        case .upcoming: return SkyPalette.azure
        case .atRisk: return SkyPalette.warning
        case .awaitingFeedback: return SkyPalette.violet
        case .past: return SkyPalette.textSecondary
        case .archived: return SkyPalette.textTertiary
        }
    }

    @ViewBuilder
    private var planList: some View {
        if presenter.visiblePlans.isEmpty {
            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text("Nothing here")
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                    Text(presenter.emptyMessage)
                        .font(SkyFont.caption(13))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(spacing: SkySpacing.m) {
                ForEach(presenter.visiblePlans) { plan in
                    VStack(spacing: 0) {
                        PlanRow(plan: plan,
                                activityName: presenter.activityName(plan.activityID),
                                placeName: presenter.placeName(plan.placeID),
                                awaitsFeedback: presenter.awaitsFeedback(plan)) {
                            presenter.open(plan)
                        }

                        HStack(spacing: SkySpacing.l) {
                            Button { presenter.openDetail(plan) } label: {
                                Label("Details", systemImage: "info.circle")
                                    .font(SkyFont.micro(11).weight(.semibold))
                                    .foregroundColor(SkyPalette.azure)
                            }
                            if plan.hasOpenRisk {
                                Button { presenter.openRisk(plan) } label: {
                                    Label("Decide", systemImage: "bolt.fill")
                                        .font(SkyFont.micro(11).weight(.semibold))
                                        .foregroundColor(SkyPalette.warning)
                                }
                            }
                            if presenter.awaitsFeedback(plan) {
                                Button { presenter.openFeedback(plan) } label: {
                                    Label("Review", systemImage: "star.bubble")
                                        .font(SkyFont.micro(11).weight(.semibold))
                                        .foregroundColor(SkyPalette.violet)
                                }
                            }
                            Spacer()
                            if plan.status == .archived {
                                Button { presenter.restore(plan) } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(SkyPalette.success)
                                }
                            } else {
                                Button { presenter.archive(plan) } label: {
                                    Image(systemName: "archivebox")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(SkyPalette.textSecondary)
                                }
                            }
                            Button { presenter.requestDelete(plan) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(SkyPalette.danger)
                            }
                        }
                        .padding(.horizontal, SkySpacing.m)
                        .padding(.top, SkySpacing.s)
                    }
                }
            }
        }
    }
}
