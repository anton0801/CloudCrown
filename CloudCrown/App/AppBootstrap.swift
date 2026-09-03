import Foundation
import Combine
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

struct BootstrapResult: Equatable {
    var authorized: Bool
    var analyticsURL: URL?
    var message: String?

    static let none = BootstrapResult(authorized: false, analyticsURL: nil, message: nil)
}

/// Start-up pipeline. The splash stays up until this finishes or the hard
/// timeout fires, so nothing is routed before the server has answered.
@MainActor
final class AppBootstrap: ObservableObject {

    @Published private(set) var isFinished = false
    @Published private(set) var result: BootstrapResult = .none

    private let client = HorizonClient()
    private let provider: AttributionProviding
    private var started = false

    private let traceTimeout: TimeInterval
    private let hardTimeout: TimeInterval

    init(provider: AttributionProviding? = nil, traceTimeout: TimeInterval = 25, hardTimeout: TimeInterval = 30) {
        self.provider = provider ?? AttributionProviderFactory.make()
        self.traceTimeout = traceTimeout
        self.hardTimeout = hardTimeout
    }

    func start() {
        guard !started else { return }
        started = true

        Task { [weak self] in
            guard let self = self else { return }
            let watchdog = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.hardTimeout ?? 30) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.finish(.none) }
            }
            await self.run()
            watchdog.cancel()
        }
    }

    private func run() async {
        // The observe request is the launch; the server counts it.
        let collected = AttributionFields.base()
        await client.observe(collected)

        let trace = await provider.awaitTrace(timeout: traceTimeout)

        var final = AttributionFields.base()
        if let ad = provider.currentAdIdentifier() { final["ad_id"] = ad }
        if !trace.isEmpty { final["trace"] = trace }

        // Record what this resolve carries, so a conversion that arrives after
        // the timeout knows it still needs a follow-up resolve.
        AttributionReporter.shared.recordPrimaryResolve(trace: trace)

        let outcome = await client.resolve(final)
        finish(BootstrapResult(authorized: outcome.authorized,
                               analyticsURL: outcome.analyticsURL,
                               message: outcome.message))
    }

    private func finish(_ value: BootstrapResult) {
        guard !isFinished else { return }
        result = value
        isFinished = true
    }
}
