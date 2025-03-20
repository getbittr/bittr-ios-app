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
import Musig2Bitcoin

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
        // First create a Signing.PublicKey with the compressed bytes
        let theirPublicKey = try! secp256k1.Schnorr.PublicKey(
            dataRepresentation: theirPublicKeyBytes,
            format: .compressed
        )

        let (privateKey, pubkey) = try LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")
        
        print("pubkey: \(pubkey)")

        let ourPrivateKeyBytes = try! privateKey.bytes
        let ourPrivateKey = try! secp256k1.Schnorr.PrivateKey.init(dataRepresentation: ourPrivateKeyBytes)
        
        let ourPublicKey = ourPrivateKey.publicKey.dataRepresentation.hex
        print("ourPublicKey: \(ourPublicKey)")

        let boltzAggregateKey = try secp256k1.MuSig.aggregate([theirPublicKey, ourPrivateKey.publicKey], format: secp256k1.Format.compressed)
        
        let hexString = String(bytes: boltzAggregateKey.dataRepresentation)

        print("boltzAggregateKey: \(boltzAggregateKey)")
        print("hexString: \(hexString)")

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
        
        // Cost of non-threshold signature addresses
        let prev_txs = ["010000000001018a60bf20ef3835698664ac5f1bd7babe6981078ae50433ee4e45a4f7d546353e0100000000feffffff02505a2b01000000001600140b2adca010bb166312ef5f904bbcec85f928e6beb44b02000000000022512052ecbd332c9320217667871743874992f1073f1c4f3ffa5a0602b987621ce40302473044022048a493285d7265ce980488d2b4c36b44975c0c65cb7758e44fd273ce30acf73402201b237c5d58c18d8a75303d3f873633463510228f3ddbe797d4c97fb6ba3f6b0c0121029b5348421694ce0dd0c454818211b31e6b5ea7bf7e215ddce4e7a4ed96168641be000000"];
        let txids: [String] = ["621d9aac4d478a66e31978b5447b47c4e2adc3f880b833ee18ed543a4fbccb05"];
        let input_indexs: [UInt32] = [1];
        let addresses: [String]  = ["bcrt1qad39rwqgjeusdmvwq7mn0p4g5x4eec3wxwcz9d"];
        let amounts: [UInt64] = [150_000];

        let base_tx = generateRawTx(prev_txs: prev_txs, txids: txids, input_indexs:input_indexs, addresses:addresses, amounts: amounts);
        
        print("base_tx: \(base_tx)")
        
        let unsignedTx = getUnsignedTx(tx:base_tx)
        
        print("unsignedTx: \(unsignedTx)")

        let refundData = RefundRequest(
            pubNonce: ourBoltzNonceHex,
            transaction: unsignedTx,
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
                
                let boltzRubenAggregateKey = try secp256k1.MuSig.aggregate([theirPublicKey, ourPrivateKey.publicKey], format: secp256k1.Format.uncompressed)
                
                let sighash = getSighash(tx: base_tx, txid: txids[0], input_index: input_indexs[0], agg_pubkey: boltzRubenAggregateKey.dataRepresentation.hex, sigversion: 1, proto: "");
                            
                print("current sighash:", sighash);
                
                // Create partial signatures
                let firstBoltzPartialSignature = try ourPrivateKey.partialSignature(
                    for: sighash.bytes,
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
                
                let sighashDigest = try! SHA256.hash(data: sighash.bytes)

                // Verify the aggregate signature
                let isOurBoltzValid = boltzRubenAggregateKey.isValidSignature(
                    firstBoltzPartialSignature,
                    publicKey: ourPrivateKey.publicKey,
                    nonce: ourBoltzNonce.pubnonce,
                    for: sighashDigest
                )

                print("isOurBoltzValid: \(isOurBoltzValid)")
                
                let aggregateSignatureHex = aggregateBoltzSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined()
                
                print("Aggregate Signature Hex 1: \(aggregateBoltzSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
                print("Aggregate Signature Hex 2: \(aggregateSignatureHex)")
                
//                 Verify the aggregate signature
                let isTheirBoltzValid = boltzAggregateKey.isValidSignature(
                    partialSig,
                    publicKey: theirPublicKey,
                    nonce: theirNonce,
                    for: sighashDigest
                )

                print("isTheirBoltzValid: \(isTheirBoltzValid)")

                let final_tx = buildTaprootTx(tx: base_tx, signature: aggregateSignatureHex, txid: txids[0], input_index: input_indexs[0]);
                
                print("current transaction:", final_tx);
                
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
