//
//  AuthService.swift
//  CloudCrown
//
//  Registration, sign-in, session refresh and account deletion against the
//  CloudCrown API. The app stays fully usable signed out — an account only
//  adds synchronisation.
//

import Foundation
import Combine

@MainActor
final class AuthService: ObservableObject, AuthTokenProviding {

    @Published private(set) var state: AuthState = .signedOut
    @Published private(set) var isWorking = false

    private let client: APIClient
    private let secureStore: SecureStoring
    private var tokens: TokenPair?
    /// Serialises refreshes so parallel 401s do not all hit the endpoint.
    private var refreshTask: Task<String?, Never>?

    private enum Key {
        static let tokens = "session-tokens"
        static let user = "session-user"
    }

    init(client: APIClient, secureStore: SecureStoring = KeychainStore()) {
        self.client = client
        self.secureStore = secureStore
        client.tokenProvider = self
        restoreSession()
    }

    var currentUser: AuthUser? { state.user }
    var isSignedIn: Bool { state.isSignedIn }

    // MARK: - Session restore

    private func restoreSession() {
        guard let tokenData = secureStore.read(Key.tokens),
              let stored = try? JSONDecoder.iso.decode(TokenPair.self, from: tokenData) else { return }
        tokens = stored
        if let userData = secureStore.read(Key.user),
           let user = try? JSONDecoder.iso.decode(AuthUser.self, from: userData) {
            state = .signedIn(user)
        }
    }

    private func persist(tokens: TokenPair?, user: AuthUser?) {
        if let tokens = tokens, let data = try? JSONEncoder.iso.encode(tokens) {
            secureStore.write(data, for: Key.tokens)
        } else {
            secureStore.delete(Key.tokens)
        }
        if let user = user, let data = try? JSONEncoder.iso.encode(user) {
            secureStore.write(data, for: Key.user)
        } else {
            secureStore.delete(Key.user)
        }
    }

    private func apply(_ session: AuthSessionResponse, fallbackUser: AuthUser? = nil) {
        let pair = session.tokenPair()
        tokens = pair
        let user = session.user ?? fallbackUser ?? state.user
        if let user = user { state = .signedIn(user) }
        persist(tokens: pair, user: user)
    }

    // MARK: - AuthTokenProviding

    func validAccessToken() async -> String? {
        guard let tokens = tokens else { return nil }
        if !tokens.isExpired() { return tokens.accessToken }
        return await refreshAccessToken()
    }

    func refreshAccessToken() async -> String? {
        if let existing = refreshTask { return await existing.value }
        guard let refreshToken = tokens?.refreshToken else { return nil }

        let task = Task { [weak self] () -> String? in
            guard let self = self else { return nil }
            do {
                let session: AuthSessionResponse = try await self.client.send(
                    "auth/refresh",
                    method: .post,
                    body: RefreshRequest(refreshToken: refreshToken),
                    authenticated: false,
                    as: AuthSessionResponse.self
                )
                self.apply(session)
                return session.accessToken
            } catch {
                return nil
            }
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    func sessionDidExpire() async {
        clearLocalSession()
    }

    // MARK: - Registration and sign-in

    func register(email: String, password: String) async throws {
        isWorking = true
        defer { isWorking = false }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let session: AuthSessionResponse = try await client.send(
            "auth/register",
            method: .post,
            body: CredentialsRequest(email: normalized, password: password),
            authenticated: false,
            as: AuthSessionResponse.self
        )
        apply(session)
    }

    func signIn(email: String, password: String) async throws {
        isWorking = true
        defer { isWorking = false }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let session: AuthSessionResponse = try await client.send(
            "auth/login",
            method: .post,
            body: CredentialsRequest(email: normalized, password: password),
            authenticated: false,
            as: AuthSessionResponse.self
        )
        apply(session)
    }

    /// Best-effort server revoke; the local session is always cleared.
    func signOut() async {
        isWorking = true
        defer { isWorking = false }
        if tokens != nil {
            try? await client.sendIgnoringResponse("auth/logout", method: .post)
        }
        clearLocalSession()
    }

    func refreshProfile() async {
        guard tokens != nil else { return }
        do {
            let user: AuthUser = try await client.send("auth/me", as: AuthUser.self)
            state = .signedIn(user)
            persist(tokens: tokens, user: user)
        } catch APIError.unauthorized {
            clearLocalSession()
        } catch {
            // A profile refresh failure never signs the user out on its own.
        }
    }

    /// The server invalidates every previously issued token, so it hands back a
    /// replacement session that must be adopted or this device signs itself out.
    func changePassword(current: String, new: String) async throws {
        isWorking = true
        defer { isWorking = false }
        let session: AuthSessionResponse = try await client.send(
            "auth/password",
            method: .post,
            body: ChangePasswordRequest(currentPassword: current, newPassword: new),
            as: AuthSessionResponse.self
        )
        apply(session)
    }

    // MARK: - Account deletion

    /// Deletes the account itself, not merely its data. The password is
    /// re-checked server-side so a lost device cannot delete the account.
    func deleteAccount(password: String) async throws -> AccountDeletionReceipt {
        isWorking = true
        defer { isWorking = false }
        let receipt: AccountDeletionReceipt = try await client.send(
            "account",
            method: .delete,
            body: DeleteAccountRequest(password: password, confirmation: "DELETE"),
            as: AccountDeletionReceipt.self
        )
        clearLocalSession()
        return receipt
    }

    private func clearLocalSession() {
        tokens = nil
        state = .signedOut
        persist(tokens: nil, user: nil)
    }
}

// MARK: - Request bodies

private struct CredentialsRequest: Encodable {
    let email: String
    let password: String
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private struct ChangePasswordRequest: Encodable {
    let currentPassword: String
    let newPassword: String
}

private struct DeleteAccountRequest: Encodable {
    let password: String
    let confirmation: String
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
}
