//
//  EmailCredentialStore.swift
//  PayGuard
//

import Foundation
import Security

enum EmailCredentialStoreError: LocalizedError {
    case encodeFailed
    case saveFailed(OSStatus)
    case readFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return PMLocalized("The password could not be encoded.")
        case .saveFailed(let status):
            return PMLocalized("The email password could not be saved. Status: %d", Int(status))
        case .readFailed(let status):
            return PMLocalized("The email password could not be read. Status: %d", Int(status))
        }
    }
}

enum EmailCredentialStore {
    private static let service = "PayGuard.EmailAccounts"

    static func makeKey(for accountID: UUID) -> String {
        "email-account-\(accountID.uuidString)"
    }

    static func savePassword(_ password: String, key: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw EmailCredentialStoreError.encodeFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EmailCredentialStoreError.saveFailed(status)
        }
    }

    static func password(for key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw EmailCredentialStoreError.readFailed(status)
        }
        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw EmailCredentialStoreError.encodeFailed
        }
        return password
    }

    static func deletePassword(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
