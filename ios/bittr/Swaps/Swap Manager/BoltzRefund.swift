//
//  BoltzRefund.swift
//  bittr
//
//  Created by Ruben Waterman on 20/03/2025.
//
import P256K
import Foundation
import CryptoKit
import LightningDevKit

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
    
    // Both claim and refund transactions are always this size.
    static let claimOrRefundTransactionVBytes: Double = 99
    
    // Calculates transaction fee using the highest priority fee rate
    static func calculateClaimOrRefundTransactionFee() async throws -> Int {
        guard let feeEstimates = await BitcoinManager.shared.getFeeEstimates() else {
            throw BoltzAPIError.requestFailed("Could not fetch fee estimates for the claim/refund transaction.")
        }
        let calculatedFee = Int(feeEstimates.fastest * claimOrRefundTransactionVBytes)
        
        return calculatedFee
    }
    
    // MARK: - Main Claim Function
    
    /// Claims a lightning-to-onchain swap by generating and broadcasting the claim transaction
    static func claimLightningToOnchainSwap(swapVC: SwapStatusViewController) async throws -> ClaimResult {
        guard let ongoingSwap = await swapVC.thisSwap else {
            Log.info("❌ No ongoing swap found")
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
            swapVC.thisSwap = ongoingSwap
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
            Log.info("❌ Failed to parse hex data or calculate transaction hash")
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
            
            let messageHashBytes = Array(sigHash)
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
                    Log.info("❌ Failed to parse signature")
                    return ClaimResult(success: false, transactionId: nil)
                }
                
                claimTx.setWitness(inputIndex: 0, witness: [hardcodedSignature])
                let finalTx = claimTx.serialize()
                
                let broadcastResponse = try await BoltzAPI.broadcastTransaction(transactionHex: finalTx.hexString)
                if let transactionId = broadcastResponse.transactionIdValue {
                    Log.info("Transaction broadcast succeeded. TXID: \(transactionId)")
                    return ClaimResult(success: true, transactionId: transactionId)
                } else {
                    Log.info("❌ Failed to broadcast transaction")
                    return ClaimResult(success: false, transactionId: nil)
                }
            } else {
                Log.info("Failed to get claim response from Boltz")
                return ClaimResult(success: false, transactionId: nil)
            }
        } else {
            Log.info("No swap output found")
            return ClaimResult(success: false, transactionId: nil)
        }
    }
    
    // MARK: - Legacy Function (keeping for backward compatibility)
    
    /// Legacy function name - now calls the new production-ready function
    static func tryBoltzClaimInternalTransactionGeneration(swapVC: SwapStatusViewController) async throws -> ClaimResult {
        return try await claimLightningToOnchainSwap(swapVC: swapVC)
    }
    
    /// Legacy function name - now calls the new production-ready function
    static func tryBoltzRefund(swapVC: SwapStatusViewController) async throws -> ClaimResult {
        return try await refundOnchainToLightningSwap(swapVC: swapVC)
    }
    
    /// Refunds an onchain-to-lightning swap by generating and broadcasting the refund transaction
    static func refundOnchainToLightningSwap(swapVC: SwapStatusViewController) async throws -> ClaimResult {
        guard let ongoingSwap = swapVC.thisSwap else {
            Log.info("❌ No ongoing swap found")
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
            Log.info("❌ Failed to parse hex data or calculate transaction hash")
            return ClaimResult(success: false, transactionId: nil)
        }
            
        if let swapOutput = detectSwap(tweakedKey: tweakedKey, transactionHex: lockupTxHex) {
                
            guard let destinationAddress = BitcoinManager.shared.bittrWallet.onchainAddresses?.getNextUnusedAddress() ?? BitcoinManager.shared.getAddress(atIndex: 0) else {
                Log.info("No destination address available for the refund.")
                return ClaimResult(success: false, transactionId: nil)
            }
            
            // Calculate refund transaction fee
            let refundFee = try await calculateClaimOrRefundTransactionFee()
            
            let refundTx = constructSingleRefundTransaction(
                swapOutput: swapOutput,        // Same output from detectSwap
                txHash: txHash,                // Hash of lockup transaction
                destinationAddress: destinationAddress,     // Where to send refunded funds
                timeoutBlockHeight: 0,         // Block height when refund becomes valid
                fee: refundFee,                // Transaction fee in satoshis
                network: network
            )
            
            let serializedTx = refundTx.serialize()
            
            let sigHash = refundTx.hashForWitnessV1(
                inputIndex: 0,
                prevoutScripts: [swapOutput.script],
                prevoutValues: [swapOutput.value]
            )
            
            let messageHashBytes = Array(sigHash)
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
                Log.debug("Received Boltz pubNonce: \(boltzPubNonce)")
                Log.debug("Received Boltz partialSignature: \(boltzPartialSignature)")
                
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
                    Log.info("❌ Failed to parse signature")
                    return ClaimResult(success: false, transactionId: nil)
                }
                
                refundTx.setWitness(inputIndex: 0, witness: [hardcodedSignature])
                let finalTx = refundTx.serialize()
                
                let broadcastResponse = try await BoltzAPI.broadcastTransaction(transactionHex: finalTx.hexString)
                if let transactionId = broadcastResponse.transactionIdValue {
                    Log.info("Transaction broadcast succeeded. TXID: \(transactionId)")
                    CacheManager.storeInvoiceDescription(preimage: transactionId, desc: ongoingSwap.dateID)
                    return ClaimResult(success: true, transactionId: transactionId)
                } else {
                    Log.info("❌ Failed to broadcast transaction")
                    return ClaimResult(success: false, transactionId: nil)
                }
            } else {
                Log.info("Failed to get claim response from Boltz")
                return ClaimResult(success: false, transactionId: nil)
            }
        } else {
            Log.info("No swap output found")
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

// MARK: - Response Validation

/// Everything Boltz returns decides where the user's money goes: the lockup
/// address a submarine swap funds, the invoice a reverse swap pays, and the
/// amounts quoted for both. It all arrives over the network, so it is all
/// rebuilt here from data the app already holds and compared before any value
/// moves.
enum SwapValidationError: LocalizedError {
    case undecodableLockupAddress(String)
    case lockupAddressMismatch(address: String, expected: String, actual: String)
    case ourKeyMissingFromLeaf(leaf: String, output: String)
    case unparsableClaimLeaf(String)
    case claimLeafHashMismatch(expected: String, actual: String)
    case unparsableInvoice
    case paymentHashMismatch(expected: String, received: String)
    case amountOutOfRange(requested: Int, quoted: Int)

    var errorDescription: String? {
        switch self {
        case .undecodableLockupAddress(let address):
            return "Lockup address could not be decoded: \(address)"
        case .lockupAddressMismatch(let address, let expected, let actual):
            return "Lockup address \(address) locks to \(actual), but this swap's keys produce \(expected)"
        case .ourKeyMissingFromLeaf(let leaf, let output):
            return "The \(leaf) leaf does not commit to our key: \(output)"
        case .unparsableClaimLeaf(let output):
            return "The claim leaf does not have the expected script layout: \(output)"
        case .claimLeafHashMismatch(let expected, let actual):
            return "The claim leaf commits to HASH160 \(actual), but our preimage hashes to \(expected)"
        case .unparsableInvoice:
            return "Reverse swap invoice could not be parsed, or carries no amount"
        case .paymentHashMismatch(let expected, let received):
            return "Invoice pays hash \(received), but our preimage hashes to \(expected)"
        case .amountOutOfRange(let requested, let quoted):
            return "Quoted \(quoted) sats against \(requested) sats requested"
        }
    }
}

enum BoltzSwapValidation {
    
    // The most a quote may ask for, as a multiple of the amount requested.
    static let maximumQuoteRatio = 2.0
    
    // MARK: Lockup address

    /// Rebuilds the Taproot output key a swap's funds lock to: the MuSig
    /// aggregate of Boltz's key and ours, tweaked by the merkle root of the two
    /// script leaves. This is the same derivation the claim and refund paths run
    /// in `claimLightningToOnchainSwap` and `refundOnchainToLightningSwap` — the
    /// point of running it here is that it happens on the way *in*, while the
    /// swap can still be abandoned for free.
    static func tweakedLockupKey(
        boltzPublicKeyHex: String,
        ourPrivateKeyHex: String,
        claimLeafOutputHex: String,
        refundLeafOutputHex: String
    ) throws -> Data {
        let boltzPublicKeyBytes = try boltzPublicKeyHex.bytes
        let ourPrivateKeyBytes = try ourPrivateKeyHex.bytes

        let boltzPublicKey = try P256K.Schnorr.PublicKey(
            dataRepresentation: boltzPublicKeyBytes,
            format: .compressed
        )
        let ourPrivateKey = try P256K.Schnorr.PrivateKey(dataRepresentation: ourPrivateKeyBytes)

        // Key order matters and is not sorted: Boltz first, then us.
        let aggregatedPublicKey = try P256K.MuSig.aggregate([boltzPublicKey, ourPrivateKey.publicKey], sortKeys: false)

        let tapTweakHash = try computeTapLeafHash(
            aggregatedPublicKey: aggregatedPublicKey,
            claimLeafOutputHex: claimLeafOutputHex,
            refundLeafOutputHex: refundLeafOutputHex
        )

        let tweakedXonlyKey = try aggregatedPublicKey.xonly.add(Array(Data(tapTweakHash)))
        return Data(tweakedXonlyKey.bytes)
    }

    /// Checks that a lockup address is the one this swap's own keys produce.
    ///
    /// A match proves our key sits inside the aggregate that guards the key
    /// path, which is the path both the cooperative claim and the cooperative
    /// refund spend, and it is what lets `detectSwap` recognise the output at
    /// all. An address we cannot reproduce is one we hold no key for.
    private static func validateLockupAddress(
        _ address: String,
        boltzPublicKeyHex: String,
        ourPrivateKeyHex: String,
        claimLeafOutputHex: String,
        refundLeafOutputHex: String,
        network: BitcoinNetwork
    ) throws {
        let tweakedKey = try tweakedLockupKey(
            boltzPublicKeyHex: boltzPublicKeyHex,
            ourPrivateKeyHex: ourPrivateKeyHex,
            claimLeafOutputHex: claimLeafOutputHex,
            refundLeafOutputHex: refundLeafOutputHex
        )

        // P2TR: OP_1 PUSH_32 <output key>
        var expectedScript = Data([0x51, 0x20])
        expectedScript.append(tweakedKey)

        guard let actualScript = AddressHandler.toOutputScript(address: address, network: network) else {
            throw SwapValidationError.undecodableLockupAddress(address)
        }

        guard actualScript == expectedScript else {
            throw SwapValidationError.lockupAddressMismatch(
                address: address,
                expected: expectedScript.hex,
                actual: actualScript.hex
            )
        }
    }

    /// Our x-only key: the compressed key without its parity byte, which is how
    /// a Taproot script refers to it. Nil when we have no record of the key —
    /// a swap restored from a file written before it was stored — so the caller
    /// can skip the leaf check and still validate everything else.
    private static func ourXonlyKeyHex(_ compressedPublicKeyHex: String?) -> String? {
        guard let compressedPublicKeyHex, compressedPublicKeyHex.count == 66 else { return nil }
        return String(compressedPublicKeyHex.dropFirst(2)).lowercased()
    }

    /// The HASH160(preimage) a reverse swap's claim leaf commits to.
    ///
    /// The leaf script is
    ///   OP_SIZE <32> OP_EQUALVERIFY OP_HASH160 <20-byte hash> OP_EQUALVERIFY
    ///   <32-byte x-only claim key> OP_CHECKSIG
    /// Parsing the pushes (rather than slicing fixed offsets) means a change to
    /// Boltz's leaf layout throws here instead of quietly returning wrong bytes.
    static func claimLeafPreimageHash160(_ claimLeafOutputHex: String) throws -> Data {
        let script = (try? claimLeafOutputHex.bytes) ?? []
        var i = 0
        func take(_ n: Int) throws -> ArraySlice<UInt8> {
            guard n >= 0, i + n <= script.count else {
                throw SwapValidationError.unparsableClaimLeaf(claimLeafOutputHex)
            }
            defer { i += n }
            return script[i..<(i + n)]
        }
        func expect(_ byte: UInt8) throws {
            guard try take(1).first == byte else {
                throw SwapValidationError.unparsableClaimLeaf(claimLeafOutputHex)
            }
        }
        try expect(0x82)               // OP_SIZE
        try expect(0x01)               // push 1 byte …
        try expect(0x20)               // … the value 32
        try expect(0x88)               // OP_EQUALVERIFY
        try expect(0xa9)               // OP_HASH160
        try expect(0x14)               // push 20 bytes …
        let hash = Data(try take(20))  // … HASH160(preimage)
        try expect(0x88)               // OP_EQUALVERIFY
        try expect(0x20)               // push 32 bytes …
        _ = try take(32)               // … x-only claim key (checked separately)
        try expect(0xac)               // OP_CHECKSIG
        guard i == script.count else {
            throw SwapValidationError.unparsableClaimLeaf(claimLeafOutputHex)
        }
        return hash
    }

    /// Checks a submarine swap's lockup address before any bitcoin is sent to it.
    ///
    /// Beyond the address, the timeout leaf has to commit to our refund key:
    /// that leaf is the script path an uncooperative refund spends, and it is
    /// the only way the funds come back if Boltz stops answering.
    /// The refund leaf reads <32-byte x-only refund key> OP_CHECKSIGVERIFY
    /// <timeout> OP_CHECKLOCKTIMEVERIFY, so our key follows the push that opens
    /// it.
    static func validateSubmarineLockup(
        address: String,
        claimPublicKeyHex: String,
        refundPrivateKeyHex: String,
        ourRefundPublicKeyHex: String?,
        claimLeafOutputHex: String,
        refundLeafOutputHex: String,
        network: BitcoinNetwork = BoltzRefund.network
    ) throws {
        try validateLockupAddress(
            address,
            boltzPublicKeyHex: claimPublicKeyHex,
            ourPrivateKeyHex: refundPrivateKeyHex,
            claimLeafOutputHex: claimLeafOutputHex,
            refundLeafOutputHex: refundLeafOutputHex,
            network: network
        )

        if let ourXonlyKeyHex = ourXonlyKeyHex(ourRefundPublicKeyHex) {
            guard refundLeafOutputHex.lowercased().hasPrefix("20" + ourXonlyKeyHex) else {
                throw SwapValidationError.ourKeyMissingFromLeaf(leaf: "refund", output: refundLeafOutputHex)
            }
        }
    }

    /// Checks a reverse swap's lockup address before its invoice is paid.
    ///
    /// Here Boltz funds the address and we claim from it, so the address is what
    /// says the coins we are paying for will be spendable by us at all. The
    /// claim leaf has to commit to our claim key for the same reason the
    /// submarine refund leaf does: it is the script path that still works when
    /// Boltz will not cooperate. The leaf reads OP_SIZE 32 OP_EQUALVERIFY
    /// OP_HASH160 <preimage hash> OP_EQUALVERIFY <32-byte x-only claim key>
    /// OP_CHECKSIG, so our key sits at the end.
    static func validateReverseLockup(
        address: String,
        refundPublicKeyHex: String,
        claimPrivateKeyHex: String,
        ourClaimPublicKeyHex: String?,
        preimageHex: String?,
        claimLeafOutputHex: String,
        refundLeafOutputHex: String,
        network: BitcoinNetwork = BoltzRefund.network
    ) throws {
        try validateLockupAddress(
            address,
            boltzPublicKeyHex: refundPublicKeyHex,
            ourPrivateKeyHex: claimPrivateKeyHex,
            claimLeafOutputHex: claimLeafOutputHex,
            refundLeafOutputHex: refundLeafOutputHex,
            network: network
        )

        if let ourXonlyKeyHex = ourXonlyKeyHex(ourClaimPublicKeyHex) {
            guard claimLeafOutputHex.lowercased().hasSuffix("20" + ourXonlyKeyHex + "ac") else {
                throw SwapValidationError.ourKeyMissingFromLeaf(leaf: "claim", output: claimLeafOutputHex)
            }
        }

        // The claim leaf also commits to HASH160(preimage). That hash guards the
        // uncooperative script-path claim — the fallback used if Boltz stops
        // answering — so it must be the hash of *our* preimage, or that path is
        // unspendable by us. Optional the same way the key check is: a swap
        // restored from a file with no preimage skips this and still validates
        // the address and key above.
        if let preimageHex, !preimageHex.isEmpty {
            let expected = RIPEMD160.hash160(Data(try preimageHex.bytes))
            let committed = try claimLeafPreimageHash160(claimLeafOutputHex)
            guard committed == expected else {
                throw SwapValidationError.claimLeafHashMismatch(expected: expected.hex, actual: committed.hex)
            }
        }
    }

    // MARK: Amounts

    // Checks that what Boltz quotes for a swap is not nonsense.
    static func validateQuotedAmount(requested: Int, quoted: Int) throws {
        guard quoted >= requested,
              Double(quoted) <= Double(requested) * maximumQuoteRatio else {
            throw SwapValidationError.amountOutOfRange(requested: requested, quoted: quoted)
        }
    }

    /// Checks that a reverse swap's invoice pays for the preimage we generated,
    /// and asks a sane price for it, before it is paid.
    ///
    /// Without the payment hash check the invoice could be any invoice at all —
    /// paying it would settle someone else's payment and leave nothing for us to
    /// claim, since the preimage that unlocks the on-chain side never comes back.
    static func validateReverseInvoice(
        _ invoice: String,
        preimageHashHex: String,
        requestedOnchainAmountSats: Int
    ) throws {
        guard let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: invoice).getValue(),
              let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis(),
              let paymentHash = parsedInvoice.paymentHash() else {
            throw SwapValidationError.unparsableInvoice
        }

        let paymentHashHex = Data(paymentHash).hex
        guard paymentHashHex.lowercased() == preimageHashHex.lowercased() else {
            throw SwapValidationError.paymentHashMismatch(expected: preimageHashHex.lowercased(), received: paymentHashHex)
        }

        try validateQuotedAmount(requested: requestedOnchainAmountSats, quoted: Int(invoiceAmountMilli / 1000))
    }
}

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - RIPEMD-160

