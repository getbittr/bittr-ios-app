//
//  BoltzRefund.swift
//  bittr
//
//  Created by Ruben Waterman on 20/03/2025.
//
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
    static func tryBoltzClaimInternalTransactionGeneration(swapVC:SwapViewController) async throws -> ClaimResult {
        
        if let ongoingSwap = await swapVC.coreVC?.bittrWallet.ongoingSwap {
            
            print("Found swap with invoice: \(ongoingSwap.boltzInvoice ?? "unknown")")
            
            let boltzServerPublicKeyBytes = try! ongoingSwap.refundPublicKey!.bytes
            
            let boltzServerPublicKey = try! P256K.Schnorr.PublicKey(
                dataRepresentation: boltzServerPublicKeyBytes,
                format: .compressed
            )
            
            let hexPrivateKey = try! ongoingSwap.privateKey!.bytes
            
            let ourPrivateKey = try! P256K.Schnorr.PrivateKey.init(dataRepresentation: hexPrivateKey)
            
            // Aggregate public keys without sorting
            let publicKeys = [boltzServerPublicKey, ourPrivateKey.publicKey]
            let aggregatedPublicKey = try P256K.MuSig.aggregate(publicKeys, sortKeys: false)
            
            print("\n=== AGGREGATED PUBLIC KEY ===")
            print("Aggregated public key: \(aggregatedPublicKey.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
            print("Aggregated x-only public key: \(aggregatedPublicKey.xonly.bytes.map { String(format: "%02x", $0) }.joined())")
            
            let claimLeafOutputHex = ongoingSwap.claimLeafOutput!
            let refundLeafOutputHex = ongoingSwap.refundLeafOutput!
            
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
            
            let lockupTxHex = ongoingSwap.lockupTx!
            
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
                
                let destinationAddress = ongoingSwap.destinationAddress!
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
                let swapID = ongoingSwap.boltzID!
                let ourNonceHex = firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined()
                let preimage = ongoingSwap.preimage!
                
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
            print("Could not load swap details.")
            return ClaimResult(success: false, transactionId: nil)
        }
    }
    
    static func tryBoltzRefund(swapVC:SwapViewController) async throws -> ClaimResult {
        
        if let ongoingSwap = swapVC.coreVC?.bittrWallet.ongoingSwap {
        
            print("Found swap with invoice: \(ongoingSwap.createdInvoice ?? "unknown")")
            
            let boltzServerPublicKeyBytes = try! ongoingSwap.claimPublicKey!.bytes
            
            let boltzServerPublicKey = try! P256K.Schnorr.PublicKey(
                dataRepresentation: boltzServerPublicKeyBytes,
                format: .compressed
            )
            
            let hexPrivateKey = try! ongoingSwap.privateKey!.bytes
            
            let ourPrivateKey = try! P256K.Schnorr.PrivateKey.init(dataRepresentation: hexPrivateKey)
            
            // Aggregate public keys without sorting
            let publicKeys = [boltzServerPublicKey, ourPrivateKey.publicKey]
            let aggregatedPublicKey = try P256K.MuSig.aggregate(publicKeys, sortKeys: false)
            
            print("\n=== AGGREGATED PUBLIC KEY ===")
            print("Aggregated public key: \(aggregatedPublicKey.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
            print("Aggregated x-only public key: \(aggregatedPublicKey.xonly.bytes.map { String(format: "%02x", $0) }.joined())")
            
            let claimLeafOutputHex = ongoingSwap.claimLeafOutput!
            let refundLeafOutputHex = ongoingSwap.refundLeafOutput!
            
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
            
            let lockupTxHex = ongoingSwap.lockupTx!
            
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
                
            guard let wallet = LightningNodeService.shared.getWallet() else {
                throw APIError.requestFailed("Wallet not available")
            }
            let destinationAddress = wallet.nextUnusedAddress(keychain: .external).address.description
            
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
            
            let ourNonceHex = firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined()
            print("Our nonce: \(ourNonceHex)")
            
            // Create claim request
            let refundRequest = RefundRequest(
                pubNonce: ourNonceHex,
                transaction: serializedTx.hexString,
                index: 0
            )
            
            // Post refund request to Boltz
            let claimResponse = try await requestRefundAndProcess(swapID: ongoingSwap.boltzID!, refundData: refundRequest)
            
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
        } else {
            print("Could not load swap details.")
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
