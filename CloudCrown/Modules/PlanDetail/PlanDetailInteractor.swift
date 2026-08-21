//
//  PlanDetailInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class PlanDetailInteractor: PlanDetailInteractorInput {

    private let repository: DataRepository

    init(repository: DataRepository) { self.repository = repository }

    var settings: AppSettings { repository.settings }

    func plan(id: UUID) -> Plan? { repository.plan(id: id) }
    func activity(id: UUID) -> ActivityTemplate? { repository.activity(id: id) }
    func place(id: UUID) -> Place? { repository.place(id: id) }
    func feedback(forPlan id: UUID) -> FeedbackEntry? { repository.feedback(forPlan: id) }
    func history(for id: UUID) -> [HistoryRecord] { repository.history(for: id) }
    func setStatus(_ id: UUID, _ status: PlanStatus) -> SaveOutcome { repository.setPlanStatus(id, status) }
}
