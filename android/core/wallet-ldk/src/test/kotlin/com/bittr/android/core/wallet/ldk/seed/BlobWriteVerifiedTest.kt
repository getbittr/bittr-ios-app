package com.bittr.android.core.wallet.ldk.seed

import com.bittr.android.core.wallet.ldk.FakeBlobCodec
import com.bittr.android.core.wallet.ldk.FakeBlobStore
import com.bittr.android.core.wallet.ldk.Mnemonics
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The write read-back — `persistSecret`'s `writeVerificationFailed`
 * (`CacheManager.swift:528–539`), ported.
 *
 * Not decoration in the original and less so here. Without it a write that
 * fails silently leaves the app believing a wallet exists when nothing
 * recoverable was stored — and the moment that belief forms is the moment the
 * user is told their wallet is ready and stops paying attention to the twelve
 * words on the previous screen. Android widens the exposure: a wrap can
 * succeed while the file write is truncated, and the key can be invalidated
 * between generation and use.
 *
 * It is not the last line of defence — the onboarding seed-confirmation gate
 * (`Signup4ViewController.swift:228–283`) means the user has typed three of
 * the words back before reaching here. It is a cheap one, and it is in the
 * source we are porting.
 */
class BlobWriteVerifiedTest {

    @Test
    fun `a dropped write fails loudly instead of reporting success`() {
        val store = FakeBlobStore().apply { dropWrites = true }
        val vault = WrappedSeedVault(FakeBlobCodec(), store)

        val failure = assertThrows(SeedWriteVerificationException::class.java) {
            vault.store(Mnemonics.IOS_VECTOR)
        }

        assertTrue(
            "The message has to name what happened; this is the one that reaches a " +
                "crash report from a user who has lost a wallet they were told existed.",
            failure.message!!.contains("absent immediately after writing"),
        )
        assertNull(vault.read())
    }

    @Test
    fun `a corrupted write fails loudly`() {
        val store = FakeBlobStore()
        val codec = object : BlobCodec {
            override fun wrap(plaintext: ByteArray) = plaintext
            override fun unwrap(blob: ByteArray) = "not what was written".toByteArray()
            override fun deleteKey() = Unit
        }

        val failure = assertThrows(SeedWriteVerificationException::class.java) {
            WrappedSeedVault(codec, store).store(Mnemonics.IOS_VECTOR)
        }

        assertTrue(failure.message!!.contains("different value"))
    }

    @Test
    fun `an unreadable write fails loudly and keeps the cause`() {
        val store = FakeBlobStore()
        val codec = FakeBlobCodec().apply {
            unwrapFailure = { IOException("keystore went away mid-write") }
        }

        val failure = assertThrows(SeedWriteVerificationException::class.java) {
            WrappedSeedVault(codec, store).store(Mnemonics.IOS_VECTOR)
        }

        assertEquals("keystore went away mid-write", failure.cause!!.message)
    }

    @Test
    fun `a good write round-trips`() {
        val vault = WrappedSeedVault(FakeBlobCodec(), FakeBlobStore())

        vault.store(Mnemonics.IOS_VECTOR)

        assertEquals(Mnemonics.IOS_VECTOR, vault.read())
        assertEquals(MnemonicPresence.Present, vault.presence())
    }

    @Test
    fun `clearing removes both the blob and the key`() {
        val codec = FakeBlobCodec()
        val vault = WrappedSeedVault(codec, FakeBlobStore())
        vault.store(Mnemonics.IOS_VECTOR)

        vault.clear()

        assertNull(vault.read())
        assertTrue(
            "Leaving the Keystore alias behind would let a later blob written under a " +
                "different seed decrypt under the old key.",
            codec.keyDeleted,
        )
        assertEquals(MnemonicPresence.NoUsableMnemonic, vault.presence())
    }
}
