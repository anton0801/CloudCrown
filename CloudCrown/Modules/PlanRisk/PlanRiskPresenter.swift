//
//  PlanRiskPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class PlanRiskPresenter: ObservableObject {

    enum ViewState: Equatable {
        case loading
        case ready
        case noRisk
        case missingPlan
        case unavailable(reason: String, isOffline: Bool)
    }

    @Published private(set) var state: ViewState = .loading
    @Published private(set) var assessment: RiskEngine.Assessment?
    @Published private(set) var alternatives: [WindowCandidate] = []
    @Published private(set) var snapshot: ConditionSnapshot?
    @Published private(set) var isCached = false
    @Published private(set) var isResolving = false
    @Published var toast: ToastPayload?
    @Published var saveError: String?

    private let interactor: PlanRiskInteractorInput
    private let router: PlanRiskRouter
    let planID: UUID
    private var didLoad = false

    init(interactor: PlanRiskInteractorInput, router: PlanRiskRouter, planID: UUID) {
        self.interactor = interactor
        self.router = router
        self.planID = planID
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var plan: Plan? { interactor.plan(id: planID) }
    var activity: ActivityTemplate? { plan.flatMap { interactor.activity(id: $0.activityID) } }
    var place: Place? { plan.flatMap { interactor.place(id: $0.placeID) } }
    var openRisk: RiskEvent? { plan?.openRisks.last }
    var backupWindow: WindowCandidate? { plan?.backupWindow }

    var resolvedRisks: [RiskEvent] { plan?.riskEvents.filter(\.isResolved) ?? [] }

    /// Required conditions that broke between the two snapshots.
    var brokenRequired: [RuleEvaluation] {
        assessment?.brokenRequired ?? openRisk?.brokenRequired ?? []
    }

    var newlyUnknown: [RuleEvaluation] { assessment?.newlyUnknown ?? [] }

    var scoreBefore: Double? { assessment?.scoreBefore ?? openRisk?.scoreBefore }
    var scoreAfter: Double? { assessment?.scoreAfter ?? openRisk?.scoreAfter }

    var scoreDelta: Double? {
        guard let after = scoreAfter, let before = scoreBefore else { return nil }
        return after - before
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !didLoad else { return }
        didLoad = true
        load()
    }

    func load() {
        guard let plan = plan else {
            state = .missingPlan
            return
        }
        guard let place = place else {
            state = .missingPlan
            return
        }

        state = .loading
        Task { [weak self] in
            guard let self = self else { return }
            let outcome = await self.interactor.refresh(place: place)
            switch outcome {
            case .fresh(let snapshot):
                self.applySnapshot(snapshot, plan: plan, cached: false)
            case .cached(let snapshot, _):
                self.applySnapshot(snapshot, plan: plan, cached: true)
            case .unavailable(let reason, let isOffline):
                // Without a comparable snapshot no new risk can be raised, but
                // an already-recorded risk is still shown from stored data.
                if self.openRisk != nil {
                    self.state = .ready
                } else {
                    self.state = .unavailable(reason: reason, isOffline: isOffline)
                }
            }
        }
    }

    private func applySnapshot(_ snapshot: ConditionSnapshot, plan: Plan, cached: Bool) {
        self.snapshot = snapshot
        self.isCached = cached
        self.assessment = interactor.assess(plan: plan, snapshot: snapshot)

        // Record a newly detected material change so History stays truthful.
        if let assessment = assessment, assessment.isMaterial, plan.openRisks.isEmpty {
            interactor.recordRisk(RiskEngine.makeEvent(from: assessment, snapshot: snapshot), planID: planID)
        }

        self.alternatives = interactor.alternatives(for: plan, snapshot: snapshot)

        if openRisk != nil || (assessment?.isMaterial ?? false) {
            state = .ready
        } else {
            state = .noRisk
        }
    }

    // MARK: - Decisions

    func requestKeep() {
        router.pendingConfirmation = .init(
            resolution: .kept,
            window: nil,
            title: "Keep this plan?",
            message: "The plan stays exactly as saved, including its original explanation. CloudCrown keeps watching and will raise a new risk only if conditions change again."
        )
    }

    func requestUseBackup() {
        guard let backup = backupWindow else { return }
        router.pendingConfirmation = .init(
            resolution: .movedToBackup,
            window: backup,
            title: "Move to the backup window?",
            message: "The plan moves to \(backup.dayText()), \(backup.timeRangeText()). The backup slot is then cleared, and the new window's explanation replaces the old one."
        )
    }

    func requestChooseAnother() {
        router.showsAlternatives = true
    }

    func selectAlternative(_ candidate: WindowCandidate) {
        router.showsAlternatives = false
        router.pendingConfirmation = .init(
            resolution: .movedToNewWindow,
            window: candidate,
            title: "Move to this window?",
            message: "The plan moves to \(candidate.dayText()), \(candidate.timeRangeText()), scored \(candidate.score.map { String(Int($0.rounded())) } ?? "unavailable") from the newest snapshot."
        )
    }

    func requestCancelPlan() {
        router.pendingConfirmation = .init(
            resolution: .cancelled,
            window: nil,
            title: "Cancel this plan?",
            message: "The plan is marked cancelled and no longer watched. It stays in History with its explanation intact."
        )
    }

    /// Nothing is replaced until the user explicitly confirms it here.
    func confirm(_ pending: PlanRiskRouter.PendingResolution) {
        guard let risk = openRisk, !isResolving else { return }
        isResolving = true
        saveError = nil
        let outcome = interactor.resolve(planID: planID,
                                         eventID: risk.id,
                                         resolution: pending.resolution,
                                         newWindow: pending.window)
        isResolving = false
        router.pendingConfirmation = nil

        if case .failure(let message) = outcome {
            saveError = message
            return
        }

        var changes: [String] = []
        if let window = pending.window {
            changes.append("New window \(window.dayText()) \(window.timeRangeText())")
            changes.append("Explanation replaced with the newest evaluation")
        } else {
            changes.append("Window unchanged")
        }

        Task { [weak self] in
            guard let self = self else { return }
            // The window moved, so the old reminder is replaced by one for the
            // new start time — or removed when the plan was cancelled.
            await self.interactor.syncReminder(planID: self.planID)
            if pending.window != nil, self.plan?.reminderMinutesBefore != nil {
                changes.append(self.plan?.reminderNotificationID != nil
                               ? "Reminder moved to the new window"
                               : "Reminder could not be rescheduled")
            }
            self.toast = ToastPayload(title: pending.resolution.title, changes: changes)
            self.load()
        }
    }

    func dismissSaveError() { saveError = nil }

    func openExplanation(_ window: WindowCandidate) {
        router.route = .explanation(window)
    }

    func openUpdatedExplanation() {
        guard let updated = assessment?.updatedWindow else { return }
        router.route = .explanation(updated)
    }
}
