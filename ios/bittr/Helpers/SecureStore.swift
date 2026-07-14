//
//  SecureStore.swift
//  bittr
//
//  Thin wrapper over the iOS Keychain for storing sensitive values (the wallet
//  mnemonic and the app PIN). Every item is written with:
//
//    • kSecAttrAccessibleWhenUnlockedThisDeviceOnly
//        Hardware-encrypted; readable only while the device is unlocked, and —
//        crucially — NEVER included in device backups (iCloud/Finder) and NEVER
//        synced through iCloud Keychain. This is the attribute that stops a
//        stored value from ever appearing on another device or in Keychain
//        Access on a Mac (the problem the old Keychain attempt hit). It also
//        can't leave the device: `ThisDeviceOnly` and `Synchronizable` are
//        mutually exclusive.
//
//    • kSecAttrSynchronizable = false
//        Belt-and-suspenders: explicitly never iCloud-synced.
//
//    • kSecUseDataProtectionKeychain = true
//        Always use the iOS-style data-protection keychain (matters if the app
//        is ever built for Mac Catalyst — without it, items land in the
//        user-visible login keychain).
//
//  No biometrics / SecAccessControl are used: values are protected by the
//  device lock, which matches the app's current PIN-only UX. The seed is only
//  ever read in the foreground with the device unlocked, so
//  `WhenUnlockedThisDeviceOnly` never blocks a legitimate read.
//

import Foundation
import Security

enum SecureStore {

    /// Scopes all items to this app. Using the (per-environment) bundle id also
    /// keeps regtest / signet / mainnet builds isolated from one another.
    private static let service = Bundle.main.bundleIdentifier ?? "com.bittr.bittr"

    enum SecureStoreError: Error {
        case unexpectedStatus(OSStatus)
        case writeVerificationFailed
    }

    // MARK: - String convenience

    static func setString(_ value: String, account: String) throws {
        try setData(Data(value.utf8), account: account)
    }

    static func getString(account: String) throws -> String? {
        guard let data = try getData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Data

    /// Insert or replace the item at `account`. Any existing item is removed
    /// first so the accessibility attributes are always applied cleanly (a bare
    /// `SecItemUpdate` would leave stale attributes in place).
    static func setData(_ data: Data, account: String) throws {
        remove(account: account)

        let query: [String: Any] = [
            kSecClass as String:                     kSecClassGenericPassword,
            kSecAttrService as String:               service,
            kSecAttrAccount as String:               account,
            kSecValueData as String:                 data,
            kSecAttrAccessible as String:            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String:        false,
            kSecUseDataProtectionKeychain as String: true,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    static func getData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String:                     kSecClassGenericPassword,
            kSecAttrService as String:               service,
            kSecAttrAccount as String:               account,
            kSecReturnData as String:                true,
            kSecMatchLimit as String:                kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    /// Delete the item. A no-op (and success) when nothing is stored.
    @discardableResult
    static func remove(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
