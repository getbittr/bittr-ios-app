package com.bittr.android.core.swaps

import fr.acinq.bitcoin.Crypto
import fr.acinq.bitcoin.PrivateKey
import fr.acinq.bitcoin.PublicKey
import kotlin.math.ceil

/** Why a Boltz response was refused. iOS's `SwapValidationError`. */
sealed class SwapValidationException(message: String) : Exception(message) {
    class UndecodableLockupAddress(address: String) : SwapValidationException("Lockup address could not be decoded: $address")
    class LockupAddressMismatch(address: String, expected: String, actual: String) :
        SwapValidationException("Lockup address $address locks to $actual, but this swap's keys produce $expected")
    class OurKeyMissingFromLeaf(leaf: String, output: String) : SwapValidationException("The $leaf leaf does not commit to our key: $output")
    class UnparsableClaimLeaf(output: String) : SwapValidationException("The claim leaf does not have the expected script layout: $output")
    class ClaimLeafHashMismatch(expected: String, actual: String) :
        SwapValidationException("The claim leaf commits to HASH160 $actual, but our preimage hashes to $expected")
    class UnparsableInvoice : SwapValidationException("Reverse swap invoice could not be parsed, or carries no amount")
    class PaymentHashMismatch(expected: String, received: String) :
        SwapValidationException("Invoice pays hash $received, but our preimage hashes to $expected")
    class AmountOutOfRange(requested: Long, quoted: Long) : SwapValidationException("Quoted $quoted sats against $requested sats requested")
    class InvalidKey(what: String) : SwapValidationException("$what is not a valid key")
}

/**
 * Boltz's published fee for one direction: a percentage of the amount plus a fixed miner fee.
 * iOS's `BoltzFeeQuote`.
 */
data class BoltzFeeQuote(val percentage: Double, val minerFeeSats: Long)

/** What a BOLT11 invoice says, read by the node's decoder. See [InvoiceInspector]. */
data class InvoiceFacts(val amountMsat: Long?, val paymentHashHex: String)

/**
 * Decodes BOLT11 invoices. `:app` implements it over ldk-node's `Bolt11Invoice`, which is a
 * native object this module cannot load; tests implement it with fixed answers.
 */
fun interface InvoiceInspector {
    /** Null when [invoice] does not parse. */
    fun inspect(invoice: String): InvoiceFacts?
}

/**
 * Every check iOS runs on what Boltz answers before any value moves — `BoltzSwapValidation`
 * (`BoltzRefund.swift:478-733`), ported check for check.
 *
 * Everything Boltz returns decides where the user's money goes: the lockup address a submarine
 * swap funds, the invoice a reverse swap pays, the amounts quoted for both. So it is all rebuilt
 * here from data the app already holds and compared, and any mismatch throws. The caller turns a
 * throw into `alert.swapValidationFailed` and abandons the swap while abandoning it is still free.
 */
object BoltzSwapValidation {

    /** The loose ceiling, as a multiple of the request, when Boltz's fee schedule was unavailable. */
    const val MAXIMUM_QUOTE_RATIO = 2.0

    /**
     * Checks a submarine swap's lockup before any bitcoin is sent to it.
     *
     * Beyond the address, the refund leaf has to commit to our refund key — it reads
     * `<32-byte x-only refund key> OP_CHECKSIGVERIFY <timeout> OP_CHECKLOCKTIMEVERIFY`, and it is
     * the only way the funds come back if Boltz stops answering.
     */
    fun validateSubmarineLockup(
        address: String,
        claimPublicKeyHex: String,
        refundPrivateKeyHex: String,
        ourRefundPublicKeyHex: String?,
        claimLeafOutputHex: String,
        refundLeafOutputHex: String,
        chain: SwapChain,
    ) {
        validateLockupAddress(address, claimPublicKeyHex, refundPrivateKeyHex, claimLeafOutputHex, refundLeafOutputHex, chain)
        ourXonlyKeyHex(ourRefundPublicKeyHex)?.let { xonly ->
            if (!refundLeafOutputHex.lowercase().startsWith("20$xonly")) {
                throw SwapValidationException.OurKeyMissingFromLeaf("refund", refundLeafOutputHex)
            }
        }
    }

    /**
     * Checks a reverse swap's lockup before its invoice is paid.
     *
     * The claim leaf reads `OP_SIZE 32 OP_EQUALVERIFY OP_HASH160 <hash> OP_EQUALVERIFY <32-byte
     * x-only claim key> OP_CHECKSIG`: it must end in our key, and its hash must be HASH160 of
     * *our* preimage, or the uncooperative claim path is unspendable by us.
     */
    fun validateReverseLockup(
        address: String,
        refundPublicKeyHex: String,
        claimPrivateKeyHex: String,
        ourClaimPublicKeyHex: String?,
        preimageHex: String?,
        claimLeafOutputHex: String,
        refundLeafOutputHex: String,
        chain: SwapChain,
    ) {
        validateLockupAddress(address, refundPublicKeyHex, claimPrivateKeyHex, claimLeafOutputHex, refundLeafOutputHex, chain)
        ourXonlyKeyHex(ourClaimPublicKeyHex)?.let { xonly ->
            if (!claimLeafOutputHex.lowercase().endsWith("20${xonly}ac")) {
                throw SwapValidationException.OurKeyMissingFromLeaf("claim", claimLeafOutputHex)
            }
        }
        if (!preimageHex.isNullOrEmpty()) {
            val expected = Crypto.hash160(Hex.decode(preimageHex))
            val committed = claimLeafPreimageHash160(claimLeafOutputHex)
            if (!committed.contentEquals(expected)) {
                throw SwapValidationException.ClaimLeafHashMismatch(expected.toHex(), committed.toHex())
            }
        }
    }

