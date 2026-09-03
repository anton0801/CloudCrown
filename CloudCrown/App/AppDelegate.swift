import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

enum Dash {
    static let appCode = "6803952990"
    static let relayKey = "DgbTucU9LFYncYp2vWiVgM"
    static let suite = "group.autotrack.trip"
    static let cookieJar = "at_trip_cookies"
    static let store = "id6803952990"
}

enum Dial {
    static let pushURL = "temp_url"
    static let fcm = "fcm_token"
    static let push = "push_token"
    static let sharedFcm = "shared_fcm"
    static let attStatus = "at_att_status"
    static let primed = "at_primed"
    static let routeURL = "at_route_url"
    static let routeMode = "at_route_mode"
    static let consentGrant = "at_consent_locked"
    static let consentDeny = "at_consent_drifted"
    static let consentAt = "at_consent_mapped_at"
}

extension Notification.Name {
    static let honked = Notification.Name("LoadTempURL")
}

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private var lead: [AnyHashable: Any] = [:]
    private var trail: [AnyHashable: Any] = [:]
    private var wait: Task<Void, Never>?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
        }

        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = Dash.relayKey
        sdk.appleAppID = Dash.appCode
        sdk.minTimeBetweenSessions = 0
        sdk.delegate = self
        sdk.deepLinkDelegate = self
        sdk.isDebug = false

        if FirebaseApp.app() != nil {
            Messaging.messaging().delegate = self
        }
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            beam(cold)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(active), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if FirebaseApp.app() != nil { Messaging.messaging().apnsToken = deviceToken }
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
        return true
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        AppsFlyerLib.shared().handleOpen(url, options: options)
        return true
    }

    @objc private func active() {
        guard #available(iOS 14, *) else { return AppsFlyerLib.shared().start() }
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(status.rawValue, forKey: Dial.attStatus)
            }
        }
    }

    private func arm() {
        wait?.cancel()
        wait = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run { self?.weld() }
        }
    }

    private func weld() {
        wait?.cancel()
        wait = nil
        var merged = lead
        for (key, value) in trail {
            let tag = "\(key)".starts(with: "deep") ? "\(key)" : "deep_\(key)"
            if merged[tag] == nil { merged[tag] = value }
        }
        AttributionManager.shared.recordConversion(merged)
    }

    private func beam(_ payload: [AnyHashable: Any]) {
        var found: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            found = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            found = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            found = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            found = url
        }
        guard let link = found else { return }

        UserDefaults.standard.set(link, forKey: Dial.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .honked, object: nil, userInfo: ["temp_url": link])
        }
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, token.isEmpty == false else { return }
        UserDefaults.standard.set(token, forKey: Dial.fcm)
        UserDefaults.standard.set(token, forKey: Dial.push)
        UserDefaults(suiteName: Dash.suite)?.set(token, forKey: Dial.sharedFcm)
        Task { @MainActor in
            PushTokenReporter.shared.submit(token)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if FirebaseApp.app() != nil { Messaging.messaging().appDidReceiveMessage(userInfo) }
        AppsFlyerLib.shared().handlePushNotification(userInfo)
        beam(userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if FirebaseApp.app() != nil { Messaging.messaging().appDidReceiveMessage(userInfo) }
        AppsFlyerLib.shared().handlePushNotification(userInfo)
        beam(userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if FirebaseApp.app() != nil { Messaging.messaging().appDidReceiveMessage(userInfo) }
        AppsFlyerLib.shared().handlePushNotification(userInfo)
        beam(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        print("onConversionDataSuccess \(conversionInfo)")
        lead = conversionInfo
        arm()
        if trail.isEmpty == false { weld() }
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Dial.primed) == false else { return }
        trail = deepLink.clickEvent
        wait?.cancel()
        wait = nil
        if lead.isEmpty == false {
            weld()
        } else {
            arm()
        }
    }
}
