//
//  WindowExplanationPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class WindowExplanationPresenter: ObservableObject {

    @Published private(set) var window: WindowCandidate
    /// Present when the newest snapshot differs from the one this window used.
    @Published private(set) var currentVersion: WindowCandidate?
    @Published private(set) var alternatives: [WindowCandidate] = []
    @Published var showsAlternatives = false
    @Published var toast: ToastPayload?

    private let interactor: WindowExplanationInteractorInput
    private let router: WindowExplanationRouter
    private var didLoad = false

    init(interactor: WindowExplanationInteractorInput,
         router: WindowExplanationRouter,
         window: WindowCandidate) {
        self.interactor = interactor
        self.router = router
        self.window = window
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var activity: ActivityTemplate? { interactor.activity(id: window.activityID) }
    var place: Place? { interactor.place(id: window.placeID) }
    var snapshot: ConditionSnapshot? { interactor.currentSnapshot(for: window.placeID) }

    var isSuperseded: Bool { currentVersion != nil }

    var passed: [RuleEvaluation] { window.passedRequired }
    var failed: [RuleEvaluation] { window.failedRequired }
    var unknown: [RuleEvaluation] { window.unknownRequired }

    var preferredSorted: [PreferredEvaluation] {
        window.preferredResults.sorted { $0.pointsEarned > $1.pointsEarned }
    }

    var totalPointsEarned: Double {
        window.preferredResults.reduce(0) { $0 + $1.pointsEarned }
    }

    var totalWeight: Int {
        window.preferredResults.reduce(0) { $0 + $1.rule.weight }
    }

    var scoreDelta: Double? {
        guard let current = currentVersion?.score, let original = window.score else { return nil }
        return current - original
    }

    var existingPlan: Plan? {
        interactor.existingPlan(activityID: window.activityID,
                                placeID: window.placeID,
                                start: window.start)
    }

    /// The trade-off: what this window gives up compared with the best nearby.
    var tradeOff: (better: WindowCandidate, gains: [String])? {
        guard let best = alternatives.first(where: { ($0.score ?? -1) > (window.score ?? -1) }) else { return nil }
        var gains: [String] = []
        for candidate in best.preferredResults {
            guard let mine = window.preferredResults.first(where: { $0.rule.metric == candidate.rule.metric }) else { continue }
            let delta = candidate.pointsEarned - mine.pointsEarned
            guard delta > 1 else { continue }
            gains.append("\(candidate.rule.metric.title): +\(String(format: "%.1f", delta)) points (\(candidate.readableMeasurement) vs \(mine.readableMeasurement))")
        }
        if gains.isEmpty {
            gains.append("A higher overall score with the same required conditions met.")
        }
        return (best, gains)
    }

    func source(for evaluation: RuleEvaluation) -> DataSource? {
        guard let id = evaluation.sourceID else { return nil }
        return snapshot?.source(id: id)
    }

    func source(for evaluation: PreferredEvaluation) -> DataSource? {
        guard let id = evaluation.sourceID else { return nil }
        return snapshot?.source(id: id)
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !didLoad else { return }
        didLoad = true
        currentVersion = interactor.reevaluate(window)
        alternatives = interactor.alternatives(for: window, count: 4)
    }

    func adoptCurrentVersion() {
        guard let current = currentVersion else { return }
        window = current
        currentVersion = nil
        toast = ToastPayload(title: "Updated to the newest forecast",
                             changes: ["Re-scored from snapshot captured \(RelativeTime.string(for: current.snapshotCapturedAt))",
                                       "Rules version \(current.rulesVersion)"])
    }

    // MARK: - Navigation

    func savePlan() {
        router.route = .planActivity(window)
    }

    func openConditions() {
        router.route = .conditions(window.placeID)
    }

    func openComparison() {
        router.route = .comparison(activityID: window.activityID, placeID: window.placeID)
    }

    func selectAlternative(_ candidate: WindowCandidate) {
        window = candidate
        currentVersion = interactor.reevaluate(candidate)
        alternatives = interactor.alternatives(for: candidate, count: 4)
        showsAlternatives = false
    }
}
