//
//  AuthView.swift
//  CloudCrown
//

import SwiftUI

struct AuthView: View {

    @StateObject private var presenter: AuthPresenter
    @StateObject private var router: AuthRouter
    @Environment(\.presentationMode) private var presentationMode

    init(presenter: @autoclosure @escaping () -> AuthPresenter,
         router: @autoclosure @escaping () -> AuthRouter) {
        _presenter = StateObject(wrappedValue: presenter())
        _router = StateObject(wrappedValue: router())
    }

    var body: some View {
        NavigationView {
            ZStack {
                SkyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SkySpacing.l) {
                        header
                        SkySegmented(options: AuthPresenter.Mode.allCases,
                                     titleFor: { $0.title },
                                     selection: Binding(
                                        get: { presenter.mode },
                                        set: { presenter.switchMode($0) }
                                     ))
                        if let message = presenter.formError {
                            SaveErrorBanner(message: message,
                                            onRetry: presenter.submit,
                                            onDismiss: presenter.dismissError)
                        }
                        if let info = presenter.infoMessage {
                            WarningBanner(level: .info, title: "Check your email", message: info)
                        }
                        formCard
                        noRecoveryCard
                        if presenter.mode == .register { requirementsCard }
                        submitButton
                        localOnlyCard
                        Spacer(minLength: SkySpacing.xl)
                    }
                    .padding(SkySpacing.l)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { presentationMode.wrappedValue.dismiss() }
                        .foregroundColor(SkyPalette.textSecondary)
                }
            }
            .onChange(of: router.didFinish) { finished in
                if finished { presentationMode.wrappedValue.dismiss() }
            }
        }
        .navigationViewStyle(.stack)
        .skyToast($presenter.toast)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: SkySpacing.s) {
            ZStack {
                Circle()
                    .fill(SkyPalette.glow(SkyPalette.lightBlue, opacity: 0.45))
                    .frame(width: 96, height: 96)
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(SkyPalette.azureGradient)
            }
            .frame(maxWidth: .infinity)

            Text(presenter.mode == .signIn ? "Sign in to sync" : "Create your account")
                .font(SkyFont.display(26))
                .foregroundColor(SkyPalette.textPrimary)
            Text("An account keeps your limits, places, activities, plans and reviews on every device you use. CloudCrown works fully without one.")
                .font(SkyFont.body(14))
                .foregroundColor(SkyPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Form

    private var formCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.m) {
                field(title: "Email",
                      placeholder: "you@example.com",
                      text: $presenter.email,
                      error: presenter.emailError,
                      isSecure: false,
                      contentType: .username,
                      keyboard: .emailAddress)

                field(title: "Password",
                      placeholder: presenter.mode == .register ? "At least 8 characters" : "Your password",
                      text: $presenter.password,
                      error: presenter.passwordError,
                      isSecure: true,
                      contentType: presenter.mode == .register ? .newPassword : .password,
                      keyboard: .default)

                if presenter.mode == .register {
                    field(title: "Repeat password",
                          placeholder: "Repeat the password",
                          text: $presenter.passwordConfirmation,
                          error: presenter.confirmationError,
                          isSecure: true,
                          contentType: .newPassword,
                          keyboard: .default)

                    Toggle(isOn: $presenter.acceptedTerms) {
                        Text("I accept the terms of use and privacy policy")
                            .font(SkyFont.caption(12))
                            .foregroundColor(SkyPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(SkyPalette.azure)

                    if let message = presenter.termsError {
                        Text(message).font(SkyFont.micro(11)).foregroundColor(SkyPalette.danger)
                    }
                    if let notice = presenter.localDataNotice {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(SkyPalette.azure)
                            Text(notice)
                                .font(SkyFont.micro(11))
                                .foregroundColor(SkyPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// Stated before the account exists, not after the password is lost.
    private var noRecoveryCard: some View {
        CloudCard(tint: SkyPalette.warning) {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                HStack(spacing: SkySpacing.s) {
                    Image(systemName: "key.slash.fill")
                        .font(.system(size: 13))
                        .foregroundColor(SkyPalette.warning)
                    Text("There is no password recovery")
                        .font(SkyFont.headline(14))
                        .foregroundColor(SkyPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(presenter.mode == .register
                     ? "CloudCrown cannot reset your password or email you a link. If you forget it, the account and anything synced to it cannot be recovered. Save the password somewhere safe — your device's password manager is a good place."
                     : "CloudCrown cannot reset your password. If you no longer have it, the account cannot be recovered.")
                    .font(SkyFont.caption(12))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your records stay on this device either way — an account only adds sync.")
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func field(title: String,
                       placeholder: String,
                       text: Binding<String>,
                       error: String?,
                       isSecure: Bool,
                       contentType: UITextContentType,
                       keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(SkyFont.micro(11).weight(.semibold))
                .foregroundColor(SkyPalette.textTertiary)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(SkyFont.body(15))
            .textContentType(contentType)
            .keyboardType(keyboard)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .padding(SkySpacing.m)
            .background(
                RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                    .fill(SkyPalette.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SkyRadius.small, style: .continuous)
                    .strokeBorder(error == nil ? Color.clear : SkyPalette.danger.opacity(0.6), lineWidth: 1)
            )
            if let error = error {
                Text(error)
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var requirementsCard: some View {
        CloudCard {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                Text("Password requirements")
                    .font(SkyFont.headline(14))
                    .foregroundColor(SkyPalette.textPrimary)
                ForEach(Array(presenter.passwordRequirements.enumerated()), id: \.offset) { index, requirement in
                    HStack(spacing: 6) {
                        Image(systemName: presenter.requirementIsMet(index) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundColor(presenter.requirementIsMet(index) ? SkyPalette.success : SkyPalette.hairline)
                        Text(requirement)
                            .font(SkyFont.caption(12))
                            .foregroundColor(presenter.requirementIsMet(index) ? SkyPalette.textPrimary : SkyPalette.textSecondary)
                    }
                }
            }
        }
    }

    private var submitButton: some View {
        SkyButton(title: presenter.mode.actionTitle,
                  icon: presenter.mode == .signIn ? "arrow.right" : "person.badge.plus",
                  kind: .primary,
                  isLoading: presenter.isWorking,
                  isEnabled: presenter.canSubmit,
                  action: presenter.submit)
    }

    private var localOnlyCard: some View {
        CloudCard(tint: SkyPalette.violet) {
            VStack(alignment: .leading, spacing: SkySpacing.s) {
                HStack(spacing: SkySpacing.s) {
                    Image(systemName: "iphone").foregroundColor(SkyPalette.violet)
                    Text("You can keep using CloudCrown without an account")
                        .font(SkyFont.headline(14))
                        .foregroundColor(SkyPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Every feature works offline and on-device. An account only adds sync between devices, and you can delete it at any time from Settings.")
                    .font(SkyFont.caption(12))
                    .foregroundColor(SkyPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("We store only your email address and the records you create. No tracking, no advertising, no third-party analytics.")
                    .font(SkyFont.micro(11))
                    .foregroundColor(SkyPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
