//
//  SettingsInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class SettingsInteractor: SettingsInteractorInput {

    private let repository: DataRepository
    private let location: LocationService
    private let notifications: NotificationService
    private let calendar: CalendarService
    private let refreshCoordinator: RefreshCoordinator
    private let backgroundScheduler: BackgroundRefreshScheduler

    init(repository: DataRepository,
         location: LocationService,
         notifications: NotificationService,
         calendar: CalendarService,
         refreshCoordinator: RefreshCoordinator,
         backgroundScheduler: BackgroundRefreshScheduler) {
        self.repository = repository
        self.location = location
        self.notifications = notifications
        self.calendar = calendar
        self.refreshCoordinator = refreshCoordinator
        self.backgroundScheduler = backgroundScheduler
    }

    var backgroundStatus: BackgroundRefreshScheduler.Status { backgroundScheduler.status }
    var lastRefreshReport: RefreshReport? { refreshCoordinator.lastReport }
    var lastRefreshCheck: Date? { repository.settings.lastRefreshCheck }

    var settings: AppSettings { repository.settings }

    var sources: [DataSource] {
        let all = repository.snapshots.values.flatMap(\.sources)
        var unique: [DataSource] = []
        for source in all.sorted(by: { $0.fetchedAt > $1.fetchedAt }) {
            if !unique.contains(where: { $0.id == source.id }) { unique.append(source) }
        }
        if unique.isEmpty {
            // Declare the providers even before any data has been fetched.
            return [
                .openMeteoForecast(fetchedAt: Date.distantPast),
                .openMeteoAir(fetchedAt: Date.distantPast),
                .openMeteoGeocoding(fetchedAt: Date.distantPast)
            ]
        }
        return unique
    }

    var counts: SettingsCounts {
        SettingsCounts(
            places: repository.places.count,
            activities: repository.activities.count,
            plans: repository.plans.count,
            alerts: repository.alerts.count,
            feedback: repository.feedback.count,
            historyRecords: repository.history.count,
            snapshots: repository.snapshots.count
        )
    }

    var locationAuthorization: LocationAuthorization {
        location.refreshAuthorization()
        return location.authorization
    }

    var notificationAuthorization: NotificationAuthorization { notifications.authorization }
    var calendarSummary: String { calendar.authorizationSummary }

    func refreshAuthorizations() async {
        location.refreshAuthorization()
        await notifications.refreshAuthorization()
    }

    func requestNotificationAuthorization() async -> Bool {
        await notifications.requestAuthorization()
    }

    func update(_ transform: (inout AppSettings) -> Void) -> SaveOutcome {
        let outcome = repository.updateSettings(transform)
        // Keep the background task registration aligned with the preference.
        if outcome.isSuccess {
            backgroundScheduler.schedule(enabled: repository.settings.backgroundRefreshEnabled)
        }
        return outcome
    }

    func runManualCheck() async -> RefreshReport {
        await refreshCoordinator.run(trigger: .manual)
    }

    func exportData() throws -> Data { try repository.exportData() }

    /// Deleting local data also cancels every scheduled notification, so no
    /// alert can outlive the records that justified it.
    func eraseAll() {
        notifications.cancelAll()
        repository.eraseAllData()
    }

    func cancelAllNotifications() { notifications.cancelAll() }
}
