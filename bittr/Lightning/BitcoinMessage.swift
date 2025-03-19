//
//  BitcoinMessage.swift
//  bittr
//
//  Created by Ruben Waterman on 12/03/2025.
//
import Foundation
import secp256k1
import CryptoKit
import BitcoinDevKit
import LightningDevKit

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
    
    // Modify requestRefundAndProcess to be async
    static func requestRefundAndProcess(swapID: String, refundData: RefundRequest) async throws -> (String?, String?) {
        try await withCheckedThrowingContinuation { continuation in
            BoltzAPI.requestRefund(swapID: swapID, refundData: refundData) { result in
                switch result {
                case .success(let response):
                    if let error = response.error {
                        continuation.resume(throwing: APIError.requestFailed(error))
                    } else {
                        continuation.resume(returning: (response.pubNonce, response.partialSignature))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Refactor the main function to await the result of requestRefundAndProcess
    static func bla() async throws -> Bool {
        let theirPublicKeyBytes = try! "03defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5".bytes
        let theirPublicKey = try! secp256k1.Schnorr.PublicKey.init(dataRepresentation: theirPublicKeyBytes, format: .compressed)

        print("theirPublicKey: \(theirPublicKey)")

        let (privateKey, _) = try LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")

        let ourPrivateKeyBytes = try! privateKey.bytes
        let ourPrivateKey = try! secp256k1.Schnorr.PrivateKey.init(dataRepresentation: ourPrivateKeyBytes)

        let boltzAggregateKey = try secp256k1.MuSig.aggregate([theirPublicKey, ourPrivateKey.publicKey])

        print("boltzAggregateKey: \(boltzAggregateKey)")

        let tweak = try! "203f0fadc9e61e8655b8b1e4d01c17bb8996d312b8767e2782671d6cac64a92bdfad02ae04b1".bytes
        let tweakedKey = try! boltzAggregateKey.add(tweak)

        print("tweakedKey: \(tweakedKey)")

        let boltzMessage = "Vires in Numeris.".data(using: .utf8)!
        let boltzMessageHash = SHA256.hash(data: boltzMessage)

        let ourBoltzNonce = try secp256k1.MuSig.Nonce.generate(
            secretKey: ourPrivateKey,
            publicKey: ourPrivateKey.publicKey,
            msg32: Array(boltzMessageHash)
        )
        let ourBoltzNonceHex = try! ourBoltzNonce.pubnonce.serialized().hex
        print("ourBoltzNonce: \(ourBoltzNonceHex)")

        let refundData = RefundRequest(
            pubNonce: ourBoltzNonceHex,
            transaction: "020000000105cbbc4f3a54ed18ee33b880f8c3ade2c4477b44b57819e3668a474dac9a1d620100000000fdffffff01f049020000000000160014eb6251b808967906ed8e07b73786a8a1ab9ce22e00000000",
            index: 0
        )

        // Now await for the refund data from the API
        let (pubNonce, partialSignature) = try await requestRefundAndProcess(swapID: "EvZHH6byHy5G", refundData: refundData)

        if let pubNonce = pubNonce, let partialSignature = partialSignature {
            // Now you can use these values outside the original closure
            print("Received PubNonce: \(pubNonce)")
            print("Received Partial Signature: \(partialSignature)")

            do {
                let theirNonce = try secp256k1.Schnorr.Nonce(hexString: pubNonce)

                // Aggregate nonces
                let aggregatedNonce = try secp256k1.MuSig.Nonce(aggregating: [ourBoltzNonce.pubnonce, theirNonce])

                print("aggregatedNonce: \(aggregatedNonce)")
                
                let boltzTransaction = "020000000105cbbc4f3a54ed18ee33b880f8c3ade2c4477b44b57819e3668a474dac9a1d620100000000fdffffff01f049020000000000160014eb6251b808967906ed8e07b73786a8a1ab9ce22e00000000".data(using: .utf8)!
                
                // Create partial signatures
                let firstBoltzPartialSignature = try ourPrivateKey.partialSignature(
                    for: boltzTransaction,
                    pubnonce: ourBoltzNonce.pubnonce,
                    secureNonce: ourBoltzNonce.secnonce,
                    publicNonceAggregate: aggregatedNonce,
                    publicKeyAggregate: boltzAggregateKey
                )

                print("firstBoltzPartialSignature: \(firstBoltzPartialSignature)")
                
                let partialSig = try secp256k1.Schnorr.PartialSignature(
                        hexString: partialSignature,
                        session: firstBoltzPartialSignature.session
                    )
                
                print("partialSig: \(partialSig)")
                    
                // Aggregate partial signatures into a full signature
                let aggregateBoltzSignature = try secp256k1.MuSig.aggregateSignatures([firstBoltzPartialSignature, partialSig])

                // Verify the aggregate signature
//                let isOurBoltzValid = boltzAggregateKey.isValidSignature(
//                    firstBoltzPartialSignature,
//                    publicKey: ourPrivateKey.publicKey,
//                    nonce: ourBoltzNonce.pubnonce,
//                    for: boltzTransaction
//                )
//
//                print("isOurBoltzValid: \(isOurBoltzValid)")
                
                let aggregateSignatureHex = aggregateBoltzSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined()
                
                print("Aggregate Signature Hex 1: \(aggregateBoltzSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
                print("Aggregate Signature Hex 2: \(aggregateSignatureHex)")
                
                // Verify the aggregate signature
//                let isTheirBoltzValid = boltzAggregateKey.isValidSignature(
//                    partialSig,
//                    publicKey: theirPublicKey,
//                    nonce: theirNonce,
//                    for: boltzMessageHash
//                )
//
//                print("isTheirBoltzValid: \(isTheirBoltzValid)")

                // Usage example:
                let txHashHex = "621d9aac4d478a66e31978b5447b47c4e2adc3f880b833ee18ed543a4fbccb05"
                let txHashBytes = txHashHex.hexToBytes()

                // Now you can use it in BTCTransaction
                let tx = BTCTransaction()
                tx.version = 2

                // Add an input
                let input = BTCTransaction.Input(
                    previousTransactionHash: txHashBytes, // Use the converted bytes here
                    previousOutputIndex: 1,              // output index you're spending
                    script: []                           // empty script for now
                )
                input.sequence = 0xfffffffd
                tx.inputs = [input]

//                // Add witness data if needed
                tx.setWitnessForInput(
                    inputIndex: 0,
                    witness: BTCTransaction.Witness(stackElements: [aggregateBoltzSignature.bytes])
                )
                
                let address = try Address(address: "bcrt1qad39rwqgjeusdmvwq7mn0p4g5x4eec3wxwcz9d", network: .regtest)
                let script = address.scriptPubkey().toBytes()

                // Add an output
                let output = BTCTransaction.Output(
                            value: 150000,
                            script: script)
                tx.outputs = [output]

                // Get the serialized transaction
                let serializedTx = tx.serialize()
                
                // Usage example:
                let hexString = serializedTx.toHexString()
                
                print("hexString: \(hexString)")
                
                let ruben = try BitcoinDevKit.Transaction.init(transactionBytes: serializedTx)
                
                
                
                
                
            } catch {
                print("Error during nonce aggregation or signature creation: \(error)")
            }
        } else {
            print("Failed to get the data.")
        }

        return true
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

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension Array where Element == UInt8 {
    func toHexString() -> String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}

// From hex string to bytes
extension String {
    func hexToBytes() -> [UInt8] {
        var start = self.startIndex
        let bytes = stride(from: 0, to: self.count, by: 2).compactMap { _ in
            let end = self.index(start, offsetBy: 2, limitedBy: self.endIndex) ?? self.endIndex
            defer { start = end }
            return UInt8(self[start..<end], radix: 16)
        }
        // For transaction hashes, we typically want to reverse the bytes
        return Array(bytes.reversed()) // Convert ReversedCollection to Array
    }
}
