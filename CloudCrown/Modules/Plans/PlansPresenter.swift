//
//  PlansPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class PlansPresenter: ObservableObject {

    enum Scope: String, CaseIterable, Identifiable {
        case upcoming, atRisk, awaitingFeedback, past, archived
        var id: String { rawValue }
        var title: String {
            switch self {
            case .upcoming: return "Upcoming"
            case .atRisk: return "At Risk"
            case .awaitingFeedback: return "To Review"
            case .past: return "Past"
            case .archived: return "Archived"
            }
        }
    }

    @Published var scope: Scope = .upcoming
    @Published var toast: ToastPayload?
    @Published var saveError: String?

    private let interactor: PlansInteractorInput
    private let router: PlansRouter
    private let coordinator: AppCoordinator

    init(interactor: PlansInteractorInput, router: PlansRouter, coordinator: AppCoordinator) {
        self.interactor = interactor
        self.router = router
        self.coordinator = coordinator
    }

    // MARK: - Derived

    var allPlans: [Plan] { interactor.plans }
    var isEmpty: Bool { interactor.plans.isEmpty }

    func plans(for scope: Scope) -> [Plan] {
        let now = Date()
        switch scope {
        case .upcoming:
            return interactor.plans
                .filter { ($0.status == .scheduled || $0.status == .atRisk) && $0.window.end >= now }
                .sorted { $0.window.start < $1.window.start }
        case .atRisk:
            return interactor.plans.filter(\.hasOpenRisk).sorted { $0.window.start < $1.window.start }
        case .awaitingFeedback:
            return interactor.plans
                .filter { $0.awaitsFeedback(hasFeedback: interactor.feedback(forPlan: $0.id) != nil) }
                .sorted { $0.window.start > $1.window.start }
        case .past:
            return interactor.plans
                .filter { $0.window.end < now && $0.status != .archived }
                .sorted { $0.window.start > $1.window.start }
        case .archived:
            return interactor.plans.filter { $0.status == .archived }
                .sorted { $0.window.start > $1.window.start }
        }
    }

    var visiblePlans: [Plan] { plans(for: scope) }

    func count(for scope: Scope) -> Int { plans(for: scope).count }

    func activityName(_ id: UUID) -> String { interactor.activity(id: id)?.name ?? "Removed activity" }
    func placeName(_ id: UUID) -> String { interactor.place(id: id)?.name ?? "Removed place" }
    func hasFeedback(_ plan: Plan) -> Bool { interactor.feedback(forPlan: plan.id) != nil }
    func awaitsFeedback(_ plan: Plan) -> Bool { plan.awaitsFeedback(hasFeedback: hasFeedback(plan)) }

    var emptyMessage: String {
        switch scope {
        case .upcoming: return "Saved windows appear here. CloudCrown then watches the conditions each plan depends on and tells you when they change."
        case .atRisk: return "No plan is at risk. A risk is only raised after two forecast snapshots have actually been compared."
        case .awaitingFeedback: return "Nothing is waiting for a review. After a planned window ends, it appears here so you can record how it really felt."
        case .past: return "No finished plans yet."
        case .archived: return "Nothing archived."
        }
    }

    // MARK: - Lifecycle

    func onAppear() {
        if let pending = coordinator.pendingPlanID {
            coordinator.pendingPlanID = nil
            router.route = .detail(pending)
        }
    }

    // MARK: - Actions

    func open(_ plan: Plan) {
        if plan.hasOpenRisk {
            router.route = .risk(plan.id)
        } else if awaitsFeedback(plan) {
            router.route = .feedback(plan.id)
        } else {
            router.route = .detail(plan.id)
        }
    }

    func openDetail(_ plan: Plan) { router.route = .detail(plan.id) }
    func openRisk(_ plan: Plan) { router.route = .risk(plan.id) }
    func openFeedback(_ plan: Plan) { router.route = .feedback(plan.id) }

    func archive(_ plan: Plan) {
        switch interactor.setStatus(plan.id, .archived) {
        case .failure(let message): saveError = message
        case .success(let changes):
            toast = ToastPayload(title: "“\(plan.title)” archived",
                                 changes: ["Its explanation and history are kept"] + changes.filter { $0.contains("Reminder") })
        }
    }

    func restore(_ plan: Plan) {
        switch interactor.setStatus(plan.id, plan.window.end < Date() ? .completed : .scheduled) {
        case .failure(let message): saveError = message
        case .success: toast = ToastPayload(title: "“\(plan.title)” restored")
        }
    }

    func dismissSaveError() { saveError = nil }

    func requestDelete(_ plan: Plan) {
        router.deletionTarget = interactor.deletionImpact(plan.id)
    }

    func performDelete(_ impact: DeletionImpact, strategy: DeletionStrategy) {
        guard let plan = interactor.plans.first(where: { $0.title == impact.entityTitle }) else {
            router.deletionTarget = nil
            return
        }
        let outcome = interactor.delete(plan.id, strategy: strategy)
        router.deletionTarget = nil
        if case .failure(let message) = outcome {
            saveError = message
            return
        }
        var changes = outcome.changes
        if plan.isCalendarConfirmed { changes.append("The calendar event was left in place") }
        switch strategy {
        case .archive: toast = ToastPayload(title: "“\(plan.title)” archived instead of deleted", changes: changes)
        case .deleteAndDetach: toast = ToastPayload(title: "“\(plan.title)” deleted", changes: changes)
        case .cancel: break
        }
    }
}
