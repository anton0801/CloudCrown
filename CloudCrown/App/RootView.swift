//
//  RootView.swift
//  CloudCrown
//
//  Main navigation: Today · Find Window · Plans · Places · History.
//  Onboarding runs first and ends by creating one real entity — never demo data.
//

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

/// Cross-module navigation requests, so one section can hand off to another
/// without duplicating state.
@MainActor
final class AppCoordinator: ObservableObject {
    @Published var selectedTab: AppTab = .today
    /// Set when another section should open a specific entity on appear.
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

struct RootView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var repository: DataRepository
    @StateObject private var coordinator = AppCoordinator()

    var body: some View {
        Group {
            if repository.settings.hasCompletedOnboarding {
                mainTabs
            } else {
                OnboardingModule.build(environment: environment)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: repository.settings.hasCompletedOnboarding)
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
