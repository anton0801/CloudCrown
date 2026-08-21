//
//  BackgroundRefreshScheduler.swift
//  CloudCrown
//
//  Registers and submits the BGTaskScheduler work that lets CloudCrown re-check
//  plans and alert rules while it is not open. iOS decides if and when the task
//  actually runs — the UI states that plainly rather than promising a schedule.
//

import Foundation
import BackgroundTasks

@MainActor
final class BackgroundRefreshScheduler: ObservableObject {

    static let refreshIdentifier = "app.CloudCrown.refresh"

    enum Status: Equatable {
        case notRegistered
        case scheduled(next: Date)
        case unavailable(String)
        case disabled

        var summary: String {
            switch self {
            case .notRegistered:
                return "Background checks are not registered on this device."
            case .scheduled(let next):
                return "Requested from iOS, earliest \(SkyFormat.fullDateTime(next, timeZone: .current)). iOS decides when it actually runs."
            case .unavailable(let reason):
                return reason
            case .disabled:
                return "Background Refresh is off, so CloudCrown only re-checks when you open it."
            }
        }
    }

    @Published private(set) var status: Status = .notRegistered

    /// The minimum gap CloudCrown asks iOS for. iOS may run it much later.
    private let minimumInterval: TimeInterval = 60 * 60

    private weak var coordinator: RefreshCoordinator?

    /// Must be called before the app finishes launching.
    func register(coordinator: RefreshCoordinator) {
        self.coordinator = coordinator
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await self.handle(refreshTask)
            }
        }
    }

    private func handle(_ task: BGAppRefreshTask) async {
        // Always queue the next one first, so a cancelled run does not end the chain.
        schedule(enabled: true)

        let work = Task { @MainActor in
            await coordinator?.run(trigger: .background)
        }

        task.expirationHandler = {
            work.cancel()
        }

        let report = await work.value
        task.setTaskCompleted(success: report != nil)
    }

    /// Submits the next request, or cancels everything when the user turned the
    /// preference off.
    func schedule(enabled: Bool) {
        guard enabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshIdentifier)
            status = .disabled
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        let earliest = Date().addingTimeInterval(minimumInterval)
        request.earliestBeginDate = earliest

        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshIdentifier)
            try BGTaskScheduler.shared.submit(request)
            status = .scheduled(next: earliest)
        } catch let error as BGTaskScheduler.Error {
            switch error.code {
            case .unavailable:
                status = .unavailable("Background App Refresh is turned off for CloudCrown in iOS Settings, or unavailable in the Simulator.")
            case .notPermitted:
                status = .unavailable("iOS does not permit background work for CloudCrown right now.")
            case .tooManyPendingTaskRequests:
                status = .unavailable("Too many pending background requests.")
            @unknown default:
                status = .unavailable(error.localizedDescription)
            }
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }
}
