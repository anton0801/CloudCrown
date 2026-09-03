import Foundation
#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

@MainActor
final class AttributionManager {

    static let shared = AttributionManager()

    private var conversion: [String: String] = [:]
    private var deepLink: [String: String] = [:]
    private var lastPublishedFingerprint: String?
    private var organicTask: Task<Void, Never>?

    /// How long to wait before re-asking AppsFlyer for precise install data
    /// when the first callback reports an organic install.
    private let organicRecheckDelay: TimeInterval = 5

    func recordConversion(_ payload: [AnyHashable: Any]) {
        // Accumulate rather than replace: a first callback (or a deep-link-only
        // weld with an empty lead) may lack af_status, and a later one supplies it.
        conversion.merge(Self.flatten(payload)) { _, new in new }
        let status = conversion["af_status"]?.lowercased()

        // No real attribution status yet — do NOT publish a partial trace, or the
        // splash would resolve and forward without the conversion. Wait for the
        // real conversion, or for the bootstrap's own timeout.
        guard let status = status else { return }

        guard status == "organic" else {
            publishMerged()
            return
        }
        guard organicTask == nil else { return }
        organicTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.organicRecheckDelay ?? 5) * 1_000_000_000))
            let precise = await Self.probe()
            await MainActor.run {
                guard let self = self else { return }
                if !precise.isEmpty {
                    self.conversion.merge(precise) { _, new in new }
                }
                self.publishMerged()
            }
        }
    }

    func recordDeepLink(_ payload: [AnyHashable: Any]) {
        deepLink.merge(Self.flatten(payload)) { _, new in new }
        // Only meaningful once a real conversion exists; then republish the
        // enriched trace (deduped inside publishMerged).
        guard conversion["af_status"] != nil else { return }
        publishMerged()
    }

    func recordConversionFailure(_ error: Error) {
    }

    private func merged() -> [String: String] {
        var result = conversion
        result.merge(deepLink) { current, _ in current }
        return result
    }

    /// Publishes the current best trace. Re-entrant: an early conversion can be
    /// superseded by a fuller one, which is delivered to a still-waiting splash
    /// or, if the splash already resolved, sent as a catch-up resolve.
    private func publishMerged() {
        let trace = merged()
        let fingerprint = AttributionReporter.fingerprint(trace)
        guard fingerprint != lastPublishedFingerprint else { return }
        lastPublishedFingerprint = fingerprint
        organicTask = nil
        Task { await AttributionRelay.shared.publish(trace) }
        AttributionReporter.shared.submitLateTrace(trace)
    }

    private static func flatten(_ payload: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in payload {
            let name = String(describing: key)
            guard !name.isEmpty else { continue }
            if let value = value as? String {
                result[name] = value
            } else if value is NSNull {
                continue
            } else {
                result[name] = String(describing: value)
            }
        }
        return result
    }

    /// Direct install_data lookup, used when the SDK first reports Organic.
    static func probe() async -> [String: String] {
        #if canImport(AppsFlyerLib)
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        #else
        let uid = InstallState.fallbackAnchor
        #endif
        guard !uid.isEmpty, !AppConstants.appleAppID.isEmpty, !AppConstants.appsFlyerDevKey.isEmpty else { return [:] }

        var components = URLComponents(string: "https://gcdsdk.appsflyer.com/install_data/v4.0/id\(AppConstants.appleAppID)")
        components?.queryItems = [
            URLQueryItem(name: "devkey", value: AppConstants.appsFlyerDevKey),
            URLQueryItem(name: "device_id", value: uid),
        ]
        guard let url = components?.url else { return [:] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return [:] }
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return flatten(dict)
        } catch {
            return [:]
        }
    }
}
