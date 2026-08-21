//
//  PlanDetailPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class PlanDetailPresenter: ObservableObject {

    @Published var toast: ToastPayload?
    @Published var saveError: String?

    private let interactor: PlanDetailInteractorInput
    private let router: PlanDetailRouter
    let planID: UUID

    init(interactor: PlanDetailInteractorInput, router: PlanDetailRouter, planID: UUID) {
        self.interactor = interactor
        self.router = router
        self.planID = planID
    }

    var plan: Plan? { interactor.plan(id: planID) }
    var settings: AppSettings { interactor.settings }
    var activity: ActivityTemplate? { plan.flatMap { interactor.activity(id: $0.activityID) } }
    var place: Place? { plan.flatMap { interactor.place(id: $0.placeID) } }
    var feedback: FeedbackEntry? { interactor.feedback(forPlan: planID) }
    var history: [HistoryRecord] { interactor.history(for: planID) }

    var awaitsFeedback: Bool {
        plan?.awaitsFeedback(hasFeedback: feedback != nil) ?? false
    }

    func openExplanation() {
        guard let plan = plan else { return }
        router.route = .explanation(plan.window)
    }

    func openBackupExplanation() {
        guard let backup = plan?.backupWindow else { return }
        router.route = .explanation(backup)
    }

    func openRisk() { router.route = .risk(planID) }
    func openFeedback() { router.route = .feedback(planID) }
    func openConditions() {
        guard let plan = plan else { return }
        router.route = .conditions(plan.placeID)
    }

    func markCompleted() {
        switch interactor.setStatus(planID, .completed) {
        case .failure(let message): saveError = message
        case .success(let changes):
            toast = ToastPayload(title: "Marked as completed",
                                 changes: ["You can still record how it went"] + changes.filter { $0.contains("Reminder") })
        }
    }

    func cancelPlan() {
        switch interactor.setStatus(planID, .cancelled) {
        case .failure(let message): saveError = message
        case .success(let changes):
            toast = ToastPayload(title: "Plan cancelled",
                                 changes: ["No further risk checks will run for it"]
                                     + changes.filter { $0.contains("Reminder") })
        }
    }

    func dismissSaveError() { saveError = nil }
}
