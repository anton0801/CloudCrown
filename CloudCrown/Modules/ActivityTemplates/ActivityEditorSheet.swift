//
//  ActivityEditorSheet.swift
//  CloudCrown
//
//  Required conditions block a window. Preferred conditions only shape the
//  score and must total exactly 100%.
//

import SwiftUI

struct ActivityEditorSheet: View {

    @ObservedObject var presenter: ActivityTemplatesPresenter
    @State private var metricPicker: MetricPickerTarget?

    enum MetricPickerTarget: Identifiable {
        case required, preferred
        var id: String { self == .required ? "required" : "preferred" }
    }

    private var draft: Binding<ActivityTemplate> {
        Binding(
            get: { presenter.editorDraft ?? ActivityTemplate(name: "", kind: .custom) },
            set: { presenter.editorDraft = $0 }
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        if let message = presenter.errorMessage {
                            SaveErrorBanner(message: message,
                                            onRetry: presenter.save,
                                            onDismiss: presenter.dismissError)
                        }
                        basicsCard
                        durationCard
                        requiredCard
                        preferredCard
                        if !presenter.draftValidationMessages.isEmpty { validationCard }
                        Spacer(minLength: 100)
                    }
                    .padding(SkySpacing.l)
                }

                VStack {
                    Spacer()
                    saveBar
                }
            }
            .navigationTitle(presenter.editorDraft?.name.isEmpty == false ? "Edit Activity" : "New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presenter.cancelEditing() }
                        .foregroundColor(SkyPalette.textSecondary)
                }
            }
            .sheet(item: $metricPicker) { target in
                MetricPickerSheet(
                    title: target == .required ? "Add Required Condition" : "Add Preferred Condition",
                    subtitle: target == .required
                        ? "A required condition blocks a window outright when it fails."
                        : "A preferred condition only shapes the score, weighted against the others.",
                    excluded: target == .required
                        ? Set(draft.wrappedValue.requiredConditions.map(\.metric))
                        : Set(draft.wrappedValue.preferredConditions.map(\.metric))
                ) { metric in
                    if target == .required { presenter.addRequired(metric) }
                    else { presenter.addPreferred(metric) }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Basics

    private var basicsCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Activity")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: SkySpacing.s)], spacing: SkySpacing.s) {
                    ForEach(ActivityKind.allCases) { kind in
                        Button { presenter.changeKind(kind) } label: {
                            VStack(spacing: 5) {
                                Image(systemName: kind.icon).font(.system(size: 16, weight: .medium))
                                Text(kind.title)
                                    .font(SkyFont.micro(10).weight(.medium))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .foregroundColor(draft.wrappedValue.kind == kind ? .white : kind.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SkySpacing.m)
                            .background(
                                RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                                    .fill(draft.wrappedValue.kind == kind
                                          ? AnyShapeStyle(kind.accent)
                                          : AnyShapeStyle(kind.accent.opacity(0.10)))
                            )
                        }
                        .buttonStyle(SkyPressStyle())
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Name").font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                    TextField("Activity name", text: draft.name)
                        .font(SkyFont.body(15))
                        .padding(SkySpacing.m)
                        .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                            .fill(SkyPalette.surfaceSunken))
                    if draft.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("A name is required.")
                            .font(SkyFont.micro(11)).foregroundColor(SkyPalette.danger)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Note (optional)").font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                    TextField("What matters for this activity", text: draft.note)
                        .font(SkyFont.body(14))
                        .padding(SkySpacing.m)
                        .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                            .fill(SkyPalette.surfaceSunken))
                }

                Toggle(isOn: draft.requiresDaylight) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Must be in daylight")
                            .font(SkyFont.caption(13).weight(.medium))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text("Checked against sunrise and sunset for the place")
                            .font(SkyFont.micro(10))
                            .foregroundColor(SkyPalette.textTertiary)
                    }
                }
                .tint(SkyPalette.azure)

                if draft.wrappedValue.requiredConditions.isEmpty && draft.wrappedValue.preferredConditions.isEmpty {
                    SkyButton(title: "Add suggested conditions for \(draft.wrappedValue.kind.title)",
                              icon: "wand.and.stars", kind: .secondary,
                              action: presenter.applySuggestions)
                }
            }
        }
    }

    // MARK: - Duration

    private var durationCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Duration & Daily Range")

                CrownDial(
                    title: "Duration",
                    unit: "min",
                    value: Binding(
                        get: { Double(draft.wrappedValue.durationMinutes) },
                        set: { draft.wrappedValue.durationMinutes = Int($0) }
                    ),
                    range: 15...300,
                    step: 15,
                    tint: SkyPalette.gold
                )
                .frame(maxWidth: .infinity)

                Text(SkyFormat.duration(minutes: draft.wrappedValue.durationMinutes))
                    .font(SkyFont.caption(13).weight(.semibold))
                    .foregroundColor(SkyPalette.textPrimary)
                    .frame(maxWidth: .infinity)

                Divider().background(SkyPalette.divider)

                timeRangeRow("Earliest", draft.earliestMinute, upperBound: draft.wrappedValue.latestMinute - 30)
                timeRangeRow("Latest", draft.latestMinute, lowerBound: draft.wrappedValue.earliestMinute + 30)

                if draft.wrappedValue.latestMinute - draft.wrappedValue.earliestMinute < draft.wrappedValue.durationMinutes {
                    Text("The daily range is shorter than the duration — no window can fit.")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.danger)
                }
            }
        }
    }

    private func timeRangeRow(_ title: String, _ value: Binding<Int>,
                              lowerBound: Int = 0, upperBound: Int = 24 * 60 - 15) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(SkyFont.caption(13)).foregroundColor(SkyPalette.textSecondary)
                Spacer()
                Text(QuietHours.text(value.wrappedValue))
                    .font(SkyFont.metric(16))
                    .foregroundColor(SkyPalette.textPrimary)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = min(upperBound, max(lowerBound, Int($0 / 15) * 15)) }
                ),
                in: 0...Double(24 * 60 - 15),
                step: 15
            )
            .tint(SkyPalette.azure)
        }
    }

    // MARK: - Required

    private var requiredCard: some View {
        CloudCard(tint: SkyPalette.danger) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Required Conditions",
                              subtitle: "A failure here blocks the window",
                              actionTitle: "Add",
                              action: { metricPicker = .required })

                if draft.wrappedValue.requiredConditions.isEmpty {
                    Text("None yet. Your Comfort Profile limits still apply on top of whatever you add here.")
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(draft.wrappedValue.requiredConditions) { rule in
                        RequiredRuleEditor(
                            rule: rule,
                            settings: presenter.settings,
                            onChange: presenter.updateRequired,
                            onRemove: { presenter.removeRequired(rule.id) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Preferred

    private var preferredCard: some View {
        CloudCard(tint: SkyPalette.azure) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Preferred Conditions",
                              subtitle: "Shape the score, weights total 100%",
                              actionTitle: "Add",
                              action: { metricPicker = .preferred })

                if draft.wrappedValue.preferredConditions.isEmpty {
                    Text("None yet. Without preferred conditions a window can pass or fail, but it cannot be scored.")
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    weightSummary
                    ForEach(draft.wrappedValue.preferredConditions) { rule in
                        PreferredRuleEditor(
                            rule: rule,
                            settings: presenter.settings,
                            onChange: presenter.updatePreferred,
                            onRemove: { presenter.removePreferred(rule.id) }
                        )
                    }
                    SkyButton(title: "Distribute weights evenly", icon: "equal.circle",
                              kind: .ghost, action: presenter.distributeWeightsEvenly)
                }
            }
        }
    }

    private var weightSummary: some View {
        let total = draft.wrappedValue.totalWeight
        let remaining = draft.wrappedValue.weightRemaining
        let isValid = draft.wrappedValue.weightIsValid
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Total weight")
                    .font(SkyFont.caption(13))
                    .foregroundColor(SkyPalette.textSecondary)
                Spacer()
                Text("\(total)%")
                    .font(SkyFont.metric(18))
                    .foregroundColor(isValid ? SkyPalette.success : SkyPalette.warning)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SkyPalette.surfaceSunken)
                    Capsule()
                        .fill(isValid ? AnyShapeStyle(SkyPalette.success) : AnyShapeStyle(SkyPalette.warning))
                        .frame(width: geo.size.width * min(1, Double(total) / 100))
                }
            }
            .frame(height: 6)
            if !isValid {
                Text(remaining > 0 ? "Weight Remaining: \(remaining)%" : "Over by \(-remaining)%")
                    .font(SkyFont.micro(11).weight(.semibold))
                    .foregroundColor(SkyPalette.warning)
            }
        }
    }

    // MARK: - Validation + save

    private var validationCard: some View {
        VStack(spacing: SkySpacing.s) {
            ForEach(presenter.draftValidationMessages, id: \.self) { message in
                WarningBanner(level: .warning, title: "Cannot save yet", message: message)
            }
        }
    }

    private var saveBar: some View {
        SkyButton(title: "Save Template", icon: "checkmark",
                  kind: .primary,
                  isLoading: presenter.isSaving,
                  isEnabled: presenter.canSaveDraft,
                  action: presenter.save)
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

// MARK: - Rule editors

struct RequiredRuleEditor: View {
    let rule: ConditionRule
    let settings: AppSettings
    let onChange: (ConditionRule) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            HStack(spacing: SkySpacing.s) {
                Image(systemName: rule.metric.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(rule.metric.accentColor)
                Text(rule.metric.title)
                    .font(SkyFont.caption(14).weight(.medium))
                    .foregroundColor(SkyPalette.textPrimary)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(SkyPalette.danger.opacity(0.7))
                }
            }

            SkySegmented(
                options: [Comparison.atMost, .atLeast],
                titleFor: { $0.title },
                selection: Binding(
                    get: { rule.comparison == .between ? .atMost : rule.comparison },
                    set: { var copy = rule; copy.comparison = $0; onChange(copy) }
                )
            )

            HStack {
                Slider(
                    value: Binding(
                        get: { rule.value },
                        set: { var copy = rule; copy.value = ($0 / step).rounded() * step; onChange(copy) }
                    ),
                    in: rule.metric.uiRange,
                    step: step
                )
                .tint(rule.metric.accentColor)

                Text("\(SkyFormat.number(settings.display(rule.value, for: rule.metric), decimals: rule.metric.decimals)) \(settings.unitSymbol(for: rule.metric))")
                    .font(SkyFont.metric(14))
                    .foregroundColor(SkyPalette.textPrimary)
                    .frame(width: 82, alignment: .trailing)
            }
        }
        .padding(SkySpacing.m)
        .background(RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
            .fill(SkyPalette.surfaceSunken))
    }

    private var step: Double { rule.metric.decimals > 0 ? 0.5 : 1 }
}

