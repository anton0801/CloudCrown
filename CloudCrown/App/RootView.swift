import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case today, findWindow, plans, places, history

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .findWindow: return "Find Window"
        case .plans: return "Plans"
        case .places: return "Places"
        case .history: return "History"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.horizon.fill"
        case .findWindow: return "square.stack.3d.up.fill"
        case .plans: return "calendar"
        case .places: return "mappin.and.ellipse"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var selectedTab: AppTab = .today
    @Published var pendingPlanID: UUID?
    @Published var pendingFinderActivityID: UUID?
    @Published var pendingFinderPlaceID: UUID?

    func openFinder(activityID: UUID? = nil, placeID: UUID? = nil) {
        pendingFinderActivityID = activityID
        pendingFinderPlaceID = placeID
        selectedTab = .findWindow
    }

    func openPlan(_ id: UUID) {
        pendingPlanID = id
        selectedTab = .plans
    }
}

enum LaunchRoute: Equatable {
    case splash
    case offer(URL)
    case analytics(URL)
    case onboarding
    case main
}

struct RootView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var repository: DataRepository
    @EnvironmentObject private var bootstrap: AppBootstrap
    @EnvironmentObject private var networkGate: NetworkGate
    @StateObject private var coordinator = AppCoordinator()

    @State private var minimumSplashElapsed = false
    @State private var route: LaunchRoute = .splash
    /// Once the special flow starts, an auth change must not yank the user out.
    @State private var inSpecialFlow = false

    private let minimumSplashDuration: TimeInterval = 1.6

    var body: some View {
        ZStack {
            content
            if networkGate.isBlocked {
                NoNetworkView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: networkGate.isBlocked)
        .animation(.easeInOut(duration: 0.3), value: route)
        .task {
            bootstrap.start()
            try? await Task.sleep(nanoseconds: UInt64(minimumSplashDuration * 1_000_000_000))
            minimumSplashElapsed = true
            tryLeaveSplash()
        }
        .onChange(of: bootstrap.isFinished) { _ in tryLeaveSplash() }
        .onChange(of: repository.settings.hasCompletedOnboarding) { _ in
            guard !inSpecialFlow else { return }
            tryLeaveSplash()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .splash:
            SplashView()
        case .offer(let url):
            NotificationOfferView {
                withAnimation { route = .analytics(url) }
            }
        case .analytics(let url):
            CrownView()
        case .onboarding:
            OnboardingModule.build(environment: environment)
        case .main:
            mainTabs
        }
    }

    private func tryLeaveSplash() {
        guard minimumSplashElapsed, bootstrap.isFinished else { return }
        guard !inSpecialFlow else { return }

        if let analyticsURL = bootstrap.result.analyticsURL {
            UserDefaults.standard.set(analyticsURL.absoluteString, forKey: Dial.routeURL)
            inSpecialFlow = true
            route = NotificationOffer.shouldShow ? .offer(analyticsURL) : .analytics(analyticsURL)
            return
        }
        route = repository.settings.hasCompletedOnboarding ? .main : .onboarding
    }

    private var mainTabs: some View {
        TabView(selection: $coordinator.selectedTab) {
            wrap(TodayModule.build(environment: environment, coordinator: coordinator), .today)
            wrap(WindowFinderModule.build(environment: environment, coordinator: coordinator), .findWindow)
            wrap(PlansModule.build(environment: environment, coordinator: coordinator), .plans)
            wrap(PlaceLibraryModule.build(environment: environment, coordinator: coordinator), .places)
            wrap(HistoryModule.build(environment: environment, coordinator: coordinator), .history)
        }
        .environmentObject(coordinator)
    }

    private func wrap<Content: View>(_ content: Content, _ tab: AppTab) -> some View {
        NavigationView {
            content
        }
        .navigationViewStyle(.stack)
        .tabItem {
            Label(tab.title, systemImage: tab.icon)
        }
        .tag(tab)
    }
}
