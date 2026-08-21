//
//  SettingsView.swift
//  CloudCrown
//

import SwiftUI

struct SettingsView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: SettingsPresenter
    @StateObject private var router: SettingsRouter

    init(presenter: @autoclosure @escaping () -> SettingsPresenter,
         router: @autoclosure @escaping () -> SettingsRouter) {
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
                    setupLinks
                    unitsSection
                    locationSection
                    permissionsSection
                    refreshSection
                    sourcesSection
                    dataSection
                    aboutSection
                    Spacer(minLength: SkySpacing.xxl)
                }
                .padding(SkySpacing.l)
            }
        }
        .navigationTitle("Settings & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presenter.onAppear() }
        .routed($router.route) { router.destination(for: $0) }
        .skyToast($presenter.toast)
        .sheet(isPresented: $router.showsExportSheet) {
            if let url = router.exportURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $router.showsEraseConfirmation) {
            EraseDataSheet(presenter: presenter)
        }
    }

    // MARK: - Setup links

    private var setupLinks: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Your setup", subtitle: "Everything a window is scored against")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SkySpacing.s),
                                GridItem(.flexible(), spacing: SkySpacing.s)],
                      spacing: SkySpacing.s) {
                linkTile("Comfort Profile", "slider.horizontal.below.square.filled.and.square",
                         SkyPalette.gold) { presenter.open(.comfortProfile) }
                linkTile("Activities", "figure.walk", SkyPalette.azure,
                         subtitle: "\(presenter.counts.activities) saved") { presenter.open(.activities) }
                linkTile("Places", "mappin.and.ellipse", SkyPalette.lightBlue,
                         subtitle: "\(presenter.counts.places) saved") { presenter.open(.places) }
                linkTile("Alert Rules", "bell.badge.fill", SkyPalette.violet,
                         subtitle: "\(presenter.counts.alerts) rules") { presenter.open(.alerts) }
            }
        }
    }

    private func linkTile(_ title: String, _ icon: String, _ color: Color,
                          subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                ZStack {
                    Circle().fill(color.opacity(0.13)).frame(width: 32, height: 32)
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
                }
                Text(title)
                    .font(SkyFont.caption(13).weight(.semibold))
                    .foregroundColor(SkyPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let subtitle = subtitle {
                    Text(subtitle).font(SkyFont.micro(10)).foregroundColor(SkyPalette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SkySpacing.m)
            .background(RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .fill(SkyPalette.surface))
            .overlay(RoundedRectangle(cornerRadius: SkyRadius.medium, style: .continuous)
                .strokeBorder(SkyPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(SkyPressStyle())
    }

    // MARK: - Units

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Units", subtitle: "Display only — stored limits never change")
            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.l) {
                    unitRow("Temperature", TemperatureUnit.allCases, presenter.settings.temperatureUnit,
                            { $0.title }) { value in presenter.update { $0.temperatureUnit = value } }
                    unitRow("Wind speed", SpeedUnit.allCases, presenter.settings.speedUnit,
                            { $0.title }) { value in presenter.update { $0.speedUnit = value } }
                    unitRow("Rain amount", PrecipitationUnit.allCases, presenter.settings.precipitationUnit,
                            { $0.title }) { value in presenter.update { $0.precipitationUnit = value } }
                    unitRow("Visibility", DistanceUnit.allCases, presenter.settings.distanceUnit,
                            { $0.title }) { value in presenter.update { $0.distanceUnit = value } }

                    Divider().background(SkyPalette.divider)

                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        Text("Air quality scale")
                            .font(SkyFont.caption(13).weight(.semibold))
                            .foregroundColor(SkyPalette.textPrimary)
                        SkySegmented(options: AQIStandard.allCases, titleFor: { $0.title },
                                     selection: Binding(
                                        get: { presenter.settings.aqiStandard },
                                        set: { value in presenter.update { $0.aqiStandard = value } }
                                     ))
                        Text(presenter.settings.aqiStandard.explanation)
                            .font(SkyFont.micro(10))
                            .foregroundColor(SkyPalette.textTertiary)
                    }
                }
            }
        }
    }

    private func unitRow<T: Hashable>(_ title: String, _ options: [T], _ current: T,
                                      _ label: @escaping (T) -> String,
                                      _ onChange: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            Text(title)
                .font(SkyFont.caption(13).weight(.semibold))
                .foregroundColor(SkyPalette.textPrimary)
            SkySegmented(options: options, titleFor: label,
                         selection: Binding(get: { current }, set: onChange))
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Location Precision",
                          subtitle: "Applied before any request leaves the device")
            CloudCard(tint: SkyPalette.lightBlue) {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    ForEach(LocationPrecision.allCases) { precision in
                        Button { presenter.setLocationPrecision(precision) } label: {
                            HStack(alignment: .top, spacing: SkySpacing.m) {
                                Image(systemName: presenter.settings.locationPrecision == precision
                                      ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 17))
                                    .foregroundColor(presenter.settings.locationPrecision == precision
                                                     ? SkyPalette.azure : SkyPalette.hairline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(precision.title)
                                        .font(SkyFont.caption(14).weight(.medium))
                                        .foregroundColor(SkyPalette.textPrimary)
                                    Text(precision.explanation)
                                        .font(SkyFont.micro(10))
                                        .foregroundColor(SkyPalette.textSecondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(SkyPressStyle())
                    }

                    Divider().background(SkyPalette.divider)

                    HStack(alignment: .top, spacing: SkySpacing.s) {
                        Image(systemName: presenter.locationAuthorization.isDenied ? "location.slash" : "location.fill")
                            .font(.system(size: 12))
                            .foregroundColor(presenter.locationAuthorization.isDenied
                                             ? SkyPalette.warning : SkyPalette.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Device location access")
                                .font(SkyFont.caption(13).weight(.semibold))
                                .foregroundColor(SkyPalette.textPrimary)
                            Text(presenter.locationAuthorization.explanation)
                                .font(SkyFont.micro(10))
                                .foregroundColor(SkyPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Consent is separate and revocable in iOS Settings at any time. CloudCrown never reads your location in the background.")
                                .font(SkyFont.micro(10))
                                .foregroundColor(SkyPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Permissions")
            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    permissionRow(
                        "Notifications",
                        presenter.notificationAuthorization.isAuthorized ? "bell.fill" : "bell.slash.fill",
                        presenter.notificationAuthorization.explanation,
                        presenter.notificationAuthorization.isAuthorized
                    )
                    if presenter.notificationAuthorization == .notDetermined {
                        SkyButton(title: "Enable notifications", icon: "bell",
                                  kind: .secondary, action: presenter.requestNotifications)
                    }
                    Divider().background(SkyPalette.divider)
                    permissionRow("Calendar", "calendar", presenter.calendarSummary, true)
                    Text("Calendar access is only requested when you tap Add to Calendar on a saved plan, and CloudCrown records an event only after iOS confirms it was saved.")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func permissionRow(_ title: String, _ icon: String, _ detail: String, _ isPositive: Bool) -> some View {
        HStack(alignment: .top, spacing: SkySpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isPositive ? SkyPalette.success : SkyPalette.warning)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(SkyFont.caption(13).weight(.semibold)).foregroundColor(SkyPalette.textPrimary)
                Text(detail).font(SkyFont.micro(10)).foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Background Refresh",
                          subtitle: "Re-checks saved plans and alert rules")
            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.m) {
                    Toggle(isOn: Binding(
                        get: { presenter.settings.backgroundRefreshEnabled },
                        set: { value in presenter.update { $0.backgroundRefreshEnabled = value } }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Check automatically")
                                .font(SkyFont.caption(13).weight(.medium))
                                .foregroundColor(SkyPalette.textPrimary)
                            Text("On launch, on returning to the app, and in the background")
                                .font(SkyFont.micro(10))
                                .foregroundColor(SkyPalette.textTertiary)
                        }
                    }
                    .tint(SkyPalette.azure)

                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        refreshDetailRow("What a check does",
                                         "Refreshes conditions for places used by a plan or rule, compares each saved plan against the newer snapshot, and delivers any alert rule that matches.")
                        refreshDetailRow("Freshness budget",
                                         "A stored snapshot older than \(Int(ConditionSnapshot.freshnessBudget / 60)) minutes is replaced. A newer one is reused.")
                        refreshDetailRow("Background scheduling",
                                         presenter.backgroundStatus.summary)
                    }

                    Divider().background(SkyPalette.divider)

                    HStack(spacing: SkySpacing.s) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                            .foregroundColor(SkyPalette.textTertiary)
                        if let last = presenter.lastRefreshCheck {
                            Text("Last checked \(RelativeTime.string(for: last))")
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.textSecondary)
                        } else {
                            Text("Not checked yet on this device")
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.unknown)
                        }
                        Spacer(minLength: 0)
                    }

                    if let report = presenter.lastRefreshReport {
                        Text("\(report.trigger.title): \(report.summary)")
                            .font(SkyFont.micro(10))
                            .foregroundColor(SkyPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SkyButton(title: presenter.isCheckingNow ? "Checking…" : "Check Now",
                              icon: "arrow.clockwise",
                              kind: .secondary,
                              isLoading: presenter.isCheckingNow,
                              action: presenter.runCheckNow)

                    Text("Check Now runs regardless of this setting. iOS decides when a background check actually runs, and may skip it entirely — CloudCrown cannot promise a schedule.")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("When a check cannot reach the network, CloudCrown keeps the stored snapshot and marks it as possibly outdated — never as current.")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func refreshDetailRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SkyFont.micro(11).weight(.semibold))
                .foregroundColor(SkyPalette.textSecondary)
            Text(detail)
                .font(SkyFont.micro(10))
                .foregroundColor(SkyPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Data Sources", subtitle: "Where every number comes from")
            ForEach(presenter.sources) { source in
                CloudCard(tint: SkyPalette.violet) {
                    VStack(alignment: .leading, spacing: SkySpacing.s) {
                        Text(source.name)
                            .font(SkyFont.headline(15))
                            .foregroundColor(SkyPalette.textPrimary)
                        Text(source.attribution)
                            .font(SkyFont.caption(12))
                            .foregroundColor(SkyPalette.textSecondary)
                        if source.fetchedAt > Date.distantPast {
                            SourceStamp(source: "Last fetched", updatedAt: source.fetchedAt,
                                        confidence: .high, compact: true)
                        } else {
                            Text("Not used yet in this install")
                                .font(SkyFont.micro(10))
                                .foregroundColor(SkyPalette.textTertiary)
                        }
                        if !source.url.isEmpty {
                            Text(source.url)
                                .font(SkyFont.micro(10))
                                .foregroundColor(SkyPalette.azure)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Text("CloudCrown adds its own rules engine (version \(WindowEngine.rulesVersion)) on top of these measurements. The engine's assumptions — worst-case aggregation inside a window, confidence by lead time — are stated wherever they affect a result.")
                .font(SkyFont.micro(10))
                .foregroundColor(SkyPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: SkySpacing.m) {
            SectionHeader(title: "Your Data", subtitle: "Stored locally on this device")

            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    countRow("Places", presenter.counts.places)
                    countRow("Activity templates", presenter.counts.activities)
                    countRow("Plans", presenter.counts.plans)
                    countRow("Alert rules", presenter.counts.alerts)
                    countRow("Feedback entries", presenter.counts.feedback)
                    countRow("History entries", presenter.counts.historyRecords)
                    countRow("Stored condition snapshots", presenter.counts.snapshots)
                }
            }

            SkyButton(title: "Export", icon: "square.and.arrow.up", kind: .secondary,
                      isLoading: presenter.isExporting, action: presenter.exportData)

            if let error = presenter.exportError {
                WarningBanner(level: .danger, title: "Export failed", message: error)
            }

            CloudCard(tint: SkyPalette.danger) {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text("Delete all data")
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                    Text("Removes everything from this device and cancels every scheduled notification. There is no account, so nothing is left on a server.")
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SkyButton(title: "Delete Account Data", icon: "trash",
                              kind: .destructive, action: presenter.requestErase)
                }
            }
        }
    }

    private func countRow(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title).font(SkyFont.caption(13)).foregroundColor(SkyPalette.textSecondary)
            Spacer()
            Text("\(count)").font(SkyFont.metric(15)).foregroundColor(SkyPalette.textPrimary)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                Text("CloudCrown")
                    .font(SkyFont.headline(15))
                    .foregroundColor(SkyPalette.textPrimary)
                Text("A planner for real conditions. CloudCrown does not provide medical guidance, and no threshold in this app is a health limit. Sensitivity settings only adjust your own numbers.")
                    .font(SkyFont.caption(12))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: SkySpacing.m) {
                    Text("Rules engine v\(WindowEngine.rulesVersion)")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                    Text("No account required")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                }
            }
        }
    }
}

// MARK: - Erase sheet

struct EraseDataSheet: View {

    @ObservedObject var presenter: SettingsPresenter
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        CloudCard(tint: SkyPalette.danger) {
                            VStack(alignment: .leading, spacing: SkySpacing.s) {
                                HStack(spacing: SkySpacing.s) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(SkyPalette.danger)
                                    Text("This cannot be undone")
                                        .font(SkyFont.headline(16))
                                        .foregroundColor(SkyPalette.textPrimary)
                                }
                                LightningLine()
                                    .stroke(SkyPalette.danger.opacity(0.65),
                                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                    .frame(height: 8)
                            }
                        }

                        VStack(alignment: .leading, spacing: SkySpacing.m) {
                            SectionHeader(title: "What will be deleted")
                            ForEach(presenter.eraseConsequences, id: \.self) { line in
                                HStack(alignment: .top, spacing: SkySpacing.s) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(SkyPalette.danger)
                                        .padding(.top, 2)
                                    Text(line)
                                        .font(SkyFont.caption(13))
                                        .foregroundColor(SkyPalette.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }

                        CloudCard {
                            VStack(alignment: .leading, spacing: SkySpacing.s) {
                                Text("Type \(presenter.eraseConfirmationPhrase) to confirm")
                                    .font(SkyFont.caption(13).weight(.semibold))
                                    .foregroundColor(SkyPalette.textPrimary)
                                TextField(presenter.eraseConfirmationPhrase, text: $presenter.eraseConfirmationText)
                                    .font(SkyFont.body(15))
                                    .autocapitalization(.allCharacters)
                                    .disableAutocorrection(true)
                                    .padding(SkySpacing.m)
                                    .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                        .fill(SkyPalette.surfaceSunken))
                            }
                        }

                        SkyButton(title: "Delete Everything", icon: "trash.fill",
                                  kind: .destructive,
                                  isEnabled: presenter.canErase) {
                            presenter.confirmErase()
                            presentationMode.wrappedValue.dismiss()
                        }

                        Spacer(minLength: SkySpacing.xl)
                    }
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle("Delete Data")
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

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
