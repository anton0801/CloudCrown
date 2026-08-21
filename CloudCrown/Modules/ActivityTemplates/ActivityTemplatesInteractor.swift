//
//  ActivityTemplatesInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class ActivityTemplatesInteractor: ActivityTemplatesInteractorInput {

    private let repository: DataRepository
    private let draftKey = "activity-template-draft"

    init(repository: DataRepository) {
        self.repository = repository
    }

    var activities: [ActivityTemplate] { repository.activities }
    var settings: AppSettings { repository.settings }

    func save(_ template: ActivityTemplate) -> SaveOutcome {
        let outcome = repository.saveActivity(template)
        if outcome.isSuccess { clearDraft() }
        return outcome
    }

    func setArchived(_ id: UUID, archived: Bool) -> SaveOutcome {
        repository.setActivityArchived(id, archived: archived)
    }

    func deletionImpact(_ id: UUID) -> DeletionImpact {
        repository.deletionImpact(activity: id)
    }

    func delete(_ id: UUID, strategy: DeletionStrategy) -> SaveOutcome {
        repository.deleteActivity(id, strategy: strategy)
    }

    func saveDraft(_ template: ActivityTemplate) { repository.saveDraft(template, key: draftKey) }
    func loadDraft() -> ActivityTemplate? { repository.loadDraft(ActivityTemplate.self, key: draftKey) }
    func clearDraft() { repository.clearDraft(key: draftKey) }
    func hasDraft() -> Bool { repository.hasDraft(key: draftKey) }
}
