//
//  DerivationPath.swift
//  ChainXS
//
//  Created by raidshift
//

import Foundation

let HARDENED_KEY_TRESHOLD: UInt32 = 0x8000_0000
let regExDerivaionPath = try? NSRegularExpression(pattern: "^[mM](/[0-9]+['’‘´`hH]{0,1})*$", options: [])
let regExDerivationPathNodes = try? NSRegularExpression(pattern: "[0-9]+['’‘´`hH]{0,1}", options: [])

struct DecomposedDerivationPath {
    var pathNodeIndexes: [UInt32]
    var isPrivate: Bool = false

    func maxChildrenDerivable(atIndex: Int) -> Int {
        let pathNodeIndex = pathNodeIndexes[atIndex]

        if pathNodeIndex < HARDENED_KEY_TRESHOLD {
            return Int(HARDENED_KEY_TRESHOLD - pathNodeIndex - 1)

        } else {
            return Int(UInt32.max - pathNodeIndex)
        }
    }

    func toString() -> String {
        var str = isPrivate ? "m" : "M"

        pathNodeIndexes.forEach { i in
            if i >= HARDENED_KEY_TRESHOLD {
                str = "\(str)/\(i - HARDENED_KEY_TRESHOLD)'"
            } else {
                str = "\(str)/\(i)"
            }
        }

        return str
    }
}

func decomposeDerivationPath(_ derivationPath: String, allowZeroNodeIndexes: Bool = true, allowPrivate: Bool = true) throws -> DecomposedDerivationPath {
    var decomposedDerivationPath = DecomposedDerivationPath(pathNodeIndexes: [], isPrivate: false)

    let trimmedDervationPath = derivationPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let nsTrimmedDervationPath = trimmedDervationPath as NSString

    if regExDerivaionPath!.matches(in: trimmedDervationPath, options: [], range: NSRange(location: 0, length: nsTrimmedDervationPath.length)).count != 1 {
        throw CHAINXS_ERR.INVALID_DERIVATION_PATH
    }

    decomposedDerivationPath.isPrivate = trimmedDervationPath.first == "m"

    if decomposedDerivationPath.isPrivate, !allowPrivate { throw CHAINXS_ERR.INVALID_DERIVATION_PATH }

    decomposedDerivationPath.pathNodeIndexes = try regExDerivationPathNodes!.matches(in: trimmedDervationPath, options: [], range: NSRange(location: 0, length: nsTrimmedDervationPath.length)).map {
        let pathNodeIndexStr = nsTrimmedDervationPath.substring(with: $0.range)
        var pathNodeIndex: UInt32!

        switch pathNodeIndexStr.last {
        case "'", "’", "‘", "´", "`", "h", "H":
            pathNodeIndex = UInt32(pathNodeIndexStr.prefix(pathNodeIndexStr.count - 1))
            if !decomposedDerivationPath.isPrivate || pathNodeIndex == nil || pathNodeIndex >= HARDENED_KEY_TRESHOLD { throw CHAINXS_ERR.INVALID_DERIVATION_PATH } else { pathNodeIndex += HARDENED_KEY_TRESHOLD }
        default:
            pathNodeIndex = UInt32(pathNodeIndexStr)
            if pathNodeIndex == nil || pathNodeIndex >= HARDENED_KEY_TRESHOLD { throw CHAINXS_ERR.INVALID_DERIVATION_PATH }
        }
        return (pathNodeIndex)
    }

    if !allowZeroNodeIndexes, decomposedDerivationPath.pathNodeIndexes.count < 1 { throw CHAINXS_ERR.INVALID_DERIVATION_PATH }

    return decomposedDerivationPath
}
