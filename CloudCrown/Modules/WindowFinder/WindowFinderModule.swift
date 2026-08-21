//
//  WindowFinderModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol WindowFinderInteractorInput: AnyObject {
    var activities: [ActivityTemplate] { get }
    var places: [Place] { get }
    var profile: ComfortProfile? { get }
    var settings: AppSettings { get }
    var setupGaps: [SetupGap] { get }
    func find(query: WindowQuery) async -> WindowFinderOutcome
    func saveDraft(_ form: WindowFinderForm)
    func loadDraft() -> WindowFinderForm?
    func clearDraft()
}

/// The interactor returns candidates and reasons already computed by the rules
/// engine. The view never re-derives a score of its own.
enum WindowFinderOutcome {
    case success(WindowSearchResult, usedCache: Bool, snapshot: ConditionSnapshot)
    case missingSnapshot(reason: String, isOffline: Bool)
    case invalidQuery(String)
}

/// The form is persisted as a draft so a cancelled search is never lost.
struct WindowFinderForm: Codable, Equatable {
    var activityID: UUID?
    var placeID: UUID?
    var startDate: Date
    var endDate: Date
    var earliestMinute: Int
    var latestMinute: Int
    var durationMinutes: Int

    static func makeDefault(activity: ActivityTemplate?, place: Place?) -> WindowFinderForm {
        let tz = place?.timeZone ?? .current
        let today = Date().startOfDay(in: tz)
        return WindowFinderForm(
            activityID: activity?.id,
            placeID: place?.id,
            startDate: today,
            endDate: today.adding(days: 2, in: tz),
            earliestMinute: activity?.earliestMinute ?? 6 * 60,
            latestMinute: activity?.latestMinute ?? 21 * 60,
            durationMinutes: activity?.durationMinutes ?? 60
        )
    }

    func makeQuery() -> WindowQuery? {
        guard let activityID = activityID, let placeID = placeID else { return nil }
        return WindowQuery(activityID: activityID,
                           placeID: placeID,
                           startDate: startDate,
                           endDate: endDate,
                           earliestMinute: earliestMinute,
                           latestMinute: latestMinute,
                           durationMinutes: durationMinutes)
    }
}

// MARK: - Router

enum WindowFinderRoute: Identifiable, Equatable {
    case explanation(WindowCandidate)
    case comparison(activityID: UUID, placeID: UUID)
    case activities
    case places
    case profile

    var id: String {
        switch self {
        case .explanation(let w): return "explain-\(w.id)"
        case .comparison(let a, let p): return "compare-\(a)-\(p)"
        case .activities: return "activities"
        case .places: return "places"
        case .profile: return "profile"
        }
    }
}

@MainActor
final class WindowFinderRouter: ObservableObject {
    @Published var route: WindowFinderRoute?
    @Published var showsFilters = false

    private let environment: AppEnvironment
    private let coordinator: AppCoordinator

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.environment = environment
        self.coordinator = coordinator
    }

    @ViewBuilder
    func destination(for route: WindowFinderRoute) -> some View {
        switch route {
        case .explanation(let window):
            WindowExplanationModule.build(environment: environment, coordinator: coordinator, window: window)
        case .comparison(let activityID, let placeID):
            DayComparisonModule.build(environment: environment, coordinator: coordinator,
                                      activityID: activityID, placeID: placeID)
        case .activities:
            ActivityTemplatesModule.build(environment: environment, openEditorImmediately: false)
        case .places:
            PlaceLibraryModule.build(environment: environment, coordinator: coordinator)
        case .profile:
            ComfortProfileModule.build(environment: environment)
        }
    }
}

// MARK: - Builder

enum WindowFinderModule {
    @MainActor
    static func build(environment: AppEnvironment, coordinator: AppCoordinator) -> some View {
        let interactor = WindowFinderInteractor(repository: environment.repository, weather: environment.weather)
        let router = WindowFinderRouter(environment: environment, coordinator: coordinator)
        let presenter = WindowFinderPresenter(interactor: interactor, router: router, coordinator: coordinator)
        return WindowFinderView(presenter: presenter, router: router)
    }
}
