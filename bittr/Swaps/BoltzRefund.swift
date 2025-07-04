//
//  BoltzRefund.swift
//  bittr
//
//  Created by Ruben Waterman on 20/03/2025.
//
import Musig2Bitcoin
import P256K
import Foundation
import CryptoKit
import BitcoinDevKit

// MARK: - Claim Result

struct ClaimResult {
    let success: Bool
    let transactionId: String?
}

// MARK: - API Models

class BoltzRefund {
    static func tryBoltzClaimInternalTransactionGeneration(swapId: String) async throws -> ClaimResult {
        if let swapDetails = SwapManager.loadSwapDetailsFromFile(swapID: swapId) {
            print("Found swap with invoice: \(swapDetails["invoice"] ?? "unknown")")
            
            let boltzServerPublicKeyBytes = try! (swapDetails["refundPublicKey"] as! String).bytes
            
            let boltzServerPublicKey = try! P256K.Schnorr.PublicKey(
                dataRepresentation: boltzServerPublicKeyBytes,
                format: .compressed
            )
            
            let hexPrivateKey = try! (swapDetails["privateKey"] as! String).bytes
            
            let ourPrivateKey = try! P256K.Schnorr.PrivateKey.init(dataRepresentation: hexPrivateKey)
            
            // Aggregate public keys without sorting
            let publicKeys = [boltzServerPublicKey, ourPrivateKey.publicKey]
            let aggregatedPublicKey = try P256K.MuSig.aggregate(publicKeys, sortKeys: false)
            
            print("\n=== AGGREGATED PUBLIC KEY ===")
            print("Aggregated public key: \(aggregatedPublicKey.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
            print("Aggregated x-only public key: \(aggregatedPublicKey.xonly.bytes.map { String(format: "%02x", $0) }.joined())")
            
            let claimLeafOutputHex = ((swapDetails["swapTree"] as! NSDictionary)["claimLeaf"] as! NSDictionary)["output"] as! String
            let refundLeafOutputHex = ((swapDetails["swapTree"] as! NSDictionary)["refundLeaf"] as! NSDictionary)["output"] as! String
            
            
            let tapTweakHash = try computeTapLeafHash(
                aggregatedPublicKey: aggregatedPublicKey,
                claimLeafOutputHex: claimLeafOutputHex,
                refundLeafOutputHex: refundLeafOutputHex
            )
            
            print("\n=== TAPROOT TWEAK COMPUTATION ===")
            print("Tap tweak hash: \(Data(tapTweakHash).map { String(format: "%02x", $0) }.joined())")
            
            // Apply the x-only tweak to the aggregated public key's x-only key
            // For Taproot, we need to use x-only tweaking which properly updates the key aggregation cache
            let tweakedXonlyKey = try aggregatedPublicKey.xonly.add(Array(Data(tapTweakHash)))
            
            // Create a new MuSig public key from the tweaked x-only key (preserves the cache)
            let tweakedAggregatedKey = try aggregatedPublicKey.add(Array(Data(tapTweakHash)))
            
            let tweakedKeyHex = tweakedXonlyKey.bytes.map { String(format: "%02x", $0) }.joined()
            
            print("\n=== TWEAKED PUBLIC KEY ===")
            print("Tweaked x-only public key: \(tweakedKeyHex)")
            
            let lockupTxHex = (swapDetails["lockupTx"] as! String)
            
            // Calculate the correct transaction hash from the lockup transaction
            guard let txHash = calculateTransactionHash(from: lockupTxHex),
                  let tweakedKey = Data(hexString: tweakedKeyHex) else {
                print("❌ Failed to parse hex data or calculate transaction hash")
                return ClaimResult(success: false, transactionId: nil)
            }
            
            print("   txHash TX: \(txHash.hexString)")
            
            if let swapOutput = detectSwap(tweakedKey: tweakedKey, transactionHex: lockupTxHex) {
                print("Found swap output:")
                print("Value: \(swapOutput.value)")
                print("Script: \(swapOutput.script.hexString)")
                print("Vout: \(swapOutput.vout)")
                
                let destinationAddress = (swapDetails["destinationAddress"] as! String)
                let exactFee = 200
                
                let claimTx = constructClaimTransaction(
                    swapOutput: swapOutput,
                    destinationAddress: destinationAddress,
                    fee: exactFee,
                    txHash: txHash,
                    network: .regtest
                )
                
                let serializedTx = claimTx.serialize()
                
                print("   Generated TX: \(serializedTx.hexString)")
                
                let sigHash = claimTx.hashForWitnessV1(
                    inputIndex: 0,
                    prevoutScripts: [swapOutput.script],
                    prevoutValues: [swapOutput.value]
                )
                
                print("   ✅ SigHash calculation: \(sigHash.hexString)")
                
                let messageHashBytes = sigHash.bytes
                let messageDigest = HashDigest(messageHashBytes)
                
                // Generate nonces for each signer
                let firstNonce = try P256K.MuSig.Nonce.generate(
                    secretKey: ourPrivateKey,
                    publicKey: ourPrivateKey.publicKey,
                    msg32: Array(messageDigest)
                )
                
                print("Our nonce: \(firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined())")
                
                // Hardcoded values for testing
                let swapID = (swapDetails["id"] as! String)
                let ourNonceHex = firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined()
                let preimage = (swapDetails["preimage"] as! String)
                
                // Create claim request
                let claimRequest = ClaimRequest(
                    index: 0,
                    transaction: serializedTx.hexString,
                    preimage: preimage,
                    pubNonce: ourNonceHex
                )
                
                // Post claim request to Boltz
                let claimResponse = try await requestClaimAndProcess(swapID: swapID, claimData: claimRequest)
                
                if let boltzPubNonce = claimResponse.pubNonce, let boltzPartialSignature = claimResponse.partialSignature {
                    print("Received Boltz pubNonce: \(boltzPubNonce)")
                    print("Received Boltz partialSignature: \(boltzPartialSignature)")
                    
                    // Convert to P256K objects
                    let externalNonce = try P256K.Schnorr.Nonce(hexString: boltzPubNonce)
                    let externalPartialSignature = try P256K.Schnorr.PartialSignature(hexString: boltzPartialSignature)
                    
                    // Aggregate with the external nonce
                    let aggregateWithExternal = try P256K.MuSig.Nonce(aggregating: [externalNonce, firstNonce.pubnonce])
                    
                    print("\n=== NONCES ===")
                    print("First Public Nonce: \(firstNonce.hexString)")
                    print("External Nonce: \(externalNonce.hexString)")
                    print("Aggregate with External: \(aggregateWithExternal.hexString)")
                    
                    let firstPartialSignature = try ourPrivateKey.partialSignature(
                        for: messageDigest,
                        pubnonce: firstNonce.pubnonce,
                        secureNonce: firstNonce.secnonce,
                        publicNonceAggregate: aggregateWithExternal,
                        publicKeyAggregate: tweakedAggregatedKey
                    )
                    
                    print("\n=== PARTIAL SIGNATURES ===")
                    print("First Partial Signature: \(firstPartialSignature.dataRepresentation.bytes.map { String(format: "%02x", $0) }.joined())")
                    print("External Partial Signature: \(externalPartialSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
                    
                    let aggregateSignature = try P256K.MuSig.aggregateSignatures([externalPartialSignature, firstPartialSignature])
                    
                    let aggregateSignatureHex = aggregateSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined()
                    
                    print("Aggregate Signature: \(aggregateSignatureHex)")
                    
                    guard let hardcodedSignature = Data(hexString: aggregateSignatureHex) else {
                        print("❌ Failed to parse signature")
                        return ClaimResult(success: false, transactionId: nil)
                    }
                    
                    claimTx.setWitness(inputIndex: 0, witness: [hardcodedSignature])
                    let finalTx = claimTx.serialize()
                    
                    print("   Generated Final TX: \(finalTx.hexString)")
                    
                    let broadcastResponse = try await BoltzAPI.broadcastTransaction(transactionHex: finalTx.hexString)
                    if let transactionId = broadcastResponse.transactionIdValue {
                        print("✅ Transaction broadcasted successfully! TXID: \(transactionId)")
                        return ClaimResult(success: true, transactionId: transactionId)
                    } else {
                        print("❌ Failed to broadcast transaction")
                        return ClaimResult(success: false, transactionId: nil)
                    }
                } else {
                    print("Failed to get claim response from Boltz")
                    return ClaimResult(success: false, transactionId: nil)
                }
            } else {
                print("No swap output found")
                return ClaimResult(success: false, transactionId: nil)
            }
        } else {
            print("Could not load swap details for ID: \(swapId)")
            return ClaimResult(success: false, transactionId: nil)
        }
    }
    
    static func tryBoltzRefund() async throws -> ClaimResult {
        // This is the public key we got when we made the API call:
        //        {
        //          "bip21": "bitcoin:bcrt1p9m2c5ug3rmyp69y7vzh32dwunlv44ch3scx8p5cktuz99udzjawq45cpsc?amount=0.01501802&label=Send%20to%20BTC%20lightning",
        //          "acceptZeroConf": false,
        //          "expectedAmount": 1501802,
        //          "id": "MPCqNHh5z34t",
        //          "address": "bcrt1p9m2c5ug3rmyp69y7vzh32dwunlv44ch3scx8p5cktuz99udzjawq45cpsc",
        //          "swapTree": {
        //            "claimLeaf": {
        //              "version": 192,
        //              "output": "a914c93255668e1dd9ee4f94f1f5a284b19a1e3fe2478820e14103ecaee2281355ed8b981f5a2916a3857100f38fa77d4ff80509f823cb12ac"
        //            },
        //            "refundLeaf": {
        //              "version": 192,
        //              "output": "2035c61bbbd4a2c348d64d3c060abdce8249d44c09e20b2d8f0c077a5ee7e3dac8ad02d704b1"
        //            }
        //          },
        //          "claimPublicKey": "03e14103ecaee2281355ed8b981f5a2916a3857100f38fa77d4ff80509f823cb12",
        //          "timeoutBlockHeight": 1239
        //        }
        let boltzServerPublicKeyBytes = try! "03e14103ecaee2281355ed8b981f5a2916a3857100f38fa77d4ff80509f823cb12".bytes
        
        let boltzServerPublicKey = try! P256K.Schnorr.PublicKey(
            dataRepresentation: boltzServerPublicKeyBytes,
            format: .compressed
        )
        
        // When we created the Swap, we used a private/public key pair from our existing wallet (in production, we should use some funny path not to mix keys)
        // hexPrivateKey: c5c8c3cac9b6c5544f0424849b1387d4868925821f2b39599c3396ccef128436
        // hexPublicKey: 02b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dc
        let (hexPrivateKey, _hexPublicKey) = try LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")
        
        // In order to aggregate the keys, I re-initialize the same key using P256K.Schnorr.PrivateKey.init but the public/private key still looks the same
        let ourPrivateKeyBytes = try! hexPrivateKey.bytes
        let ourPrivateKey = try! P256K.Schnorr.PrivateKey.init(dataRepresentation: ourPrivateKeyBytes)
        
        // For some reason, when I want to later on use the getSighash function, that only accepts uncompressed keys, so we're using that as the format here already
        // Aggregate public keys without sorting
        let publicKeys = [boltzServerPublicKey, ourPrivateKey.publicKey]
        let aggregatedPublicKey = try P256K.MuSig.aggregate(publicKeys, sortKeys: false)
        
        print("\n=== AGGREGATED PUBLIC KEY ===")
        print("Aggregated public key: \(aggregatedPublicKey.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
        print("Aggregated x-only public key: \(aggregatedPublicKey.xonly.bytes.map { String(format: "%02x", $0) }.joined())")
        
        let claimLeafOutputHex = "a914c93255668e1dd9ee4f94f1f5a284b19a1e3fe2478820e14103ecaee2281355ed8b981f5a2916a3857100f38fa77d4ff80509f823cb12ac"
        let refundLeafOutputHex = "2035c61bbbd4a2c348d64d3c060abdce8249d44c09e20b2d8f0c077a5ee7e3dac8ad02d704b1"
        
        let tapTweakHash = try computeTapLeafHash(
            aggregatedPublicKey: aggregatedPublicKey,
            claimLeafOutputHex: claimLeafOutputHex,
            refundLeafOutputHex: refundLeafOutputHex
        )
        
        print("\n=== TAPROOT TWEAK COMPUTATION ===")
        print("Tap tweak hash: \(Data(tapTweakHash).map { String(format: "%02x", $0) }.joined())")
        
        // Apply the x-only tweak to the aggregated public key's x-only key
        // For Taproot, we need to use x-only tweaking which properly updates the key aggregation cache
        let tweakedXonlyKey = try aggregatedPublicKey.xonly.add(Array(Data(tapTweakHash)))
        
        // Create a new MuSig public key from the tweaked x-only key (preserves the cache)
        let tweakedAggregatedKey = try aggregatedPublicKey.add(Array(Data(tapTweakHash)))
        
        let tweakedKeyHex = tweakedXonlyKey.bytes.map { String(format: "%02x", $0) }.joined()
        
        print("\n=== TWEAKED PUBLIC KEY ===")
        print("Tweaked x-only public key: \(tweakedKeyHex)")
        
        let lockupTxHex = "010000000001025db76eea327d62490d7602347260c9700036626d5da4432d998d8524770a816b0000000000feffffff74e35b159a7a68254e5030f384702fdf42e109d0713fa6bed2d895e7c7b5885c0000000000feffffff02b79aa800000000001600143a8c33ece9ee68f8184812d1972fb597a794dfbc6aea1600000000002251202ed58a71111ec81d149e60af1535dc9fd95ae2f1860c70d3165f0452f1a2975c02473044022066147339fa3363631b0b93c35370105fca990bcc2f0619452de9978a805a8efb022073c00325219baf0abf4d61931d7224b5c3f92c49e40aa4ac0915aa7a0d852cc601210372a8fc2ea03fa4ec2722f70b387d0d7b7ffaec98103d25757dd7b32d94ff535802473044022058e4495e31bf588ea8f1dbbdbcb3691ee76b014c57ddb5d76cfda542db7c5fc00220163925ea3810d6327e12661fb5ec39fcf3ddeb5ca0b17a40b9767e2c30c9f926012102a0ab06e19e43c283b65ebe09c1b49f4a3748cbf6f60f13abdaad5166fc755225e7000000"
        
        // Calculate the correct transaction hash from the lockup transaction
        guard let txHash = calculateTransactionHash(from: lockupTxHex),
              let tweakedKey = Data(hexString: tweakedKeyHex) else {
            print("❌ Failed to parse hex data or calculate transaction hash")
            return ClaimResult(success: false, transactionId: nil)
        }
        
        print("   txHash TX: \(txHash.hexString)")
        
        if let swapOutput = detectSwap(tweakedKey: tweakedKey, transactionHex: lockupTxHex) {
            print("Found swap output:")
            print("Value: \(swapOutput.value)")
            print("Script: \(swapOutput.script.hexString)")
            print("Vout: \(swapOutput.vout)")
            
            let destinationAddress = "bcrt1qekjssnr0rahwxtk0jaeth9x5gyavec7pgkgugh"
            let exactFee = 200
            
            let refundTx = constructSingleRefundTransaction(
                  swapOutput: swapOutput,              // Same output from detectSwap
                  txHash: txHash,                // Hash of lockup transaction
                  destinationAddress: destinationAddress,     // Where to send refunded funds
                  timeoutBlockHeight: 0,          // Block height when refund becomes valid
                  fee: exactFee                             // Transaction fee in satoshis
              )
            
            let serializedTx = refundTx.serialize()
            
            print("   Generated TX: \(serializedTx.hexString)")
            
            let sigHash = refundTx.hashForWitnessV1(
                inputIndex: 0,
                prevoutScripts: [swapOutput.script],
                prevoutValues: [swapOutput.value]
            )
            
            print("   ✅ SigHash calculation: \(sigHash.hexString)")
            
            let messageHashBytes = sigHash.bytes
            let messageDigest = HashDigest(messageHashBytes)
            
            // Generate nonces for each signer
            let firstNonce = try P256K.MuSig.Nonce.generate(
                secretKey: ourPrivateKey,
                publicKey: ourPrivateKey.publicKey,
                msg32: Array(messageDigest)
            )
            
            print("Our nonce: \(firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined())")
            
            // Hardcoded values for testing
//            let swapID = (swapDetails["id"] as! String)
            let swapId = "MPCqNHh5z34t"
            let ourNonceHex = firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined()
            
            // Create claim request
            let refundRequest = RefundRequest(
                pubNonce: ourNonceHex,
                transaction: serializedTx.hexString,
                index: 0
            )
            
            // Post claim request to Boltz
            let claimResponse = try await requestRefundAndProcess(swapID: swapId, refundData: refundRequest)
            
            if let boltzPubNonce = claimResponse.pubNonce, let boltzPartialSignature = claimResponse.partialSignature {
                print("Received Boltz pubNonce: \(boltzPubNonce)")
                print("Received Boltz partialSignature: \(boltzPartialSignature)")
                
                // Convert to P256K objects
                let externalNonce = try P256K.Schnorr.Nonce(hexString: boltzPubNonce)
                let externalPartialSignature = try P256K.Schnorr.PartialSignature(hexString: boltzPartialSignature)
                
                // Aggregate with the external nonce
                let aggregateWithExternal = try P256K.MuSig.Nonce(aggregating: [externalNonce, firstNonce.pubnonce])
                
                print("\n=== NONCES ===")
                print("First Public Nonce: \(firstNonce.hexString)")
                print("External Nonce: \(externalNonce.hexString)")
                print("Aggregate with External: \(aggregateWithExternal.hexString)")
                
                let firstPartialSignature = try ourPrivateKey.partialSignature(
                    for: messageDigest,
                    pubnonce: firstNonce.pubnonce,
                    secureNonce: firstNonce.secnonce,
                    publicNonceAggregate: aggregateWithExternal,
                    publicKeyAggregate: tweakedAggregatedKey
                )
                
                print("\n=== PARTIAL SIGNATURES ===")
                print("First Partial Signature: \(firstPartialSignature.dataRepresentation.bytes.map { String(format: "%02x", $0) }.joined())")
                print("External Partial Signature: \(externalPartialSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
                
                let aggregateSignature = try P256K.MuSig.aggregateSignatures([externalPartialSignature, firstPartialSignature])
                
                let aggregateSignatureHex = aggregateSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined()
                
                print("Aggregate Signature: \(aggregateSignatureHex)")
                
                guard let hardcodedSignature = Data(hexString: aggregateSignatureHex) else {
                    print("❌ Failed to parse signature")
                    return ClaimResult(success: false, transactionId: nil)
                }
                
                refundTx.setWitness(inputIndex: 0, witness: [hardcodedSignature])
                let finalTx = refundTx.serialize()
                
                print("   Generated Final TX: \(finalTx.hexString)")
                
                let broadcastResponse = try await BoltzAPI.broadcastTransaction(transactionHex: finalTx.hexString)
                if let transactionId = broadcastResponse.transactionIdValue {
                    print("✅ Transaction broadcasted successfully! TXID: \(transactionId)")
                    return ClaimResult(success: true, transactionId: transactionId)
                } else {
                    print("❌ Failed to broadcast transaction")
                    return ClaimResult(success: false, transactionId: nil)
                }
            } else {
                print("Failed to get claim response from Boltz")
                return ClaimResult(success: false, transactionId: nil)
            }
        } else {
            print("No swap output found")
            return ClaimResult(success: false, transactionId: nil)
        }
    }
    
    static func requestRefundAndProcess(swapID: String, refundData: RefundRequest) async throws -> RefundResponse {
        try await withCheckedThrowingContinuation { continuation in
            BoltzAPI.requestRefund(swapID: swapID, refundData: refundData) { result in
                switch result {
                case .success(let response):
                    if let error = response.error {
                        continuation.resume(throwing: APIError.requestFailed(error))
                    } else {
                        continuation.resume(returning: response)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    static func requestClaimAndProcess(swapID: String, claimData: ClaimRequest) async throws -> ClaimResponse {
        try await withCheckedThrowingContinuation { continuation in
            BoltzAPI.requestClaim(swapID: swapID, claimData: claimData) { result in
                switch result {
                case .success(let response):
                    if let error = response.error {
                        continuation.resume(throwing: APIError.requestFailed(error))
                    } else {
                        continuation.resume(returning: response)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
