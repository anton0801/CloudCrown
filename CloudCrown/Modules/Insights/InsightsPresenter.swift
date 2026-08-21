//
//  InsightsPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class InsightsPresenter: ObservableObject {

    @Published private(set) var report: InsightsEngine.Report?
    @Published var selectedActivityID: UUID?
    @Published var toast: ToastPayload?

    private let interactor: InsightsInteractorInput
    private let router: InsightsRouter

    init(interactor: InsightsInteractorInput, router: InsightsRouter) {
        self.interactor = interactor
        self.router = router
    }

    // MARK: - Derived

    var activities: [ActivityTemplate] { interactor.activities }
    var totalRated: Int { interactor.totalRated }
    var requiredCount: Int { InsightsEngine.minimumRatedEntries }

    var selectedActivityName: String {
        guard let id = selectedActivityID,
              let activity = interactor.activity(id: id) else { return "All activities" }
        return activity.name
    }

    var isUnlocked: Bool { report?.isUnlocked ?? false }
    var remaining: Int { report?.remaining ?? requiredCount }
    var ratedCount: Int { report?.ratedCount ?? 0 }
    var insights: [InsightsEngine.Insight] { report?.insights ?? [] }

    func planTitle(_ id: UUID) -> String { interactor.plan(id: id)?.title ?? "Deleted plan" }

    // MARK: - Lifecycle

    func onAppear() { rebuild() }

    func rebuild() {
        report = interactor.buildReport(activityID: selectedActivityID)
    }

    func selectActivity(_ activity: ActivityTemplate?) {
        selectedActivityID = activity?.id
        router.showsActivityPicker = false
        rebuild()
        toast = ToastPayload(title: activity.map { "Showing \($0.name)" } ?? "Showing all activities")
    }

    // MARK: - Navigation

    func openSourcePlans(_ insight: InsightsEngine.Insight) {
        let unique = Array(Set(insight.supportingPlanIDs))
        router.route = .sourcePlans(unique, insight.title)
    }

    func openActivityPicker() { router.showsActivityPicker = true }
}
