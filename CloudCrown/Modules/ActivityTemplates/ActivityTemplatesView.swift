//
//  ActivityTemplatesView.swift
//  CloudCrown
//

import SwiftUI

struct ActivityTemplatesView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: ActivityTemplatesPresenter
    @StateObject private var router: ActivityTemplatesRouter

    init(presenter: @autoclosure @escaping () -> ActivityTemplatesPresenter,
         router: @autoclosure @escaping () -> ActivityTemplatesRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SkySpacing.l) {
                    if let message = presenter.errorMessage {
                        SaveErrorBanner(message: message, onDismiss: presenter.dismissError)
                    }
                    if presenter.isEmpty {
                        emptyState
                    } else {
                        activeSection
                        archivedSection
                    }
                    Spacer(minLength: SkySpacing.xxl)
                }
                .padding(SkySpacing.l)
            }
        }
        .navigationTitle("Activities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { presenter.startCreating() } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(SkyPalette.azure)
            }
        }
        .onAppear { presenter.onAppear() }
        .skyToast($presenter.toast)
        .sheet(item: $router.editing) { _ in
            ActivityEditorSheet(presenter: presenter)
        }
        .sheet(item: Binding(
            get: { router.deletionTarget.map { DeletionSheetPayload(impact: $0) } },
            set: { if $0 == nil { router.deletionTarget = nil } }
        )) { payload in
            DeletionConsequencesSheet(impact: payload.impact) { strategy in
                presenter.performDelete(payload.impact, strategy: strategy)
            }
        }
        .alert("Unsaved activity found", isPresented: $router.showsDraftPrompt) {
            Button("Discard", role: .destructive) { presenter.discardDraft() }
            Button("Restore draft") { presenter.restoreDraft() }
        } message: {
            Text("You closed the editor with unsaved changes. Nothing was created — the draft was kept on this device.")
        }
    }

    // MARK: - Sections

    private var emptyState: some View {
        EmptyStateView(
            icon: "figure.walk",
            title: "No activity templates yet",
            message: "An activity defines which conditions block a window outright, and which only shape its score. Without one, CloudCrown has nothing to evaluate against.",
            primaryTitle: "Add Activity",
            primaryAction: { presenter.startCreating() },
            firstStepHint: "Start with the activity you actually plan most often."
        )
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Your Activities",
                          subtitle: "\(presenter.active.count) active",
                          actionTitle: "Add",
                          action: { presenter.startCreating() })
            ForEach(presenter.active) { template in
                activityCard(template)
            }
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        if !presenter.archived.isEmpty {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                Button {
                    withAnimation { router.showsArchived.toggle() }
                } label: {
                    HStack {
                        Text("Archived (\(presenter.archived.count))")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textSecondary)
                        Spacer()
                        Image(systemName: router.showsArchived ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(SkyPalette.textTertiary)
                    }
                }
                if router.showsArchived {
                    ForEach(presenter.archived) { template in
                        activityCard(template)
                    }
                }
            }
        }
    }

    private func activityCard(_ template: ActivityTemplate) -> some View {
        CloudCard(tint: template.kind.accent) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: SkySpacing.m) {
                    ZStack {
                        Circle().fill(template.kind.accent.opacity(0.14)).frame(width: 40, height: 40)
                        Image(systemName: template.kind.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(template.kind.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(SkyFont.headline(16))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text("\(template.kind.title) · \(SkyFormat.duration(minutes: template.durationMinutes))")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if template.isArchived {
                        SkyChip(title: "Archived", icon: "archivebox.fill", color: SkyPalette.textTertiary)
                    }
                }

                HStack(spacing: SkySpacing.s) {
                    SkyChip(title: "\(template.requiredConditions.count) required",
                            icon: "lock.fill", color: SkyPalette.danger)
                    SkyChip(title: "\(template.preferredConditions.count) preferred · \(template.totalWeight)%",
                            icon: "slider.horizontal.3",
                            color: template.weightIsValid ? SkyPalette.azure : SkyPalette.warning)
                    if template.requiresDaylight {
                        SkyChip(title: "Daylight", icon: "sun.max.fill", color: SkyPalette.gold)
                    }
                }

                if !template.weightIsValid {
                    WarningBanner(
                        level: .warning,
                        title: "Weight Remaining: \(template.weightRemaining)%",
                        message: "Preferred weights must total exactly 100% before this template can score a window."
                    )
                }

                if template.requiredConditions.isEmpty {
                    Text("No required conditions — only your Comfort Profile limits will block a window.")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(template.requiredConditions.prefix(3)) { rule in
                            HStack(spacing: 5) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(SkyPalette.danger)
                                Text(rule.summary)
                                    .font(SkyFont.micro(11))
                                    .foregroundColor(SkyPalette.textSecondary)
                            }
                        }
                        if template.requiredConditions.count > 3 {
                            Text("+\(template.requiredConditions.count - 3) more")
                                .font(SkyFont.micro(10))
                                .foregroundColor(SkyPalette.textTertiary)
                        }
                    }
                }

                Divider().background(SkyPalette.divider)

                HStack(spacing: SkySpacing.l) {
                    Button { presenter.startEditing(template) } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(SkyFont.micro(12).weight(.semibold))
                            .foregroundColor(SkyPalette.azure)
                    }
                    if template.isArchived {
                        Button { presenter.restore(template) } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                                .font(SkyFont.micro(12).weight(.semibold))
                                .foregroundColor(SkyPalette.success)
                        }
                    } else {
                        Button { presenter.archive(template) } label: {
                            Label("Archive", systemImage: "archivebox")
                                .font(SkyFont.micro(12).weight(.semibold))
                                .foregroundColor(SkyPalette.textSecondary)
                        }
                    }
                    Spacer()
                    Button { presenter.requestDelete(template) } label: {
                        Label("Delete", systemImage: "trash")
                            .font(SkyFont.micro(12).weight(.semibold))
                            .foregroundColor(SkyPalette.danger)
                    }
                }
            }
        }
    }
}

/// Wrapper so a DeletionImpact can drive `.sheet(item:)`.
struct DeletionSheetPayload: Identifiable {
    let id = UUID()
    let impact: DeletionImpact
}
