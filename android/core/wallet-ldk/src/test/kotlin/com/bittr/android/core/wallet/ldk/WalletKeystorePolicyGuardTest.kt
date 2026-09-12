package com.bittr.android.core.wallet.ldk

import com.bittr.android.core.wallet.ldk.WalletSourceTree.modulePath
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The negative half of BIT-8 rules 2, 3 and 5, and of §3's Direct Boot clause.
 *
 * Every other test in this module proves the code is right *today*. This one
 * keeps it right: each banned symbol below is a single line someone could add
 * in good faith — tightening security, or reaching for the obvious API — that
 * would break a decided rule while leaving every behavioural test green.
 *
 * These are **routing rules, not bans on ever thinking about the topic**. If
 * one of them genuinely needs to change, the way to change it is to re-open
 * the issue named in the failure message. That is the point: the rule was a
 * founder's decision with a cost attached, and the cost is not visible from
 * the call site.
 */
class WalletKeystorePolicyGuardTest {

    private data class BannedSymbol(
        val symbol: String,
        val why: String,
    )

    private companion object {
        val BANNED = listOf(
            BannedSymbol(
                "setUserAuthenticationRequired",
                "BIT-8 rule 2. An auth-bound key breaks the two unauthenticated seed " +
                    "reads iOS keeps working — CoreViewController.swift:229 (start after " +
                    "ten failed PIN attempts) and ResetApp.swift:131 (remove wallet " +
                    "without signing in). Neither has a PIN to offer, so the post-lockout " +
                    "removal path becomes 'the app cannot be recovered'. BIT-8 rule 5: if " +
                    "this is reintroduced, that path is re-designed FIRST.",
            ),
            BannedSymbol(
                "setUnlockedDeviceRequired",
                "BIT-8 rule 2. Stops the node starting in the background — the property " +
                    "the iOS author changed the mnemonic's accessibility class to preserve " +
                    "(CacheManager.swift:473–475).",
            ),
            BannedSymbol(
                "createDeviceProtectedStorageContext",
                "seed-storage-security §3. Device-encrypted storage is readable before " +
                    "the first unlock, so moving the blob there downgrades it below iOS's " +
                    "afterFirstUnlockThisDeviceOnly — silently, with every other test in " +
                    "this module still green. The CE default is the whole mechanism.",
            ),
            BannedSymbol(
                "directBootAware",
                "Same reason as the line above, from the manifest side.",
            ),
            BannedSymbol(
                "PBEKeySpec",
                // The biometric unlock prompt is named obliquely on purpose: :app's
                // BiometricApiGuardTest bans that class name outside the files that
                // gate it, and it scans this module's sources too. A failure message
                // is a string literal, so it is code as far as that scan is
                // concerned — naming the class here would trip a second guard and
                // teach whoever hits it that allowlisting a file with no call in it
                // is normal.
                "BIT-8 rule 5. No PIN-derived wrapping. A 4–6 digit PIN is a verifier, " +
                    "not key material, and wrapping under it breaks the no-PIN wallet-" +
                    "removal path and conflicts with biometric unlock (BIT-13), which " +
                    "collects no PIN at all.",
            ),
            BannedSymbol(
                "SecretKeyFactory.getInstance(\"PBKDF2",
                "BIT-8 rule 5, as above.",
            ),
            BannedSymbol(
                "androidx.security.crypto",
                "seed-storage-security §4. EncryptedSharedPreferences hides exactly the " +
                    "key parameters rules 2 and 5 are stated in terms of, which would make " +
                    "them unenforceable and untestable. Use KeyGenParameterSpec + Cipher.",
            ),
        )
    }

    @Test
    fun `no banned key-handling symbol appears in the wallet implementation`() {
        val offenders = WalletSourceTree.mainSources().flatMap { file ->
            // Comments stripped: this module's KDoc names every banned symbol
            // on purpose, next to the thing it constrains. See
            // WalletSourceTree.codeOf.
            val code = WalletSourceTree.codeOf(file)
            BANNED.filter { it.symbol in code }
                .map { "${file.modulePath()} references ${it.symbol}\n      ${it.why}" }
        }

        assertTrue(
            "A decided rule in BIT-8 / BIT-20 has been broken by a single line. These " +
                "are founder's decisions with costs that are not visible from the call " +
                "site; changing one means re-opening the issue named below, not a " +
                "judgement call in the code.\n\n  " +
                offenders.joinToString("\n\n  "),
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the guard is actually scanning the sources it claims to`() {
        // A source-scan test that walks an empty tree passes silently. This
        // asserts the scan can see a symbol it is supposed to see, so a green
        // result above means "checked", not "found nothing to check".
        val sources = WalletSourceTree.mainSources()
        assertTrue(
            "Expected to find the Keystore spec among the scanned sources.",
            sources.any { "KeyGenParameterSpec" in WalletSourceTree.codeOf(it) },
        )
        assertTrue(
            "Expected to find the quarantine implementation among the scanned sources.",
            sources.any { "quarantineLightningState" in WalletSourceTree.codeOf(it) },
        )
    }
}
