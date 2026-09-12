package com.bittr.android.core.wallet.ldk.seed

import android.os.Build
import android.security.keystore.KeyInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * **BIT-8 rule 2, on a device — what the platform actually gave us.**
 *
 * `KeystoreKeySpecTest` asserts what we *asked* for; this asserts what we
 * *got*, by reading `KeyInfo` back off a key the Android Keystore really
 * generated. The two are different questions and only the second one can
 * catch an OEM build that ignores a flag.
 *
 * The third question — whether the key survives a lock-screen change — is
 * BIT-18/K1, across the device matrix. It is not here because it needs `adb`
 * to mutate the lock screen between two halves of one test, which an
 * instrumented test cannot do to itself.
 *
 * **Status: run in CI.** BIT-59 added the `wallet-instrumented` job, which runs
 * this class on an API 34 `aosp_atd` emulator via
 * `:core:wallet-ldk:connectedDebugAndroidTest` on every push. The previous note
 * here said "written, not yet run", and that was worth its own line for as long
 * as it was true: a test that has never executed is closer to a comment than to
 * a check, and [theBlobRoundTripsThroughTheRealKeystore] is what that costs —
 * it carried an inverted assertion for its whole unrun life, demanding the
 * plaintext BE present in the wrapped blob.
 */
@RunWith(AndroidJUnit4::class)
class KeystoreKeyInfoTest {

    private val alias = "com.bittr.android.wallet.seed.instrumentation-test"

    @Before
    @After
    fun removeTestKey() {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.run {
            if (containsAlias(alias)) deleteEntry(alias)
        }
    }

    @Test
    fun neitherAuthenticationFlagSurvivesKeyGeneration() {
        val info = keyInfoFor(generateWalletKey())

        assertFalse(
            "The generated key reports user authentication as required. Rule 2 says " +
                "it must not be: an auth-bound key breaks the two unauthenticated seed " +
                "reads iOS keeps working, including removing the wallet after ten " +
                "failed PIN attempts.",
            info.isUserAuthenticationRequired,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            assertFalse(
                "The generated key reports unlocked-device as required.",
                info.isUnlockedDeviceRequired,
            )
        }
        assertEquals(256, info.keySize)
    }

    @Test
    fun theBlobRoundTripsThroughTheRealKeystore() {
        val codec = AndroidKeystoreBlobCodec(alias)
        val mnemonic =
            "void super old faith primary cradle behave crucial vault minor walk random"

        val blob = codec.wrap(mnemonic.toByteArray())

        // Searched over the BYTES, not over `String(blob)`. The blob is
        // [ivLength][iv][AES-GCM ciphertext], so almost all of it is not valid
        // UTF-8, and decoding it maps every bad sequence to U+FFFD. That would
        // weaken this assertion in the one direction that matters: a negative
        // search over a string in which arbitrary bytes have already collapsed
        // into replacement characters can miss a match that is really there.
        assertEquals(
            "The blob must not contain the plaintext.",
            -1,
            blob.indexOfSubsequence(mnemonic.toByteArray()),
        )
        assertArrayEquals(mnemonic.toByteArray(), codec.unwrap(blob))
    }

    @Test
    fun twoWrapsOfTheSamePlaintextDiffer() {
        val codec = AndroidKeystoreBlobCodec(alias)
        val plaintext = "the same twelve words".toByteArray()

        // setRandomizedEncryptionRequired(true) means a fresh IV per call.
        // Identical ciphertext would mean IV reuse, which is catastrophic for
        // GCM rather than merely untidy.
        assertFalse(codec.wrap(plaintext).contentEquals(codec.wrap(plaintext)))
    }

    @Test
    fun deletingTheKeyMakesTheBlobUnreadableAndThatIsRecoverable() {
        val codec = AndroidKeystoreBlobCodec(alias)
        val blob = codec.wrap("some words".toByteArray())

        codec.deleteKey()

        // BIT-20 rule 3: this must classify as "no usable mnemonic" — a lost
        // cache that routes to the restore screen — and never as a transient
        // failure that would abort, nor as a success.
        val presence = try {
            AndroidKeystoreBlobCodec(alias).unwrap(blob)
            error("expected the unwrap to fail after the key was deleted")
        } catch (throwable: Throwable) {
            SeedVaultFailures.classify(throwable)
        }
        assertEquals(MnemonicPresence.NoUsableMnemonic, presence)
    }

    /**
     * Records where the key material sits. Deliberately not an assertion:
     * API 26–27 devices legitimately fall back to a software keystore and
     * there is no API to require otherwise, so a fixed expectation here would
     * be a test that fails honestly on hardware we support.
     */
    @Test
    fun recordTheObservedSecurityLevel() {
        AndroidKeystoreBlobCodec(alias).wrap("x".toByteArray())
        val level = AndroidKeystoreBlobCodec(alias).observedSecurityLevel()

        println(
            "KEYSTORE_SECURITY_LEVEL api=${Build.VERSION.SDK_INT} " +
                "device=${Build.MANUFACTURER}/${Build.MODEL} level=$level",
        )
        assertTrue("Expected a security level to be reported.", level.isNotBlank())
    }

    /** First index at which [needle] occurs in this array, or -1. */
    private fun ByteArray.indexOfSubsequence(needle: ByteArray): Int {
        if (needle.isEmpty() || needle.size > size) return -1
        for (start in 0..size - needle.size) {
            if ((needle.indices).all { this[start + it] == needle[it] }) return start
        }
        return -1
    }

    private fun generateWalletKey(): SecretKey =
        KeyGenerator.getInstance("AES", "AndroidKeyStore")
            .apply { init(WalletKeySpec.build(alias)) }
            .generateKey()

    private fun keyInfoFor(key: SecretKey): KeyInfo =
        SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
            .getKeySpec(key, KeyInfo::class.java) as KeyInfo
}
