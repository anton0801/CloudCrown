//
//  ComfortProfilePresenter.swift
//  CloudCrown
//

import SwiftUI

@MainActor
final class ComfortProfilePresenter: ObservableObject {

    @Published var draft: ComfortProfile
    @Published private(set) var isSaving = false
    @Published private(set) var isEditing = false
    @Published private(set) var errorMessage: String?

    @Published var toast: ToastPayload?
    @Published var selectedMetric: MetricKind = .temperature

    private let interactor: ComfortProfileInteractorInput
    private let router: ComfortProfileRouter
    private var originalProfile: ComfortProfile?

    init(interactor: ComfortProfileInteractorInput, router: ComfortProfileRouter) {
        self.interactor = interactor
        self.router = router
        let existing = interactor.profile
        self.originalProfile = existing
        self.draft = existing ?? ComfortProfile(
            thresholds: MetricKind.constrainable.map { ComfortThreshold(metric: $0, minValue: nil, maxValue: nil) }
        )
    }

    // MARK: - Derived

    var settings: AppSettings { interactor.settings }
    var hasProfile: Bool { originalProfile != nil }
    var hasChanges: Bool { draft != originalProfile }
    var definedCount: Int { draft.definedCount }
    var isUsable: Bool { draft.isUsable }
    var missingCore: [MetricKind] { draft.missingCoreMetrics }
    var usesGeneralDefaults: Bool { draft.usesGeneralDefaults }
    var dependentSummary: String { interactor.dependentSummary() }

    var editableMetrics: [MetricKind] { MetricKind.constrainable }

    /// Invalid ranges are blocked at the source, so this lists what is wrong.
    var validationErrors: [String] {
        var errors: [String] = []
        for threshold in draft.thresholds {
            guard let min = threshold.minValue, let max = threshold.maxValue else { continue }
            if min > max {
                errors.append("\(threshold.metric.title): the minimum (\(SkyFormat.number(min, decimals: threshold.metric.decimals))) is above the maximum (\(SkyFormat.number(max, decimals: threshold.metric.decimals))).")
            }
        }
        return errors
    }

    var canSave: Bool { validationErrors.isEmpty && hasChanges && !isSaving }

    func threshold(for metric: MetricKind) -> ComfortThreshold {
        draft.threshold(for: metric) ?? ComfortThreshold(metric: metric, minValue: nil, maxValue: nil)
    }

    func binding(for metric: MetricKind) -> Binding<ComfortThreshold> {
        Binding(
            get: { self.threshold(for: metric) },
            set: { updated in
                if let index = self.draft.thresholds.firstIndex(where: { $0.metric == metric }) {
                    self.draft.thresholds[index] = updated
                } else {
                    self.draft.thresholds.append(updated)
                }
                self.draft.usesGeneralDefaults = false
                self.isEditing = true
            }
        )
    }

    func sensitivity(for kind: SensitivityKind) -> SensitivityLevel { draft.level(for: kind) }

    func setSensitivity(_ level: SensitivityLevel, for kind: SensitivityKind) {
        if let index = draft.sensitivities.firstIndex(where: { $0.kind == kind }) {
            draft.sensitivities[index].level = level
        } else {
            draft.sensitivities.append(SensitivityEntry(kind: kind, level: level))
        }
        isEditing = true
    }

    /// Explains how a sensitivity changes the effective limit — never hidden.
    func sensitivityEffect(for kind: SensitivityKind) -> String? {
        let level = draft.level(for: kind)
        guard level != .notSet, level != .normal else { return nil }
        guard let metric = MetricKind.constrainable.first(where: { ComfortProfile.sensitivityKind(for: $0) == kind }),
              let raw = threshold(for: metric).maxValue else { return nil }
        let effective = raw * level.thresholdMultiplier
        return "\(metric.title) limit \(SkyFormat.number(raw, decimals: metric.decimals)) → effective \(SkyFormat.number(effective, decimals: metric.decimals)) \(metric.canonicalUnit)"
    }

    // MARK: - Lifecycle

    func onAppear() {
        if interactor.hasDraft(), originalProfile == nil || interactor.loadDraft() != originalProfile {
            router.showsDraftPrompt = true
        }
    }

    func restoreDraft() {
        if let draft = interactor.loadDraft() {
            self.draft = draft
            isEditing = true
        }
        router.showsDraftPrompt = false
    }

    func discardDraft() {
        interactor.clearDraft()
        router.showsDraftPrompt = false
    }

    // MARK: - Actions

    func applyGeneralDefaults() {
        draft = interactor.generalDefaults()
        // Preserve sensitivities the user already declared.
        if let original = originalProfile {
            draft.sensitivities = original.sensitivities
        }
        isEditing = true
        toast = ToastPayload(title: "General defaults applied",
                             changes: ["Not medical guidance", "\(draft.definedCount) limits filled in", "Review each one before saving"])
    }

    func startCustomEditing() {
        isEditing = true
    }

    func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        let outcome = interactor.save(draft, appliedDefaults: draft.usesGeneralDefaults)
        isSaving = false

        switch outcome {
        case .failure(let message):
            // Nothing was written: stay in edit mode and keep the entered values.
            errorMessage = message
        case .success(let changes):
            originalProfile = interactor.profile
            draft = interactor.profile ?? draft
            isEditing = false
            toast = ToastPayload(
                title: "Comfort Profile saved",
                changes: changes.isEmpty ? ["\(draft.definedCount) limits defined"] : Array(changes.prefix(4))
            )
        }
    }

    func dismissError() { errorMessage = nil }

    func cancelEditing() {
        if hasChanges {
            interactor.saveDraft(draft)
            toast = ToastPayload(title: "Draft kept", changes: ["Your unsaved limits were stored on this device"])
        }
        draft = originalProfile ?? draft
        isEditing = false
    }

    func requestReset() { router.showsResetConfirmation = true }

    func confirmReset() {
        if case .failure(let message) = interactor.reset() {
            router.showsResetConfirmation = false
            errorMessage = message
            return
        }
        originalProfile = nil
        draft = ComfortProfile(
            thresholds: MetricKind.constrainable.map { ComfortThreshold(metric: $0, minValue: nil, maxValue: nil) }
        )
        router.showsResetConfirmation = false
        isEditing = false
        toast = ToastPayload(title: "Comfort Profile reset",
                             changes: ["All limits cleared", "Window results are unavailable until limits are set again"])
    }

    func openUnits() { router.showsUnitsSheet = true }

    func changeUnits(_ transform: (inout AppSettings) -> Void) {
        switch interactor.updateUnits(transform) {
        case .failure(let message):
            errorMessage = message
        case .success(let changes):
            if !changes.isEmpty {
                toast = ToastPayload(title: "Units updated", changes: changes)
            }
        }
    }
}
