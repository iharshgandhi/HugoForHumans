// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation
/// An FTP/SFTP username and password pair — the shape a deploy target wants.
///
/// Outside the platform `#if` because it is data, not a way of storing it: the
/// Keychain implementation and the no-keychain fallback must agree on it, or a
/// secret written by one could not be read by the other.
public struct CredentialHostSecret {
    public var username: String
    public var password: String
    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// A stored secret's identity. The account is the human-meaningful part
/// ("github.com/iharshgandhi"), so several accounts can coexist.
public struct CredentialKey: Hashable, Codable {
    public var service: String
    public var account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    public static let github = CredentialKey(service: "HugoForHumans.GitHub", account: "")
    public static func githubAccount(_ login: String) -> CredentialKey {
        CredentialKey(service: "HugoForHumans.GitHub", account: login.lowercased())
    }
    public static func host(_ host: String) -> CredentialKey {
        CredentialKey(service: "HugoForHumans.Host", account: host.lowercased())
    }
}

#if canImport(Security)
import Security

/// Secrets storage, backed by the macOS login Keychain.
///
/// Deployment needs a GitHub token and an FTP/SFTP password. Neither belongs in
/// `UserDefaults`, in `hugo.toml`, or in a file the user might commit — so they
/// go in the Keychain, which is already unlocked for the person sitting at the
/// machine and is never synced anywhere.
///
/// Deliberately no data-protection keychain: that requires an app entitlement and
/// an unsigned Command Line Tools binary is refused with
/// `errSecInteractionNotAllowed` (-25300). The file-based login keychain works
/// from a plain tool, which is what this app is during development.
enum CredentialVault {

    /// Re-exported so call sites can spell `CredentialVault.Key`, which reads
    /// better at a use site than the bare file-scope name.
    typealias Key = CredentialKey
    typealias HostSecret = CredentialHostSecret

    /// Why the Keychain refused. The raw status is kept so the message can name
    /// the real cause instead of guessing.
    enum VaultError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case notFound

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "No stored password for this account."
            case .unexpectedStatus(let status):
                let text = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
                return "The Keychain refused the request (\(status)): \(text)"
            }
        }
    }

    /// Whether secrets can actually be stored.
    ///
    /// The Keychain can exist and still refuse an unsigned binary, so this is
    /// answered by trying a real round trip rather than by assuming.
    static var isAvailable: Bool { vaultProbeResult }

    static func set(_ secret: String, for key: Key) throws -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }

        // SecItemUpdate first: on a keychain that already holds the item this
        // avoids the add failing with errSecDuplicateItem.
        let query = baseQuery(key)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw VaultError.unexpectedStatus(addStatus) }
            return true
        default:
            throw VaultError.unexpectedStatus(updateStatus)
        }
    }

    // MARK: - Read

    /// Returns the stored secret, or nil when there is none.
    static func get(_ key: Key) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw VaultError.unexpectedStatus(status)
        }
    }

    /// True when a secret exists, without reading it into memory.
    static func has(_ key: Key) -> Bool {
        var query = baseQuery(key)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Removes a stored secret. Returns true when something was deleted.
    @discardableResult
    static func remove(_ key: Key) throws -> Bool {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw VaultError.unexpectedStatus(status)
        }
    }

    // MARK: - Listing

    /// Every account this app has stored something for, for a "manage
    /// connections" list. Names only — never values.
    static func storedAccounts() -> [(service: String, account: String)] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        // Only this app's own entries.
        query[kSecReturnData as String] = false
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let service = item[kSecAttrService as String] as? String,
                  String(service).hasPrefix("HugoForHumans.") else { return nil }
            let account = item[kSecAttrAccount as String] as? String ?? ""
            return (service, account)
        }
    }

    // MARK: - Internals

    private static func baseQuery(_ key: Key) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.service,
        ]
        if !key.account.isEmpty {
            query[kSecAttrAccount as String] = key.account
        }
        return query
    }

    // MARK: - Host credentials

    /// Separator between the username and the password inside one Keychain
    /// item. A newline cannot work: a password is allowed to contain one, and
    /// splitting on it would silently hand the wrong password to the server.
    private static let fieldSeparator = "\u{1F}"  // ASCII unit separator

    static func hostSecret(for host: String) -> HostSecret? {
        // `get` already returns an optional, so `try?` flattens to String? here.
        guard let raw = try? get(.host(host)), !raw.isEmpty else { return nil }
        // A value written by an older build used a newline; keep reading those.
        if let range = raw.range(of: fieldSeparator) {
            return HostSecret(username: String(raw[raw.startIndex..<range.lowerBound]),
                              password: String(raw[range.upperBound...]))
        }
        if let range = raw.range(of: "\n") {
            return HostSecret(username: String(raw[raw.startIndex..<range.lowerBound]),
                              password: String(raw[range.upperBound...]))
        }
        return HostSecret(username: "", password: raw)
    }

    static func setHostSecret(_ secret: HostSecret, for host: String) throws {
        try set(secret.username + fieldSeparator + secret.password, for: .host(host))
    }
}
#endif  // canImport(Security)

#if canImport(Security)

/// Whether the Keychain actually accepted a write from this binary.
private let vaultProbeResult: Bool = {
    let probe = "__hfh_probe__"
    guard (try? CredentialVault.set("1", for: CredentialKey(service: "hugoforhumans.probe", account: probe))) == true else {
        return false
    }
    _ = try? CredentialVault.remove(CredentialKey(service: "hugoforhumans.probe", account: probe))
    return true
}()

#endif

#if !canImport(Security)

/// Stand-in for platforms with no system keychain.
///
/// The alternative is a file on disk, which is exactly what a secret must not be
/// stored in, and silently falling back to one would be worse than not working
/// at all. So every operation refuses, and says why. `isAvailable` lets the UI
/// explain that before the user is asked to type a password they cannot keep.
enum CredentialVault {

    typealias Key = CredentialKey
    typealias HostSecret = CredentialHostSecret

    /// No keychain exists on this platform.
    enum VaultUnavailable: LocalizedError {
        case unsupported
        var errorDescription: String? {
            "This platform has no system keychain, so credentials cannot be stored securely."
        }
    }

    static var isAvailable: Bool { false }

    static func set(_ secret: String, for key: Key) throws -> Bool { throw VaultUnavailable.unsupported }
    static func get(_ key: Key) throws -> String? { throw VaultUnavailable.unsupported }
    static func has(_ key: Key) -> Bool { false }
    static func remove(_ key: Key) throws -> Bool { false }
    static func storedAccounts() -> [(service: String, account: String)] { [] }
    static func hostSecret(for host: String) -> HostSecret? { nil }
    static func setHostSecret(_ secret: HostSecret, for host: String) throws {
        throw VaultUnavailable.unsupported
    }
}

#endif  // !canImport(Security)
