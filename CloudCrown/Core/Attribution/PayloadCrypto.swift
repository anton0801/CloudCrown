import Foundation
import CryptoKit

enum PayloadCrypto {

    static var isConfigured: Bool { key != nil }

    private static var key: SymmetricKey? {
        let hex = AppConstants.payloadKeyHex
        guard hex.count == 64 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return SymmetricKey(data: Data(bytes))
    }

    /// Returns the request body: sealed when a key is configured, plain otherwise.
    static func envelope(_ object: [String: Any]) throws -> [String: Any] {
        let json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let key = key else { return object }
        let sealed = try AES.GCM.seal(json, using: key)
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        return ["payload": combined.base64EncodedString()]
    }

    enum CryptoError: LocalizedError {
        case sealFailed
        var errorDescription: String? { "The request payload could not be encrypted." }
    }
}
