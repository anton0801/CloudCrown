//
//  AuthPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class AuthPresenter: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable {
        case signIn, register
        var id: String { rawValue }
        var title: String { self == .signIn ? "Sign In" : "Create Account" }
        var actionTitle: String { self == .signIn ? "Sign In" : "Create Account" }
    }

    @Published var mode: Mode
    @Published var email = ""
    @Published var password = ""
    @Published var passwordConfirmation = ""
    @Published var acceptedTerms = false

    @Published private(set) var isWorking = false
    @Published private(set) var formError: String?
    @Published private(set) var fieldErrors: [String: String] = [:]
    @Published private(set) var infoMessage: String?
    @Published var toast: ToastPayload?
    /// Errors are only shown once the user has tried to submit.
    @Published private(set) var didAttemptSubmit = false

    private let interactor: AuthInteractorInput
    private let router: AuthRouter

    init(interactor: AuthInteractorInput, router: AuthRouter, mode: Mode) {
        self.interactor = interactor
        self.router = router
        self.mode = mode
    }

    // MARK: - Validation

    var emailError: String? {
        fieldErrors["email"] ?? (didAttemptSubmit ? CredentialValidator.emailError(email) : nil)
    }

    var passwordError: String? {
        if let server = fieldErrors["password"] { return server }
        guard didAttemptSubmit else { return nil }
        return mode == .register
            ? CredentialValidator.passwordError(password)
            : (password.isEmpty ? "Enter your password." : nil)
    }

    var confirmationError: String? {
        guard mode == .register, didAttemptSubmit else { return nil }
        return CredentialValidator.confirmationError(password, passwordConfirmation)
    }

    var termsError: String? {
        guard mode == .register, didAttemptSubmit, !acceptedTerms else { return nil }
        return "Please confirm you accept the terms and privacy policy."
    }

    var passwordRequirements: [String] {
        ["At least \(CredentialValidator.minimumPasswordLength) characters",
         "At least one letter",
         "At least one number"]
    }

    func requirementIsMet(_ index: Int) -> Bool {
        switch index {
        case 0: return password.count >= CredentialValidator.minimumPasswordLength
        case 1: return password.rangeOfCharacter(from: .letters) != nil
        case 2: return password.rangeOfCharacter(from: .decimalDigits) != nil
        default: return false
        }
    }

    var canSubmit: Bool {
        guard !isWorking else { return false }
        guard CredentialValidator.emailError(email) == nil else { return false }
        switch mode {
        case .signIn:
            return !password.isEmpty
        case .register:
            return CredentialValidator.passwordError(password) == nil
                && CredentialValidator.confirmationError(password, passwordConfirmation) == nil
                && acceptedTerms
        }
    }

    var localRecordCount: Int { interactor.localRecordCount }

    var localDataNotice: String? {
        guard mode == .register, localRecordCount > 0 else { return nil }
        return "The \(localRecordCount) record\(localRecordCount == 1 ? "" : "s") already on this device will be uploaded to your new account."
    }

    // MARK: - Actions

    func switchMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        didAttemptSubmit = false
        formError = nil
        fieldErrors = [:]
        infoMessage = nil
    }

    func submit() {
        didAttemptSubmit = true
        formError = nil
        fieldErrors = [:]
        guard canSubmit else { return }

        isWorking = true
        Task { [weak self] in
            guard let self = self else { return }
            do {
                switch self.mode {
                case .signIn:
                    try await self.interactor.signIn(email: self.email, password: self.password)
                case .register:
                    try await self.interactor.register(email: self.email, password: self.password)
                }
                // Only after the session exists does syncing make sense.
                await self.interactor.syncAfterSignIn()
                self.isWorking = false
                self.router.didFinish = true
            } catch let error as APIError {
                self.isWorking = false
                self.present(error)
            } catch {
                self.isWorking = false
                self.formError = error.localizedDescription
            }
        }
    }

    private func present(_ error: APIError) {
        if case .validation(let message, let fields) = error {
            fieldErrors = fields
            formError = fields.isEmpty ? message : nil
            return
        }
        if error == .emailAlreadyRegistered {
            fieldErrors = ["email": "An account already exists for this email."]
            formError = nil
            infoMessage = "Switch to Sign In to use this email."
            return
        }
        if error == .invalidCredentials {
            formError = error.localizedDescription
            return
        }
        formError = error.localizedDescription
    }

    func dismissError() { formError = nil }
}
