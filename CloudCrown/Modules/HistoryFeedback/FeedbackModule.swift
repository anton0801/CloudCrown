//
//  FeedbackModule.swift
//  CloudCrown
//
//  Feedback stores the real-world assessment next to the forecast snapshot the
//  plan relied on. The forecast itself is never overwritten.
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol FeedbackInteractorInput: AnyObject {
    var settings: AppSettings { get }
    func plan(id: UUID) -> Plan?
    func activity(id: UUID) -> ActivityTemplate?
    func place(id: UUID) -> Place?
    func existingFeedback(planID: UUID) -> FeedbackEntry?
    func save(_ entry: FeedbackEntry) -> SaveOutcome
    func forecastSamples(plan: Plan) -> [MetricSample]
    func saveDraft(_ entry: FeedbackEntry)
    func loadDraft(planID: UUID) -> FeedbackEntry?
    func clearDraft()
}

// MARK: - Router

@MainActor
final class FeedbackRouter: ObservableObject {
    @Published var didFinish = false
}

// MARK: - Builder

enum FeedbackModule {
    @MainActor
    static func build(environment: AppEnvironment, planID: UUID) -> some View {
        let interactor = FeedbackInteractor(repository: environment.repository)
        let router = FeedbackRouter()
        let presenter = FeedbackPresenter(interactor: interactor, router: router, planID: planID)
        return FeedbackView(presenter: presenter, router: router)
    }
}
