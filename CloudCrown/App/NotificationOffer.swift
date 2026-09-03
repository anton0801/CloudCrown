import Foundation

enum NotificationOffer {

    private enum Key {
        static let done = "cc.offer.done"
        static let skippedAt = "cc.offer.skippedAt"
    }

    private static let store = UserDefaults.standard
    private static let secondChanceDelay: TimeInterval = 3 * 24 * 60 * 60

    static var shouldShow: Bool {
        if store.bool(forKey: Key.done) { return false }
        guard let firstSkip = store.object(forKey: Key.skippedAt) as? Date else { return true }
        return Date().timeIntervalSince(firstSkip) >= secondChanceDelay
    }

    /// Any answer to the system prompt retires the offer for good.
    static func markAnswered() {
        store.set(true, forKey: Key.done)
    }

    /// First skip earns one repeat after three days; a skip after that ends it.
    static func markSkipped() {
        if let firstSkip = store.object(forKey: Key.skippedAt) as? Date {
            if Date().timeIntervalSince(firstSkip) >= secondChanceDelay {
                store.set(true, forKey: Key.done)
            }
            return
        }
        store.set(Date(), forKey: Key.skippedAt)
    }

    static func reset() {
        store.removeObject(forKey: Key.done)
        store.removeObject(forKey: Key.skippedAt)
    }
}
