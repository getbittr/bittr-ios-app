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
    
    /// Calculates transaction fee using the highest priority fee rate
    /// Both claim and refund transactions are always 99 vbytes in size
    static func calculateClaimOrRefundTransactionFee() async throws -> Int {
        guard let feeEstimates = await BitcoinManager.shared.getFeeEstimates() else {
            throw BoltzAPIError.requestFailed("Could not fetch fee estimates for the claim/refund transaction.")
        }
        let transactionSizeVBytes = 99 // Fixed size for claim/refund transactions

        let calculatedFee = Int(feeEstimates.fastest * Double(transactionSizeVBytes))
        
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
    case unparsableInvoice
    case paymentHashMismatch(expected: String, received: String)
    case amountOutOfRange(requested: Int, quoted: Int, allowedSpread: Int)

    var errorDescription: String? {
        switch self {
        case .undecodableLockupAddress(let address):
            return "Lockup address could not be decoded: \(address)"
        case .lockupAddressMismatch(let address, let expected, let actual):
            return "Lockup address \(address) locks to \(actual), but this swap's keys produce \(expected)"
        case .ourKeyMissingFromLeaf(let leaf, let output):
            return "The \(leaf) leaf does not commit to our key: \(output)"
        case .unparsableInvoice:
            return "Reverse swap invoice could not be parsed, or carries no amount"
        case .paymentHashMismatch(let expected, let received):
            return "Invoice pays hash \(received), but our preimage hashes to \(expected)"
        case .amountOutOfRange(let requested, let quoted, let allowedSpread):
            return "Quoted \(quoted) sats against \(requested) sats requested, outside the allowed spread of \(allowedSpread) sats"
        }
    }
}

enum BoltzSwapValidation {

    // The spread a quote may carry over the amount that was asked for: Boltz's
    // percentage cut plus the miner fee for the transaction it broadcasts. Both
    // directions pay one — a submarine swap sends more on-chain than the invoice
    // it redeems, a reverse swap pays an invoice larger than the coins it gets
    // back. This is a sanity bound, not a fee quote: it is set wide enough to
    // clear a busy mempool, and the exact fee is still put to the user in the
    // confirmation alert. Anything beyond it is treated as a tampered response
    // rather than an expensive one.
    static let maximumSpreadPercentage = 5.0
    static let minimumSpreadSats = 10_000

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
    }

    // MARK: Amounts

    /// Checks that what Boltz quotes for a swap is what was asked for plus a
    /// plausible fee, in either direction: `quoted` is always the leg the user
    /// pays, `requested` the leg they receive.
    static func validateQuotedAmount(requested: Int, quoted: Int) throws {
        let allowedSpread = max(
            minimumSpreadSats,
            Int((Double(requested) * maximumSpreadPercentage / 100).rounded(.up))
        )
        guard quoted >= requested, quoted <= requested + allowedSpread else {
            throw SwapValidationError.amountOutOfRange(
                requested: requested,
                quoted: quoted,
                allowedSpread: allowedSpread
            )
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
