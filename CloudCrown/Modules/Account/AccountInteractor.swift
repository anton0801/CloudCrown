//
//  AccountInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class AccountInteractor: AccountInteractorInput {

    private let auth: AuthService
    private let sync: SyncService
    private let repository: DataRepository

    init(auth: AuthService, sync: SyncService, repository: DataRepository) {
        self.auth = auth
        self.sync = sync
        self.repository = repository
    }

    var user: AuthUser? { auth.currentUser }
    var syncStatus: SyncStatus { sync.status }
    var pendingChangeCount: Int { sync.pendingChangeCount }
    var lastSyncedAt: Date? { repository.syncState.lastSuccessAt }

    var recordCounts: AccountRecordCounts {
        AccountRecordCounts(places: repository.places.count,
                            activities: repository.activities.count,
                            plans: repository.plans.count,
                            alerts: repository.alerts.count,
                            feedback: repository.feedback.count)
    }

    func refreshProfile() async { await auth.refreshProfile() }
    func syncNow() async { await sync.syncAndWait(reason: .manual) }
    func signOut() async { await auth.signOut() }

    func changePassword(current: String, new: String) async throws {
        try await auth.changePassword(current: current, new: new)
    }

    /// Deletes the account on the server, then removes the data it owned from
    /// this device. Both halves must happen for the promise to be honest.
    func deleteAccount(password: String) async throws -> AccountDeletionReceipt {
        let receipt = try await auth.deleteAccount(password: password)
        sync.purgeLocalDataAfterAccountDeletion()
        return receipt
    }

    func exportData() throws -> Data { try repository.exportData() }
}
