import Foundation
#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif
#if canImport(AdSupport)
import AdSupport
#endif

@MainActor
final class SDKAttributionProvider: AttributionProviding {

    var anchor: String {
        #if canImport(AppsFlyerLib)
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        if !uid.isEmpty { return uid }
        #endif
        return InstallState.fallbackAnchor
    }

    var relayIdentifier: String? {
        #if canImport(FirebaseCore)
        return FirebaseApp.app()?.options.gcmSenderID
        #else
        return nil
        #endif
    }

    /// Only returned once ATT is authorised; the all-zero placeholder is dropped.
    func currentAdIdentifier() -> String? {
        #if canImport(AppTrackingTransparency) && canImport(AdSupport)
        guard #available(iOS 14, *) else { return nil }
        guard ATTrackingManager.trackingAuthorizationStatus == .authorized else { return nil }
        let identifier = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        guard identifier != "00000000-0000-0000-0000-000000000000" else { return nil }
        return identifier
        #else
        return nil
        #endif
    }

    func awaitTrace(timeout: TimeInterval) async -> [String: String] {
        await AttributionRelay.shared.awaitTrace(timeout: timeout)
    }
}

enum AttributionProviderFactory {
    @MainActor
    static func make() -> AttributionProviding {
        #if canImport(AppsFlyerLib)
        return SDKAttributionProvider()
        #else
        return NoopAttributionProvider()
        #endif
    }
}
