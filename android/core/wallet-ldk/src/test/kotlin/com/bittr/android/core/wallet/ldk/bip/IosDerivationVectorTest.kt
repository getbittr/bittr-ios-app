package com.bittr.android.core.wallet.ldk.bip

import com.bittr.android.core.wallet.ldk.Mnemonics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * **K5 — BIP32 derivation is byte-identical to iOS.**
 *
 * The fixture is not invented for Android. It is the vector already pinned in
 * the iOS source at `BitcoinMessage.swift:363–367`, read from this repository:
 * a 12-word mnemonic, the path `m/84'/1'/0'/0/0`, and the private and public
 * keys iOS's own hand-rolled BIP32 is expected to produce. Using the same
 * constants is the point — it is what makes this a parity test rather than a
 * self-consistency test.
 *
 * Why it matters beyond tidiness: the backend verifies signatures made with
 * these keys (`Transfer2ViewController.swift:344–362` registers the account
 * xpub at signup), so a derivation that differs from iOS's by one byte
 * produces a wallet the server does not recognise as the user's.
 */
class IosDerivationVectorTest {

    private companion object {
        // ios/bittr/Helpers/BitcoinMessage.swift:363–367
        const val PATH = "m/84'/1'/0'/0/0"
        const val EXPECTED_PRIVATE_KEY =
            "4b596bede18150db341c9b1a71e1549bb69e3669805895ff8ad8ca873f76be09"
        const val EXPECTED_PUBLIC_KEY =
            "038338ab3db0f0e1ed78e295e4074197e6a0ab97195013690ecdf5a37998211049"
    }

    @Test
    fun `first receive key matches the iOS vector`() {
        val derived = Bip84Account.derive(Mnemonics.IOS_VECTOR, PATH)

        assertEquals(
            "BIP32 private key at $PATH diverged from the iOS vector. " +
                "The backend verifies signatures from this key; a divergence here is a " +
                "wallet the server will not recognise as the user's.",
            EXPECTED_PRIVATE_KEY,
            derived.privateKey.toHex(),
        )
        assertEquals(
            "Compressed public key at $PATH diverged from the iOS vector.",
            EXPECTED_PUBLIC_KEY,
            derived.publicKey.toHex(),
        )
    }

    @Test
    fun `the account xpub is the one BDK puts in a BIP84 descriptor`() {
        val xpub = Bip84Account.accountXpub(Mnemonics.IOS_VECTOR, mainnet = false)

        // tpub, not vpub: BDK's `Descriptor.newBip84` embeds the BIP32-prefixed
        // key, and iOS reads its `xpub_key` straight out of that descriptor
        // string (`BDKManager.swift:127–139`). Encoding this as vpub would be
        // "more correct" for BIP84 and wrong for parity.
        assertTrue(
            "Account xpub should carry the testnet BIP32 prefix, was: $xpub",
            xpub.startsWith("tpub"),
        )
        assertEquals(
            "Account derivation is not stable across calls.",
            xpub,
            Bip84Account.accountXpub(Mnemonics.IOS_VECTOR, mainnet = false),
        )
        assertNotEquals(
            "Mainnet and non-mainnet accounts must not collide — they are different " +
                "coin types (m/84'/0' vs m/84'/1') and a collision would let signet " +
                "state be adopted by a mainnet wallet.",
            xpub,
            Bip84Account.accountXpub(Mnemonics.IOS_VECTOR, mainnet = true),
        )
    }

    @Test
    fun `different mnemonics produce different accounts`() {
        assertNotEquals(
            Bip84Account.accountXpub(Mnemonics.IOS_VECTOR, mainnet = false),
            Bip84Account.accountXpub(Mnemonics.OTHER, mainnet = false),
        )
    }
}
