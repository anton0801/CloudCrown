//
//  PlansInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class PlansInteractor: PlansInteractorInput {

    private let repository: DataRepository

    init(repository: DataRepository) { self.repository = repository }

    var plans: [Plan] { repository.plans }

    func activity(id: UUID) -> ActivityTemplate? { repository.activity(id: id) }
    func place(id: UUID) -> Place? { repository.place(id: id) }
    func feedback(forPlan id: UUID) -> FeedbackEntry? { repository.feedback(forPlan: id) }
    func setStatus(_ id: UUID, _ status: PlanStatus) -> SaveOutcome { repository.setPlanStatus(id, status) }
    func deletionImpact(_ id: UUID) -> DeletionImpact { repository.deletionImpact(plan: id) }
    func delete(_ id: UUID, strategy: DeletionStrategy) -> SaveOutcome { repository.deletePlan(id, strategy: strategy) }
}
