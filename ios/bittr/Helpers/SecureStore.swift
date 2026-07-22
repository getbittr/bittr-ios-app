//
//  SecureStore.swift
//  bittr
//
//  Thin wrapper over the iOS Keychain for storing sensitive values (the wallet
//  mnemonic, the app PIN, and in-flight swap refund keys). Every item shares
//  these invariants:
//
//    • …ThisDeviceOnly accessibility
//        Hardware-encrypted; NEVER included in device backups (iCloud/Finder)
//        and NEVER synced through iCloud Keychain. This is what stops a stored
//        value from ever appearing on another device or in Keychain Access on
//        a Mac (the problem the old Keychain attempt hit). `ThisDeviceOnly`
//        and `Synchronizable` are mutually exclusive.
//
//    • kSecAttrSynchronizable = false
//        Belt-and-suspenders: explicitly never iCloud-synced.
//
//    • kSecUseDataProtectionKeychain = true
//        Always use the iOS-style data-protection keychain (matters if the app
//        is ever built for Mac Catalyst — without it, items land in the
//        user-visible login keychain).
//
//  The unlock requirement differs per secret, because the app declares the
//  `fetch` and `remote-notification` background modes and genuinely runs while
//  the device is locked:
//
//    • afterFirstUnlockThisDeviceOnly — the mnemonic and swap refund keys.
//        Node start and swap processing happen in background wakes (silent
//        pushes for held HTLCs and swap status); `WhenUnlocked` would silently
//        break exactly those flows on a locked device. Readable any time after
//        the device's first unlock since boot.
//
//    • whenUnlockedThisDeviceOnly — the PIN.
//        Only ever read at the foreground unlock screen, so it keeps the
//        strictest class for free.
//
//  No biometrics / SecAccessControl are used: values are protected by the
//  device lock, which matches the app's current PIN-only UX.
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

    /// Unlock requirement for an item. Both variants are ThisDeviceOnly
    /// (never backed up, never synced) — see the header for which secret
    /// uses which and why.
    enum Accessibility {
        case whenUnlockedThisDeviceOnly
        case afterFirstUnlockThisDeviceOnly

        var attribute: CFString {
            switch self {
            case .whenUnlockedThisDeviceOnly: return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }
    }

    // MARK: - String convenience

    static func setString(_ value: String, account: String, accessibility: Accessibility = .whenUnlockedThisDeviceOnly) throws {
        try setData(Data(value.utf8), account: account, accessibility: accessibility)
    }

    static func getString(account: String) throws -> String? {
        guard let data = try getData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Data

    /// Insert or replace the item at `account`. Adds the item, and if one already
    /// exists, updates it in place. This is atomic: an existing value is only
    /// ever replaced, never removed-then-re-added — so a failed write can't leave
    /// nothing stored (which a delete-then-add could, if the add failed after the
    /// delete succeeded). The accessibility attribute is (re)applied on both the
    /// add and the update, so it never goes stale.
    static func setData(_ data: Data, account: String, accessibility: Accessibility = .whenUnlockedThisDeviceOnly) throws {
        // Identity of the item — also the search query when updating.
        let identity: [String: Any] = [
            kSecClass as String:                     kSecClassGenericPassword,
            kSecAttrService as String:               service,
            kSecAttrAccount as String:               account,
            kSecUseDataProtectionKeychain as String: true,
        ]

        var addQuery = identity
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = accessibility.attribute
        addQuery[kSecAttrSynchronizable as String] = false

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // An item already exists — replace its value in place (atomic).
            // The accessibility attribute is re-applied here too, so a
            // rewrite also migrates an item to its intended class.
            let attributes: [String: Any] = [
                kSecValueData as String:      data,
                kSecAttrAccessible as String: accessibility.attribute,
            ]
            let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SecureStoreError.unexpectedStatus(updateStatus)
            }
        default:
            throw SecureStoreError.unexpectedStatus(addStatus)
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
            kSecClass as String:                     kSecClassGenericPassword,
            kSecAttrService as String:               service,
            kSecAttrAccount as String:               account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Delete every item of ours whose account begins with `accountPrefix`
    /// (e.g. the per-swap refund keys, "swapkey_", on wallet reset). Nothing
    /// stored is not an error.
    static func removeAll(accountPrefix: String) {
        let query: [String: Any] = [
            kSecClass as String:                     kSecClassGenericPassword,
            kSecAttrService as String:               service,
            kSecReturnAttributes as String:          true,
            kSecMatchLimit as String:                kSecMatchLimitAll,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return }
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(accountPrefix) {
                remove(account: account)
            }
        }
    }
}
