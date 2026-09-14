package com.bittr.android.core.swaps

import fr.acinq.bitcoin.ByteVector
import fr.acinq.bitcoin.ByteVector32
import fr.acinq.bitcoin.OutPoint
import fr.acinq.bitcoin.PrivateKey
import fr.acinq.bitcoin.Satoshi
import fr.acinq.bitcoin.Script
import fr.acinq.bitcoin.ScriptFlags
import fr.acinq.bitcoin.ScriptTree
import fr.acinq.bitcoin.Transaction
import fr.acinq.bitcoin.TxId
import fr.acinq.bitcoin.TxIn
import fr.acinq.bitcoin.TxOut
import fr.acinq.bitcoin.XonlyPublicKey
import fr.acinq.bitcoin.crypto.musig2.IndividualNonce
import fr.acinq.bitcoin.crypto.musig2.Musig2
import fr.acinq.bitcoin.crypto.musig2.SecretNonce
import fr.acinq.bitcoin.crypto.musig2.Session
import fr.acinq.bitcoin.utils.Either
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class BoltzTaprootTest {

    private val boltz = PrivateKey(Hex.decode("11".repeat(32)))
    private val ours = PrivateKey(Hex.decode("22".repeat(32)))

    // The leaves of iOS's example submarine response (SwapManager.swift:256).
    private val claimLeaf = Hex.decode("a914ed96f252263cd8cc0a616602875f76bfb0c70fcd8820611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61fac")
    private val refundLeaf = Hex.decode("2004cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24ad02df01b1")

    @Test
    fun `the merkle root is BIP341's, whichever leaf comes first`() {
        val tree = ScriptTree.Branch(ScriptTree.Leaf(ByteVector(claimLeaf), 0xc0), ScriptTree.Leaf(ByteVector(refundLeaf), 0xc0))
        assertArrayEquals(tree.hash().toByteArray(), BoltzTaproot.merkleRoot(claimLeaf, refundLeaf))
        assertArrayEquals(BoltzTaproot.merkleRoot(refundLeaf, claimLeaf), BoltzTaproot.merkleRoot(claimLeaf, refundLeaf))
    }

    @Test
    fun `the output key is the BIP341 tweak of the unsorted aggregate`() {
        val lockup = BoltzTaproot.lockup(boltz.publicKey(), ours.publicKey(), claimLeaf, refundLeaf)
        val aggregate = Musig2.aggregateKeys(listOf(boltz.publicKey(), ours.publicKey()))
        val (expected, _) = aggregate.outputKey(ByteVector32(BoltzTaproot.merkleRoot(claimLeaf, refundLeaf)))
        assertArrayEquals(expected.value.toByteArray(), lockup.outputKey)
    }

    @Test
    fun `key order is part of the address - Boltz first, not sorted`() {
        val boltzFirst = BoltzTaproot.lockup(boltz.publicKey(), ours.publicKey(), claimLeaf, refundLeaf)
        val oursFirst = BoltzTaproot.lockup(ours.publicKey(), boltz.publicKey(), claimLeaf, refundLeaf)
        assertFalse(boltzFirst.outputKey.contentEquals(oursFirst.outputKey))
    }

    @Test
    fun `a MuSig2 claim with Boltz's partial signature spends the lockup`() {
        val lockup = BoltzTaproot.lockup(boltz.publicKey(), ours.publicKey(), claimLeaf, refundLeaf)
        val funding = fundingTransaction(lockup, 100_000)
        val output = assertNotNull(BoltzTaproot.detectSwapOutput(funding, lockup)).let { BoltzTaproot.detectSwapOutput(funding, lockup)!! }
        assertEquals(1, output.vout)

        val destination = Script.write(Script.pay2wpkh(PrivateKey(Hex.decode("33".repeat(32))).publicKey()))
        val spend = BoltzTaproot.unsignedSpend(funding, output, destination, feeSats = 99 * 2, refund = false)
        assertEquals(BoltzTaproot.CLAIM_SEQUENCE, spend.txIn.single().sequence)
        assertEquals(100_000L - 198L, spend.txOut.single().amount.toLong())

        val message = BoltzTaproot.sighash(spend, output)
        val session = BoltzTaproot.startSigning(ours, boltz.publicKey(), lockup, message)
        val (boltzNonceHex, boltzPartialHex) = boltzSigns(lockup, message, session.publicNonceHex)

        val signed = BoltzTaproot.signed(spend, session.finish(boltzNonceHex, boltzPartialHex))
        Transaction.correctlySpends(signed, listOf(funding), ScriptFlags.STANDARD_SCRIPT_VERIFY_FLAGS)
    }

    @Test(expected = SwapSigningException::class)
    fun `a tampered partial signature from Boltz is refused before broadcast`() {
        val lockup = BoltzTaproot.lockup(boltz.publicKey(), ours.publicKey(), claimLeaf, refundLeaf)
        val funding = fundingTransaction(lockup, 50_000)
        val output = BoltzTaproot.detectSwapOutput(funding, lockup)!!
        val spend = BoltzTaproot.unsignedSpend(funding, output, lockup.script, feeSats = 500, refund = true)
        val message = BoltzTaproot.sighash(spend, output)
        val session = BoltzTaproot.startSigning(ours, boltz.publicKey(), lockup, message)
        val (nonce, partial) = boltzSigns(lockup, message, session.publicNonceHex)
        val tampered = Hex.decode(partial).also { it[31] = (it[31].toInt() xor 1).toByte() }.toHex()
        session.finish(nonce, tampered)
    }

    @Test
    fun `an output paying some other key is not the swap`() {
        val lockup = BoltzTaproot.lockup(boltz.publicKey(), ours.publicKey(), claimLeaf, refundLeaf)
        val other = BoltzTaproot.lockup(ours.publicKey(), boltz.publicKey(), claimLeaf, refundLeaf)
        assertNull(BoltzTaproot.detectSwapOutput(fundingTransaction(other, 10_000), lockup))
    }

    @Test
    fun `a regtest P2TR address decodes to the lockup script`() {
        val lockup = BoltzTaproot.lockup(boltz.publicKey(), ours.publicKey(), claimLeaf, refundLeaf)
        val address = XonlyPublicKey(ByteVector32(lockup.outputKey)).let { fr.acinq.bitcoin.Bech32.encodeWitnessAddress("bcrt", 1, lockup.outputKey) }
        assertArrayEquals(lockup.script, BoltzTaproot.outputScript(address, SwapChain.REGTEST))
        assertNull(BoltzTaproot.outputScript(address, SwapChain.MAINNET))
    }

    private fun fundingTransaction(lockup: BoltzTaproot.Lockup, sats: Long): Transaction = Transaction(
        2L,
        listOf(TxIn(OutPoint(TxId(ByteVector32(ByteArray(32) { 7 })), 0L), ByteArray(0), 0xffffffffL)),
        listOf(
            TxOut(Satoshi(1_000), Script.write(Script.pay2wpkh(boltz.publicKey()))),
            TxOut(Satoshi(sats), lockup.script),
        ),
        0L,
    )

    /** What Boltz does with our nonce: its own nonce and partial signature, as hex. */
    private fun boltzSigns(lockup: BoltzTaproot.Lockup, message: ByteVector32, ourNonceHex: String): Pair<String, String> {
        val (secret, public) = SecretNonce.generate(ByteVector32(ByteArray(32) { 9 }), boltz, boltz.publicKey(), message, lockup.tweakedCache, null)
        val aggregate = (IndividualNonce.aggregate(listOf(public, IndividualNonce(Hex.decode(ourNonceHex)))) as Either.Right).value
        val partial = (Session.create(aggregate, message, lockup.tweakedCache).sign(secret, boltz) as Either.Right).value
        return public.toByteArray().toHex() to partial.toByteArray().toHex()
    }
}
