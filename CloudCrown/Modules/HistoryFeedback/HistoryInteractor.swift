//
//  HistoryInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class HistoryInteractor: HistoryInteractorInput {

    private let repository: DataRepository

    init(repository: DataRepository) { self.repository = repository }

    var records: [HistoryRecord] { repository.history }
    var feedback: [FeedbackEntry] { repository.feedback }
    var plans: [Plan] { repository.plans }
    var ratedCount: Int { repository.ratedFeedback.count }

    func plan(id: UUID?) -> Plan? { repository.plan(id: id) }
    func activity(id: UUID) -> ActivityTemplate? { repository.activity(id: id) }
    func place(id: UUID) -> Place? { repository.place(id: id) }
}
