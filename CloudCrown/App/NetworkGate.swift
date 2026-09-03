import Foundation
import Network
import Combine

/// Once connectivity is lost the gate latches shut: the app shows a blocking
/// screen and stops reacting to path updates until it is relaunched.
@MainActor
final class NetworkGate: ObservableObject {

    @Published private(set) var isBlocked = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.cloudcrown.network-gate")
    private var latched = false

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status != .satisfied else { return }
            Task { @MainActor in self?.latch() }
        }
        monitor.start(queue: queue)
    }

    private func latch() {
        guard !latched else { return }
        latched = true
        isBlocked = true
        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }
}
