package com.bittr.android.core.wallet.ldk.bip

import fr.acinq.bitcoin.ByteVector32
import fr.acinq.bitcoin.Crypto
import fr.acinq.bitcoin.PrivateKey
import fr.acinq.bitcoin.PublicKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LnurlAuthSignerTest {

    private val key = ByteArray(32) { (it + 1).toByte() }
    private val k1 = ByteArray(32) { (0xE0 + it).toByte() }

    @Test
    fun `the signature is low-S DER that verifies against the returned key`() {
        val signed = LnurlAuthSigner.sign(k1, key)
        val der = signed.signatureHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

        assertTrue(Crypto.isLowDERSignature(der))
        assertEquals(PrivateKey(key).publicKey().toHex(), signed.keyHex)
        assertEquals(66, signed.keyHex.length)
        val compact = Crypto.sign(ByteVector32(k1), PrivateKey(key))
        assertTrue(Crypto.verifySignature(k1, compact, PublicKey.fromHex(signed.keyHex)))
    }

    @Test
    fun `DER integers drop leading zeros and pad a high bit`() {
        val compact = ByteArray(64).also {
            it[31] = 0x01 // r = 1
            it[32] = 0x80.toByte() // s has its high bit set
        }
        val der = LnurlAuthSigner.der(compact)
        assertEquals(0x30, der[0].toInt())
        assertEquals(listOf<Byte>(0x02, 0x01, 0x01), der.slice(2..4))
        assertEquals(listOf<Byte>(0x02, 33, 0x00, 0x80.toByte()), der.slice(5..8))
    }
}
