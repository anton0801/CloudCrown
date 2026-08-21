//
//  ComfortProfileView.swift
//  CloudCrown
//

import SwiftUI

struct ComfortProfileView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: ComfortProfilePresenter
    @StateObject private var router: ComfortProfileRouter

    init(presenter: @autoclosure @escaping () -> ComfortProfilePresenter,
         router: @autoclosure @escaping () -> ComfortProfileRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SkySpacing.l) {
                    summaryCard
                    if let message = presenter.errorMessage {
                        SaveErrorBanner(message: message,
                                        onRetry: presenter.save,
                                        onDismiss: presenter.dismissError)
                    }
                    if !presenter.hasProfile && !presenter.isEditing {
                        emptyState
                    } else {
                        if presenter.usesGeneralDefaults { defaultsBanner }
                        if !presenter.validationErrors.isEmpty { validationBanner }
                        unitsRow
                        metricEditor
                        sensitivitySection
                        dangerZone
                    }
                    Spacer(minLength: 100)
                }
                .padding(SkySpacing.l)
            }

            if presenter.isEditing || presenter.hasChanges {
                VStack {
                    Spacer()
                    saveBar
                }
            }
        }
        .navigationTitle("Comfort Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presenter.onAppear() }
        .skyToast($presenter.toast)
        .alert("Reset all limits?", isPresented: $router.showsResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { presenter.confirmReset() }
        } message: {
            Text("Every threshold returns to Not set. \(presenter.dependentSummary) Existing plans keep the explanation they were saved with.")
        }
        .alert("Unsaved limits found", isPresented: $router.showsDraftPrompt) {
            Button("Discard", role: .destructive) { presenter.discardDraft() }
            Button("Restore draft") { presenter.restoreDraft() }
        } message: {
            Text("You left this screen with unsaved changes. They were kept on this device.")
        }
        .sheet(isPresented: $router.showsUnitsSheet) {
            UnitsSheet(settings: presenter.settings) { transform in
                presenter.changeUnits(transform)
            }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        CloudCard(tint: SkyPalette.gold) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                HStack(spacing: SkySpacing.m) {
                    CrownBadge(
                        progress: Double(presenter.definedCount) / Double(max(1, MetricKind.constrainable.count)),
                        tint: SkyPalette.gold,
                        size: 54,
                        label: "\(presenter.definedCount)"
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(presenter.hasProfile ? "Your limits" : "No limits saved yet")
                            .font(SkyFont.headline(16))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text("\(presenter.definedCount) of \(MetricKind.constrainable.count) metrics defined")
                            .font(SkyFont.caption(12))
                            .foregroundColor(SkyPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                if presenter.isUsable {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(SkyPalette.success)
                        Text("Enough is defined to score windows.")
                            .font(SkyFont.caption(12))
                            .foregroundColor(SkyPalette.success)
                    }
                } else {
                    WarningBanner(
                        level: .unknown,
                        title: "Windows cannot be scored yet",
                        message: "Still undefined: " + presenter.missingCore.map(\.title).joined(separator: ", ")
                            + ". An undefined limit is Unknown — it is never treated as zero or as “no limit”."
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "slider.horizontal.below.square.filled.and.square",
            title: "Set your comfort limits",
            message: "CloudCrown does not guess what good weather means for you. Define your own thresholds, or start from general values and adjust them.",
            primaryTitle: "Set My Limits",
            primaryAction: presenter.startCustomEditing,
            secondaryTitle: "Use General Defaults",
            secondaryAction: presenter.applyGeneralDefaults,
            firstStepHint: "Start with temperature — it blocks more windows than anything else."
        )
    }

    private var defaultsBanner: some View {
        WarningBanner(
            level: .warning,
            title: "These are general starting points",
            message: ComfortProfile.generalDefaultsDisclaimer + " Nothing here is a medical threshold."
        )
    }

    private var validationBanner: some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            ForEach(presenter.validationErrors, id: \.self) { error in
                WarningBanner(level: .danger, title: "Invalid range", message: error)
            }
        }
    }

    // MARK: - Units

    private var unitsRow: some View {
        Button(action: presenter.openUnits) {
            HStack(spacing: SkySpacing.s) {
                Image(systemName: "ruler.fill")
                    .font(.system(size: 13))
                    .foregroundColor(SkyPalette.azure)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Units")
                        .font(SkyFont.caption(14).weight(.semibold))
                        .foregroundColor(SkyPalette.textPrimary)
                    Text("\(presenter.settings.temperatureUnit.symbol) · \(presenter.settings.speedUnit.symbol) · \(presenter.settings.precipitationUnit.symbol) · \(presenter.settings.distanceUnit.symbol)")
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SkyPalette.hairline)
            }
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

    // MARK: - Metric editor

    private var metricEditor: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Thresholds", subtitle: "Tap a metric, then turn each bound on or off")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SkySpacing.s) {
                    ForEach(presenter.editableMetrics, id: \.self) { metric in
                        let defined = presenter.threshold(for: metric).isDefined
                        SkyChip(
                            title: metric.shortTitle,
                            icon: defined ? "checkmark" : metric.icon,
                            color: metric.accentColor,
                            isSelected: presenter.selectedMetric == metric
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                presenter.selectedMetric = metric
                                presenter.startCustomEditing()
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            CloudCard {
                ThresholdEditor(
                    metric: presenter.selectedMetric,
                    threshold: presenter.binding(for: presenter.selectedMetric),
                    settings: presenter.settings,
                    showsMinimum: allowsMinimum(presenter.selectedMetric),
                    showsMaximum: true
                )
            }

            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text("All thresholds")
                        .font(SkyFont.headline(14))
                        .foregroundColor(SkyPalette.textPrimary)
                    ForEach(presenter.editableMetrics, id: \.self) { metric in
                        Button {
                            withAnimation { presenter.selectedMetric = metric }
                        } label: {
                            HStack {
                                Image(systemName: metric.icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(metric.accentColor)
                                    .frame(width: 20)
                                Text(metric.title)
                                    .font(SkyFont.caption(13))
                                    .foregroundColor(SkyPalette.textPrimary)
                                Spacer()
                                let threshold = presenter.threshold(for: metric)
                                if threshold.isDefined {
                                    Text(displaySummary(threshold))
                                        .font(SkyFont.micro(12).weight(.semibold))
                                        .foregroundColor(SkyPalette.textPrimary)
                                } else {
                                    UnknownTag(text: "Not set")
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private func allowsMinimum(_ metric: MetricKind) -> Bool {
        switch metric {
        case .temperature, .apparentTemperature, .visibility: return true
        default: return false
        }
    }

    /// Renders a stored (canonical) threshold in the user's chosen units.
    private func displaySummary(_ threshold: ComfortThreshold) -> String {
        let metric = threshold.metric
        let unit = presenter.settings.unitSymbol(for: metric)
        let d = metric.decimals
        func fmt(_ v: Double) -> String {
            SkyFormat.number(presenter.settings.display(v, for: metric), decimals: d)
        }
        switch (threshold.minValue, threshold.maxValue) {
        case let (min?, max?): return "\(fmt(min))–\(fmt(max)) \(unit)"
        case let (min?, nil): return "≥ \(fmt(min)) \(unit)"
        case let (nil, max?): return "≤ \(fmt(max)) \(unit)"
        default: return "Not set"
        }
    }

    // MARK: - Sensitivity

    private var sensitivitySection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Sensitivity",
                          subtitle: "Adjusts your own limits — never a medical classification")

            CloudCard {
                VStack(spacing: SkySpacing.m) {
                    ForEach(SensitivityKind.allCases) { kind in
                        VStack(alignment: .leading, spacing: SkySpacing.s) {
                            HStack(spacing: SkySpacing.s) {
                                Image(systemName: kind.icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(SkyPalette.violet)
                                    .frame(width: 18)
                                Text(kind.title)
                                    .font(SkyFont.caption(13).weight(.medium))
                                    .foregroundColor(SkyPalette.textPrimary)
                                Spacer()
                            }
                            SkySegmented(
                                options: SensitivityLevel.allCases,
                                titleFor: { $0.title },
                                selection: Binding(
                                    get: { presenter.sensitivity(for: kind) },
                                    set: { presenter.setSensitivity($0, for: kind) }
                                )
                            )
                            if let effect = presenter.sensitivityEffect(for: kind) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right").font(.system(size: 9))
                                    Text(effect).font(SkyFont.micro(10))
                                }
                                .foregroundColor(SkyPalette.textTertiary)
                            }
                        }
                        if kind != SensitivityKind.allCases.last {
                            Divider().background(SkyPalette.divider)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Danger zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Reset")
            CloudCard(tint: SkyPalette.danger) {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text("Clearing every limit stops CloudCrown from scoring any window until you define them again.")
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(presenter.dependentSummary)
                        .font(SkyFont.micro(11))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    SkyButton(title: "Reset Profile", icon: "arrow.counterclockwise",
                              kind: .destructive, action: presenter.requestReset)
                }
            }
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: SkySpacing.s) {
            if !presenter.validationErrors.isEmpty {
                Text("Fix the invalid range before saving.")
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.danger)
            }
            HStack(spacing: SkySpacing.s) {
                SkyButton(title: "Cancel", kind: .ghost, fullWidth: false, action: presenter.cancelEditing)
                SkyButton(title: "Save Profile", icon: "checkmark",
                          kind: .primary, isLoading: presenter.isSaving,
                          isEnabled: presenter.canSave, action: presenter.save)
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

// MARK: - Units sheet

struct UnitsSheet: View {
    let settings: AppSettings
    let onChange: ((inout AppSettings) -> Void) -> Void

    @Environment(\.presentationMode) private var presentationMode
    @State private var temperature: TemperatureUnit
    @State private var speed: SpeedUnit
    @State private var precipitation: PrecipitationUnit
    @State private var distance: DistanceUnit

    init(settings: AppSettings, onChange: @escaping ((inout AppSettings) -> Void) -> Void) {
        self.settings = settings
        self.onChange = onChange
        _temperature = State(initialValue: settings.temperatureUnit)
        _speed = State(initialValue: settings.speedUnit)
        _precipitation = State(initialValue: settings.precipitationUnit)
        _distance = State(initialValue: settings.distanceUnit)
    }

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SkySpacing.l) {
                        CloudCard {
                            VStack(alignment: .leading, spacing: SkySpacing.l) {
                                unitRow("Temperature", TemperatureUnit.allCases, $temperature) { $0.title }
                                unitRow("Wind speed", SpeedUnit.allCases, $speed) { $0.title }
                                unitRow("Rain amount", PrecipitationUnit.allCases, $precipitation) { $0.title }
                                unitRow("Visibility", DistanceUnit.allCases, $distance) { $0.title }
                            }
                        }
                        Text("Values are stored in metric units and converted only for display, so changing a unit never changes a saved limit.")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle("Units")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onChange { settings in
                            settings.temperatureUnit = temperature
                            settings.speedUnit = speed
                            settings.precipitationUnit = precipitation
                            settings.distanceUnit = distance
                        }
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(SkyFont.headline(15))
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func unitRow<T: Hashable>(_ title: String, _ options: [T], _ selection: Binding<T>,
                                      _ label: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            Text(title)
                .font(SkyFont.caption(13).weight(.semibold))
                .foregroundColor(SkyPalette.textPrimary)
            SkySegmented(options: options, titleFor: label, selection: selection)
        }
    }
}
