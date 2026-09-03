import Foundation

/// Single hand-off point between the SDK callbacks and the start-up pipeline.
/// Deliberately not NotificationCenter: exactly one consumer waits for exactly
/// one merged result.
actor AttributionRelay {

    static let shared = AttributionRelay()

    private var value: [String: String]?
    private var waiters: [CheckedContinuation<[String: String], Never>] = []

    func publish(_ trace: [String: String]) {
        guard value == nil else { return }
        value = trace
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume(returning: trace) }
    }

    func current() -> [String: String]? { value }

    /// Resolves as soon as a trace is published, or with whatever is known when
    /// the timeout elapses.
    func awaitTrace(timeout: TimeInterval) async -> [String: String] {
        if let value = value { return value }

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.releaseWaiters()
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<[String: String], Never>) in
            waiters.append(continuation)
        }
        timeoutTask.cancel()
        return result
    }

    private func releaseWaiters() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume(returning: value ?? [:]) }
    }
}
