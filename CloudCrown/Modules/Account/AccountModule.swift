//
//  AccountModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol AccountInteractorInput: AnyObject {
    var user: AuthUser? { get }
    var syncStatus: SyncStatus { get }
    var pendingChangeCount: Int { get }
    var lastSyncedAt: Date? { get }
    var recordCounts: AccountRecordCounts { get }
    func refreshProfile() async
    func syncNow() async
    func signOut() async
    func changePassword(current: String, new: String) async throws
    func deleteAccount(password: String) async throws -> AccountDeletionReceipt
    func exportData() throws -> Data
}

struct AccountRecordCounts {
    let places: Int
    let activities: Int
    let plans: Int
    let alerts: Int
    let feedback: Int

    var total: Int { places + activities + plans + alerts + feedback }

    var lines: [String] {
        var out: [String] = []
        if places > 0 { out.append("\(places) place\(places == 1 ? "" : "s")") }
        if activities > 0 { out.append("\(activities) activity template\(activities == 1 ? "" : "s")") }
        if plans > 0 { out.append("\(plans) plan\(plans == 1 ? "" : "s")") }
        if alerts > 0 { out.append("\(alerts) alert rule\(alerts == 1 ? "" : "s")") }
        if feedback > 0 { out.append("\(feedback) review\(feedback == 1 ? "" : "s")") }
        return out.isEmpty ? ["No records stored yet"] : out
    }
}

// MARK: - Router

@MainActor
final class AccountRouter: ObservableObject {
    @Published var showsAuth = false
    @Published var showsDeleteFlow = false
    @Published var showsChangePassword = false
    @Published var showsExportSheet = false
    @Published var exportURL: URL?

    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    @ViewBuilder
    func authScreen(mode: AuthPresenter.Mode) -> some View {
        AuthModule.build(environment: environment, mode: mode)
    }
}

// MARK: - Builder

enum AccountModule {
    @MainActor
    static func build(environment: AppEnvironment) -> some View {
        let interactor = AccountInteractor(auth: environment.auth,
                                           sync: environment.sync,
                                           repository: environment.repository)
        let router = AccountRouter(environment: environment)
        let presenter = AccountPresenter(interactor: interactor, router: router)
        return AccountView(presenter: presenter, router: router)
    }
}
