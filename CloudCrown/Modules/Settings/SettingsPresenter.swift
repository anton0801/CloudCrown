//
//  SettingsPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class SettingsPresenter: ObservableObject {

    @Published private(set) var isExporting = false
    @Published private(set) var exportError: String?
    @Published var toast: ToastPayload?
    @Published var eraseConfirmationText: String = ""
    @Published var saveError: String?
    @Published private(set) var isCheckingNow = false
    @Published private(set) var manualCheckSummary: String?

    private let interactor: SettingsInteractorInput
    private let router: SettingsRouter

    init(interactor: SettingsInteractorInput, router: SettingsRouter) {
        self.interactor = interactor
        self.router = router
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var sources: [DataSource] { interactor.sources }
    var counts: SettingsCounts { interactor.counts }
    var locationAuthorization: LocationAuthorization { interactor.locationAuthorization }
    var notificationAuthorization: NotificationAuthorization { interactor.notificationAuthorization }
    var calendarSummary: String { interactor.calendarSummary }
    var accountEmail: String? { interactor.accountEmail }
    var syncStatus: SyncStatus { interactor.syncStatus }
    var isSignedIn: Bool { interactor.accountEmail != nil }

    /// Deleting requires typing the word, so it cannot happen by mistake.
    var eraseConfirmationPhrase: String { "DELETE" }
    var canErase: Bool { eraseConfirmationText.trimmingCharacters(in: .whitespaces).uppercased() == eraseConfirmationPhrase }

    var eraseConsequences: [String] {
        let c = counts
        var lines: [String] = []
        if c.places > 0 { lines.append("\(c.places) place\(c.places == 1 ? "" : "s")") }
        if c.activities > 0 { lines.append("\(c.activities) activity template\(c.activities == 1 ? "" : "s")") }
        if c.plans > 0 { lines.append("\(c.plans) plan\(c.plans == 1 ? "" : "s")") }
        if c.alerts > 0 { lines.append("\(c.alerts) alert rule\(c.alerts == 1 ? "" : "s") — all scheduled notifications cancelled") }
        if c.feedback > 0 { lines.append("\(c.feedback) feedback entr\(c.feedback == 1 ? "y" : "ies")") }
        if c.historyRecords > 0 { lines.append("\(c.historyRecords) history entr\(c.historyRecords == 1 ? "y" : "ies")") }
        if c.snapshots > 0 { lines.append("\(c.snapshots) stored condition snapshot\(c.snapshots == 1 ? "" : "s")") }
        if lines.isEmpty { lines.append("Nothing is stored yet") }
        return lines
    }

    // MARK: - Lifecycle

    func onAppear() {
        Task { await interactor.refreshAuthorizations() }
    }

    // MARK: - Settings

    func update(_ transform: (inout AppSettings) -> Void) {
        switch interactor.update(transform) {
        case .failure(let message):
            saveError = message
        case .success(let changes):
            saveError = nil
            if !changes.isEmpty {
                toast = ToastPayload(title: "Settings updated", changes: changes)
            }
        }
    }

    func dismissSaveError() { saveError = nil }

    // MARK: - Refresh

    var backgroundStatus: BackgroundRefreshScheduler.Status { interactor.backgroundStatus }
    var lastRefreshCheck: Date? { interactor.lastRefreshCheck }
    var lastRefreshReport: RefreshReport? { interactor.lastRefreshReport }

    /// Runs the same cycle the background task runs, so the user can see
    /// exactly what automatic checking does.
    func runCheckNow() {
        guard !isCheckingNow else { return }
        isCheckingNow = true
        manualCheckSummary = nil
        Task { [weak self] in
            guard let self = self else { return }
            let report = await self.interactor.runManualCheck()
            self.isCheckingNow = false
            self.manualCheckSummary = report.summary
            self.toast = ToastPayload(title: "Check complete", changes: [report.summary])
        }
    }

    func setLocationPrecision(_ precision: LocationPrecision) {
        update { $0.locationPrecision = precision }
    }

    func requestNotifications() {
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await self.interactor.requestNotificationAuthorization()
            self.update { settings in settings.notificationsEnabled = granted }
            self.toast = ToastPayload(
                title: granted ? "Notifications enabled" : "Notifications not enabled",
                changes: granted ? [] : ["Alert rules will still evaluate but nothing will be delivered"]
            )
        }
    }

    // MARK: - Export

    func exportData() {
        guard !isExporting else { return }
        isExporting = true
        exportError = nil
        do {
            let data = try interactor.exportData()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("CloudCrown-export.json")
            try data.write(to: url, options: .atomic)
            router.exportURL = url
            router.showsExportSheet = true
            toast = ToastPayload(title: "Export ready",
                                 changes: ["\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) of JSON",
                                           "Includes every place, activity, plan, alert and review"])
        } catch {
            exportError = error.localizedDescription
        }
        isExporting = false
    }

    // MARK: - Erase

    func requestErase() {
        eraseConfirmationText = ""
        router.showsEraseConfirmation = true
    }

    func confirmErase() {
        guard canErase else { return }
        interactor.eraseAll()
        router.showsEraseConfirmation = false
        eraseConfirmationText = ""
        toast = ToastPayload(title: "All local data deleted",
                             changes: ["Scheduled notifications cancelled", "The app is back to its first-run state"])
    }

    // MARK: - Navigation

    func open(_ route: SettingsRoute) { router.route = route }
}
