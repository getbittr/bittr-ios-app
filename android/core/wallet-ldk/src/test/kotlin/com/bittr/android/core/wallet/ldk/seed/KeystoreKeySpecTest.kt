package com.bittr.android.core.wallet.ldk.seed

import android.security.keystore.KeyProperties
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * **BIT-8 rule 2 — the Keystore key is non-auth-bound.**
 *
 * The rule reads like a weakening and is not. It is the faithful port of the
 * mnemonic's actual iOS accessibility class,
 * `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`CacheManager.swift:358`,
 * re-applied at `:475`) — not `WhenUnlocked`, which is the PIN's class.
 *
 * What makes it scope rather than preference is what breaks otherwise. Two
 * seed reads in the shipping iOS app happen with no PIN and no biometric, and
 * both are recovery paths: `CoreViewController.swift:229` (wallet start at
 * launch after ten failed PIN attempts) and `ResetApp.swift:131` (remove
 * wallet without signing in). `setUserAuthenticationRequired(true)` breaks
 * exactly those, turning post-lockout removal into "the app cannot be
 * recovered". BIT-8 rule 5 says that if an auth-bound key is ever
 * reintroduced, the no-PIN removal path is re-designed *first*.
 *
 * This test reads the built spec back on the JVM. Its on-device complement,
 * `KeystoreKeyInfoTest`, reads `KeyInfo` off a key the platform actually
 * generated; and BIT-18/K1 runs the lock-screen mutation matrix. Three
 * different questions — what we asked for, what we got, and what survives a
 * lock-screen change.
 *
 * Runs at API 28+ because `isUnlockedDeviceRequired` is API 28. At 26–27 the
 * flag does not exist to be set, so the rule holds there by construction.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 34])
class KeystoreKeySpecTest {

    @Test
    fun `neither authentication flag is set`() {
        val spec = WalletKeySpec.build()

        assertFalse(
            "setUserAuthenticationRequired(true) breaks the two unauthenticated seed " +
                "reads iOS deliberately keeps working — including removing the wallet " +
                "after ten failed PIN attempts, which collects no PIN by definition.",
            spec.isUserAuthenticationRequired,
        )
        assertFalse(
            "setUnlockedDeviceRequired(true) is the same mistake wearing a different " +
                "hat: it would stop the node starting in the background, which is the " +
                "property the iOS author changed the accessibility class to preserve " +
                "(CacheManager.swift:473–475).",
            spec.isUnlockedDeviceRequired,
        )
    }

    @Test
    fun `the key is AES-256 GCM with a fresh IV per encryption`() {
        val spec = WalletKeySpec.build()

        assertEquals(256, spec.keySize)
        assertTrue(KeyProperties.BLOCK_MODE_GCM in spec.blockModes)
        assertTrue(KeyProperties.ENCRYPTION_PADDING_NONE in spec.encryptionPaddings)
        assertTrue(
            "GCM fails catastrophically on IV reuse. Letting the Keystore generate " +
                "the IV is what makes reuse unrepresentable rather than merely " +
                "unlikely.",
            spec.isRandomizedEncryptionRequired,
        )
        assertEquals(
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            spec.purposes,
        )
    }

    @Test
    fun `the alias is namespaced and versioned`() {
        // Versioned because a future key-parameter change cannot rewrap in
        // place: the old key is the only thing that can read the old blob. A
        // v2 alias alongside v1 is how that migration stays a migration rather
        // than a data loss.
        assertTrue(WalletKeySpec.ALIAS.startsWith("com.bittr.android."))
        assertTrue(WalletKeySpec.ALIAS.endsWith(".v1"))
    }
}
