//
//  InsightsInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class InsightsInteractor: InsightsInteractorInput {

    private let repository: DataRepository

    init(repository: DataRepository) { self.repository = repository }

    var activities: [ActivityTemplate] { repository.activities }
    var totalRated: Int { repository.ratedFeedback.count }

    func buildReport(activityID: UUID?) -> InsightsEngine.Report {
        InsightsEngine.build(feedback: repository.feedback,
                             plans: repository.plans,
                             places: repository.places,
                             activityID: activityID)
    }

    func plan(id: UUID) -> Plan? { repository.plan(id: id) }
    func place(id: UUID) -> Place? { repository.place(id: id) }
    func activity(id: UUID) -> ActivityTemplate? { repository.activity(id: id) }
}