    /**
     * Boltz's quote may be no more than its published fee allows: the request, plus the percentage
     * (rounded up), plus the miner fee, plus `max(request / 100, 1000)` for rounding and fee drift.
     * With no fee schedule the ceiling is twice the request.
     */
    fun validateQuotedAmount(requested: Long, quoted: Long, fee: BoltzFeeQuote?) {
        val maxQuoted = if (fee != null) {
            val percentageFee = ceil(requested.toDouble() * fee.percentage / 100.0).toLong()
            val tolerance = maxOf(requested / 100, 1000L)
            requested + percentageFee + fee.minerFeeSats + tolerance
        } else {
            (requested.toDouble() * MAXIMUM_QUOTE_RATIO).toLong()
        }
        if (quoted < requested || quoted > maxQuoted) throw SwapValidationException.AmountOutOfRange(requested, quoted)
    }

    /**
     * The reverse swap's invoice must pay for the preimage we generated, and ask a sane price.
     * Without the hash check it could be any invoice at all, and paying it would leave nothing
     * for us to claim.
     */
    fun validateReverseInvoice(
        invoice: String,
        preimageHashHex: String,
        requestedOnchainAmountSats: Long,
        fee: BoltzFeeQuote?,
        inspector: InvoiceInspector,
    ) {
        val facts = inspector.inspect(invoice)
        val amountMsat = facts?.amountMsat ?: throw SwapValidationException.UnparsableInvoice()
        val received = facts.paymentHashHex.lowercase()
        if (received != preimageHashHex.lowercase()) {
            throw SwapValidationException.PaymentHashMismatch(preimageHashHex.lowercase(), received)
        }
        validateQuotedAmount(requestedOnchainAmountSats, amountMsat / 1000, fee)
    }

    /**
     * The HASH160 a claim leaf commits to, reading its pushes rather than slicing offsets, so a
     * change to Boltz's layout throws instead of returning wrong bytes.
     */
    fun claimLeafPreimageHash160(claimLeafOutputHex: String): ByteArray {
        val script = runCatching { Hex.decode(claimLeafOutputHex) }.getOrElse { ByteArray(0) }
        var i = 0
        fun fail(): Nothing = throw SwapValidationException.UnparsableClaimLeaf(claimLeafOutputHex)
        fun take(n: Int): ByteArray {
            if (i + n > script.size) fail()
            return script.copyOfRange(i, i + n).also { i += n }
        }
        fun expect(byte: Int) {
            if ((take(1)[0].toInt() and 0xff) != byte) fail()
        }
        expect(0x82) // OP_SIZE
        expect(0x01) // push 1 byte …
        expect(0x20) // … the value 32
        expect(0x88) // OP_EQUALVERIFY
        expect(0xa9) // OP_HASH160
        expect(0x14) // push 20 bytes …
        val hash = take(20)
        expect(0x88) // OP_EQUALVERIFY
        expect(0x20) // push 32 bytes …
        take(32) //     … x-only claim key, checked separately
        expect(0xac) // OP_CHECKSIG
        if (i != script.size) fail()
        return hash
    }

    /**
     * The Taproot output key a swap's funds lock to must be the one this swap's own keys produce.
     * An address we cannot reproduce is one we hold no key for.
     */
    private fun validateLockupAddress(
        address: String,
        boltzPublicKeyHex: String,
        ourPrivateKeyHex: String,
        claimLeafOutputHex: String,
        refundLeafOutputHex: String,
        chain: SwapChain,
    ) {
        val boltzKey = runCatching { PublicKey(Hex.decode(boltzPublicKeyHex)).also { require(it.isValid()) } }
            .getOrElse { throw SwapValidationException.InvalidKey("Boltz's public key") }
        val ourKey = runCatching { PrivateKey(Hex.decode(ourPrivateKeyHex)) }
            .getOrElse { throw SwapValidationException.InvalidKey("Our private key") }
        val claimLeaf = runCatching { Hex.decode(claimLeafOutputHex) }.getOrElse { throw SwapValidationException.UnparsableClaimLeaf(claimLeafOutputHex) }
        val refundLeaf = runCatching { Hex.decode(refundLeafOutputHex) }.getOrElse { throw SwapValidationException.OurKeyMissingFromLeaf("refund", refundLeafOutputHex) }

        val expected = runCatching { BoltzTaproot.lockup(boltzKey, ourKey.publicKey(), claimLeaf, refundLeaf).script }
            .getOrElse { throw SwapValidationException.InvalidKey("The aggregate key") }
        val actual = BoltzTaproot.outputScript(address, chain) ?: throw SwapValidationException.UndecodableLockupAddress(address)
        if (!actual.contentEquals(expected)) {
            throw SwapValidationException.LockupAddressMismatch(address, expected.toHex(), actual.toHex())
        }
    }

    /**
     * Our x-only key hex — the compressed key without its parity byte. Null when there is no
     * record of the key (a swap restored from an older file), so the leaf check is skipped and
     * everything else still validates.
     */
    private fun ourXonlyKeyHex(compressedPublicKeyHex: String?): String? =
        compressedPublicKeyHex?.takeIf { it.length == 66 }?.drop(2)?.lowercase()
}