struct PreferredRuleEditor: View {
    let rule: PreferredRule
    let settings: AppSettings
    let onChange: (PreferredRule) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            HStack(spacing: SkySpacing.s) {
                Image(systemName: rule.metric.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(rule.metric.accentColor)
                Text(rule.metric.title)
                    .font(SkyFont.caption(14).weight(.medium))
                    .foregroundColor(SkyPalette.textPrimary)
                Spacer()
                Text("\(rule.weight)%")
                    .font(SkyFont.metric(15))
                    .foregroundColor(SkyPalette.azure)
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(SkyPalette.danger.opacity(0.7))
                }
            }

            SkySegmented(
                options: PreferenceDirection.allCases,
                titleFor: { direction in
                    switch direction {
                    case .lower: return "Lower"
                    case .higher: return "Higher"
                    case .target: return "Target"
                    }
                },
                selection: Binding(
                    get: { rule.direction },
                    set: { direction in
                        var copy = rule
                        copy.direction = direction
                        if direction == .target && copy.target == nil {
                            let range = rule.metric.uiRange
                            copy.target = range.lowerBound + (range.upperBound - range.lowerBound) * 0.5
                        }
                        onChange(copy)
                    }
                )
            )

            if rule.direction == .target {
                HStack {
                    Text("Target").font(SkyFont.micro(11)).foregroundColor(SkyPalette.textTertiary)
                    Slider(
                        value: Binding(
                            get: { rule.target ?? rule.metric.uiRange.lowerBound },
                            set: { var copy = rule; copy.target = $0; onChange(copy) }
                        ),
                        in: rule.metric.uiRange,
                        step: rule.metric.decimals > 0 ? 0.5 : 1
                    )
                    .tint(rule.metric.accentColor)
                    Text("\(SkyFormat.number(settings.display(rule.target ?? 0, for: rule.metric), decimals: rule.metric.decimals))")
                        .font(SkyFont.metric(13))
                        .foregroundColor(SkyPalette.textPrimary)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            HStack {
                Text("Weight").font(SkyFont.micro(11)).foregroundColor(SkyPalette.textTertiary)
                Slider(
                    value: Binding(
                        get: { Double(rule.weight) },
                        set: { var copy = rule; copy.weight = Int($0); onChange(copy) }
                    ),
                    in: 0...100,
                    step: 5
                )
                .tint(SkyPalette.azure)
            }
        }
        .padding(SkySpacing.m)
        .background(RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
            .fill(SkyPalette.surfaceSunken))
    }
}

// MARK: - Metric picker

struct MetricPickerSheet: View {
    let title: String
    let subtitle: String
    let excluded: Set<MetricKind>
    let onPick: (MetricKind) -> Void

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.m) {
                        Text(subtitle)
                            .font(SkyFont.caption(13))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(MetricKind.constrainable.filter { !excluded.contains($0) }, id: \.self) { metric in
                            Button {
                                onPick(metric)
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                HStack(spacing: SkySpacing.m) {
                                    ZStack {
                                        Circle().fill(metric.accentColor.opacity(0.13)).frame(width: 34, height: 34)
                                        Image(systemName: metric.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(metric.accentColor)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(metric.title)
                                            .font(SkyFont.caption(14).weight(.medium))
                                            .foregroundColor(SkyPalette.textPrimary)
                                        Text("Measured in \(metric.canonicalUnit)")
                                            .font(SkyFont.micro(10))
                                            .foregroundColor(SkyPalette.textTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundColor(metric.accentColor)
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
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle(title)
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
