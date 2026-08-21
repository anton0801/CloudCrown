//
//  FeedbackPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class FeedbackPresenter: ObservableObject {

    @Published var comfortRating: Int?
    @Published var wouldRepeat: Bool?
    @Published var selectedTags: Set<FeedbackTag> = []
    @Published var note: String = ""
    @Published var actualValues: [MetricKind: Double] = [:]
    @Published private(set) var isSaving = false
    @Published var saveError: String?
    @Published private(set) var isExisting = false
    @Published var toast: ToastPayload?

    private let interactor: FeedbackInteractorInput
    private let router: FeedbackRouter
    let planID: UUID
    private var existingEntry: FeedbackEntry?
    private var didAppear = false

    init(interactor: FeedbackInteractorInput, router: FeedbackRouter, planID: UUID) {
        self.interactor = interactor
        self.router = router
        self.planID = planID
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var plan: Plan? { interactor.plan(id: planID) }
    var activity: ActivityTemplate? { plan.flatMap { interactor.activity(id: $0.activityID) } }
    var place: Place? { plan.flatMap { interactor.place(id: $0.placeID) } }

    var forecastSamples: [MetricSample] {
        plan.map { interactor.forecastSamples(plan: $0) } ?? []
    }

    /// Only metrics the plan actually relied on can be corrected here.
    var editableMetrics: [MetricKind] {
        forecastSamples.map(\.kind)
    }

    var canSave: Bool { !isSaving && plan != nil }

    /// The rating is optional for closing, but required for Insights.
    var insightsNote: String {
        comfortRating == nil
            ? "You can save without a rating. Personal Insights only counts rated activities, so this one would not be included."
            : "This will count towards Personal Insights."
    }

    func forecastValue(_ metric: MetricKind) -> Double? {
        forecastSamples.first(where: { $0.kind == metric })?.value.value
    }

    func difference(_ metric: MetricKind) -> Double? {
        guard let actual = actualValues[metric], let forecast = forecastValue(metric) else { return nil }
        return actual - forecast
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !didAppear else { return }
        didAppear = true

        if let existing = interactor.existingFeedback(planID: planID) {
            apply(existing)
            existingEntry = existing
            isExisting = true
        } else if let draft = interactor.loadDraft(planID: planID) {
            apply(draft)
            toast = ToastPayload(title: "Draft restored",
                                 changes: ["Your unsaved review was kept on this device"])
        }
    }

    private func apply(_ entry: FeedbackEntry) {
        comfortRating = entry.comfortRating
        wouldRepeat = entry.wouldRepeat
        selectedTags = Set(entry.tags)
        note = entry.note
        for sample in entry.actualConditions {
            if let value = sample.value.value { actualValues[sample.kind] = value }
        }
    }

    // MARK: - Editing

    func toggleTag(_ tag: FeedbackTag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            // "Conditions matched" is mutually exclusive with mismatch tags.
            if tag == .conditionsMatched {
                selectedTags = selectedTags.filter { $0 == .betterThanExpected }
            } else if tag != .betterThanExpected {
                selectedTags.remove(.conditionsMatched)
            }
            selectedTags.insert(tag)
        }
    }

    func setActual(_ metric: MetricKind, _ value: Double?) {
        if let value = value { actualValues[metric] = value } else { actualValues[metric] = nil }
    }

    // MARK: - Save

    func save() {
        guard let plan = plan, canSave else { return }
        isSaving = true
        saveError = nil

        let samples: [MetricSample] = actualValues.compactMap { metric, value in
            MetricSample(
                kind: metric,
                value: MetricValue(value: value,
                                   unit: metric.canonicalUnit,
                                   observation: .observed,
                                   updatedAt: Date(),
                                   confidence: .high,
                                   sourceID: "user-report")
            )
        }

        var entry = existingEntry ?? FeedbackEntry(
            planID: plan.id,
            activityID: plan.activityID,
            placeID: plan.placeID,
            forecastSnapshotID: plan.window.snapshotID,
            forecastCapturedAt: plan.window.snapshotCapturedAt,
            forecastScore: plan.window.score,
            windowStart: plan.window.start,
            windowEnd: plan.window.end
        )
        entry.actualConditions = samples
        entry.comfortRating = comfortRating
        entry.wouldRepeat = wouldRepeat
        entry.tags = Array(selectedTags)
        entry.note = note

        let outcome = interactor.save(entry)
        isSaving = false

        switch outcome {
        case .failure(let message):
            // The review screen stays open with the entered values intact.
            saveError = message
        case .success(let changes):
            existingEntry = entry
            isExisting = true
            toast = ToastPayload(title: "Feedback saved", changes: Array(changes.prefix(3)))
            router.didFinish = true
        }
    }

    func dismissSaveError() { saveError = nil }

    func cancel() {
        guard let plan = plan else {
            router.didFinish = true
            return
        }
        let hasContent = comfortRating != nil || wouldRepeat != nil || !selectedTags.isEmpty
            || !note.isEmpty || !actualValues.isEmpty
        if hasContent && existingEntry == nil {
            var draft = FeedbackEntry(
                planID: plan.id,
                activityID: plan.activityID,
                placeID: plan.placeID,
                comfortRating: comfortRating,
                wouldRepeat: wouldRepeat,
                tags: Array(selectedTags),
                note: note,
                forecastSnapshotID: plan.window.snapshotID,
                forecastCapturedAt: plan.window.snapshotCapturedAt,
                forecastScore: plan.window.score,
                windowStart: plan.window.start,
                windowEnd: plan.window.end
            )
            draft.actualConditions = actualValues.map { metric, value in
                MetricSample(kind: metric,
                             value: MetricValue(value: value, unit: metric.canonicalUnit,
                                                observation: .observed, updatedAt: Date(),
                                                confidence: .high, sourceID: "user-report"))
            }
            interactor.saveDraft(draft)
        }
        router.didFinish = true
    }
}
