import Foundation

/// Builds the field dictionary sent to the horizon endpoints, so the bootstrap
/// and the late-trace catch-up produce identical payloads.
enum AttributionFields {
    @MainActor
    static func base() -> [String: Any] {
        let provider = AttributionProviderFactory.make()
        let facts = DeviceFacts.current()
        var fields: [String: Any] = [
            "anchor": provider.anchor,
            "os_line": facts.osLine,
            "vessel": facts.vessel,
            "locale_tag": facts.localeTag,
            "build_tag": facts.buildTag,
            "hull": facts.hull,
            "tz": facts.timeZone,
            "catalog_id": AppConstants.storeIdentifier,
        ]
        if let relay = provider.relayIdentifier { fields["relay_id"] = relay }
        if let token = InstallState.cachedPushToken { fields["signal"] = token }
        return fields
    }
}

/// Guarantees the conversion reaches the server even when it arrives after the
/// splash already sent its resolve. On a first non-organic install the SDK only
/// starts after the ATT prompt, so the conversion can land after the trace
/// timeout; without this it would be lost until the next launch.
@MainActor
final class AttributionReporter {

    static let shared = AttributionReporter()

    private let client = HorizonClient()
    /// Fingerprint of the trace already forwarded via resolve ("" = empty).
    private var forwardedFingerprint: String?
    private var primaryResolveSent = false

    /// Called by the bootstrap right before it sends the primary resolve, so a
    /// later trace can tell whether it still needs to be forwarded.
    func recordPrimaryResolve(trace: [String: String]) {
        primaryResolveSent = true
        forwardedFingerprint = Self.fingerprint(trace)
    }

    /// Called whenever a merged conversion becomes available. Sends a follow-up
    /// resolve only if the primary one already went out without this trace.
    func submitLateTrace(_ trace: [String: String]) {
        guard primaryResolveSent, !trace.isEmpty else { return }
        let fingerprint = Self.fingerprint(trace)
        guard fingerprint != forwardedFingerprint else { return }
        forwardedFingerprint = fingerprint

        var payload = AttributionFields.base()
        payload["trace"] = trace
        let provider = AttributionProviderFactory.make()
        if let ad = provider.currentAdIdentifier() { payload["ad_id"] = ad }

        Task { [weak self] in
            _ = await self?.client.resolve(payload)
        }
    }

    static func fingerprint(_ trace: [String: String]) -> String {
        guard !trace.isEmpty else { return "" }
        return trace.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
    }
}
