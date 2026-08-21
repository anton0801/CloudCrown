//
//  WindowFinderInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class WindowFinderInteractor: WindowFinderInteractorInput {

    private let repository: DataRepository
    private let weather: WeatherFetching
    private let draftKey = "window-finder-form"

    init(repository: DataRepository, weather: WeatherFetching) {
        self.repository = repository
        self.weather = weather
    }

    var activities: [ActivityTemplate] { repository.activeActivities }
    var places: [Place] { repository.activePlaces }
    var profile: ComfortProfile? { repository.profile }
    var settings: AppSettings { repository.settings }
    var setupGaps: [SetupGap] { repository.setupGaps }

    func find(query: WindowQuery) async -> WindowFinderOutcome {
        if let message = query.validationMessage {
            return .invalidQuery(message)
        }
        guard let activity = repository.activity(id: query.activityID),
              let place = repository.place(id: query.placeID) else {
            return .invalidQuery("The selected activity or place no longer exists.")
        }

        var snapshot = repository.snapshot(for: place.id)
        var usedCache = false

        let needsFetch = snapshot == nil
            || snapshot!.isStale
            || (snapshot!.hours.last?.date ?? .distantPast) < query.endDate

        if needsFetch {
            let days = max(1, min(10, Calendar.current.dateComponents([.day], from: Date(), to: query.endDate).day.map { $0 + 2 } ?? 7))
            do {
                let fetched = try await weather.fetchSnapshot(for: place,
                                                              precision: repository.settings.locationPrecision,
                                                              forecastDays: days)
                repository.storeSnapshot(fetched)
                snapshot = fetched
            } catch {
                guard snapshot != nil else {
                    let isOffline = (error as? WeatherServiceError)?.isOffline ?? false
                    return .missingSnapshot(reason: error.localizedDescription, isOffline: isOffline)
                }
                usedCache = true
            }
        }

        guard let resolved = snapshot else {
            return .missingSnapshot(reason: "No conditions are stored for this place.", isOffline: false)
        }

        let result = WindowEngine.findWindows(query: query,
                                              activity: activity,
                                              profile: repository.profile,
                                              place: place,
                                              snapshot: resolved,
                                              usedCachedSnapshot: usedCache)
        return .success(result, usedCache: usedCache, snapshot: resolved)
    }

    func saveDraft(_ form: WindowFinderForm) { repository.saveDraft(form, key: draftKey) }
    func loadDraft() -> WindowFinderForm? { repository.loadDraft(WindowFinderForm.self, key: draftKey) }
    func clearDraft() { repository.clearDraft(key: draftKey) }
}
