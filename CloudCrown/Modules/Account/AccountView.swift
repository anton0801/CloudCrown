//
//  AccountView.swift
//  CloudCrown
//
//  Account state, synchronisation, and in-app account deletion.
//

import SwiftUI

struct AccountView: View {

    @StateObject private var presenter: AccountPresenter
    @StateObject private var router: AccountRouter

    init(presenter: @autoclosure @escaping () -> AccountPresenter,
         router: @autoclosure @escaping () -> AccountRouter) {
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
                    if presenter.isSignedIn {
                        accountCard
                        syncCard
                        securityCard
                        dataCard
                        dangerCard
                    } else {
                        signedOutState
                    }
                    Spacer(minLength: SkySpacing.xxl)
                }
                .padding(SkySpacing.l)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presenter.onAppear() }
        .skyToast($presenter.toast)
        .sheet(isPresented: $router.showsAuth) { router.authScreen(mode: .signIn) }
        .sheet(isPresented: $router.showsDeleteFlow) { DeleteAccountSheet(presenter: presenter) }
        .sheet(isPresented: $router.showsChangePassword) { ChangePasswordSheet(presenter: presenter) }
        .sheet(isPresented: $router.showsExportSheet) {
            if let url = router.exportURL { ShareSheet(items: [url]) }
        }
    }

    // MARK: - Signed out

    private var signedOutState: some View {
        VStack(spacing: SkySpacing.l) {
            EmptyStateView(
                icon: "person.crop.circle.badge.plus",
                title: "No account",
                message: "CloudCrown works fully without an account — everything is stored on this device. An account adds synchronisation across your devices.",
                primaryTitle: "Sign In or Create Account",
                primaryAction: presenter.openSignIn,
                firstStepHint: "Your existing records will be uploaded when you create an account."
            )
            CloudCard {
                VStack(alignment: .leading, spacing: SkySpacing.s) {
                    Text("Stored on this device")
                        .font(SkyFont.headline(14))
                        .foregroundColor(SkyPalette.textPrimary)
                    ForEach(presenter.recordCounts.lines, id: \.self) { line in
                        HStack(spacing: 6) {
                            Circle().fill(SkyPalette.textTertiary).frame(width: 3, height: 3)
                            Text(line).font(SkyFont.caption(12)).foregroundColor(SkyPalette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        CloudCard(tint: SkyPalette.azure) {
            HStack(spacing: SkySpacing.m) {
                ZStack {
                    Circle().fill(SkyPalette.azure.opacity(0.14)).frame(width: 46, height: 46)
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(SkyPalette.azure)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(presenter.user?.email ?? "")
                        .font(SkyFont.headline(15))
                        .foregroundColor(SkyPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let created = presenter.user?.createdAt {
                        Text("Member since \(SkyFormat.dayShort(created, timeZone: .current))")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Sync

    private var syncCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Synchronisation",
                              subtitle: "Profile, places, activities, plans, alerts and reviews")

                HStack(spacing: SkySpacing.s) {
                    Image(systemName: syncIcon)
                        .font(.system(size: 13))
                        .foregroundColor(syncColor)
                    Text(presenter.syncStatus.summary)
                        .font(SkyFont.caption(12))
                        .foregroundColor(SkyPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                if presenter.pendingChangeCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 11))
                            .foregroundColor(SkyPalette.warning)
                        Text("\(presenter.pendingChangeCount) change\(presenter.pendingChangeCount == 1 ? "" : "s") waiting to upload")
                            .font(SkyFont.micro(11))
                            .foregroundColor(SkyPalette.warning)
                    }
                }

                SkyButton(title: presenter.syncStatus.isRunning ? "Syncing…" : "Sync Now",
                          icon: "arrow.triangle.2.circlepath",
                          kind: .secondary,
                          isLoading: presenter.syncStatus.isRunning,
                          action: presenter.syncNow)

                Text("Condition snapshots and the local activity log are not uploaded: snapshots can be re-fetched, and history is a record of what happened on this device.")
                    .font(SkyFont.micro(10))
                    .foregroundColor(SkyPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var syncIcon: String {
        switch presenter.syncStatus {
        case .success: return "checkmark.icloud.fill"
        case .failed: return "exclamationmark.icloud.fill"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        default: return "icloud"
        }
    }

    private var syncColor: Color {
        switch presenter.syncStatus {
        case .success: return SkyPalette.success
        case .failed: return SkyPalette.danger
        default: return SkyPalette.textTertiary
        }
    }

    // MARK: - Security

    private var securityCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Security")
                SkyButton(title: "Change Password", icon: "key.fill", kind: .ghost) {
                    router.showsChangePassword = true
                }
                SkyButton(title: "Sign Out", icon: "rectangle.portrait.and.arrow.right",
                          kind: .ghost, isLoading: presenter.isWorking, action: presenter.signOut)
                Text("Signing out keeps your data on this device and stops syncing. It does not delete anything — but you will need your password to sign back in, and there is no password reset.")
                    .font(SkyFont.micro(10))
                    .foregroundColor(SkyPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Data

    private var dataCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Your data", subtitle: "What this account holds")
                ForEach(presenter.recordCounts.lines, id: \.self) { line in
                    HStack(spacing: 6) {
                        Circle().fill(SkyPalette.textTertiary).frame(width: 3, height: 3)
                        Text(line).font(SkyFont.caption(12)).foregroundColor(SkyPalette.textSecondary)
                    }
                }
                SkyButton(title: "Export", icon: "square.and.arrow.up",
                          kind: .ghost, action: presenter.exportData)
            }
        }
    }

    // MARK: - Delete

    private var dangerCard: some View {
        CloudCard(tint: SkyPalette.danger) {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                SectionHeader(title: "Delete Account")
                Text("Permanently removes your account and everything stored under it, on the server and on this device.")
                    .font(SkyFont.caption(12))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SkyButton(title: "Delete Account", icon: "trash.fill",
                          kind: .destructive, action: presenter.startDeletion)
            }
        }
    }
}

// MARK: - Deletion sheet

struct DeleteAccountSheet: View {

    @ObservedObject var presenter: AccountPresenter
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
                                    Text("This permanently deletes your account")
                                        .font(SkyFont.headline(16))
                                        .foregroundColor(SkyPalette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                LightningLine()
                                    .stroke(SkyPalette.danger.opacity(0.65),
                                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                    .frame(height: 8)
                            }
                        }

                        VStack(alignment: .leading, spacing: SkySpacing.m) {
                            SectionHeader(title: "What happens")
                            ForEach(presenter.deletionConsequences, id: \.self) { line in
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
                            VStack(alignment: .leading, spacing: SkySpacing.m) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Confirm your password")
                                        .font(SkyFont.micro(11).weight(.semibold))
                                        .foregroundColor(SkyPalette.textTertiary)
                                    SecureField("Your password", text: $presenter.deletePassword)
                                        .font(SkyFont.body(15))
                                        .textContentType(.password)
                                        .padding(SkySpacing.m)
                                        .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                            .fill(SkyPalette.surfaceSunken))
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Type \(presenter.deleteConfirmationPhrase) to confirm")
                                        .font(SkyFont.micro(11).weight(.semibold))
                                        .foregroundColor(SkyPalette.textTertiary)
                                    TextField(presenter.deleteConfirmationPhrase, text: $presenter.deleteConfirmationText)
                                        .font(SkyFont.body(15))
                                        .autocapitalization(.allCharacters)
                                        .disableAutocorrection(true)
                                        .padding(SkySpacing.m)
                                        .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                                            .fill(SkyPalette.surfaceSunken))
                                }
                            }
                        }

                        if let error = presenter.deletionError {
                            SaveErrorBanner(message: error)
                        }

                        SkyButton(title: "Delete My Account", icon: "trash.fill",
                                  kind: .destructive,
                                  isLoading: presenter.isDeleting,
                                  isEnabled: presenter.canDelete,
                                  action: presenter.confirmDeletion)

                        VStack(alignment: .leading, spacing: SkySpacing.s) {
                            Text("If you only want to stop syncing, use Sign Out instead — that keeps your account and your data.")
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            // There is no password reset, so a lost password
                            // would otherwise leave no way to delete the account.
                            Text("No longer know your password? Email \(AppSupport.email) from the address on the account and we will delete it for you.")
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: SkySpacing.xl)
                    }
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle("Delete Account")
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

// MARK: - Change password sheet

struct ChangePasswordSheet: View {

    @ObservedObject var presenter: AccountPresenter
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        CloudCard {
                            VStack(alignment: .leading, spacing: SkySpacing.m) {
                                secureField("Current password", $presenter.currentPassword, nil)
                                secureField("New password", $presenter.newPassword, presenter.newPasswordError)
                                secureField("Repeat new password", $presenter.newPasswordConfirmation, presenter.confirmationError)
                            }
                        }
                        if let error = presenter.passwordError {
                            SaveErrorBanner(message: error)
                        }
                        SkyButton(title: "Change Password", icon: "checkmark",
                                  kind: .primary,
                                  isEnabled: presenter.canChangePassword,
                                  action: presenter.changePassword)
                        Spacer(minLength: SkySpacing.xl)
                    }
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle("Change Password")
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

    private func secureField(_ title: String, _ text: Binding<String>, _ error: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(SkyFont.micro(11).weight(.semibold)).foregroundColor(SkyPalette.textTertiary)
            SecureField(title, text: text)
                .font(SkyFont.body(15))
                .textContentType(.password)
                .padding(SkySpacing.m)
                .background(RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                    .fill(SkyPalette.surfaceSunken))
            if let error = error {
                Text(error).font(SkyFont.micro(11)).foregroundColor(SkyPalette.danger)
            }
        }
    }
}
