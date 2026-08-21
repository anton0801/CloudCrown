//
//  RiskEngine.swift
//  CloudCrown
//
//  Compares the snapshot a plan was saved from with the newest snapshot.
//  A risk is only raised after two snapshot versions have actually differed.
//

import Foundation

struct RiskEngine {

    /// A score drop of at least this many points counts as material.
    static let materialScoreDrop: Double = 15

    struct Assessment {
        let plan: Plan
        let updatedWindow: WindowCandidate
        let brokenRequired: [RuleEvaluation]
        let newlyUnknown: [RuleEvaluation]
        let scoreBefore: Double?
        let scoreAfter: Double?
        let isMaterial: Bool
        let reason: String

        var scoreDelta: Double? {
            guard let a = scoreAfter, let b = scoreBefore else { return nil }
            return a - b
        }
    }

    /// Returns nil when the newest snapshot is the same one the plan already
    /// used — no comparison, therefore no alert.
    static func assess(plan: Plan,
                       activity: ActivityTemplate,
                       profile: ComfortProfile?,
                       place: Place,
                       snapshot: ConditionSnapshot) -> Assessment? {

        guard snapshot.id != plan.window.snapshotID else { return nil }
        guard snapshot.capturedAt > plan.window.snapshotCapturedAt else { return nil }
        guard let updated = WindowEngine.reevaluate(window: plan.window,
                                                    activity: activity,
                                                    profile: profile,
                                                    place: place,
                                                    snapshot: snapshot) else { return nil }

        let previouslyPassing = Set(plan.window.passedRequired.map { $0.rule.metric })
        let broken = updated.failedRequired.filter { previouslyPassing.contains($0.rule.metric) }
        let newlyUnknown = updated.unknownRequired.filter { previouslyPassing.contains($0.rule.metric) }

        let before = plan.window.score
        let after = updated.score
        let drop: Double? = {
            guard let a = after, let b = before else { return nil }
            return b - a
        }()

        let scoreIsMaterial = (drop ?? 0) >= materialScoreDrop
        let isMaterial = !broken.isEmpty || !newlyUnknown.isEmpty || scoreIsMaterial

        let reason: String
        if !broken.isEmpty {
            let details = broken.map { "\($0.rule.metric.title) now \($0.readableMeasurement)" }
            reason = "Required conditions no longer hold: \(details.joined(separator: "; "))."
        } else if !newlyUnknown.isEmpty {
            let names = newlyUnknown.map { $0.rule.metric.title }.joined(separator: ", ")
            reason = "\(names) is no longer available, so this window can no longer be verified."
        } else if scoreIsMaterial, let drop = drop {
            reason = "The score dropped \(Int(drop.rounded())) points against the same required conditions."
        } else {
            reason = "The forecast moved, but your required conditions still hold."
        }

        return Assessment(plan: plan,
                          updatedWindow: updated,
                          brokenRequired: broken,
                          newlyUnknown: newlyUnknown,
                          scoreBefore: before,
                          scoreAfter: after,
                          isMaterial: isMaterial,
                          reason: reason)
    }

    static func makeEvent(from assessment: Assessment, snapshot: ConditionSnapshot) -> RiskEvent {
        RiskEvent(
            id: UUID(),
            detectedAt: Date(),
            previousSnapshotID: assessment.plan.window.snapshotID,
            previousCapturedAt: assessment.plan.window.snapshotCapturedAt,
            newSnapshotID: snapshot.id,
            newCapturedAt: snapshot.capturedAt,
            brokenRequired: assessment.brokenRequired + assessment.newlyUnknown,
            scoreBefore: assessment.scoreBefore,
            scoreAfter: assessment.scoreAfter,
            resolution: nil,
            resolvedAt: nil
        )
    }
}
