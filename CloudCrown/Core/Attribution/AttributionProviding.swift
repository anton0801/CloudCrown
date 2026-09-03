import Foundation

struct AttributionSnapshot {
    var anchor: String
    var adIdentifier: String?
    var pushToken: String?
    var catalogIdentifier: String?
    var relayIdentifier: String?
    var trace: [String: String]

    static func baseline() -> AttributionSnapshot {
        AttributionSnapshot(
            anchor: InstallState.fallbackAnchor,
            adIdentifier: nil,
            pushToken: InstallState.cachedPushToken,
            catalogIdentifier: AppConstants.storeIdentifier,
            relayIdentifier: nil,
            trace: [:]
        )
    }
}

@MainActor
protocol AttributionProviding: AnyObject {
    var anchor: String { get }
    var relayIdentifier: String? { get }
    func currentAdIdentifier() -> String?
    /// Waits for the merged conversion, or gives up after the timeout.
    func awaitTrace(timeout: TimeInterval) async -> [String: String]
}

@MainActor
final class NoopAttributionProvider: AttributionProviding {
    var anchor: String { InstallState.fallbackAnchor }
    var relayIdentifier: String? { nil }
    func currentAdIdentifier() -> String? { nil }
    func awaitTrace(timeout: TimeInterval) async -> [String: String] { [:] }
}
