//
//  ActivityTemplatesPresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class ActivityTemplatesPresenter: ObservableObject {

    @Published private(set) var isSaving = false
    @Published var toast: ToastPayload?
    @Published var editorDraft: ActivityTemplate?
    @Published var errorMessage: String?

    private let interactor: ActivityTemplatesInteractorInput
    private let router: ActivityTemplatesRouter
    private let opensEditorImmediately: Bool
    private var didAppear = false
    private var originalForEditing: ActivityTemplate?

    init(interactor: ActivityTemplatesInteractorInput,
         router: ActivityTemplatesRouter,
         opensEditorImmediately: Bool) {
        self.interactor = interactor
        self.router = router
        self.opensEditorImmediately = opensEditorImmediately
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var active: [ActivityTemplate] { interactor.activities.filter { !$0.isArchived } }
    var archived: [ActivityTemplate] { interactor.activities.filter(\.isArchived) }
    var isEmpty: Bool { active.isEmpty && archived.isEmpty }

    var draftHasChanges: Bool {
        guard let draft = editorDraft else { return false }
        guard let original = originalForEditing else { return true }
        return draft != original
    }

    var canSaveDraft: Bool {
        guard let draft = editorDraft else { return false }
        return draft.isValid && !isSaving
    }

    var draftValidationMessages: [String] {
        guard let draft = editorDraft else { return [] }
        var messages: [String] = []
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            messages.append("A name is required.")
        }
        if !draft.weightIsValid {
            let remaining = draft.weightRemaining
            messages.append(remaining > 0
                ? "Weight Remaining: \(remaining)% — preferred conditions must total exactly 100%."
                : "Over by \(-remaining)% — preferred conditions must total exactly 100%.")
        }
        if draft.latestMinute - draft.earliestMinute < draft.durationMinutes {
            messages.append("The daily time range is shorter than the duration.")
        }
        return messages
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !didAppear else { return }
        didAppear = true
        if interactor.hasDraft() {
            router.showsDraftPrompt = true
        } else if opensEditorImmediately {
            startCreating()
        }
    }

    func restoreDraft() {
        if let draft = interactor.loadDraft() {
            originalForEditing = nil
            editorDraft = draft
            router.editing = draft
        }
        router.showsDraftPrompt = false
    }

    func discardDraft() {
        interactor.clearDraft()
        router.showsDraftPrompt = false
        if opensEditorImmediately { startCreating() }
    }

    // MARK: - Editing

    func startCreating(kind: ActivityKind = .walking) {
        let template = ActivityTemplate(
            name: kind.title,
            kind: kind,
            requiredConditions: [],
            preferredConditions: [],
            durationMinutes: kind.defaultDurationMinutes,
            requiresDaylight: kind == .photography
        )
        originalForEditing = nil
        editorDraft = template
        router.editing = template
    }

    func startEditing(_ template: ActivityTemplate) {
        originalForEditing = template
        editorDraft = template
        router.editing = template
    }

    func changeKind(_ kind: ActivityKind) {
        guard var draft = editorDraft else { return }
        let wasDefaultName = draft.name == draft.kind.title
        draft.kind = kind
        if wasDefaultName { draft.name = kind.title }
        if draft.requiredConditions.isEmpty && draft.preferredConditions.isEmpty {
            draft.durationMinutes = kind.defaultDurationMinutes
        }
        editorDraft = draft
    }

    /// Adds the kind's suggested rules — presented as suggestions the user
    /// applies deliberately, never written silently.
    func applySuggestions() {
        guard var draft = editorDraft else { return }
        let required = draft.kind.suggestedRequiredMetrics.filter { metric in
            !draft.requiredConditions.contains(where: { $0.metric == metric })
        }
        for metric in required {
            draft.requiredConditions.append(defaultRule(for: metric))
        }
        let preferredMetrics = draft.kind.suggestedPreferredMetrics.filter { metric in
            !draft.preferredConditions.contains(where: { $0.metric == metric })
        }
        for metric in preferredMetrics {
            draft.preferredConditions.append(
                PreferredRule(metric: metric,
                              direction: metric.higherIsBetter ? .higher : .lower,
                              weight: 0)
            )
        }
        editorDraft = draft
        distributeWeightsEvenly()
        toast = ToastPayload(title: "Suggestions added",
                             changes: ["\(required.count) required", "\(preferredMetrics.count) preferred", "Adjust or remove any of them"])
    }

    private func defaultRule(for metric: MetricKind) -> ConditionRule {
        let range = metric.uiRange
        let value = range.lowerBound + (range.upperBound - range.lowerBound) * 0.4
        return ConditionRule(metric: metric,
                             comparison: metric.higherIsBetter ? .atLeast : .atMost,
                             value: (value / 5).rounded() * 5)
    }

    func addRequired(_ metric: MetricKind) {
        guard var draft = editorDraft else { return }
        guard !draft.requiredConditions.contains(where: { $0.metric == metric }) else { return }
        draft.requiredConditions.append(defaultRule(for: metric))
        editorDraft = draft
    }

    func removeRequired(_ id: UUID) {
        guard var draft = editorDraft else { return }
        draft.requiredConditions.removeAll { $0.id == id }
        editorDraft = draft
    }

    func updateRequired(_ rule: ConditionRule) {
        guard var draft = editorDraft else { return }
        guard let index = draft.requiredConditions.firstIndex(where: { $0.id == rule.id }) else { return }
        draft.requiredConditions[index] = rule
        editorDraft = draft
    }

    func addPreferred(_ metric: MetricKind) {
        guard var draft = editorDraft else { return }
        guard !draft.preferredConditions.contains(where: { $0.metric == metric }) else { return }
        draft.preferredConditions.append(
            PreferredRule(metric: metric,
                          direction: metric.higherIsBetter ? .higher : .lower,
                          weight: 0)
        )
        editorDraft = draft
        distributeWeightsEvenly()
    }

    func removePreferred(_ id: UUID) {
        guard var draft = editorDraft else { return }
        draft.preferredConditions.removeAll { $0.id == id }
        editorDraft = draft
        if !(editorDraft?.preferredConditions.isEmpty ?? true) { distributeWeightsEvenly() }
    }

    func updatePreferred(_ rule: PreferredRule) {
        guard var draft = editorDraft else { return }
        guard let index = draft.preferredConditions.firstIndex(where: { $0.id == rule.id }) else { return }
        draft.preferredConditions[index] = rule
        editorDraft = draft
    }

    func distributeWeightsEvenly() {
        guard var draft = editorDraft, !draft.preferredConditions.isEmpty else { return }
        let count = draft.preferredConditions.count
        let base = 100 / count
        let remainder = 100 - base * count
        for (index, _) in draft.preferredConditions.enumerated() {
            draft.preferredConditions[index].weight = base + (index < remainder ? 1 : 0)
        }
        editorDraft = draft
    }

    // MARK: - Persistence

    func save() {
        guard var draft = editorDraft, draft.isValid, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        let outcome = interactor.save(draft)
        isSaving = false

        switch outcome {
        case .failure(let message):
            // The editor stays open with everything the user typed.
            editorDraft = draft
            errorMessage = message
        case .success(let changes):
            editorDraft = nil
            originalForEditing = nil
            router.editing = nil
            toast = ToastPayload(title: "“\(draft.name)” saved", changes: Array(changes.prefix(4)))
        }
    }

    func dismissError() { errorMessage = nil }

    func cancelEditing() {
        if let draft = editorDraft, draftHasChanges {
            interactor.saveDraft(draft)
            toast = ToastPayload(title: "Draft kept",
                                 changes: ["Nothing was created", "Your changes were stored on this device"])
        }
        editorDraft = nil
        originalForEditing = nil
        router.editing = nil
    }

    func archive(_ template: ActivityTemplate) {
        switch interactor.setArchived(template.id, archived: true) {
        case .failure(let message): errorMessage = message
        case .success:
            toast = ToastPayload(title: "“\(template.name)” archived",
                                 changes: ["Existing plans keep working", "Restore it any time"])
        }
    }

    func restore(_ template: ActivityTemplate) {
        switch interactor.setArchived(template.id, archived: false) {
        case .failure(let message): errorMessage = message
        case .success: toast = ToastPayload(title: "“\(template.name)” restored")
        }
    }

    func requestDelete(_ template: ActivityTemplate) {
        router.deletionTarget = interactor.deletionImpact(template.id)
    }

    func performDelete(_ impact: DeletionImpact, strategy: DeletionStrategy) {
        guard let template = interactor.activities.first(where: { $0.name == impact.entityTitle }) else {
            router.deletionTarget = nil
            return
        }
        let outcome = interactor.delete(template.id, strategy: strategy)
        router.deletionTarget = nil
        if case .failure(let message) = outcome {
            errorMessage = message
            return
        }
        switch strategy {
        case .archive:
            toast = ToastPayload(title: "“\(template.name)” archived instead of deleted")
        case .deleteAndDetach:
            toast = ToastPayload(title: "“\(template.name)” deleted",
                                 changes: ["Dependent plans were archived", "Feedback history was kept"])
        case .cancel:
            break
        }
    }
}
