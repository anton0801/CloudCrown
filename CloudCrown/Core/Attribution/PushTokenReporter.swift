import Foundation

/// FCM hands the token over asynchronously, usually after the start-up requests
/// have already gone out. This sends it on its own as soon as it arrives, and
/// never sends the same value twice.
@MainActor
final class PushTokenReporter {

    static let shared = PushTokenReporter()

    private let client = HorizonClient()
    private var inFlight = false

    func submit(_ token: String) {
        InstallState.cachedPushToken = token
        report()
    }

    func report() {
        guard let token = InstallState.cachedPushToken, !token.isEmpty else { return }
        guard token != InstallState.deliveredPushToken, !inFlight else { return }

        inFlight = true
        let provider = AttributionProviderFactory.make()
        let facts = DeviceFacts.current()
        let fields: [String: Any] = [
            "anchor": provider.anchor,
            "signal": token,
            "catalog_id": AppConstants.storeIdentifier,
            "relay_id": provider.relayIdentifier as Any,
            "os_line": facts.osLine,
            "vessel": facts.vessel,
            "locale_tag": facts.localeTag,
            // This is a field update, not a launch: the server must not count it.
            "tick": false,
        ]

        Task { [weak self] in
            let delivered = await self?.client.observe(fields) ?? false
            await MainActor.run {
                if delivered { InstallState.deliveredPushToken = token }
                self?.inFlight = false
            }
        }
    }
}
