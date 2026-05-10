import Foundation
import Security

struct KeychainManager {

    private static let serviceName = "com.getbittr.bittr"

    // MARK: - Core Operations

    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Migration

    static func migrateFromUserDefaults() {
        guard !UserDefaults.standard.bool(forKey: "keychain_migration_v1") else { return }

        let defaults = UserDefaults.standard

        let mnemonicKey = EnvironmentConfig.cacheKey(for: "mnemonic")
        if let mnemonic = defaults.value(forKey: mnemonicKey) as? String {
            if save(mnemonic, forKey: mnemonicKey) {
                defaults.removeObject(forKey: mnemonicKey)
            }
        }

        let pinKey = EnvironmentConfig.cacheKey(for: "pin")
        if let pin = defaults.value(forKey: pinKey) as? String {
            if save(pin, forKey: pinKey) {
                defaults.removeObject(forKey: pinKey)
            }
        }

        migrateSwapPrivateKeys()

        defaults.set(true, forKey: "keychain_migration_v1")
    }

    private static func migrateSwapPrivateKeys() {
        if let swapDict = UserDefaults.standard.value(forKey: "ongoingswap") as? NSDictionary,
           let privateKey = swapDict["privateKey"] as? String,
           let boltzID = swapDict["boltzID"] as? String {
            let swapKeyName = "swapkey_\(boltzID)"
            if save(privateKey, forKey: swapKeyName) {
                let mutableSwap = swapDict.mutableCopy() as! NSMutableDictionary
                mutableSwap.removeObject(forKey: "privateKey")
                UserDefaults.standard.set(mutableSwap, forKey: "ongoingswap")
            }
        }

        migrateSwapFilesOnDisk()
    }

    private static func migrateSwapFilesOnDisk() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let privateKey = dict["privateKey"] as? String else { continue }

            let swapID = file.deletingPathExtension().lastPathComponent
            let swapKeyName = "swapkey_\(swapID)"
            if save(privateKey, forKey: swapKeyName) {
                var updated = dict
                updated.removeValue(forKey: "privateKey")
                if let updatedData = try? JSONSerialization.data(withJSONObject: updated, options: .prettyPrinted) {
                    try? updatedData.write(to: file)
                }
            }
        }
    }
}
