import Foundation

enum AppConstants {
    static var appsFlyerDevKey: String { Dash.relayKey }
    static var appleAppID: String { Dash.appCode }
    static var storeIdentifier: String { Dash.store }

    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "" }

    static var payloadKeyHex: String {
        (Bundle.main.object(forInfoDictionaryKey: "CCPayloadKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
