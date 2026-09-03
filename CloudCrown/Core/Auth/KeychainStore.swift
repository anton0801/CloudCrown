//
//  KeychainStore.swift
//  CloudCrown
//
//  Tokens live in the Keychain, never in UserDefaults or a plain file.
//  Items are device-only and unavailable until first unlock.
//

import Foundation
import Security

protocol SecureStoring: AnyObject {
    func read(_ key: String) -> Data?
    @discardableResult func write(_ data: Data, for key: String) -> Bool
    @discardableResult func delete(_ key: String) -> Bool
}

final class KeychainStore: SecureStoring {

    private let service: String

    init(service: String = "app.CloudCrown.auth") {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    func read(_ key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    func write(_ data: Data, for key: String) -> Bool {
        let query = baseQuery(key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Device-only: tokens are never synced to iCloud or another device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }

        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    @discardableResult
    func delete(_ key: String) -> Bool {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// In-memory replacement used by tests.
final class MemorySecureStore: SecureStoring {
    private var items: [String: Data] = [:]
    func read(_ key: String) -> Data? { items[key] }
    @discardableResult func write(_ data: Data, for key: String) -> Bool { items[key] = data; return true }
    @discardableResult func delete(_ key: String) -> Bool { items[key] = nil; return true }
}
