//
//  StringExt.swift
//
//  Created by raidshift
//

import Foundation

extension String {
    static let base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

    var base58CheckData: Data {
        // remove leading and trailing whitespaces
        let string = trimmingCharacters(in: CharacterSet.whitespaces)

        guard !string.isEmpty else { return Data() }

        var zerosCount = 0
        var length = 0
        for c in string {
            if c != "1" { break }
            zerosCount += 1
        }

        let size = string.lengthOfBytes(using: String.Encoding.utf8) * 733 / 1000 + 1 - zerosCount
        var base58: [UInt8] = Array(repeating: 0, count: size)
        for c in string where c != " " {
            // search for base58 character
            guard let base58Index = String.base58Alphabet.firstIndex(of: c) else { return Data() }

            var carry = base58Index.utf16Offset(in: String.base58Alphabet)
            var i = 0
            for j in 0 ... base58.count where carry != 0 || i < length {
                carry += 58 * Int(base58[base58.count - j - 1])
                base58[base58.count - j - 1] = UInt8(carry % 256)
                carry /= 256
                i += 1
            }

            assert(carry == 0)
            length = i
        }

        // skip leading zeros
        var zerosToRemove = 0

        for b in base58 {
            if b != 0 { break }
            zerosToRemove += 1
        }
        base58.removeFirst(zerosToRemove)

        var result: [UInt8] = Array(repeating: 0, count: zerosCount)
        for b in base58 {
            result.append(b)
        }
        return Data(result)
    }

    var hexaToBytes: [UInt8] {
        var last = first
        return dropFirst().compactMap {
            guard
                let lastHexDigitValue = last?.hexDigitValue,
                let hexDigitValue = $0.hexDigitValue
            else {
                last = $0
                return nil
            }
            defer { last = nil }
            return UInt8(lastHexDigitValue * 16 + hexDigitValue)
        }
    }
}
