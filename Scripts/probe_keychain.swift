import Foundation
import Security

// Probe: can a CLT-built tool use the login Keychain at all?
let service = "hfh-probe"
let account = "probe"

// Clean any previous run.
SecItemDelete([
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
] as CFDictionary)

let add: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecValueData as String: "secret-value".data(using: .utf8)!,
]
let addStatus = SecItemAdd(add as CFDictionary, nil)
print("SecItemAdd status: \(addStatus)")

var query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne,
]
var item: CFTypeRef?
let readStatus = SecItemCopyMatching(query as CFDictionary, &item)
print("SecItemCopyMatching status: \(readStatus)")
if readStatus != errSecSuccess {
    let msg = SecCopyErrorMessageString(readStatus, nil) as String? ?? "?"
    print("  message: \(msg)")
    print("  (-25300 = interaction not allowed; -34018 = missing entitlement)")
}
if let data = item as? Data {
    print("read back: \(String(decoding: data, as: UTF8.self))")
} else {
    print("read back: nothing")
}

SecItemDelete([
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
] as CFDictionary)
print("cleaned up")
