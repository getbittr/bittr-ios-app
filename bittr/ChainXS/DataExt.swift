//
//  DataExt.swift
//
//  Created by raidshift
//

import Foundation

enum DATA_ERR: Error {
    case CORE_RND
    case FORMAT_BASE64
    case BITS_CONVERSION
}

let DATA_ERR_TEXT_FORMAT_BASE64 = "Input data is not base64 encoded"
let DATA_ERR_CORE_RND = "Invoking random number generator failed"
let DATA_ERR_BITS_CONVERSION = "Failed to perform bits conversion"

extension DATA_ERR: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .CORE_RND:
            return NSLocalizedString(DATA_ERR_CORE_RND, comment: DATA_ERR_CORE_RND)
        case .FORMAT_BASE64:
            return NSLocalizedString(DATA_ERR_TEXT_FORMAT_BASE64, comment: DATA_ERR_TEXT_FORMAT_BASE64)
        case .BITS_CONVERSION:
            return NSLocalizedString(DATA_ERR_TEXT_FORMAT_BASE64, comment: DATA_ERR_TEXT_FORMAT_BASE64)
        }
    }
}

extension Data {
    public init(randomOfLength count: Int) throws {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != 0 { throw DATA_ERR.CORE_RND }
        self.init(bytes)
    }

    var hexString: String {
        return map { byte in String(format: "%02x", byte) }.joined()
    }

    var base58CheckString: String {
        var bytes = [UInt8](self)
        var zerosCount = 0
        var length = 0

        for b in bytes {
            if b != 0 { break }
            zerosCount += 1
        }

        bytes.removeFirst(zerosCount)

        let size = bytes.count * 138 / 100 + 1

        var base58: [UInt8] = Array(repeating: 0, count: size)
        for b in bytes {
            var carry = Int(b)
            var i = 0

            for j in 0 ... base58.count - 1 where carry != 0 || i < length {
                carry += 256 * Int(base58[base58.count - j - 1])
                base58[base58.count - j - 1] = UInt8(carry % 58)
                carry /= 58
                i += 1
            }

            assert(carry == 0)

            length = i
        }

        // skip leading zeros
        var zerosToRemove = 0
        var str = ""
        for b in base58 {
            if b != 0 { break }
            zerosToRemove += 1
        }
        base58.removeFirst(zerosToRemove)

        while zerosCount > 0 {
            str = "\(str)1"
            zerosCount -= 1
        }

        for b in base58 {
            str = "\(str)\(String.base58Alphabet[String.Index(utf16Offset: Int(b), in: String.base58Alphabet)])"
        }

        return str
    }

    var left: Data {
        return subdata(in: 0 ..< count / 2)
    }

    var right: Data {
        return subdata(in: count / 2 ..< count)
    }

    func convertBits(from: Int, to: Int, pad: Bool) throws -> Data {
        var acc = 0
        var bits = 0
        let maxv: Int = (1 << to) - 1
        let maxAcc: Int = (1 << (from + to - 1)) - 1
        var odata = Data()
        for ibyte in self {
            acc = ((acc << from) | Int(ibyte)) & maxAcc
            bits += from
            while bits >= to {
                bits -= to
                odata.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits != 0 {
                odata.append(UInt8((acc << (to - bits)) & maxv))
            }
        } else if bits >= from || ((acc << (to - bits)) & maxv) != 0 {
            throw DATA_ERR.BITS_CONVERSION
        }
        return odata
    }
}
