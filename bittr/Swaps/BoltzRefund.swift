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
    // Environment-aware network selection
    static var network: BitcoinNetwork {
        return EnvironmentConfig.network
    }
    
    // MARK: - Fee Calculation Helper
    
    /// Calculates transaction fee using the highest priority fee rate
    /// Both claim and refund transactions are always 99 vbytes in size
    static func calculateClaimOrRefundTransactionFee() async throws -> Int {
        let feeEstimates = try LightningNodeService.shared.getEsploraClient()!.getFeeEstimates()
        let highPriorityFeeRate = feeEstimates[1]! // Highest priority fee rate
        let transactionSizeVBytes = 99 // Fixed size for claim/refund transactions
        
        let calculatedFee = Int(highPriorityFeeRate * Double(transactionSizeVBytes))
        
        return calculatedFee
    }
    
    // MARK: - Main Claim Function
    
    /// Claims a lightning-to-onchain swap by generating and broadcasting the claim transaction
    static func claimLightningToOnchainSwap(swapVC: SwapViewController) async throws -> ClaimResult {
        guard let ongoingSwap = await swapVC.coreVC?.bittrWallet.ongoingSwap else {
            print("❌ No ongoing swap found")
            return ClaimResult(success: false, transactionId: nil)
        }
        
        // Calculate claim transaction fee if not already stored
        let claimFee: Int
        if let storedFee = ongoingSwap.claimTransactionFee {
            claimFee = storedFee
        } else {
            claimFee = try await calculateClaimOrRefundTransactionFee()
            // Store the calculated fee for future use
            ongoingSwap.claimTransactionFee = claimFee
            CacheManager.saveLatestSwap(ongoingSwap)
        }
        
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
        
        let claimLeafOutputHex = ongoingSwap.claimLeafOutput!
        let refundLeafOutputHex = ongoingSwap.refundLeafOutput!
        
        let tapTweakHash = try computeTapLeafHash(
            aggregatedPublicKey: aggregatedPublicKey,
            claimLeafOutputHex: claimLeafOutputHex,
            refundLeafOutputHex: refundLeafOutputHex
        )
        
        // Apply the x-only tweak to the aggregated public key's x-only key
        // For Taproot, we need to use x-only tweaking which properly updates the key aggregation cache
        let tweakedXonlyKey = try aggregatedPublicKey.xonly.add(Array(Data(tapTweakHash)))
        
        let tweakedKeyHex = tweakedXonlyKey.bytes.map { String(format: "%02x", $0) }.joined()
        
        let lockupTxHex = ongoingSwap.lockupTx!
        
        // Calculate the correct transaction hash from the lockup transaction
        guard let txHash = calculateTransactionHash(from: lockupTxHex),
              let tweakedKey = Data(hexString: tweakedKeyHex) else {
            print("❌ Failed to parse hex data or calculate transaction hash")
            return ClaimResult(success: false, transactionId: nil)
        }
        
        if let swapOutput = detectSwap(tweakedKey: tweakedKey, transactionHex: lockupTxHex) {
            
            let destinationAddress = ongoingSwap.destinationAddress!
            
            let claimTx = constructClaimTransaction(
                swapOutput: swapOutput,
                destinationAddress: destinationAddress,
                fee: claimFee,
                txHash: txHash,
                network: network
            )
            
            let serializedTx = claimTx.serialize()
            
            let sigHash = claimTx.hashForWitnessV1(
                inputIndex: 0,
                prevoutScripts: [swapOutput.script],
                prevoutValues: [swapOutput.value]
            )
            
            let messageHashBytes = sigHash.bytes
            let messageDigest = HashDigest(messageHashBytes)
            
            // Generate nonces for each signer
            let firstNonce = try P256K.MuSig.Nonce.generate(
                secretKey: ourPrivateKey,
                publicKey: ourPrivateKey.publicKey,
                msg32: Array(messageDigest)
            )
            
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
                // Convert to P256K objects
                let externalNonce = try P256K.Schnorr.Nonce(hexString: boltzPubNonce)
                let externalPartialSignature = try P256K.Schnorr.PartialSignature(hexString: boltzPartialSignature)
                
                // Aggregate with the external nonce
                let aggregateWithExternal = try P256K.MuSig.Nonce(aggregating: [externalNonce, firstNonce.pubnonce])
                
                let firstPartialSignature = try ourPrivateKey.partialSignature(
                    for: messageDigest,
                    pubnonce: firstNonce.pubnonce,
                    secureNonce: firstNonce.secnonce,
                    publicNonceAggregate: aggregateWithExternal,
                    xonlyKeyAggregate: tweakedXonlyKey
                )
                
                let aggregateSignature = try P256K.MuSig.aggregateSignatures([externalPartialSignature, firstPartialSignature])
                
                let aggregateSignatureHex = aggregateSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined()
                
                guard let hardcodedSignature = Data(hexString: aggregateSignatureHex) else {
                    print("❌ Failed to parse signature")
                    return ClaimResult(success: false, transactionId: nil)
                }
                
                claimTx.setWitness(inputIndex: 0, witness: [hardcodedSignature])
                let finalTx = claimTx.serialize()
                
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
    
    // MARK: - Legacy Function (keeping for backward compatibility)
    
    /// Legacy function name - now calls the new production-ready function
    static func tryBoltzClaimInternalTransactionGeneration(swapVC: SwapViewController) async throws -> ClaimResult {
        return try await claimLightningToOnchainSwap(swapVC: swapVC)
    }
    
    /// Legacy function name - now calls the new production-ready function
    static func tryBoltzRefund(swapVC: SwapViewController) async throws -> ClaimResult {
        return try await refundOnchainToLightningSwap(swapVC: swapVC)
    }
    
    /// Refunds an onchain-to-lightning swap by generating and broadcasting the refund transaction
    static func refundOnchainToLightningSwap(swapVC: SwapViewController) async throws -> ClaimResult {
        guard let ongoingSwap = swapVC.coreVC?.bittrWallet.ongoingSwap else {
            print("❌ No ongoing swap found")
            return ClaimResult(success: false, transactionId: nil)
        }
            
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
            
            let claimLeafOutputHex = ongoingSwap.claimLeafOutput!
            let refundLeafOutputHex = ongoingSwap.refundLeafOutput!
            
            let tapTweakHash = try computeTapLeafHash(
                aggregatedPublicKey: aggregatedPublicKey,
                claimLeafOutputHex: claimLeafOutputHex,
                refundLeafOutputHex: refundLeafOutputHex
            )
            
            // Apply the x-only tweak to the aggregated public key's x-only key
            // For Taproot, we need to use x-only tweaking which properly updates the key aggregation cache
            let tweakedXonlyKey = try aggregatedPublicKey.xonly.add(Array(Data(tapTweakHash)))
            
            let tweakedKeyHex = tweakedXonlyKey.bytes.map { String(format: "%02x", $0) }.joined()
            
            let lockupTxHex = ongoingSwap.lockupTx!
            
            // Calculate the correct transaction hash from the lockup transaction
            guard let txHash = calculateTransactionHash(from: lockupTxHex),
                  let tweakedKey = Data(hexString: tweakedKeyHex) else {
                print("❌ Failed to parse hex data or calculate transaction hash")
                return ClaimResult(success: false, transactionId: nil)
            }
            
            if let swapOutput = detectSwap(tweakedKey: tweakedKey, transactionHex: lockupTxHex) {
                
            guard let wallet = LightningNodeService.shared.getWallet() else {
                throw APIError.requestFailed("Wallet not available")
            }
            let destinationAddress = wallet.nextUnusedAddress(keychain: .external).address.description
            
            // Calculate refund transaction fee
            let refundFee = try await calculateClaimOrRefundTransactionFee()
            
            let refundTx = constructSingleRefundTransaction(
                  swapOutput: swapOutput,              // Same output from detectSwap
                  txHash: txHash,                // Hash of lockup transaction
                  destinationAddress: destinationAddress,     // Where to send refunded funds
                  timeoutBlockHeight: 0,          // Block height when refund becomes valid
                  fee: refundFee,                  // Transaction fee in satoshis
                  network: network
              )
            
            let serializedTx = refundTx.serialize()
            
            let sigHash = refundTx.hashForWitnessV1(
                inputIndex: 0,
                prevoutScripts: [swapOutput.script],
                prevoutValues: [swapOutput.value]
            )
            
            let messageHashBytes = sigHash.bytes
            let messageDigest = HashDigest(messageHashBytes)
            
            // Generate nonces for each signer
            let firstNonce = try P256K.MuSig.Nonce.generate(
                secretKey: ourPrivateKey,
                publicKey: ourPrivateKey.publicKey,
                msg32: Array(messageDigest)
            )
            
            let ourNonceHex = firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined()
            
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
                
                let firstPartialSignature = try ourPrivateKey.partialSignature(
                    for: messageDigest,
                    pubnonce: firstNonce.pubnonce,
                    secureNonce: firstNonce.secnonce,
                    publicNonceAggregate: aggregateWithExternal,
                    xonlyKeyAggregate: tweakedXonlyKey
                )
                
                let aggregateSignature = try P256K.MuSig.aggregateSignatures([externalPartialSignature, firstPartialSignature])
                
                let aggregateSignatureHex = aggregateSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined()
                
                guard let hardcodedSignature = Data(hexString: aggregateSignatureHex) else {
                    print("❌ Failed to parse signature")
                    return ClaimResult(success: false, transactionId: nil)
                }
                
                refundTx.setWitness(inputIndex: 0, witness: [hardcodedSignature])
                let finalTx = refundTx.serialize()
                
                let broadcastResponse = try await BoltzAPI.broadcastTransaction(transactionHex: finalTx.hexString)
                if let transactionId = broadcastResponse.transactionIdValue {
                    print("✅ Transaction broadcasted successfully! TXID: \(transactionId)")
                    CacheManager.storeInvoiceDescription(hash: transactionId, desc: ongoingSwap.dateID)
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
