//
//  HistoryPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class HistoryPresenter: ObservableObject {

    enum Tab: String, CaseIterable, Identifiable {
        case reviews, activityLog
        var id: String { rawValue }
        var title: String { self == .reviews ? "Reviews" : "Activity Log" }
    }

    @Published var tab: Tab = .reviews
    @Published var entityFilter: EntityType?
    @Published var toast: ToastPayload?

    private let interactor: HistoryInteractorInput
    private let router: HistoryRouter

    init(interactor: HistoryInteractorInput, router: HistoryRouter) {
        self.interactor = interactor
        self.router = router
    }

    // MARK: - Derived

    var records: [HistoryRecord] {
        guard let filter = entityFilter else { return interactor.records }
        return interactor.records.filter { $0.entityType == filter }
    }

    var feedbackEntries: [FeedbackEntry] {
        interactor.feedback.sorted { $0.windowStart > $1.windowStart }
    }

    var pendingReviews: [Plan] {
        interactor.plans
            .filter { plan in
                plan.awaitsFeedback(hasFeedback: interactor.feedback.contains(where: { $0.planID == plan.id }))
            }
            .sorted { $0.window.start > $1.window.start }
    }

    var ratedCount: Int { interactor.ratedCount }
    var insightsRequired: Int { InsightsEngine.minimumRatedEntries }
    var insightsUnlocked: Bool { ratedCount >= insightsRequired }
    var insightsRemaining: Int { max(0, insightsRequired - ratedCount) }

    var isEmpty: Bool { interactor.records.isEmpty && interactor.feedback.isEmpty }

    var availableFilters: [EntityType] {
        Array(Set(interactor.records.map(\.entityType))).sorted { $0.title < $1.title }
    }

    func planTitle(_ id: UUID) -> String { interactor.plan(id: id)?.title ?? "Deleted plan" }
    func activityName(_ id: UUID) -> String { interactor.activity(id: id)?.name ?? "Removed activity" }
    func placeName(_ id: UUID) -> String { interactor.place(id: id)?.name ?? "Removed place" }
    func timeZone(_ placeID: UUID) -> TimeZone { interactor.place(id: placeID)?.timeZone ?? .current }

    // MARK: - Navigation

    func openRecord(_ record: HistoryRecord) {
        guard let id = record.entityID else { return }
        switch record.entityType {
        case .plan: router.route = .plan(id)
        case .feedback:
            if let entry = interactor.feedback.first(where: { $0.id == id }) {
                router.route = .feedback(entry.planID)
            }
        default: break
        }
    }

    func openFeedback(_ entry: FeedbackEntry) { router.route = .feedback(entry.planID) }
    func openReview(_ plan: Plan) { router.route = .feedback(plan.id) }
    func openInsights() { router.route = .insights }
}
