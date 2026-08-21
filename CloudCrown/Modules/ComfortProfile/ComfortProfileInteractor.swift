//
//  ComfortProfileInteractor.swift
//  CloudCrown
//

import Foundation

@MainActor
final class ComfortProfileInteractor: ComfortProfileInteractorInput {

    private let repository: DataRepository
    private let draftKey = "comfort-profile-draft"

    init(repository: DataRepository) {
        self.repository = repository
    }

    var profile: ComfortProfile? { repository.profile }
    var settings: AppSettings { repository.settings }

    func generalDefaults() -> ComfortProfile { ComfortProfile.generalDefaults() }

    func save(_ profile: ComfortProfile, appliedDefaults: Bool) -> SaveOutcome {
        let outcome = repository.saveProfile(profile, appliedDefaults: appliedDefaults)
        // The draft is only discarded once the profile is actually stored.
        if outcome.isSuccess { clearDraft() }
        return outcome
    }

    func reset() -> SaveOutcome {
        let outcome = repository.resetProfile()
        if outcome.isSuccess { clearDraft() }
        return outcome
    }

    func saveDraft(_ profile: ComfortProfile) { repository.saveDraft(profile, key: draftKey) }
    func loadDraft() -> ComfortProfile? { repository.loadDraft(ComfortProfile.self, key: draftKey) }
    func clearDraft() { repository.clearDraft(key: draftKey) }
    func hasDraft() -> Bool { repository.hasDraft(key: draftKey) }

    func updateUnits(_ transform: (inout AppSettings) -> Void) -> SaveOutcome {
        repository.updateSettings(transform)
    }

    /// What a reset would affect, listed before it happens.
    func dependentSummary() -> String {
        let plans = repository.upcomingPlans.count
        let alerts = repository.alerts.count
        var parts: [String] = []
        if plans > 0 { parts.append("\(plans) upcoming plan\(plans == 1 ? "" : "s") lose their scoring basis") }
        if alerts > 0 { parts.append("\(alerts) alert rule\(alerts == 1 ? "" : "s") stop matching windows") }
        if parts.isEmpty { return "No plans or alert rules depend on these limits yet." }
        return parts.joined(separator: ", ") + "."
    }
}
