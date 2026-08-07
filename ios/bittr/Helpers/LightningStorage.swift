//
//  LightningStorage.swift
//  bittr
//
//  Created by Tom Melters on 18/07/2023.
//

import Foundation
import LDKNode

struct LightningStorage {
    
    func getDocumentsDirectory() -> String {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let pathString = path.path
        return pathString
    }
    
    //  This is the directory LDK Node persists into.
    //    1. Never sync it to other devices (excludeFromBackup).
    //    2. Never allow restoring of the channel on a new device (quarantineLightningState).
    //       This is a migration for existing users, whose iCloud still holds their channel data.
    //       Trying to restore a foreign channel on a new device, would force-close the channel and potentially         lose the remaining funds.
    
    
// MARK: - Backup exclusion
    
    // The URL that houses the files.
    static var documentsURL: URL {
        URL(fileURLWithPath: LightningStorage().getDocumentsDirectory())
    }
    
    // LDK Node channel monitors and channel manager files.
    // SQLite may carry `-wal`/`-shm` siblings, hence the prefix match.
    private static let ldkStateFilePrefix = "ldk_node_data.sqlite"
    
    // Keep Documents out of every iCloud/Finder backup.
    static func excludeFromBackup() {
        setExcludedFromBackup(documentsURL)
        for file in lightningStateFiles() {
            setExcludedFromBackup(file)
        }
    }
    
    private static func setExcludedFromBackup(_ url: URL) {
        var target = url
        do {
            if try target.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true {
                // File has already been excluded from backups.
                return
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try target.setResourceValues(values)
            Log.info("Excluded \(target.lastPathComponent) from device backups.")
        } catch {
            Log.info("Could not exclude \(target.lastPathComponent) from device backups: \(error)")
        }
    }
    
    
// MARK: - Quarantine
    
    // A new URL to quarantine foreign LDK Node data.
    private static var quarantineURL: URL {
        documentsURL.appendingPathComponent("foreign_ldk_state", isDirectory: true)
    }
    
    // All currently available LDK Node channel data.
    private static func lightningStateFiles() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return contents.filter { $0.lastPathComponent.hasPrefix(ldkStateFilePrefix) }
    }
    
    // Check whether LDK Node has channel data persisted here.
    static func hasLightningState() -> Bool {
        !lightningStateFiles().isEmpty
    }
    
    // Quarantine any foreign LDK Node data (don't delete it).
    // This file is the only thing that could help sweep funds from a force-closed channel.
    static func quarantineLightningState() throws {
        let fileManager = FileManager.default
        let stateFiles = lightningStateFiles()
        
        guard !stateFiles.isEmpty else {
            // There are no LDK Node files on this device.
            return
        }
        
        if fileManager.fileExists(atPath: quarantineURL.path) {
            // Replace existing quarantined data with the latest.
            try fileManager.removeItem(at: quarantineURL)
        }
        
        // Create quarantine directory.
        try fileManager.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
        // Add all foreign LDK Node data into quarantine.
        for file in stateFiles {
            try fileManager.moveItem(at: file, to: quarantineURL.appendingPathComponent(file.lastPathComponent))
            Log.info("Quarantined Lightning state: \(file.lastPathComponent)")
        }
    }
}
