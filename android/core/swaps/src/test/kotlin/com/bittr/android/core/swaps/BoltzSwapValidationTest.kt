package com.bittr.android.core.swaps

import fr.acinq.bitcoin.Bech32
import fr.acinq.bitcoin.Crypto
import fr.acinq.bitcoin.PrivateKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * The tampered-response cases `evil_boltz_wrong_address.yaml` and `evil_boltz_wrong_invoice.yaml`
 * drive on iOS, as JVM tests: each is a Boltz answer that must be refused before funds move.
 */
class BoltzSwapValidationTest {

    private val boltz = PrivateKey(Hex.decode("11".repeat(32)))
    private val ours = PrivateKey(Hex.decode("22".repeat(32)))
    private val oursHex = Hex.encode(ours.value.toByteArray())
    private val oursPublicHex = ours.publicKey().value.toByteArray().toHex()
    private val boltzPublicHex = boltz.publicKey().value.toByteArray().toHex()
    private fun xonly(key: PrivateKey) = key.publicKey().value.toByteArray().copyOfRange(1, 33).toHex()

    /** The attacker address the iOS evil harness substitutes (EvilBoltz.swift). */
    private val attackerAddress = "bcrt1pcz9mae53csyv8d0t4fansh446jdjey2pg2djn5utqver5e42gp5s507k3j"

    // A submarine swap: Boltz claims with the preimage, we refund after the timeout.
    private val submarineClaimLeaf = "a914" + "ab".repeat(20) + "8820" + xonly(boltz) + "ac"
    private val submarineRefundLeaf = "20" + xonly(ours) + "ad" + "02df01" + "b1"

    // A reverse swap: we claim with the preimage, Boltz refunds after the timeout.
    private val preimage = "5a".repeat(32)
    private val reverseClaimLeaf = "82012088a914" + Crypto.hash160(Hex.decode(preimage)).toHex() + "8820" + xonly(ours) + "ac"
    private val reverseRefundLeaf = "20" + xonly(boltz) + "ad" + "024d01" + "b1"

    private fun addressFor(claimLeaf: String, refundLeaf: String): String {
        val lockup = BoltzTaproot.lockup(boltz.publicKey(), ours.publicKey(), Hex.decode(claimLeaf), Hex.decode(refundLeaf))
        return Bech32.encodeWitnessAddress("bcrt", 1, lockup.outputKey)
    }

    private fun submarine(address: String, refundLeaf: String = submarineRefundLeaf) =
        BoltzSwapValidation.validateSubmarineLockup(address, boltzPublicHex, oursHex, oursPublicHex, submarineClaimLeaf, refundLeaf, SwapChain.REGTEST)

    private fun reverse(address: String, claimLeaf: String = reverseClaimLeaf, preimageHex: String? = preimage) =
        BoltzSwapValidation.validateReverseLockup(address, boltzPublicHex, oursHex, oursPublicHex, preimageHex, claimLeaf, reverseRefundLeaf, SwapChain.REGTEST)

    @Test
    fun `a submarine lockup built from our keys passes`() {
        submarine(addressFor(submarineClaimLeaf, submarineRefundLeaf))
    }

    @Test
    fun `a substituted lockup address is refused`() {
        assertThrows(SwapValidationException.LockupAddressMismatch::class.java) { submarine(attackerAddress) }
    }

    @Test
    fun `an address on another chain is refused`() {
        val lockup = BoltzTaproot.lockup(boltz.publicKey(), ours.publicKey(), Hex.decode(submarineClaimLeaf), Hex.decode(submarineRefundLeaf))
        val mainnet = Bech32.encodeWitnessAddress("bc", 1, lockup.outputKey)
        assertThrows(SwapValidationException.UndecodableLockupAddress::class.java) { submarine(mainnet) }
    }

    @Test
    fun `a refund leaf that does not commit to our key is refused`() {
        val foreignLeaf = "20" + xonly(boltz) + "ad" + "02df01" + "b1"
        // Built so the address matches the tampered tree: only the leaf check can catch it.
        assertThrows(SwapValidationException.OurKeyMissingFromLeaf::class.java) {
            submarine(addressFor(submarineClaimLeaf, foreignLeaf), refundLeaf = foreignLeaf)
        }
    }

    @Test
    fun `a reverse lockup built from our keys and preimage passes`() {
        reverse(addressFor(reverseClaimLeaf, reverseRefundLeaf))
    }

