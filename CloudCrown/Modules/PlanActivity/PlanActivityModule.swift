//
//  PlanActivityModule.swift
//  CloudCrown
//

import SwiftUI
import EventKit

// MARK: - Contract

@MainActor
protocol PlanActivityInteractorInput: AnyObject {
    var settings: AppSettings { get }
    func activity(id: UUID) -> ActivityTemplate?
    func place(id: UUID) -> Place?
    func existingPlan(activityID: UUID, placeID: UUID, start: Date) -> Plan?
    func backupCandidates(for window: WindowCandidate) -> [WindowCandidate]
    func save(_ plan: Plan) -> SaveOutcome
    /// Cancels any previous reminder and schedules the new one, returning the
    /// identifier only when iOS actually accepted it.
    func syncReminder(plan: Plan, placeName: String) async -> String?
    func requestNotificationAuthorization() async -> Bool
    var notificationAuthorization: NotificationAuthorization { get }
    func refreshNotificationAuthorization() async
    func requestCalendarAccess() async -> Bool
    func makeCalendarEvent(plan: Plan, placeName: String) -> EKEvent
    var eventStore: EKEventStore { get }
    func saveDraft(_ plan: Plan)
    func loadDraft() -> Plan?
    func clearDraft()
}

// MARK: - Router

@MainActor
final class PlanActivityRouter: ObservableObject {
    @Published var showsCalendarEditor = false
    @Published var showsBackupPicker = false
    @Published var didFinish = false
}

// MARK: - Builder

enum PlanActivityModule {
    @MainActor
    static func build(environment: AppEnvironment,
                      coordinator: AppCoordinator,
                      window: WindowCandidate) -> some View {
        let interactor = PlanActivityInteractor(repository: environment.repository,
                                                notifications: environment.notifications,
                                                calendar: environment.calendar)
        let router = PlanActivityRouter()
        let presenter = PlanActivityPresenter(interactor: interactor,
                                              router: router,
                                              coordinator: coordinator,
                                              window: window)
        return PlanActivityView(presenter: presenter, router: router)
    }
}