/// RIPEMD-160 (ISO/IEC 10118-3). Neither CryptoKit nor the platform provides
/// it, yet Bitcoin's HASH160 = RIPEMD160(SHA256(x)) needs it — here, to check
/// the HASH160(preimage) a reverse swap's claim leaf commits to. Verified
/// against the standard test vectors in bittrTests (RIPEMD160Tests).
enum RIPEMD160 {

    /// Bitcoin HASH160: RIPEMD160(SHA256(data)).
    static func hash160(_ data: Data) -> Data {
        hash(Data(SHA256.hash(data: data)))
    }

    static func hash(_ message: Data) -> Data {
        var h0: UInt32 = 0x6745_2301
        var h1: UInt32 = 0xEFCD_AB89
        var h2: UInt32 = 0x98BA_DCFE
        var h3: UInt32 = 0x1032_5476
        var h4: UInt32 = 0xC3D2_E1F0

        // Pad: 0x80, zero-fill to 56 mod 64, then the 64-bit little-endian bit length.
        var msg = [UInt8](message)
        let bitLength = UInt64(msg.count) &* 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0x00) }
        for shift in stride(from: 0, through: 56, by: 8) {
            msg.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var block = 0
        while block < msg.count {
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let b = block + i * 4
                x[i] = UInt32(msg[b])
                    | (UInt32(msg[b + 1]) << 8)
                    | (UInt32(msg[b + 2]) << 16)
                    | (UInt32(msg[b + 3]) << 24)
            }

            var al = h0, bl = h1, cl = h2, dl = h3, el = h4
            var ar = h0, br = h1, cr = h2, dr = h3, er = h4

            for j in 0..<80 {
                let round = j / 16
                var tl = al &+ f(j, bl, cl, dl) &+ x[rl[j]] &+ kl[round]
                tl = rol(tl, sl[j]) &+ el
                al = el; el = dl; dl = rol(cl, 10); cl = bl; bl = tl

                var tr = ar &+ f(79 - j, br, cr, dr) &+ x[rr[j]] &+ kr[round]
                tr = rol(tr, sr[j]) &+ er
                ar = er; er = dr; dr = rol(cr, 10); cr = br; br = tr
            }

            let t = h1 &+ cl &+ dr
            h1 = h2 &+ dl &+ er
            h2 = h3 &+ el &+ ar
            h3 = h4 &+ al &+ br
            h4 = h0 &+ bl &+ cr
            h0 = t

            block += 64
        }

        var out = [UInt8]()
        out.reserveCapacity(20)
        for h in [h0, h1, h2, h3, h4] {
            out.append(UInt8(h & 0xff))
            out.append(UInt8((h >> 8) & 0xff))
            out.append(UInt8((h >> 16) & 0xff))
            out.append(UInt8((h >> 24) & 0xff))
        }
        return Data(out)
    }

    private static func rol(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }

    // Nonlinear function, selected by round index j (0...79).
    private static func f(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch j {
        case 0...15:  return x ^ y ^ z
        case 16...31: return (x & y) | (~x & z)
        case 32...47: return (x | ~y) ^ z
        case 48...63: return (x & z) | (y & ~z)
        default:      return x ^ (y | ~z)      // 64...79
        }
    }

    // Added constants per 16-round group, left and right lines.
    private static let kl: [UInt32] = [0x0000_0000, 0x5A82_7999, 0x6ED9_EBA1, 0x8F1B_BCDC, 0xA953_FD4E]
    private static let kr: [UInt32] = [0x50A2_8BE6, 0x5C4D_D124, 0x6D70_3EF3, 0x7A6D_76E9, 0x0000_0000]

    // Message-word selection.
    private static let rl: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
    ]
    private static let rr: [Int] = [
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
    ]

    // Rotate-left amounts.
    private static let sl: [UInt32] = [
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
    ]
    private static let sr: [UInt32] = [
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
    ]
}
