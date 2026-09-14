package com.bittr.android.core.swaps

import fr.acinq.bitcoin.Block
import fr.acinq.bitcoin.BlockHash
import fr.acinq.bitcoin.ByteVector32
import fr.acinq.bitcoin.ByteVector64
import fr.acinq.bitcoin.Crypto
import fr.acinq.bitcoin.OutPoint
import fr.acinq.bitcoin.PrivateKey
import fr.acinq.bitcoin.PublicKey
import fr.acinq.bitcoin.Satoshi
import fr.acinq.bitcoin.Script
import fr.acinq.bitcoin.ScriptWitness
import fr.acinq.bitcoin.SigHash
import fr.acinq.bitcoin.Transaction
import fr.acinq.bitcoin.TxIn
import fr.acinq.bitcoin.TxOut
import fr.acinq.bitcoin.XonlyPublicKey
import fr.acinq.bitcoin.crypto.musig2.AggregatedNonce
import fr.acinq.bitcoin.crypto.musig2.IndividualNonce
import fr.acinq.bitcoin.crypto.musig2.KeyAggCache
import fr.acinq.bitcoin.crypto.musig2.SecretNonce
import fr.acinq.bitcoin.crypto.musig2.Session
import fr.acinq.bitcoin.utils.Either
import java.security.SecureRandom

/** Which chain a swap's addresses are on. Debug builds are regtest, as on iOS. */
enum class SwapChain(internal val chainHash: BlockHash) {
    REGTEST(Block.RegtestGenesisBlock.hash),
    MAINNET(Block.LivenetGenesisBlock.hash),
}

/**
 * The Taproot output a swap's funds lock to, and the MuSig2 key-path spend out of it —
 * iOS's `computeTapLeafHash`, `detectSwap`, `constructClaimTransaction` and the signing
 * half of `BoltzRefund.claimLightningToOnchainSwap` / `refundOnchainToLightningSwap`.
 *
 * ## The lockup
 *
 * `P = MuSig2.aggregate([boltzKey, ourKey])`, **unsorted, Boltz first** — the order is part
 * of the key, and a sorted aggregate is a different address the validation would reject.
 * The script tree has the two leaves Boltz returns; the merkle root is the tagged hash of
 * the two leaf hashes in lexicographic order, the tweak is `TapTweak(xonly(P) || root)`,
 * and the output key is the x-only tweak of `P`. The lockup script is `OP_1 <output key>`.
 *
 * ## The spend
 *
 * Claim and refund both spend the key path: one input, one output, version 1, `SIGHASH_DEFAULT`.
 * We make a nonce, Boltz sends its nonce and partial signature for the transaction we
 * showed it, we sign against the aggregate nonce (Boltz's first, as iOS orders them) and the
 * two partial signatures aggregate to one Schnorr signature. That signature is **verified
 * against the output key before it goes anywhere** — iOS broadcasts without checking; a
 * signature that does not verify would only be rejected by the network, but finding out here
 * turns a silent broadcast failure into a named one.
 */
object BoltzTaproot {

    /** The tapscript leaf version Boltz's leaves carry (`version: 192`). */
    private const val LEAF_VERSION = 0xc0

    /** Claims signal RBF (`0xfffffffd`); refunds use `0xfffffffe`. iOS's two sequences. */
    const val CLAIM_SEQUENCE = 0xfffffffdL
    const val REFUND_SEQUENCE = 0xfffffffeL

    fun tapLeafHash(script: ByteArray): ByteArray =
        Crypto.taggedHash(byteArrayOf(LEAF_VERSION.toByte()) + compactSize(script.size) + script, "TapLeaf").toByteArray()

    fun merkleRoot(claimLeaf: ByteArray, refundLeaf: ByteArray): ByteArray {
        val claim = tapLeafHash(claimLeaf)
        val refund = tapLeafHash(refundLeaf)
        val (left, right) = if (compareUnsigned(claim, refund) < 0) claim to refund else refund to claim
        return Crypto.taggedHash(left + right, "TapBranch").toByteArray()
    }

    /** The key aggregate and its cache, tweaked for the tree — everything signing needs. */
    class Lockup internal constructor(
        internal val tweakedCache: KeyAggCache,
        /** The 32-byte x-only output key. */
        val outputKey: ByteArray,
    ) {
        /** `OP_1 PUSH32 <output key>`. */
        val script: ByteArray get() = byteArrayOf(0x51, 0x20) + outputKey
    }

    fun lockup(boltzPublicKey: PublicKey, ourPublicKey: PublicKey, claimLeaf: ByteArray, refundLeaf: ByteArray): Lockup {
        val (aggregate, cache) = KeyAggCache.create(listOf(boltzPublicKey, ourPublicKey))
        val tweak = Crypto.taggedHash(aggregate.value.toByteArray() + merkleRoot(claimLeaf, refundLeaf), "TapTweak")
        val (tweakedCache, tweakedKey) = cache.tweak(tweak, true).orThrow()
        return Lockup(tweakedCache, XonlyPublicKey(tweakedKey).value.toByteArray())
    }

    /** The output script [address] pays to, or null when it is not an address on [chain]. */
    fun outputScript(address: String, chain: SwapChain): ByteArray? =
        when (val result = fr.acinq.bitcoin.Bitcoin.addressToPublicKeyScript(chain.chainHash, address)) {
            is Either.Right -> Script.write(result.value)
            is Either.Left -> null
        }

