//
//  BitcoinMessage.swift
//  bittr
//
//  Created by Ruben Waterman on 12/03/2025.
//
import Foundation
import secp256k1
import CryptoKit

enum SegwitType {
    case p2wpkh
    case p2shP2wpkh
    case none
}

class BitcoinMessage {
    static func magicHash(message: String) -> Data {
        let messageBuffer = message.data(using: .utf8)!
        let prefixBuffer = "Bitcoin Signed Message:\n".data(using: .utf8)!
        
        let prefixLength = varintEncode(prefixBuffer.count)
        let messageLength = varintEncode(messageBuffer.count)
        
        var combined = Data()
        combined.append(prefixLength)
        combined.append(prefixBuffer)
        combined.append(messageLength)
        combined.append(messageBuffer)
        
        // Single SHA256 instead of double
        return sha256(combined)
    }
    
    static func varintEncode(_ value: Int) -> Data {
        if value < 0xfd {
            return Data([UInt8(value)])
        } else if value <= 0xffff {
            var data = Data([0xfd])
            data.append(UInt8(value & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
            return data
        } else if value <= 0xffffffff {
            var data = Data([0xfe])
            data.append(UInt8(value & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8((value >> 16) & 0xff))
            data.append(UInt8((value >> 24) & 0xff))
            return data
        } else {
            var data = Data([0xff])
            let bigValue = UInt64(value)
            for i in 0..<8 {
                data.append(UInt8((bigValue >> (i * 8)) & 0xff))
            }
            return data
        }
    }
    
    static func sha256(_ data: Data) -> Data {
        let hash = SHA256.hash(data: data)
        return Data(hash)
    }
    
    static func sign(message: String, privateKeyHex: String, segwitType: SegwitType = .none) throws -> String {
        let privateBytes = try! privateKeyHex.bytes
        let messageHash = magicHash(message: message)
        
        // Create recovery private key
        let recoveryKey = try secp256k1.Recovery.PrivateKey(dataRepresentation: privateBytes)
        
        // Create recovery signature
        let recoverySignature = try recoveryKey.signature(for: messageHash)
        let compactRep = try recoverySignature.compactRepresentation
        
        // Get recovery ID (0-3)
        var recoveryId = compactRep.recoveryId & 3
        
        print("segwitType: \(segwitType)")
        
        // Adjust recovery ID based on segwit type
        switch segwitType {
        case .p2wpkh:
            recoveryId += 8 + 4  // Add 8 for segwit and 4 for P2WPKH
        case .p2shP2wpkh:
            recoveryId += 8      // Add 8 for segwit only
        case .none:
            recoveryId += 4      // Add 4 for compressed
        }
        
        print ("Recovery ID: \(recoveryId)")
        
        // Create final signature format
        var signatureData = Data()
        signatureData.append(UInt8(27 + recoveryId))  // Base (27) + adjusted recoveryId
        signatureData.append(compactRep.signature)
        
        return signatureData.base64EncodedString()
    }
}
