import Foundation
import Security
import CommonCrypto

protocol SecretStorage {
    func read() -> Data?
    func write(_ data: Data) -> Bool
}

struct KeychainStorage: SecretStorage {
    let service = "com.local.SecureMyMac.pin"
    var account = "app-pin-hash"

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() -> Data? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    func write(_ data: Data) -> Bool {
        SecItemDelete(base as CFDictionary)
        var q = base
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

final class MemoryStorage: SecretStorage {
    private var data: Data?
    func read() -> Data? { data }
    func write(_ d: Data) -> Bool { data = d; return true }
}

/// Stores salt + PBKDF2 hash of the PIN. The PIN itself is never stored or logged.
struct PinStore {
    let storage: SecretStorage
    static let rounds: UInt32 = 150_000

    var hasPin: Bool { storage.read() != nil }

    static func isValidFormat(_ pin: String) -> Bool {
        (4...6).contains(pin.count) && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    func setPin(_ pin: String) -> Bool {
        guard Self.isValidFormat(pin) else { return false }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { return false }
        return storage.write(salt + Self.hash(pin, salt: salt))
    }

    func verify(_ pin: String) -> Bool {
        guard let stored = storage.read(), stored.count == 48 else { return false }
        let salt = stored.prefix(16)
        let expected = stored.suffix(32)
        let actual = Self.hash(pin, salt: Data(salt))
        // constant-time compare
        var diff: UInt8 = 0
        for (a, b) in zip(expected, actual) { diff |= a ^ b }
        return diff == 0 && actual.count == expected.count
    }

    static func hash(_ pin: String, salt: Data) -> Data {
        var out = Data(count: 32)
        let pw = Array(pin.utf8)
        _ = out.withUnsafeMutableBytes { outPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     pw.map { Int8(bitPattern: $0) }, pw.count,
                                     saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                     outPtr.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        return out
    }
}