    /** The output of [lockupTransaction] that pays the lockup — iOS's `detectSwap`. */
    data class SwapOutput(val vout: Int, val valueSats: Long, val script: ByteArray)

    fun detectSwapOutput(lockupTransaction: Transaction, lockup: Lockup): SwapOutput? {
        val expected = lockup.script
        lockupTransaction.txOut.forEachIndexed { index, output ->
            if (output.publicKeyScript.toByteArray().contentEquals(expected)) {
                return SwapOutput(index, output.amount.toLong(), expected)
            }
        }
        return null
    }

    /**
     * The claim or refund transaction, unsigned — iOS's `constructClaimTransaction`.
     *
     * The witness holds 64 zero bytes, which is what iOS serialises for Boltz to sign against:
     * it is the size of the signature that will replace it, so the transaction Boltz sees has
     * the weight of the one that is broadcast. The output is the lockup value less [feeSats],
     * floored at zero as iOS floors it.
     */
    fun unsignedSpend(
        lockupTransaction: Transaction,
        output: SwapOutput,
        destinationScript: ByteArray,
        feeSats: Long,
        refund: Boolean,
    ): Transaction {
        val input = TxIn(OutPoint(lockupTransaction, output.vout.toLong()), ByteArray(0), if (refund) REFUND_SEQUENCE else CLAIM_SEQUENCE)
            .updateWitness(ScriptWitness(listOf(fr.acinq.bitcoin.ByteVector(ByteArray(64)))))
        val value = (output.valueSats - maxOf(0L, feeSats)).coerceAtLeast(0L)
        return Transaction(1L, listOf(input), listOf(TxOut(Satoshi(value), destinationScript)), 0L)
    }

    /** BIP341 key-path sighash of input 0, `SIGHASH_DEFAULT`. */
    fun sighash(spend: Transaction, output: SwapOutput): ByteVector32 =
        spend.hashForSigningTaprootKeyPath(0, listOf(TxOut(Satoshi(output.valueSats), output.script)), SigHash.SIGHASH_DEFAULT)

    /**
     * Our half of a MuSig2 session, from nonce to the final witness.
     *
     * Single use: a secret nonce signs once. [publicNonceHex] goes to Boltz; [finish] takes
     * what Boltz sends back.
     */
    class SigningSession internal constructor(
        private val ourKey: PrivateKey,
        private val boltzKey: PublicKey,
        private val lockup: Lockup,
        private val message: ByteVector32,
        private val secretNonce: SecretNonce,
        private val publicNonce: IndividualNonce,
    ) {
        val publicNonceHex: String get() = publicNonce.toByteArray().toHex()

        /**
         * Combine Boltz's partial signature with ours and verify the result against the output key.
         *
         * @throws SwapSigningException when Boltz's nonce or partial signature is malformed, its
         *   partial signature does not verify, or the aggregate does not verify.
         */
        fun finish(boltzNonceHex: String, boltzPartialSignatureHex: String): ByteVector64 {
            val boltzNonce = runCatching { IndividualNonce(Hex.decode(boltzNonceHex)) }
                .getOrElse { throw SwapSigningException("Boltz's nonce is malformed") }
            val boltzPartial = runCatching { ByteVector32(Hex.decode(boltzPartialSignatureHex)) }
                .getOrElse { throw SwapSigningException("Boltz's partial signature is malformed") }
            val aggregateNonce: AggregatedNonce = IndividualNonce.aggregate(listOf(boltzNonce, publicNonce))
                .orThrow { SwapSigningException("Nonces do not aggregate") }
            val session = Session.create(aggregateNonce, message, lockup.tweakedCache)
            if (!session.verify(boltzPartial, boltzNonce, boltzKey)) {
                throw SwapSigningException("Boltz's partial signature does not verify")
            }
            val ours = session.sign(secretNonce, ourKey).orThrow { SwapSigningException("Could not sign") }
            val signature = session.aggregateSigs(listOf(boltzPartial, ours))
                .orThrow { SwapSigningException("Partial signatures do not aggregate") }
            if (!Crypto.verifySignatureSchnorr(message, signature, XonlyPublicKey(ByteVector32(lockup.outputKey)))) {
                throw SwapSigningException("The aggregate signature does not verify against the lockup")
            }
            return signature
        }
    }

    fun startSigning(
        ourKey: PrivateKey,
        boltzKey: PublicKey,
        lockup: Lockup,
        message: ByteVector32,
        random: SecureRandom = SecureRandom(),
    ): SigningSession {
        val sessionId = ByteArray(32).also(random::nextBytes)
        val (secret, public) = SecretNonce.generate(
            ByteVector32(sessionId),
            ourKey,
            ourKey.publicKey(),
            message,
            lockup.tweakedCache,
            null,
        )
        return SigningSession(ourKey, boltzKey, lockup, message, secret, public)
    }

    /** [spend] with the key-path signature in its witness, ready to broadcast. */
    fun signed(spend: Transaction, signature: ByteVector64): Transaction =
        spend.updateWitness(0, Script.witnessKeyPathPay2tr(signature))

    private fun <T> Either<Throwable, T>.orThrow(failure: () -> Exception = { SwapSigningException("MuSig2 failed") }): T = when (this) {
        is Either.Right -> value
        is Either.Left -> throw failure()
    }
}

class SwapSigningException(message: String) : Exception(message)
