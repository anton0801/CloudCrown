//
//  ActivityTemplatesModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol ActivityTemplatesInteractorInput: AnyObject {
    var activities: [ActivityTemplate] { get }
    var settings: AppSettings { get }
    func save(_ template: ActivityTemplate) -> SaveOutcome
    func setArchived(_ id: UUID, archived: Bool) -> SaveOutcome
    func deletionImpact(_ id: UUID) -> DeletionImpact
    func delete(_ id: UUID, strategy: DeletionStrategy) -> SaveOutcome
    func saveDraft(_ template: ActivityTemplate)
    func loadDraft() -> ActivityTemplate?
    func clearDraft()
    func hasDraft() -> Bool
}

// MARK: - Router

@MainActor
final class ActivityTemplatesRouter: ObservableObject {
    @Published var editing: ActivityTemplate?
    @Published var deletionTarget: DeletionImpact?
    @Published var showsDraftPrompt = false
    @Published var showsArchived = false
}

// MARK: - Builder

enum ActivityTemplatesModule {
    @MainActor
    static func build(environment: AppEnvironment, openEditorImmediately: Bool) -> some View {
        let interactor = ActivityTemplatesInteractor(repository: environment.repository)
        let router = ActivityTemplatesRouter()
        let presenter = ActivityTemplatesPresenter(interactor: interactor,
                                                   router: router,
                                                   opensEditorImmediately: openEditorImmediately)
        return ActivityTemplatesView(presenter: presenter, router: router)
    }
}
