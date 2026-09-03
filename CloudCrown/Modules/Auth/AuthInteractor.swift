//
//  AuthInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class AuthInteractor: AuthInteractorInput {

    private let auth: AuthService
    private let sync: SyncService
    private let repository: DataRepository

    init(auth: AuthService, sync: SyncService, repository: DataRepository) {
        self.auth = auth
        self.sync = sync
        self.repository = repository
    }

    func register(email: String, password: String) async throws {
        try await auth.register(email: email, password: password)
    }

    func signIn(email: String, password: String) async throws {
        try await auth.signIn(email: email, password: password)
    }

    func syncAfterSignIn() async {
        await sync.syncAndWait(reason: .signIn)
    }

    /// What already exists on this device, so the user is told what happens to it.
    var localRecordCount: Int {
        repository.places.count + repository.activities.count
            + repository.plans.count + repository.feedback.count
            + (repository.profile == nil ? 0 : 1)
    }
}
