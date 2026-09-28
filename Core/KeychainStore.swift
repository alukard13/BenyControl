import Foundation
import Security

enum KeychainStore {
    private static let service = "com.example.BenyControl"
    private static let legacyAccount = "charger-pin"

    static func savePIN(_ pin: String) throws {
        try savePIN(pin, account: legacyAccount)
    }

    static func savePIN(_ pin: String, for chargerID: UUID) throws {
        try savePIN(pin, account: account(for: chargerID))
    }

    static func loadPIN() throws -> String {
        try loadPIN(account: legacyAccount)
    }

    static func loadPIN(for chargerID: UUID) throws -> String {
        try loadPIN(account: account(for: chargerID))
    }

    static func deletePIN(for chargerID: UUID) throws {
        let status = SecItemDelete(query(account: account(for: chargerID)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private static func savePIN(_ pin: String, account: String) throws {
        let data = Data(pin.utf8)
        SecItemDelete(query(account: account) as CFDictionary)
        let addQuery = query(account: account).merging([kSecValueData: data]) { _, newValue in newValue }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private static func loadPIN(account: String) throws -> String {
        var result: CFTypeRef?
        let lookupQuery = query(account: account).merging([
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]) { _, newValue in newValue }
        let status = SecItemCopyMatching(lookupQuery as CFDictionary, &result)
        guard status != errSecItemNotFound else { return "" }
        guard status == errSecSuccess, let data = result as? Data, let pin = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: status)
        }
        return pin
    }

    private static func account(for chargerID: UUID) -> String {
        "charger-pin-\(chargerID.uuidString)"
    }

    private static func query(account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "No se pudo acceder al PIN seguro (\(status))." }
    }
}
