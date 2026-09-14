package com.bittr.android.core.wallet.ldk.bip

import fr.acinq.bitcoin.ByteVector64
import fr.acinq.bitcoin.Crypto
import fr.acinq.bitcoin.PrivateKey
import java.util.Base64
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class BitcoinMessageSignerTest {

    private val wif = "L4rK1yDtCWekvXuE6oXD9jCYfFNV2cWRpVuPLBcCU2z8TrisoyY1"
    private val message = "This is an example of a signed message."

    private fun key(): PrivateKey = PrivateKey.fromBase58(wif, 0x80.toByte()).first

    @Test
    fun `matches the bitcoinjs-message p2wpkh vector`() {
        // bitcoinjs-message's README vector for a segwit P2WPKH signature (header 'J' = 39).
        assertEquals(
            "J9L5yLFjti0QTHhPyFrZCT1V/MMnBtXKmoiKDZ78NDBjERki6ZTQZdSMCtkgoNmp17By9ItJr8o7ChX0XxY91nk=",
            BitcoinMessageSigner.signP2wpkh(message, key()),
        )
    }

    @Test
    fun `the header carries the P2WPKH flag and the signature recovers the signing key`() {
        val decoded = Base64.getDecoder().decode(BitcoinMessageSigner.signP2wpkh("I confirm I'm the sole owner", key()))
        assertEquals(65, decoded.size)
        val recoveryId = decoded[0] - 27 - 12
        assert(recoveryId in 0..3) { "header ${decoded[0]} is not a P2WPKH header" }
        val recovered = Crypto.recoverPublicKey(
            ByteVector64(decoded.copyOfRange(1, 65)),
            BitcoinMessageSigner.messageDigest("I confirm I'm the sole owner"),
            recoveryId,
        )
        assertEquals(key().publicKey(), recovered)
    }

    @Test
    fun `compact sizes are written as Bitcoin writes them`() {
        assertArrayEquals(byteArrayOf(24), BitcoinMessageSigner.varint(24))
        assertArrayEquals(byteArrayOf(0xfd.toByte(), 0x00, 0x01), BitcoinMessageSigner.varint(256))
    }

    @Test
    fun `the signing path is the first external address of account 0`() {
        assertEquals("m/84'/1'/0'/0/0", BitcoinMessageSigner.defaultSigningPath(mainnet = false))
        assertEquals("m/84'/0'/0'/0/0", BitcoinMessageSigner.defaultSigningPath(mainnet = true))
    }
}
