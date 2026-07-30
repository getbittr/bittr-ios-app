//
//  FileManager+Extensions.swift
//  bittr
//
//  Created by Tom Melters on 18/07/2023.
//

import Foundation

extension FileManager {
    
    // Rotates the LDK Node log before `start`: keeps the active log small and loadable in Log View, while preserving the previous session as `ldk_node_previous.log` so a crash or channel close can still be investigated after a relaunch.
    static func deleteLDKNodeLogLatestFile() throws {
        let documentsURL = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])
        let current = documentsURL.appendingPathComponent("ldk_node.log")
        guard FileManager.default.fileExists(atPath: current.path) else { return }
        let previous = documentsURL.appendingPathComponent("ldk_node_previous.log")
        try? FileManager.default.removeItem(at: previous)
        try FileManager.default.moveItem(at: current, to: previous)
    }
}
