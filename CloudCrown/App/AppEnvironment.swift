//
//  AppEnvironment.swift
//  CloudCrown
//
//  The dependency container passed to every VIPER module builder.
//

import SwiftUI
import Combine

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
    let apiClient: APIClient
    let auth: AuthService
    let sync: SyncService

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

        // REST layer: the client owns transport, AuthService owns the session,
        // SyncService owns reconciliation. The app works fully signed out.
        let client = APIClient()
        self.apiClient = client
        let authService = AuthService(client: client)
        self.auth = authService
        self.sync = SyncService(client: client, repository: repository, auth: authService)
        // The repository retires a plan's reminder when the plan stops being
        // actionable, so no notification outlives its plan.
        repository.attach(notificationCanceller: notifications)
        observeSessionForDeviceLink()
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

    private let horizon = HorizonClient()
    private var deviceLinkCancellable: AnyCancellable?
    private var linkedAnchor: String?

    /// Ties the attribution device record to the account once one exists.
    private func observeSessionForDeviceLink() {
        deviceLinkCancellable = auth.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self = self, state.isSignedIn else { return }
                Task { @MainActor in await self.linkDevice() }
            }
    }

    private func linkDevice() async {
        let anchor = AttributionProviderFactory.make().anchor
        guard linkedAnchor != anchor else { return }
        guard let token = await auth.validAccessToken() else { return }
        if await horizon.link(anchor: anchor, accessToken: token) {
            linkedAnchor = anchor
        }
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
            if auth.isSignedIn {
                sync.sync(reason: trigger == .manual ? .manual : .appActive)
            }
        }
    }
}
