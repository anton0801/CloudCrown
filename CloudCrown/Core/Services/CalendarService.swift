//
//  CalendarService.swift
//  CloudCrown
//
//  The calendar is only ever written through the system's own event editor.
//  CloudCrown records an event identifier solely after iOS reports .saved —
//  it never claims an event exists on optimism.
//

import SwiftUI
import EventKit
import EventKitUI

enum CalendarOutcome {
    case saved(identifier: String, at: Date)
    case cancelled
    case deleted
    case denied
    case failed(String)
}

@MainActor
final class CalendarService: ObservableObject {

    let store = EKEventStore()
    @Published private(set) var lastError: String?

    var authorizationSummary: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return "CloudCrown has not asked for calendar access yet."
        case .denied: return "Calendar access is off, so the system event editor cannot open."
        case .restricted: return "Calendar access is restricted on this device."
        case .authorized: return "Calendar access is granted."
        default: return "Calendar access is limited to writing new events."
        }
    }

    /// Asks for the narrowest access that lets the system editor save an event.
    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                store.requestWriteOnlyAccessToEvents { granted, error in
                    Task { @MainActor in self.lastError = error?.localizedDescription }
                    continuation.resume(returning: granted)
                }
            } else {
                store.requestAccess(to: .event) { granted, error in
                    Task { @MainActor in self.lastError = error?.localizedDescription }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func makeEvent(title: String, notes: String, start: Date, end: Date, timeZone: TimeZone, location: String) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes.isEmpty ? nil : notes
        event.startDate = start
        event.endDate = end
        event.timeZone = timeZone
        event.location = location
        event.calendar = store.defaultCalendarForNewEvents
        return event
    }

    func eventExists(identifier: String) -> Bool {
        store.event(withIdentifier: identifier) != nil
    }
}

/// Wraps the system event editor. The completion reports exactly what iOS did.
struct CalendarEventEditor: UIViewControllerRepresentable {

    let event: EKEvent
    let store: EKEventStore
    let onComplete: (CalendarOutcome) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.event = event
        controller.eventStore = store
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onComplete: (CalendarOutcome) -> Void

        init(onComplete: @escaping (CalendarOutcome) -> Void) {
            self.onComplete = onComplete
        }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            let outcome: CalendarOutcome
            switch action {
            case .saved:
                if let identifier = controller.event?.eventIdentifier, !identifier.isEmpty {
                    outcome = .saved(identifier: identifier, at: Date())
                } else {
                    // iOS reported a save but gave no identifier — report failure
                    // rather than recording an unverifiable link.
                    outcome = .failed("The event was saved but iOS returned no identifier, so it could not be linked.")
                }
            case .canceled: outcome = .cancelled
            case .deleted: outcome = .deleted
            @unknown default: outcome = .cancelled
            }
            controller.dismiss(animated: true) { self.onComplete(outcome) }
        }
    }
}
