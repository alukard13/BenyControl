import Foundation
import Security

enum KeychainStore {
    private static let service = "com.example.BenyControl"
    private static let account = "charger-pin"

    static func savePIN(_ pin: String) throws {
        let data = Data(pin.utf8)
        SecItemDelete(query() as CFDictionary)
        let addQuery = query().merging([kSecValueData: data]) { _, newValue in newValue }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func loadPIN() throws -> String {
        var result: CFTypeRef?
        let lookupQuery = query().merging([
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

    private static func query() -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "No se pudo acceder al PIN seguro (\(status))." }
    }
}
