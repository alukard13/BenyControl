import Foundation
import Security

enum KeychainStore {
    private static let service = "com.example.BenyControl"
    private static let account = "charger-pin"

    static func savePIN(_ pin: String) throws {
        let data = Data(pin.utf8)
        SecItemDelete(query())
        let status = SecItemAdd(query() + [kSecValueData: data], nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    static func loadPIN() throws -> String {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query() + [kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne], &result)
        guard status != errSecItemNotFound else { return "" }
        guard status == errSecSuccess, let data = result as? Data, let pin = String(data: data, encoding: .utf8) else {
            throw KeychainError(status)
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
