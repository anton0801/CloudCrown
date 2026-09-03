//
//  AccountPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class AccountPresenter: ObservableObject {

    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var toast: ToastPayload?

    // Deletion flow
    @Published var deletePassword = ""
    @Published var deleteConfirmationText = ""
    @Published private(set) var isDeleting = false
    @Published private(set) var deletionError: String?

    // Password change
    @Published var currentPassword = ""
    @Published var newPassword = ""
    @Published var newPasswordConfirmation = ""
    @Published private(set) var passwordError: String?

    private let interactor: AccountInteractorInput
    private let router: AccountRouter

    init(interactor: AccountInteractorInput, router: AccountRouter) {
        self.interactor = interactor
        self.router = router
    }

    // MARK: - Derived

    var user: AuthUser? { interactor.user }
    var isSignedIn: Bool { user != nil }
    var syncStatus: SyncStatus { interactor.syncStatus }
    var pendingChangeCount: Int { interactor.pendingChangeCount }
    var lastSyncedAt: Date? { interactor.lastSyncedAt }
    var recordCounts: AccountRecordCounts { interactor.recordCounts }

    var deleteConfirmationPhrase: String { "DELETE" }

    var canDelete: Bool {
        !isDeleting
            && !deletePassword.isEmpty
            && deleteConfirmationText.trimmingCharacters(in: .whitespaces).uppercased() == deleteConfirmationPhrase
    }

    /// Stated plainly before anything is destroyed.
    var deletionConsequences: [String] {
        var lines = [
            "Your account and email address are permanently removed from the CloudCrown server.",
            "Everything synced to the account is deleted on the server."
        ]
        lines.append(contentsOf: recordCounts.lines.map { "\($0) will be removed from this device" })
        lines.append("Any scheduled reminders for your plans are cancelled.")
        lines.append("This cannot be undone, and the same email can be registered again afterwards.")
        return lines
    }

    var canChangePassword: Bool {
        !isWorking
            && !currentPassword.isEmpty
            && CredentialValidator.passwordError(newPassword) == nil
            && newPassword == newPasswordConfirmation
    }

    var newPasswordError: String? {
        newPassword.isEmpty ? nil : CredentialValidator.passwordError(newPassword)
    }

    var confirmationError: String? {
        newPasswordConfirmation.isEmpty ? nil
            : (newPassword == newPasswordConfirmation ? nil : "The passwords do not match.")
    }

    // MARK: - Actions

    func onAppear() {
        guard isSignedIn else { return }
        Task { await interactor.refreshProfile() }
    }

    func openSignIn() { router.showsAuth = true }

    func syncNow() {
        guard !isWorking else { return }
        isWorking = true
        Task { [weak self] in
            guard let self = self else { return }
            await self.interactor.syncNow()
            self.isWorking = false
            switch self.interactor.syncStatus {
            case .failed(let message): self.errorMessage = message
            case .success(_, let summary): self.toast = ToastPayload(title: "Synced", changes: [summary])
            default: break
            }
        }
    }

    func signOut() {
        isWorking = true
        Task { [weak self] in
            guard let self = self else { return }
            await self.interactor.signOut()
            self.isWorking = false
            self.toast = ToastPayload(title: "Signed out",
                                      changes: ["Your data stays on this device", "Sign in again to resume syncing"])
        }
    }

    func changePassword() {
        guard canChangePassword else { return }
        isWorking = true
        passwordError = nil
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.interactor.changePassword(current: self.currentPassword, new: self.newPassword)
                self.currentPassword = ""
                self.newPassword = ""
                self.newPasswordConfirmation = ""
                self.router.showsChangePassword = false
                self.toast = ToastPayload(title: "Password changed")
            } catch let error as APIError {
                self.passwordError = error.localizedDescription
            } catch {
                self.passwordError = error.localizedDescription
            }
            self.isWorking = false
        }
    }

    func startDeletion() {
        deletePassword = ""
        deleteConfirmationText = ""
        deletionError = nil
        router.showsDeleteFlow = true
    }

    func confirmDeletion() {
        guard canDelete else { return }
        isDeleting = true
        deletionError = nil
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let receipt = try await self.interactor.deleteAccount(password: self.deletePassword)
                self.isDeleting = false
                self.router.showsDeleteFlow = false
                var changes = ["Account removed from the server", "Local records deleted"]
                if let purgeAt = receipt.purgeAt {
                    changes.append("Server backups purged by \(SkyFormat.fullDateTime(purgeAt, timeZone: .current))")
                }
                self.toast = ToastPayload(title: "Account deleted", changes: changes)
            } catch let error as APIError {
                self.isDeleting = false
                // Nothing was deleted, so the sheet stays open with the reason.
                self.deletionError = error == .invalidCredentials
                    ? "That password is not correct. The account was not deleted."
                    : error.localizedDescription
            } catch {
                self.isDeleting = false
                self.deletionError = error.localizedDescription
            }
        }
    }

    func exportData() {
        do {
            let data = try interactor.exportData()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("CloudCrown-export.json")
            try data.write(to: url, options: .atomic)
            router.exportURL = url
            router.showsExportSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() { errorMessage = nil }
}
