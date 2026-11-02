import Foundation
import Security

/// One generic password in the login Keychain. The app has no Keychain entitlements, so this uses the file-based login
/// Keychain, whose item only CacheDrop's signed app reads without asking. Neither Reset nor a reinstall touches it.
struct KeychainItem {
    let service: String, account: String, label: String

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
    func read() throws -> Data? {
        var query = query; query[kSecReturnData] = true; query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return data
    }
    func write(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData] = data; item[kSecAttrLabel] = label
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// Keeps the license key in the login Keychain as one generic password.
@MainActor public final class KeychainLicenseKeyStore: LicenseKeyStore {
    /// Stored names: a rename would lose the key on every Mac, so they never change (#448).
    public static let service = "com.patrickbourget.CacheDrop.license", account = "license-key"
    private let item = KeychainItem(service: service, account: account, label: "CacheDrop license key")
    public init() {}

    public func read() throws -> String? { try item.read().map { String(decoding: $0, as: UTF8.self) } }
    public func write(_ value: String) throws { try item.write(Data(value.utf8)) }
    public func remove() throws { try item.remove() }
}

/// Keeps the trial's count, in bytes as decimal text, in its own login Keychain item, apart from the license key's, so a
/// reinstall or Reset in Saved data keeps it (Decision 137).
@MainActor public final class KeychainTrialStore: TrialStore {
    /// Stored names: a rename would start every Mac's trial over, so they never change (#448).
    public static let service = "com.patrickbourget.CacheDrop.trial", account = "freed-bytes"
    private let item = KeychainItem(service: service, account: account, label: "CacheDrop free trial")
    public init() {}

    public func read() throws -> Int64? { try item.read().map(Self.count(from:)) }
    public func write(_ value: Int64) throws { try item.write(Data(String(value).utf8)) }
    /// The count an item holds; anything but decimal text reads as unreadable rather than as a fresh trial.
    static func count(from data: Data) throws -> Int64 {
        guard let count = Int64(String(decoding: data, as: UTF8.self)) else { throw KeychainError(status: errSecDecode) }
        return count
    }
}

struct KeychainError: Error { let status: OSStatus }
