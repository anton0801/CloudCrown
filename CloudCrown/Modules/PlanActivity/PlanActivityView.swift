//
//  PlanActivityView.swift
//  CloudCrown
//

import SwiftUI

struct PlanActivityView: View {

    // Owned via @StateObject so the presenter survives parent re-renders.
    @StateObject private var presenter: PlanActivityPresenter
    @StateObject private var router: PlanActivityRouter

    init(presenter: @autoclosure @escaping () -> PlanActivityPresenter,
         router: @autoclosure @escaping () -> PlanActivityRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SkySpacing.l) {
                    windowCard
                    if let message = presenter.saveError {
                        SaveErrorBanner(message: message,
                                        onRetry: presenter.save,
                                        onDismiss: presenter.dismissSaveError)
                    }
                    if presenter.isUpdatingExisting && presenter.savedPlan == nil { duplicateCard }
                    detailsCard
                    reminderCard
                    backupCard
                    calendarCard
                    Spacer(minLength: 110)
                }
                .padding(SkySpacing.l)
            }

            VStack {
                Spacer()
                saveBar
            }
        }
        .navigationTitle(presenter.isUpdatingExisting ? "Update Plan" : "Plan Activity")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presenter.onAppear() }
        .skyToast($presenter.toast)
        .onChange(of: router.didFinish) { finished in
            if finished { presentationMode.wrappedValue.dismiss() }
        }
        .sheet(isPresented: $router.showsBackupPicker) {
            BackupWindowPicker(options: presenter.backupOptions) { presenter.selectBackup($0) }
        }
        .sheet(isPresented: $router.showsCalendarEditor) {
            if let event = presenter.makeCalendarEvent() {
                CalendarEventEditor(event: event, store: presenter.eventStore) { outcome in
                    presenter.handleCalendarOutcome(outcome)
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Window

    private var windowCard: some View {
        CelestialCard(gradient: LinearGradient(
            colors: [presenter.window.verdict.color, presenter.window.verdict.color.opacity(0.72)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )) {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                Text(presenter.window.dayText())
                    .font(SkyFont.micro(11).weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(presenter.window.timeRangeText())
                    .font(SkyFont.display(26))
                    .foregroundColor(.white)
                HStack(spacing: SkySpacing.s) {
                    Text(presenter.activity?.name ?? "Activity")
                        .font(SkyFont.caption(13).weight(.semibold))
                    Text("·").font(SkyFont.caption(13))
                    Text(presenter.placeName).font(SkyFont.caption(13))
                }
                .foregroundColor(.white.opacity(0.92))
                Text("The explanation is frozen with this plan, so you can always see what you agreed to.")
                    .font(SkyFont.micro(11))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var duplicateCard: some View {
        WarningBanner(
            level: .info,
            title: "A plan already exists for this window",
            message: "Saving will update “\(presenter.duplicatePlan?.title ?? "")” instead of creating a second, duplicate plan."
        )
    }

    // MARK: - Details

    private var detailsCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Plan details")

                VStack(alignment: .leading, spacing: 5) {
                    Text("Title").font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                    TextField("Plan title", text: $presenter.title)
                        .font(SkyFont.body(15))
                        .padding(SkySpacing.m)
                        .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                            .fill(SkyPalette.surfaceSunken))
                    if presenter.title.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("A title is required.").font(SkyFont.micro(11)).foregroundColor(SkyPalette.danger)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Preparation notes").font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
                    TextEditor(text: $presenter.notes)
                        .font(SkyFont.body(14))
                        .frame(height: 88)
                        .padding(SkySpacing.s)
                        .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                            .fill(SkyPalette.surfaceSunken))
                    Text("What to bring, what to check before leaving.")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                }
            }
        }
    }

    // MARK: - Reminder

    private var reminderCard: some View {
        CloudCard(tint: SkyPalette.violet) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Reminder", subtitle: "A local notification before the window starts")

                HStack(spacing: SkySpacing.s) {
                    SkyChip(title: "Off", color: SkyPalette.textSecondary,
                            isSelected: presenter.reminderMinutes == nil) {
                        presenter.reminderMinutes = nil
                    }
                    ForEach(presenter.reminderOptions, id: \.self) { minutes in
                        SkyChip(title: SkyFormat.duration(minutes: minutes),
                                color: SkyPalette.violet,
                                isSelected: presenter.reminderMinutes == minutes) {
                            presenter.reminderMinutes = minutes
                        }
                    }
                }

                if let fireAt = presenter.reminderFireTime {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.fill").font(.system(size: 10)).foregroundColor(SkyPalette.violet)
                        Text("Would fire at \(SkyFormat.fullDateTime(fireAt, timeZone: presenter.window.timeZone))")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                    }
                    if presenter.reminderIsInPast {
                        Text("That time has already passed — no notification will be scheduled.")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.warning)
                    }
                }

                if presenter.notificationAuthorization == .denied {
                    WarningBanner(level: .warning, title: "Notifications are off",
                                  message: presenter.notificationAuthorization.explanation + " The plan will still be saved.")
                }

                if let message = presenter.reminderStatusMessage {
                    WarningBanner(level: .warning, title: "Reminder not scheduled", message: message)
                }
            }
        }
    }

    // MARK: - Backup

    private var backupCard: some View {
        CloudCard(tint: SkyPalette.gold) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Backup Window",
                              subtitle: "Offered first if this plan comes under risk")

                if let backup = presenter.backupWindow {
                    HStack(spacing: SkySpacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(backup.dayText()) · \(backup.timeRangeText())")
                                .font(SkyFont.caption(14).weight(.semibold))
                                .foregroundColor(SkyPalette.textPrimary)
                            Text(backup.headline)
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        GlowRing(score: backup.score, verdictColor: backup.verdict.color, size: 44)
                    }
                    HStack(spacing: SkySpacing.m) {
                        Button(action: presenter.openBackupPicker) {
                            Text("Change").font(SkyFont.micro(12).weight(.semibold)).foregroundColor(SkyPalette.azure)
                        }
                        Button(action: presenter.clearBackup) {
                            Text("Remove").font(SkyFont.micro(12).weight(.semibold)).foregroundColor(SkyPalette.danger)
                        }
                    }
                } else if presenter.backupOptions.isEmpty {
                    Text("No other usable window was found nearby, so there is nothing to offer as a backup.")
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    SkyButton(title: "Add Backup Window", icon: "arrow.triangle.2.circlepath",
                              kind: .secondary, action: presenter.openBackupPicker)
                }
            }
        }
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Calendar", subtitle: "Opened through the system editor")

                if presenter.calendarIsConfirmed, let confirmedAt = presenter.savedPlan?.calendarConfirmedAt {
                    HStack(spacing: SkySpacing.s) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(SkyPalette.success)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Event confirmed by iOS")
                                .font(SkyFont.caption(13).weight(.semibold))
                                .foregroundColor(SkyPalette.textPrimary)
                            Text("Saved \(RelativeTime.string(for: confirmedAt))")
                                .font(SkyFont.micro(10))
                                .foregroundColor(SkyPalette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    SkyButton(title: "Add to Calendar", icon: "calendar.badge.plus",
                              kind: .secondary,
                              isEnabled: presenter.savedPlan != nil,
                              action: presenter.addToCalendar)
                    Text("CloudCrown records a calendar link only after iOS confirms the event was saved. Until then the plan shows no calendar status.")
                        .font(SkyFont.micro(10))
                        .foregroundColor(SkyPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message = presenter.calendarStatusMessage {
                    WarningBanner(level: .info, title: "Calendar", message: message)
                }
            }
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: SkySpacing.s) {
            if presenter.savedPlan != nil {
                HStack(spacing: SkySpacing.s) {
                    SkyButton(title: "Done", kind: .ghost, fullWidth: true) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    SkyButton(title: "Save Changes", icon: "checkmark", kind: .primary,
                              isLoading: presenter.isSaving,
                              isEnabled: presenter.canSave,
                              action: presenter.save)
                }
            } else {
                HStack(spacing: SkySpacing.s) {
                    SkyButton(title: "Cancel", kind: .ghost, fullWidth: false, action: presenter.cancel)
                    SkyButton(title: presenter.isUpdatingExisting ? "Update Existing" : "Save Plan",
                              icon: "calendar.badge.plus",
                              kind: .primary,
                              isLoading: presenter.isSaving,
                              isEnabled: presenter.canSave,
                              action: presenter.save)
                }
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

// MARK: - Backup picker

struct BackupWindowPicker: View {
    let options: [WindowCandidate]
    let onPick: (WindowCandidate) -> Void

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SkySpacing.m) {
                        Text("Only windows that meet every required condition are offered as a backup.")
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
            .navigationTitle("Backup Window")
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
