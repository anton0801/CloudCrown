//
//  AlertRulesView.swift
//  CloudCrown
//

import SwiftUI

struct AlertRulesView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: AlertRulesPresenter
    @StateObject private var router: AlertRulesRouter

    init(presenter: @autoclosure @escaping () -> AlertRulesPresenter,
         router: @autoclosure @escaping () -> AlertRulesRouter) {
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
                    permissionCard
                    if !presenter.isEmpty { automaticCheckCard }
                    if presenter.isEmpty {
                        emptyState
                    } else {
                        rulesSection
                        historySection
                    }
                    Spacer(minLength: SkySpacing.xxl)
                }
                .padding(SkySpacing.l)
            }
        }
        .navigationTitle("Alert Rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: presenter.startCreating) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(SkyPalette.azure)
                .disabled(!presenter.canCreate)
            }
        }
        .onAppear { presenter.onAppear() }
        .skyToast($presenter.toast)
        .sheet(isPresented: Binding(
            get: { router.isCreating || router.editing != nil },
            set: { if !$0 { presenter.cancelEditing() } }
        )) {
            AlertRuleEditorSheet(presenter: presenter)
        }
        .alert("Unsaved alert rule", isPresented: $router.showsDraftPrompt) {
            Button("Discard", role: .destructive) { presenter.discardDraft() }
            Button("Restore draft") { presenter.restoreDraft() }
        } message: {
            Text("You closed the editor with unsaved changes. Nothing was created.")
        }
        .alert(item: $router.deletionTarget) { rule in
            Alert(
                title: Text("Delete “\(rule.name)”?"),
                message: Text("This rule will stop evaluating and no further notifications will be scheduled for it. Delivered alerts stay in History."),
                primaryButton: .destructive(Text("Delete")) { presenter.confirmDelete() },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Permission

    @ViewBuilder
    private var permissionCard: some View {
        if !presenter.notificationAuthorization.isAuthorized {
            CloudCard(tint: SkyPalette.warning) {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    HStack(spacing: SkySpacing.s) {
                        Image(systemName: "bell.slash.fill").foregroundColor(SkyPalette.warning)
                        Text("Notifications are not enabled")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                    }
                    Text(presenter.notificationAuthorization.explanation + " Rules can still be created and tested — they simply will not be delivered.")
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if presenter.notificationAuthorization == .notDetermined {
                        SkyButton(title: "Enable notifications", icon: "bell",
                                  kind: .secondary, action: presenter.requestNotificationPermission)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "bell.badge",
            title: presenter.canCreate ? "No alert rules yet" : "Add a place first",
            message: presenter.canCreate
                ? "A rule watches one place over a chosen period and notifies you when a window appears, a plan degrades, or a measurement crosses your threshold."
                : "An alert rule cannot exist without a place, a period and a threshold. Save a place first.",
            primaryTitle: primaryTitle,
            primaryAction: primaryAction,
            firstStepHint: firstStepHint
        )
    }

    private var primaryTitle: String? {
        presenter.canCreate ? "Create Alert" : nil
    }

    private var primaryAction: (() -> Void)? {
        guard presenter.canCreate else { return nil }
        return { presenter.startCreating() }
    }

    private var firstStepHint: String? {
        presenter.canCreate
            ? "Start with “a good window appears” for the activity you care about most."
            : nil
    }

    // MARK: - Automatic checking

    private var automaticCheckCard: some View {
        CloudCard(tint: SkyPalette.azure) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "When rules are checked",
                              subtitle: "Evaluation is automatic — Test Run is only a preview")

                Text(presenter.automaticCheckSummary)
                    .font(SkyFont.caption(12))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SkySpacing.s) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(SkyPalette.textTertiary)
                    if let last = presenter.lastCheck {
                        Text("Last checked \(RelativeTime.string(for: last))")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                    } else {
                        Text("Not checked yet on this device")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.unknown)
                    }
                }

                if let report = presenter.lastReport {
                    HStack(alignment: .top, spacing: SkySpacing.s) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10))
                            .foregroundColor(SkyPalette.textTertiary)
                        Text("\(report.trigger.title): \(report.summary)")
                            .font(SkyFont.micro(10))
                            .foregroundColor(SkyPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SkyButton(title: presenter.isCheckingNow ? "Checking…" : "Check All Rules Now",
                          icon: "arrow.clockwise",
                          kind: .secondary,
                          isLoading: presenter.isCheckingNow,
                          action: presenter.runCheckNow)

                Text("A check refreshes conditions, compares saved plans against the newer snapshot, and delivers any rule that matches — subject to its quiet hours and cooldown.")
                    .font(SkyFont.micro(10))
                    .foregroundColor(SkyPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Your rules", subtitle: "\(presenter.rules.count) total")
            ForEach(presenter.rules) { rule in
                CloudCard(tint: rule.kind.color) {
                    VStack(alignment: .leading, spacing: SkySpacing.m) {
                        HStack(spacing: SkySpacing.m) {
                            ZStack {
                                Circle().fill(rule.kind.color.opacity(0.14)).frame(width: 38, height: 38)
                                Image(systemName: rule.kind.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(rule.kind.color)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name)
                                    .font(SkyFont.headline(15))
                                    .foregroundColor(SkyPalette.textPrimary)
                                Text(rule.kind.shortTitle)
                                    .font(SkyFont.micro(11))
                                    .foregroundColor(SkyPalette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            if rule.isPaused {
                                SkyChip(title: "Paused", icon: "pause.fill", color: SkyPalette.textTertiary)
                            }
                        }

                        Text(rule.summary)
                            .font(SkyFont.caption(12))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: SkySpacing.s) {
                            SkyChip(title: presenter.placeName(rule.placeID), icon: "mappin", color: SkyPalette.azure)
                            if let name = presenter.activityName(rule.activityID) {
                                SkyChip(title: name, icon: "figure.walk", color: SkyPalette.lightBlue)
                            }
                        }
                        HStack(spacing: SkySpacing.s) {
                            SkyChip(title: "Quiet \(rule.quietHours.summary)", icon: "moon.fill", color: SkyPalette.violet)
                            SkyChip(title: "Cooldown \(rule.cooldownSummary)", icon: "hourglass", color: SkyPalette.textSecondary)
                        }

                        if let firedAt = rule.lastFiredAt {
                            Text("Last delivered \(RelativeTime.string(for: firedAt))")
                                .font(SkyFont.micro(10))
                                .foregroundColor(SkyPalette.textTertiary)
                        } else {
                            Text("Never delivered yet")
                                .font(SkyFont.micro(10))
                                .foregroundColor(SkyPalette.textTertiary)
                        }

                        Divider().background(SkyPalette.divider)

                        HStack(spacing: SkySpacing.l) {
                            Button { presenter.startEditing(rule) } label: {
                                Label("Edit", systemImage: "pencil")
                                    .font(SkyFont.micro(12).weight(.semibold))
                                    .foregroundColor(SkyPalette.azure)
                            }
                            Button { presenter.togglePause(rule) } label: {
                                Label(rule.isPaused ? "Resume" : "Pause",
                                      systemImage: rule.isPaused ? "play.fill" : "pause.fill")
                                    .font(SkyFont.micro(12).weight(.semibold))
                                    .foregroundColor(rule.isPaused ? SkyPalette.success : SkyPalette.textSecondary)
                            }
                            Spacer()
                            Button { presenter.requestDelete(rule) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(SkyPalette.danger)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Delivery history

    @ViewBuilder
    private var historySection: some View {
        if !presenter.events.isEmpty {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                Button { withAnimation { router.showsHistory.toggle() } } label: {
                    HStack {
                        Text("Delivery history (\(presenter.events.count))")
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textSecondary)
                        Spacer()
                        Image(systemName: router.showsHistory ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(SkyPalette.textTertiary)
                    }
                }
                if router.showsHistory {
                    ForEach(presenter.events.prefix(20)) { event in
                        CloudCard {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: event.wasSuppressed ? "bell.slash.fill" : "bell.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(event.wasSuppressed ? SkyPalette.textTertiary : SkyPalette.success)
                                    Text(event.title)
                                        .font(SkyFont.caption(13).weight(.medium))
                                        .foregroundColor(SkyPalette.textPrimary)
                                    Spacer()
                                    Text(RelativeTime.string(for: event.firedAt))
                                        .font(SkyFont.micro(10))
                                        .foregroundColor(SkyPalette.textTertiary)
                                }
                                Text(event.wasSuppressed ? (event.suppressionReason ?? "Suppressed") : event.body)
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
}

// MARK: - Editor

struct AlertRuleEditorSheet: View {

    @ObservedObject var presenter: AlertRulesPresenter

    private var draft: Binding<AlertRule> {
        Binding(
            get: { presenter.editorDraft ?? AlertRule(name: "", kind: .windowAppears, placeID: UUID()) },
            set: { presenter.editorDraft = $0 }
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        if let message = presenter.saveError {
                            SaveErrorBanner(message: message,
                                            onRetry: presenter.save,
                                            onDismiss: presenter.dismissSaveError)
                        }
                        kindCard
                        scopeCard
                        if draft.wrappedValue.kind == .metricThreshold { thresholdCard }
                        deliveryCard
                        testCard
                        ForEach(presenter.draftValidationMessages, id: \.self) { message in
                            WarningBanner(level: .warning, title: "Cannot save yet", message: message)
                        }
                        Spacer(minLength: 100)
                    }
                    .padding(SkySpacing.l)
                }

                VStack {
                    Spacer()
                    SkyButton(title: "Save Rule", icon: "checkmark", kind: .primary,
                              isLoading: presenter.isSaving,
                              isEnabled: presenter.canSaveDraft,
                              action: presenter.save)
                        .padding(.horizontal, SkySpacing.l)
                        .padding(.vertical, SkySpacing.l)
                        .background(
                            LinearGradient(colors: [SkyPalette.cloudWhite.opacity(0), SkyPalette.cloudWhite],
                                           startPoint: .top, endPoint: .bottom)
                                .ignoresSafeArea()
                        )
                }
            }
            .navigationTitle("Alert Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presenter.cancelEditing() }
                        .foregroundColor(SkyPalette.textSecondary)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var kindCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Condition", subtitle: "What should trigger this rule")
                ForEach(AlertKind.allCases) { kind in
                    Button { presenter.changeKind(kind) } label: {
                        HStack(alignment: .top, spacing: SkySpacing.m) {
                            Image(systemName: draft.wrappedValue.kind == kind ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 17))
                                .foregroundColor(draft.wrappedValue.kind == kind ? kind.color : SkyPalette.hairline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(SkyFont.caption(14).weight(.medium))
                                    .foregroundColor(SkyPalette.textPrimary)
                                Text(kind.explanation)
                                    .font(SkyFont.micro(10))
                                    .foregroundColor(SkyPalette.textSecondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(SkyPressStyle())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Rule name").font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                    TextField("Morning walk window", text: draft.name)
                        .font(SkyFont.body(15))
                        .padding(SkySpacing.m)
                        .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                            .fill(SkyPalette.surfaceSunken))
                }
            }
        }
    }

    private var scopeCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Where and when", subtitle: "A rule cannot exist without a place and a period")

                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text("Place").font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SkySpacing.s) {
                            ForEach(presenter.places) { place in
                                SkyChip(title: place.name, icon: "mappin", color: SkyPalette.azure,
                                        isSelected: draft.wrappedValue.placeID == place.id) {
                                    draft.wrappedValue.placeID = place.id
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                if draft.wrappedValue.kind == .windowAppears {
                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        Text("Activity").font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                        if presenter.activities.isEmpty {
                            Text("No activity exists yet, so there are no required conditions to watch for.")
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.danger)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: SkySpacing.s) {
                                    ForEach(presenter.activities) { activity in
                                        SkyChip(title: activity.name, icon: activity.kind.icon,
                                                color: activity.kind.accent,
                                                isSelected: draft.wrappedValue.activityID == activity.id) {
                                            draft.wrappedValue.activityID = activity.id
                                        }
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    HStack {
                        Text("Period").font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                        Spacer()
                        Text("\(draft.wrappedValue.horizonDays) day\(draft.wrappedValue.horizonDays == 1 ? "" : "s") ahead")
                            .font(SkyFont.caption(13).weight(.semibold))
                            .foregroundColor(SkyPalette.textPrimary)
                    }
                    Slider(value: Binding(
                        get: { Double(draft.wrappedValue.horizonDays) },
                        set: { draft.wrappedValue.horizonDays = Int($0) }
                    ), in: 1...7, step: 1)
                    .tint(SkyPalette.azure)
                }
            }
        }
    }

    private var thresholdCard: some View {
        CloudCard(tint: SkyPalette.violet) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Threshold")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SkySpacing.s) {
                        ForEach(MetricKind.constrainable, id: \.self) { metric in
                            SkyChip(title: metric.shortTitle, icon: metric.icon, color: metric.accentColor,
                                    isSelected: draft.wrappedValue.metric == metric) {
                                draft.wrappedValue.metric = metric
                                if draft.wrappedValue.threshold == nil {
                                    let range = metric.uiRange
                                    draft.wrappedValue.threshold = range.lowerBound + (range.upperBound - range.lowerBound) * 0.5
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }

                if let metric = draft.wrappedValue.metric {
                    SkySegmented(
                        options: [Comparison.atMost, .atLeast],
                        titleFor: { $0 == .atMost ? "Notify above" : "Notify below" },
                        selection: draft.comparison
                    )

                    CrownDial(
                        title: "Threshold",
                        unit: presenter.settings.unitSymbol(for: metric),
                        value: Binding(
                            get: { draft.wrappedValue.threshold ?? metric.uiRange.lowerBound },
                            set: { draft.wrappedValue.threshold = $0 }
                        ),
                        range: metric.uiRange,
                        step: metric.decimals > 0 ? 0.5 : 1,
                        tint: metric.accentColor,
                        isSet: draft.wrappedValue.threshold != nil
                    )
                    .frame(maxWidth: .infinity)

                    Text(draft.wrappedValue.comparison == .atMost
                         ? "You are notified when the measurement rises above this value — i.e. when it stops meeting “at most”."
                         : "You are notified when the measurement falls below this value.")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var deliveryCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Delivery", subtitle: "Quiet hours and cooldown are applied before sending")

                Toggle(isOn: draft.quietHours.isEnabled) {
                    Text("Quiet hours")
                        .font(SkyFont.caption(13).weight(.medium))
                        .foregroundColor(SkyPalette.textPrimary)
                }
                .tint(SkyPalette.violet)

                if draft.wrappedValue.quietHours.isEnabled {
                    quietRow("From", draft.quietHours.startMinute)
                    quietRow("Until", draft.quietHours.endMinute)
                    Text("Times are evaluated in the place's own time zone.")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                }

                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    HStack {
                        Text("Cooldown").font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                        Spacer()
                        Text(draft.wrappedValue.cooldownSummary)
                            .font(SkyFont.caption(13).weight(.semibold))
                            .foregroundColor(SkyPalette.textPrimary)
                    }
                    Slider(value: Binding(
                        get: { Double(draft.wrappedValue.cooldownMinutes) },
                        set: { draft.wrappedValue.cooldownMinutes = Int($0 / 30) * 30 }
                    ), in: 30...1440, step: 30)
                    .tint(SkyPalette.azure)
                    Text("Identical results are also de-duplicated, so the same window never notifies you twice.")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(isOn: draft.isPaused) {
                    Text("Pause this rule")
                        .font(SkyFont.caption(13).weight(.medium))
                        .foregroundColor(SkyPalette.textPrimary)
                }
                .tint(SkyPalette.warning)
            }
        }
    }

    private func quietRow(_ title: String, _ binding: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(SkyFont.micro(11)).foregroundColor(SkyPalette.textTertiary)
                Spacer()
                Text(QuietHours.text(binding.wrappedValue))
                    .font(SkyFont.metric(15))
                    .foregroundColor(SkyPalette.textPrimary)
            }
            Slider(value: Binding(
                get: { Double(binding.wrappedValue) },
                set: { binding.wrappedValue = Int($0 / 30) * 30 }
            ), in: 0...Double(24 * 60 - 30), step: 30)
            .tint(SkyPalette.violet)
        }
    }

    private var testCard: some View {
        CloudCard(tint: SkyPalette.gold) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Test run",
                              subtitle: "A preview only — it never sends a notification")
                SkyButton(title: "Run against current data", icon: "play.circle",
                          kind: .secondary,
                          isEnabled: presenter.canSaveDraft,
                          action: presenter.testRun)
                if let message = presenter.testResultMessage {
                    WarningBanner(
                        level: presenter.testResultIsPositive ? .info : .unknown,
                        title: presenter.testResultIsPositive ? "Would notify" : "Would not notify",
                        message: message
                    )
                }
                Text("Real delivery happens automatically when CloudCrown opens or runs in the background. Notification text is kept minimal — a place, a day and a time. No coordinates and no personal detail are included.")
                    .font(SkyFont.micro(10))
                    .foregroundColor(SkyPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
