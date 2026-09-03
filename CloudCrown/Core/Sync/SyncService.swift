//
//  SyncService.swift
//  CloudCrown
//
//  Pull-then-push delta sync against the CloudCrown API. Local-first: the app
//  works fully signed out, and syncing only ever adds cross-device continuity.
//

import Foundation
import Combine

enum SyncStatus: Equatable {
    case idle
    case syncing
    case success(at: Date, summary: String)
    case failed(String)
    case signedOut

    var isRunning: Bool { self == .syncing }

    var summary: String {
        switch self {
        case .idle: return "Not synced yet on this device."
        case .syncing: return "Syncing…"
        case .success(let at, let summary): return "\(summary) · \(RelativeTime.string(for: at))"
        case .failed(let message): return message
        case .signedOut: return "Sign in to sync across your devices."
        }
    }
}

@MainActor
final class SyncService: ObservableObject {

    @Published private(set) var status: SyncStatus = .signedOut
    @Published private(set) var lastReport: MergeReport?

    private let client: APIClient
    private let repository: DataRepository
    private let auth: AuthService
    private var runningTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(client: APIClient, repository: DataRepository, auth: AuthService) {
        self.client = client
        self.repository = repository
        self.auth = auth

        status = auth.isSignedIn ? .idle : .signedOut

        // Signing in or out changes what syncing means, so react to it.
        auth.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .signedOut:
                    self.status = .signedOut
                case .signedIn(let user):
                    self.status = .idle
                    self.handleSignIn(user: user)
                }
            }
            .store(in: &cancellables)
    }

    var pendingChangeCount: Int {
        guard auth.isSignedIn else { return 0 }
        let changes = repository.changes(since: repository.syncState.lastSyncedAt)
        return (changes.profile == nil ? 0 : 1) + changes.places.count + changes.activities.count
            + changes.plans.count + changes.alerts.count + changes.feedback.count + changes.tombstones.count
    }

    /// When a different account signs in on this device, local records from the
    /// previous account are cleared rather than merged into the new one.
    private func handleSignIn(user: AuthUser) {
        let previousOwner = repository.syncState.ownerUserID
        if let previousOwner = previousOwner, previousOwner != user.id {
            _ = repository.resetForAccountChange(newOwnerID: user.id)
        } else {
            _ = repository.updateSyncState { $0.ownerUserID = user.id }
        }
        sync(reason: .signIn)
    }

    enum Reason: String {
        case signIn, manual, appActive, afterChange

        var isUserInitiated: Bool { self == .manual }
    }

    func sync(reason: Reason) {
        guard auth.isSignedIn else {
            status = .signedOut
            return
        }
        if let existing = runningTask, !existing.isCancelled, status.isRunning {
            // A sync is already in flight; a second request would duplicate work.
            return
        }
        runningTask = Task { [weak self] in
            await self?.performSync(reason: reason)
        }
    }

    func syncAndWait(reason: Reason) async {
        guard auth.isSignedIn else {
            status = .signedOut
            return
        }
        await performSync(reason: reason)
    }

    private func performSync(reason: Reason) async {
        status = .syncing
        let since = repository.syncState.lastSyncedAt

        do {
            // 1. Pull first, so local edits are merged on top of server state.
            var query: [String: String] = [:]
            if let since = since {
                query["since"] = ISO8601DateFormatter.withFractionalSeconds.string(from: since)
            }
            let pull: SyncPullResponse = try await client.send("sync", method: .get,
                                                               query: query, as: SyncPullResponse.self)
            let merge = repository.applyRemote(pull)
            if case .failure(let message) = merge.outcome {
                status = .failed("Downloaded changes could not be saved: \(message)")
                _ = repository.updateSyncState { $0.lastError = message }
                return
            }
            lastReport = merge.report

            // 2. Push whatever is still newer locally.
            let changes = repository.changes(since: since)
            var pushedCount = 0
            if !changes.isEmpty {
                let request = SyncPushRequest(
                    clientTime: Date(),
                    profile: changes.profile,
                    places: changes.places,
                    activities: changes.activities,
                    plans: changes.plans,
                    alerts: changes.alerts,
                    feedback: changes.feedback,
                    tombstones: changes.tombstones
                )
                pushedCount = request.totalCount
                let push: SyncPushResponse = try await client.send("sync", method: .post,
                                                                   body: request, as: SyncPushResponse.self)
                repository.clearTombstones(upTo: push.serverTime)
                // The watermark comes from the pull, never the push: a push
                // timestamp would jump past anything another device wrote
                // between the two calls.
                _ = repository.updateSyncState {
                    $0.lastSyncedAt = pull.serverTime
                    $0.lastSuccessAt = Date()
                    $0.lastError = nil
                }
            } else {
                _ = repository.updateSyncState {
                    $0.lastSyncedAt = pull.serverTime
                    $0.lastSuccessAt = Date()
                    $0.lastError = nil
                }
            }

            var parts: [String] = []
            if pushedCount > 0 { parts.append("\(pushedCount) sent") }
            if !merge.report.isEmpty { parts.append(merge.report.summary) }
            status = .success(at: Date(), summary: parts.isEmpty ? "Up to date" : parts.joined(separator: ", "))

        } catch let error as APIError {
            if error.requiresReauthentication {
                status = .signedOut
                return
            }
            // A failed sync never discards local data; it stays pending.
            let message = error.localizedDescription
            status = .failed(message)
            _ = repository.updateSyncState { $0.lastError = message }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Clears local records that belonged to the account being removed.
    func purgeLocalDataAfterAccountDeletion() {
        _ = repository.resetForAccountChange(newOwnerID: nil)
        status = .signedOut
        lastReport = nil
    }
}
