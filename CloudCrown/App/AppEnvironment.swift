//
//  AppEnvironment.swift
//  CloudCrown
//
//  The dependency container passed to every VIPER module builder.
//

import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {

    let repository: DataRepository
    let weather: WeatherFetching
    let geocoding: GeocodingServicing
    let location: LocationService
    let notifications: NotificationService
    let calendar: CalendarService
    let refreshCoordinator: RefreshCoordinator
    let backgroundScheduler: BackgroundRefreshScheduler

    init(repository: DataRepository,
         weather: WeatherFetching,
         geocoding: GeocodingServicing,
         location: LocationService,
         notifications: NotificationService,
         calendar: CalendarService) {
        self.repository = repository
        self.weather = weather
        self.geocoding = geocoding
        self.location = location
        self.notifications = notifications
        self.calendar = calendar
        self.refreshCoordinator = RefreshCoordinator(repository: repository,
                                                     weather: weather,
                                                     notifications: notifications)
        self.backgroundScheduler = BackgroundRefreshScheduler()
        // The repository retires a plan's reminder when the plan stops being
        // actionable, so no notification outlives its plan.
        repository.attach(notificationCanceller: notifications)
    }

    static func live() -> AppEnvironment {
        AppEnvironment(
            repository: DataRepository(store: LocalStore()),
            weather: WeatherService(),
            geocoding: GeocodingService(),
            location: LocationService(),
            notifications: NotificationService(),
            calendar: CalendarService()
        )
    }

    /// Registers the background task and runs the first check. Called once at
    /// launch; registration must happen before the app finishes launching.
    func bootstrap() {
        backgroundScheduler.register(coordinator: refreshCoordinator)
    }

    func startRefresh(trigger: RefreshTrigger) {
        Task { @MainActor in
            await refreshCoordinator.run(trigger: trigger)
            backgroundScheduler.schedule(enabled: repository.settings.backgroundRefreshEnabled)
        }
    }
}