    @Test
    fun `a claim leaf committing to another preimage is refused`() {
        val otherLeaf = "82012088a914" + "cd".repeat(20) + "8820" + xonly(ours) + "ac"
        val address = BoltzTaproot.lockup(boltz.publicKey(), ours.publicKey(), Hex.decode(otherLeaf), Hex.decode(reverseRefundLeaf))
            .let { Bech32.encodeWitnessAddress("bcrt", 1, it.outputKey) }
        assertThrows(SwapValidationException.ClaimLeafHashMismatch::class.java) { reverse(address, claimLeaf = otherLeaf) }
    }

    @Test
    fun `a claim leaf ending in someone else's key is refused`() {
        val otherLeaf = "82012088a914" + Crypto.hash160(Hex.decode(preimage)).toHex() + "8820" + xonly(boltz) + "ac"
        val address = BoltzTaproot.lockup(boltz.publicKey(), ours.publicKey(), Hex.decode(otherLeaf), Hex.decode(reverseRefundLeaf))
            .let { Bech32.encodeWitnessAddress("bcrt", 1, it.outputKey) }
        assertThrows(SwapValidationException.OurKeyMissingFromLeaf::class.java) { reverse(address, claimLeaf = otherLeaf) }
    }

    @Test
    fun `the claim leaf's hash is read from iOS's example response`() {
        val leaf = "82012088a91475b687397f92783b38c7381725bfcf27d65eef3f8820036f6171920eec6d2f377e4c0ab88960307c7d9d817ddf65585bc28a8334be1aac"
        assertEquals("75b687397f92783b38c7381725bfcf27d65eef3f", BoltzSwapValidation.claimLeafPreimageHash160(leaf).toHex())
        assertThrows(SwapValidationException.UnparsableClaimLeaf::class.java) { BoltzSwapValidation.claimLeafPreimageHash160(leaf + "00") }
        assertThrows(SwapValidationException.UnparsableClaimLeaf::class.java) { BoltzSwapValidation.claimLeafPreimageHash160("a914") }
    }

    @Test
    fun `a quote must sit between the request and the published fee plus tolerance`() {
        val fee = BoltzFeeQuote(percentage = 0.25, minerFeeSats = 300)
        // 50 000 + ceil(125) + 300 + max(500, 1000)
        BoltzSwapValidation.validateQuotedAmount(50_000, 51_425, fee)
        BoltzSwapValidation.validateQuotedAmount(50_000, 50_000, fee)
        assertThrows(SwapValidationException.AmountOutOfRange::class.java) { BoltzSwapValidation.validateQuotedAmount(50_000, 51_426, fee) }
        assertThrows(SwapValidationException.AmountOutOfRange::class.java) { BoltzSwapValidation.validateQuotedAmount(50_000, 49_999, fee) }
    }

    @Test
    fun `without a fee schedule the ceiling is twice the request`() {
        BoltzSwapValidation.validateQuotedAmount(50_000, 100_000, null)
        assertThrows(SwapValidationException.AmountOutOfRange::class.java) { BoltzSwapValidation.validateQuotedAmount(50_000, 100_001, null) }
    }

    @Test
    fun `a reverse invoice must pay our preimage hash`() {
        val hash = Crypto.sha256(Hex.decode(preimage)).toHex()
        val good = InvoiceInspector { InvoiceFacts(amountMsat = 50_500_000, paymentHashHex = hash) }
        BoltzSwapValidation.validateReverseInvoice("lnbcrt…", hash, 50_000, null, good)

        val wrongHash = InvoiceInspector { InvoiceFacts(amountMsat = 50_500_000, paymentHashHex = "00".repeat(32)) }
        assertThrows(SwapValidationException.PaymentHashMismatch::class.java) {
            BoltzSwapValidation.validateReverseInvoice("lnbcrt…", hash, 50_000, null, wrongHash)
        }
        assertThrows(SwapValidationException.UnparsableInvoice::class.java) {
            BoltzSwapValidation.validateReverseInvoice("garbage", hash, 50_000, null) { null }
        }
        assertThrows(SwapValidationException.UnparsableInvoice::class.java) {
            BoltzSwapValidation.validateReverseInvoice("lnbcrt…", hash, 50_000, null) { InvoiceFacts(null, hash) }
        }
    }
}
