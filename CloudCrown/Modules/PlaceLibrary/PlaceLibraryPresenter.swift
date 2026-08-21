//
//  PlaceLibraryPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class PlaceLibraryPresenter: ObservableObject {

    @Published var searchQuery = ""
    @Published private(set) var searchResults: [PlaceSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchError: String?
    @Published private(set) var isResolvingLocation = false
    @Published private(set) var locationError: String?
    @Published private(set) var isSaving = false
    @Published var saveError: String?
    @Published var toast: ToastPayload?
    @Published var editorDraft: Place?

    private let interactor: PlaceLibraryInteractorInput
    private let router: PlaceLibraryRouter
    private var searchTask: Task<Void, Never>?
    private var originalForEditing: Place?

    init(interactor: PlaceLibraryInteractorInput, router: PlaceLibraryRouter) {
        self.interactor = interactor
        self.router = router
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var active: [Place] { interactor.places.filter { !$0.isArchived } }
    var archived: [Place] { interactor.places.filter(\.isArchived) }
    var isEmpty: Bool { interactor.places.isEmpty }
    var locationAuthorization: LocationAuthorization { interactor.locationAuthorization }

    var canSaveDraft: Bool {
        guard let draft = editorDraft else { return false }
        return draft.isValid && !isSaving
    }

    var draftValidationMessages: [String] {
        guard let draft = editorDraft else { return [] }
        var messages: [String] = []
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            messages.append("A name is required so you can recognise this place.")
        }
        if !(-90...90).contains(draft.latitude) {
            messages.append("Latitude must be between −90 and 90.")
        }
        if !(-180...180).contains(draft.longitude) {
            messages.append("Longitude must be between −180 and 180.")
        }
        return messages
    }

    func snapshot(for place: Place) -> ConditionSnapshot? { interactor.snapshot(for: place.id) }
    func planCount(for place: Place) -> Int { interactor.planCount(for: place.id) }

    // MARK: - Search

    func search(_ query: String) {
        searchTask?.cancel()
        searchError = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await self.interactor.search(trimmed)
                guard !Task.isCancelled else { return }
                self.searchResults = results
                self.searchError = results.isEmpty ? "No place matched “\(trimmed)”." : nil
            } catch {
                guard !Task.isCancelled else { return }
                if case WeatherServiceError.cancelled = error { return }
                self.searchError = error.localizedDescription
                self.searchResults = []
            }
            self.isSearching = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchQuery = ""
        searchResults = []
        searchError = nil
        isSearching = false
    }

    // MARK: - Creating

    func startAdding() {
        editorDraft = Place(name: "", latitude: 0, longitude: 0, source: .manual)
        originalForEditing = nil
        router.isAdding = true
    }

    func startEditing(_ place: Place) {
        editorDraft = place
        originalForEditing = place
        router.editing = place
    }

    func useCurrentLocation() {
        guard !isResolvingLocation else { return }
        isResolvingLocation = true
        locationError = nil
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let place = try await self.interactor.resolveCurrentPlace()
                self.editorDraft = place
                self.originalForEditing = nil
                self.router.isAdding = true
            } catch {
                self.locationError = error.localizedDescription
            }
            self.isResolvingLocation = false
        }
    }

    func selectSearchResult(_ result: PlaceSearchResult) {
        editorDraft = result.makePlace()
        originalForEditing = nil
        clearSearch()
        router.isAdding = true
    }

    func save() {
        guard var draft = editorDraft, draft.isValid, !isSaving else { return }
        isSaving = true
        saveError = nil
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        let outcome = interactor.save(draft)
        isSaving = false

        switch outcome {
        case .failure(let message):
            // The editor stays open so nothing the user typed is lost.
            editorDraft = draft
            saveError = message
        case .success(let changes):
            editorDraft = nil
            originalForEditing = nil
            router.isAdding = false
            router.editing = nil
            toast = ToastPayload(title: "“\(draft.name)” saved", changes: Array(changes.prefix(3)))
        }
    }

    func dismissSaveError() { saveError = nil }

    func cancelEditing() {
        editorDraft = nil
        originalForEditing = nil
        router.isAdding = false
        router.editing = nil
    }

    // MARK: - Actions

    func setDefault(_ place: Place) {
        switch interactor.setDefault(place.id) {
        case .failure(let message): saveError = message
        case .success:
            toast = ToastPayload(title: "“\(place.name)” is now default",
                                 changes: ["Today and new searches start here"])
        }
    }

    func archive(_ place: Place) {
        switch interactor.setArchived(place.id, archived: true) {
        case .failure(let message): saveError = message
        case .success:
            toast = ToastPayload(title: "“\(place.name)” archived",
                                 changes: ["Stored conditions and history are kept"])
        }
    }

    func restore(_ place: Place) {
        switch interactor.setArchived(place.id, archived: false) {
        case .failure(let message): saveError = message
        case .success: toast = ToastPayload(title: "“\(place.name)” restored")
        }
    }

    func requestDelete(_ place: Place) {
        router.deletionTarget = interactor.deletionImpact(place.id)
    }

    func performDelete(_ impact: DeletionImpact, strategy: DeletionStrategy) {
        guard let place = interactor.places.first(where: { $0.name == impact.entityTitle }) else {
            router.deletionTarget = nil
            return
        }
        let outcome = interactor.delete(place.id, strategy: strategy)
        router.deletionTarget = nil
        if case .failure(let message) = outcome {
            saveError = message
            return
        }
        switch strategy {
        case .archive: toast = ToastPayload(title: "“\(place.name)” archived instead of deleted")
        case .deleteAndDetach:
            toast = ToastPayload(title: "“\(place.name)” deleted",
                                 changes: ["Dependent plans archived", "Alert rules for this place removed", "Feedback history kept"])
        case .cancel: break
        }
    }

    func openConditions(_ place: Place) {
        router.route = .conditions(place.id)
    }
}
