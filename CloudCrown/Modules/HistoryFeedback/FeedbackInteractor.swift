//
//  FeedbackInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class FeedbackInteractor: FeedbackInteractorInput {

    private let repository: DataRepository
    private let draftKey = "feedback-draft"

    init(repository: DataRepository) { self.repository = repository }

    var settings: AppSettings { repository.settings }

    func plan(id: UUID) -> Plan? { repository.plan(id: id) }
    func activity(id: UUID) -> ActivityTemplate? { repository.activity(id: id) }
    func place(id: UUID) -> Place? { repository.place(id: id) }
    func existingFeedback(planID: UUID) -> FeedbackEntry? { repository.feedback(forPlan: planID) }

    func save(_ entry: FeedbackEntry) -> SaveOutcome {
        let outcome = repository.saveFeedback(entry)
        if outcome.isSuccess { clearDraft() }
        return outcome
    }

    /// What the forecast said for this window, taken from the plan's own frozen
    /// evaluation so it cannot drift.
    func forecastSamples(plan: Plan) -> [MetricSample] {
        var samples: [MetricSample] = []
        for evaluation in plan.window.requiredResults {
            guard let value = evaluation.measuredValue else { continue }
            samples.append(MetricSample(
                kind: evaluation.rule.metric,
                value: MetricValue(value: value,
                                   unit: evaluation.rule.metric.canonicalUnit,
                                   observation: evaluation.observation ?? .forecast,
                                   updatedAt: plan.window.snapshotCapturedAt,
                                   confidence: evaluation.confidence,
                                   sourceID: evaluation.sourceID ?? "")
            ))
        }
        for evaluation in plan.window.preferredResults {
            guard let value = evaluation.measuredValue,
                  !samples.contains(where: { $0.kind == evaluation.rule.metric }) else { continue }
            samples.append(MetricSample(
                kind: evaluation.rule.metric,
                value: MetricValue(value: value,
                                   unit: evaluation.rule.metric.canonicalUnit,
                                   observation: .forecast,
                                   updatedAt: plan.window.snapshotCapturedAt,
                                   confidence: evaluation.confidence,
                                   sourceID: evaluation.sourceID ?? "")
            ))
        }
        return samples
    }

    func saveDraft(_ entry: FeedbackEntry) { repository.saveDraft(entry, key: draftKey) }

    func loadDraft(planID: UUID) -> FeedbackEntry? {
        guard let draft = repository.loadDraft(FeedbackEntry.self, key: draftKey),
              draft.planID == planID else { return nil }
        return draft
    }

    func clearDraft() { repository.clearDraft(key: draftKey) }
}
