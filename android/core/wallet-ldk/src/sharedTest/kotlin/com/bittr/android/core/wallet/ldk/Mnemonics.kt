package com.bittr.android.core.wallet.ldk

/**
 * Test mnemonics, visible to both the JVM tests and the instrumented tests.
 *
 * **Shared rather than duplicated, on purpose.** [IOS_VECTOR] is not an Android
 * invention — it is the vector pinned in the iOS source at
 * `BitcoinMessage.swift:363–367`, and three tests now derive from it through two
 * different implementations:
 *
 * - `IosDerivationVectorTest` (JVM) — bitcoin-kmp must reproduce iOS's keys.
 * - `SwapRefundKeyDerivationTest` (JVM) — BIT-8 rule 1's re-derivability.
 * - `BdkAccountXpubParityTest` (instrumented) — BDK must agree with bitcoin-kmp.
 *
 * The third one is why this file exists. `androidTest` cannot see `test`, so the
 * parity test could only have reached this constant by copying it — and a copied
 * vector that drifts turns a parity test into a test that compares one
 * implementation against a stale expectation of itself. This directory is added
 * to both source sets in `build.gradle.kts`.
 *
 * Neither value is secret and neither is ever used against a real network: no
 * mainnet keys, no production node access, no real funds.
 */
object Mnemonics {
    /** `ios/bittr/Helpers/BitcoinMessage.swift:363–367`. */
    const val IOS_VECTOR = "void super old faith primary cradle behave crucial vault minor walk random"

    /**
     * The mnemonic BIP84 publishes its own test vectors against.
     *
     * This is external ground truth: the addresses it produces are stated in the
     * BIP itself, so a test against them checks our derivation against the
     * standard rather than against another copy of ourselves.
     * `Bip84AddressVectorTest` is what uses it that way.
     */
    const val BIP84_VECTOR =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

    /**
     * A valid mnemonic that is not [IOS_VECTOR], for negative controls.
     *
     * Same string as [BIP84_VECTOR] — kept as a separate name because the two
     * roles are unrelated, and a test asserting "two mnemonics differ" should not
     * read as though it were asserting something about the BIP84 vectors.
     */
    const val OTHER = BIP84_VECTOR
}
