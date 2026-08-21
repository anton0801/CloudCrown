//
//  NotificationService.swift
//  CloudCrown
//
//  Local notifications only. Payloads deliberately carry the minimum personal
//  detail — a place name and a time, never coordinates or health information.
//

import Foundation
import UserNotifications

enum NotificationAuthorization {
    case notDetermined, denied, authorized, provisional

    var isAuthorized: Bool { self == .authorized || self == .provisional }

    var explanation: String {
        switch self {
        case .notDetermined: return "CloudCrown has not asked for notification permission yet."
        case .denied: return "Notifications are off in iOS Settings, so alert rules cannot reach you."
        case .authorized: return "Notifications are allowed."
        case .provisional: return "Notifications are delivered quietly."
        }
    }
}

/// Lets the repository cancel a plan's reminder when the plan is cancelled,
/// archived or deleted, without depending on the concrete service.
@MainActor
protocol PlanNotificationCancelling: AnyObject {
    func cancel(identifier: String)
}

/// The delivery surface the refresh cycle needs. Keeping it narrow lets the
/// alert pipeline be exercised without the system notification centre.
@MainActor
protocol AlertNotifying: AnyObject {
    var authorization: NotificationAuthorization { get }
    func refreshAuthorization() async
    func deliver(title: String, body: String, identifier: String) async -> Bool
}

@MainActor
final class NotificationService: ObservableObject, PlanNotificationCancelling, AlertNotifying {

    @Published private(set) var authorization: NotificationAuthorization = .notDetermined

    private let center = UNUserNotificationCenter.current()

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: authorization = .notDetermined
        case .denied: authorization = .denied
        case .authorized: authorization = .authorized
        case .provisional: authorization = .provisional
        case .ephemeral: authorization = .authorized
        @unknown default: authorization = .notDetermined
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            return granted
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    /// Schedules a plan reminder. Returns the identifier, or nil if it could
    /// not be scheduled — the caller must not claim success on nil.
    func scheduleReminder(planTitle: String, placeName: String, fireAt: Date, planID: UUID) async -> String? {
        guard authorization.isAuthorized else { return nil }
        guard fireAt > Date() else { return nil }

        let content = UNMutableNotificationContent()
        content.title = planTitle
        content.body = "Starts soon at \(placeName)."
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = Self.reminderIdentifier(for: planID)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            return identifier
        } catch {
            return nil
        }
    }

    /// Delivers an alert-rule notification immediately. Body is kept minimal.
    @discardableResult
    func deliver(title: String, body: String, identifier: String) async -> Bool {
        guard authorization.isAuthorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    /// Cancels any previous reminder for the plan and schedules the new one.
    /// Returns the identifier only when iOS actually accepted the request, so
    /// callers can never claim a reminder that does not exist.
    func syncReminder(for plan: Plan, placeName: String) async -> String? {
        if let existing = plan.reminderNotificationID {
            cancel(identifier: existing)
        }
        // Also cancel by convention: the identifier is derived from the plan id,
        // so a request left over from an earlier save is cleared too.
        cancel(identifier: Self.reminderIdentifier(for: plan.id))

        guard let offset = plan.reminderMinutesBefore else { return nil }
        guard plan.status == .scheduled || plan.status == .atRisk else { return nil }

        let fireAt = plan.window.start.addingTimeInterval(TimeInterval(-offset * 60))
        return await scheduleReminder(planTitle: plan.title,
                                      placeName: placeName,
                                      fireAt: fireAt,
                                      planID: plan.id)
    }

    static func reminderIdentifier(for planID: UUID) -> String {
        "plan-\(planID.uuidString)"
    }

    func cancel(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }
}
