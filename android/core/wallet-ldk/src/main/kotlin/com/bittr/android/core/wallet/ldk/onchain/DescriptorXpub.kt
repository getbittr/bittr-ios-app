package com.bittr.android.core.wallet.ldk.onchain

/**
 * Reading the account xpub back out of a BIP84 descriptor string.
 *
 * Port of the inline parse in `didStartBDK` (`BDKManager.swift:127–139`):
 *
 * ```swift
 * let components = descriptor.components(separatedBy: "]")
 * if components.count > 1 {
 *     let xpubPart = components[1].split(separator: "/").first
 *     ...
 * }
 * ```
 *
 * A BIP84 external descriptor from `Descriptor.newBip84` looks like
 * `wpkh([1a2b3c4d/84'/1'/0']tpubDC.../0/&#42;)#checksum`, so splitting on `]` and
 * taking everything before the next `/` yields the account xpub.
 *
 * (The wildcard is written as an entity because Kotlin block comments nest: a
 * literal `/` followed by `&#42;` in this KDoc opens a comment that never closes,
 * and the file stops compiling.)
 *
 * ## This string is not cosmetic, which is why it is parsed here and tested
 *
 * `self.xpub` is what the app POSTs to our backend as `xpub_key` at signup
 * (`Transfer2ViewController.swift:344–362`). It is the identifier the server ties
 * the account to, so a malformed value is not a display bug — it is an account
 * that cannot be matched to its own wallet, on a request that happens once.
 *
 * Two things about the iOS version are preserved deliberately:
 *
 * - **Failure is `null`, not a throw.** iOS logs `"Error: Could not extract
 *   XPUB"` and carries on with `self.xpub` unset; the wallet still starts. Making
 *   this throw would turn an unparseable descriptor into a failed wallet start,
 *   which is a worse outcome than a missing backend field.
 * - **`components[1]`, not the last component.** A descriptor has exactly one
 *   `]`, so the two agree today. They stop agreeing the day a multipath
 *   descriptor shows up, and `components[1]` is the behaviour iOS actually has.
 *
 * ## The parity question this does *not* answer
 *
 * The same account xpub is derived a second, independent way — `Bip84Account`,
 * via bitcoin-kmp on the JVM — because the BIT-20 discriminator needs it before
 * anything native is loaded. **Those two derivations agreeing is an assumption
 * until a test asserts it**, and it cannot be asserted here: one side needs BDK's
 * native library. `BdkAccountXpubParityTest` (instrumented) is that test.
 *
 * Proved by `DescriptorXpubTest` for the parsing half.
 */
object DescriptorXpub {

    /**
     * The account xpub embedded in [descriptor], or null if it is not shaped like
     * a descriptor with a key origin.
     */
    fun extract(descriptor: String): String? {
        val afterOrigin = descriptor.split("]").getOrNull(1) ?: return null
        val xpub = afterOrigin.split("/").firstOrNull()
        // `split` never yields an empty list, but it does yield [""] for an empty
        // input — and "" is a value that would sail into the signup request and
        // read as a present-but-blank field on the server.
        return xpub?.takeIf { it.isNotEmpty() }
    }
}
