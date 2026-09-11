package com.bittr.android

import com.bittr.android.SourceTree.repoPath
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the storage model BIT-8 decided, in the one place a JVM test can see it.
 *
 * The seed is wrapped by an Android Keystore AES/GCM key that is **not** bound to
 * user authentication and **not** bound to the device being unlocked. That is the
 * faithful port of the mnemonic's iOS Keychain class
 * `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`CacheManager.swift:358`).
 *
 * Adding `setUserAuthenticationRequired(true)` or `setUnlockedDeviceRequired(true)`
 * looks like a safe hardening and is not: it would make the wallet unable to act
 * while the screen is off — which BIT-6's node has to do to answer an incoming
 * HTLC — and would be unusable on a device with no lockscreen credential at all.
 * Both are one-line changes that no other test in the build would notice, so the
 * rule is checked here rather than left to a code review nobody schedules.
 *
 * This is not a ban either: if the decision is revisited, change BIT-8 and this
 * test together. What it prevents is changing it by accident.
 */
class KeystoreKeySpecGuardTest {

    private companion object {
        const val STORE = "core/wallet-keystore/src/main/kotlin/com/bittr/android/" +
            "core/wallet/keystore/KeystoreSecureStore.kt"

        /** Flags that would harden the key past what iOS does. */
        val FORBIDDEN_CALLS = listOf(
            "setUserAuthenticationRequired(true)",
            "setUnlockedDeviceRequired(true)",
        )

        /** What the key must be, so a weakening is caught as well as a hardening. */
        val REQUIRED_CALLS = listOf(
            "KeyProperties.BLOCK_MODE_GCM",
            "KeyProperties.ENCRYPTION_PADDING_NONE",
            "setKeySize(KEY_BITS)",
        )
    }

    private val source: String by lazy {
        val file = File(SourceTree.root, STORE)
        assertTrue(
            "Expected the Keystore store at ${file.repoPath()}. If it moved, update " +
                "this guard — do not delete it.",
            file.isFile,
        )
        file.readText()
    }

    @Test
    fun `the seed key is not bound to user authentication`() {
        FORBIDDEN_CALLS.forEach { call ->
            assertTrue(
                "$STORE calls $call. That is a deliberate departure from BIT-8's " +
                    "storage model, which ports iOS's afterFirstUnlockThisDeviceOnly. " +
                    "A key bound this way cannot be used while the screen is off, and " +
                    "cannot be created at all on a device with no lockscreen " +
                    "credential. Change BIT-8 first, then this test.",
                !source.contains(call),
            )
        }
    }

    @Test
    fun `the seed key is AES-256 GCM`() {
        REQUIRED_CALLS.forEach { call ->
            assertTrue(
                "$STORE no longer configures $call. The seed blob's confidentiality " +
                    "rests entirely on this key spec.",
                source.contains(call),
            )
        }
        assertTrue(
            "$STORE must seal with AES/GCM/NoPadding.",
            source.contains("\"AES/GCM/NoPadding\""),
        )
        assertEquals(
            "Key size must stay at 256 bits.",
            256,
            Regex("KEY_BITS = (\\d+)").find(source)?.groupValues?.get(1)?.toInt(),
        )
    }

    /**
     * A `catch` that turns an unreadable seed into `null` would present a user whose
     * key material is intact-but-unreadable with a fresh signup screen, and the words
     * they wrote down would no longer match the wallet the app then created.
     */
    @Test
    fun `an unreadable seed is an error, never an empty result`() {
        assertTrue(
            "$STORE must not return null from read() on a decryption failure.",
            source.contains("throw WalletStorageException(\"Could not decrypt"),
        )
    }
}
