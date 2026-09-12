package com.bittr.android.core.keystore.probe

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * The envelope format is the one part of K1 that can be tested without a device, and the one
 * part whose bugs would be misread as a Keystore result: a truncation bug here surfaces in
 * phase 2 as "the key did not survive the mutation".
 */
class K1EnvelopeTest {

    @Test
    fun `round-trips iv and ciphertext`() {
        val iv = ByteArray(12) { it.toByte() }
        val ciphertext = ByteArray(64) { (255 - it).toByte() }

        val decoded = K1Envelope.decode(K1Envelope.encode(iv, ciphertext))

        assertArrayEquals(iv, decoded.iv)
        assertArrayEquals(ciphertext, decoded.ciphertext)
    }

    @Test
    fun `carries a 16-byte iv, not just the 12-byte GCM default`() {
        // Not every Keystore implementation hands back a 12-byte GCM IV, and the length byte
        // exists so that a device that does something else is still readable at open time.
        val iv = ByteArray(16) { 0x5A }
        val decoded = K1Envelope.decode(K1Envelope.encode(iv, byteArrayOf(1, 2, 3)))

        assertEquals(16, decoded.iv.size)
        assertArrayEquals(byteArrayOf(1, 2, 3), decoded.ciphertext)
    }

    @Test
    fun `rejects a truncated envelope instead of returning short arrays`() {
        val full = K1Envelope.encode(ByteArray(12), ByteArray(32))

        assertThrows(IllegalArgumentException::class.java) {
            K1Envelope.decode(full.copyOfRange(0, 8))
        }
    }

    @Test
    fun `rejects an unknown version byte`() {
        val full = K1Envelope.encode(ByteArray(12), ByteArray(32)).also { it[0] = 9 }

        assertThrows(IllegalArgumentException::class.java) { K1Envelope.decode(full) }
    }

    @Test
    fun `rejects an iv that does not fit the length byte`() {
        assertThrows(IllegalArgumentException::class.java) {
            K1Envelope.encode(ByteArray(256), ByteArray(1))
        }
    }
}
