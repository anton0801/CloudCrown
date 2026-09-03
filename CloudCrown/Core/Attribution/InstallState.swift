import Foundation

enum InstallState {

    private enum Key {
        static let anchor = "cc.anchor.local"
        static let signalCache = Dial.fcm
        static let signalSent = "cc.signal.sent"
        static let attState = Dial.attStatus
        static let installStamp = "cc.install.stamp"
    }

    private static let store = UserDefaults.standard

    /// Used only until the SDK reports its own identifier.
    static var fallbackAnchor: String {
        if let existing = store.string(forKey: Key.anchor), !existing.isEmpty { return existing }
        let generated = UUID().uuidString
        store.set(generated, forKey: Key.anchor)
        return generated
    }

    static var cachedPushToken: String? {
        get { store.string(forKey: Key.signalCache) }
        set { store.set(newValue, forKey: Key.signalCache) }
    }

    static var deliveredPushToken: String? {
        get { store.string(forKey: Key.signalSent) }
        set { store.set(newValue, forKey: Key.signalSent) }
    }

    static var trackingStatus: Int {
        get { store.integer(forKey: Key.attState) }
        set { store.set(newValue, forKey: Key.attState) }
    }

    static var installedAt: Date {
        if let stamp = store.object(forKey: Key.installStamp) as? Date { return stamp }
        let now = Date()
        store.set(now, forKey: Key.installStamp)
        return now
    }
}
