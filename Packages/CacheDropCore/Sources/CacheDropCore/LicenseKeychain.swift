import Foundation
import Security

/// Keeps the license key in the login Keychain as one generic password. The app has no Keychain entitlements, so this
/// uses the file-based login Keychain, whose item only CacheDrop's signed app reads without asking.
@MainActor public final class KeychainLicenseKeyStore: LicenseKeyStore {
    /// Stored names: a rename would lose the key on every Mac, so they never change (#448).
    public static let service = "com.patrickbourget.CacheDrop.license", account = "license-key"
    public init() {}

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account]
    }
    public func read() throws -> String? {
        var query = query; query[kSecReturnData] = true; query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }
    public func write(_ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData] = data; item[kSecAttrLabel] = "CacheDrop license key"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    public func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

struct KeychainError: Error { let status: OSStatus }
