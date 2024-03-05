//
//  LightningStorage.swift
//  bittr
//
//  Created by Tom Melters on 18/07/2023.
//

import Foundation
import LDKNode
import LDKNodeFFI

struct LightningStorage {
    func getDocumentsDirectory() -> String {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let pathString = path.path
        //print("Path string: " + pathString)
        return pathString
    }
}
