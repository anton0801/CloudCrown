//
//  CloudCrownApp.swift
//  CloudCrown
//

import SwiftUI

@main
struct CloudCrownApp: App {

    @StateObject private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let live = AppEnvironment.live()
        _environment = StateObject(wrappedValue: live)
        Self.configureAppearance()
        // BGTaskScheduler requires registration before launch completes.
        live.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.repository)
                .tint(SkyPalette.azure)
                // SkyPalette is a fixed light palette with no dark variants, so
                // the scheme is pinned. Without this, Dark Mode leaves every
                // explicit colour unchanged while any default-coloured text —
                // notably every TextField — flips to white on a white card.
                .preferredColorScheme(.light)
                .task {
                    // First automatic check of the session.
                    environment.startRefresh(trigger: .launch)
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                environment.startRefresh(trigger: .foreground)
            case .background:
                environment.backgroundScheduler.schedule(
                    enabled: environment.repository.settings.backgroundRefreshEnabled
                )
            default:
                break
            }
        }
    }

    private static func configureAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.backgroundColor = UIColor(SkyPalette.cloudWhite.opacity(0.72))
        navigation.titleTextAttributes = [
            .foregroundColor: UIColor(SkyPalette.deepBlue),
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navigation.largeTitleTextAttributes = [
            .foregroundColor: UIColor(SkyPalette.deepBlue),
            .font: UIFont.systemFont(ofSize: 32, weight: .bold)
        ]
        navigation.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundColor = UIColor(SkyPalette.cloudWhite.opacity(0.88))
        tab.shadowColor = UIColor(SkyPalette.hairline)
        UITabBar.appearance().standardAppearance = tab
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tab
        }
    }
}
