package com.bittr.android.core.wallet.ldk.onchain

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.wallet.ldk.Mnemonics
import com.bittr.android.core.wallet.ldk.bip.Bip84Account
import org.bitcoindevkit.Descriptor
import org.bitcoindevkit.DescriptorSecretKey
import org.bitcoindevkit.KeychainKind
import org.bitcoindevkit.Mnemonic
import org.bitcoindevkit.Network
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * **The two account-xpub derivations agree.**
 *
 * `Bip84Account`'s class comment has named this test since the class was written:
 *
 * > Both derivations must agree, and that is not assumed: the instrumented
 * > `BdkAccountXpubParityTest` derives the account xpub both ways on a device and
 * > asserts they are the same string.
 *
 * **It did not exist.** That is the same failure shape `WalletLayeringGuardTest`
 * and the three Robolectric classes were written to close — a named guarantee with
 * nothing behind it — so it is closed the same way, with the test rather than by
 * softening the comment.
 *
 * ## Why two derivations exist at all
 *
 * The wallet derives its BIP84 account xpub twice, from the same mnemonic, through
 * two unrelated implementations:
 *
 * - **bitcoin-kmp**, on the JVM (`Bip84Account.accountXpub`). The BIT-20
 *   discriminator needs the xpub *before* anything native is loaded, because the
 *   guard decides whether a state directory belongs to the incoming seed before
 *   booting a node against it. Nothing native can run that early.
 * - **BDK**, natively (`Descriptor.newBip84` → `DescriptorXpub.extract`). This is
 *   the one iOS uses, and its output is what the app POSTs as `xpub_key` at signup
 *   (`Transfer2ViewController.swift:344–362`).
 *
 * ## What a failure here would mean
 *
 * Not a discriminator mismatch — the discriminator writes and reads through
 * bitcoin-kmp consistently, so it agrees with itself either way. The damage is
 * elsewhere and quieter:
 *
 * 1. **The account registered with the backend would not be the account the
 *    discriminator identifies**, so the server's idea of the wallet and the
 *    device's idea of its own state would be keyed on different strings.
 * 2. **`IosDerivationVectorTest` asserts the tpub prefix and claims, in its own
 *    comment, that this is "the one BDK puts in a BIP84 descriptor".** That claim
 *    is checked by *no* test on the JVM, because the BDK half cannot run there.
 *    This is the test that earns it.
 *
 * Instrumented because `bdk-android` is a UniFFI wrapper over a native `.so`.
 * **Status: runs in CI** — BIT-59's `wallet-instrumented` job executes
 * `:core:wallet-ldk:connectedDebugAndroidTest` on an API 34 emulator on every push.
 */
@RunWith(AndroidJUnit4::class)
class BdkAccountXpubParityTest {

    /**
     * Derive the account xpub the way iOS does: build the BIP84 external
     * descriptor from the mnemonic, then read the key back out of the descriptor
     * string (`BDKManager.swift:120–139`).
     */
    private fun bdkAccountXpub(mnemonic: String, network: Network): String? {
        Mnemonic.fromString(mnemonic).use { bdkMnemonic ->
            // `password: nil` on iOS is the empty passphrase; the Kotlin binding
            // takes a nullable String in the same position.
            DescriptorSecretKey(network, bdkMnemonic, null).use { rootKey ->
                Descriptor.newBip84(rootKey, KeychainKind.EXTERNAL, network).use { descriptor ->
                    return DescriptorXpub.extract(descriptor.toString())
                }
            }
        }
    }

    @Test
    fun bdkAndBitcoinKmpDeriveTheSameSignetAccountXpub() {
        val fromBdk = bdkAccountXpub(Mnemonics.IOS_VECTOR, Network.SIGNET)
        val fromBitcoinKmp = Bip84Account.accountXpub(Mnemonics.IOS_VECTOR, mainnet = false)

        assertNotNull(
            "Could not extract an xpub from BDK's descriptor. Either the descriptor " +
                "format changed or DescriptorXpub.extract no longer matches it.",
            fromBdk,
        )
        assertEquals(
            "BDK and bitcoin-kmp derived different account xpubs from the same " +
                "mnemonic. The BDK value is what gets registered with the backend as " +
                "xpub_key; the bitcoin-kmp value is what the BIT-20 discriminator " +
                "identifies the LDK state directory with. They must be the same string.",
            fromBitcoinKmp,
            fromBdk,
        )
    }

    @Test
    fun bdkAndBitcoinKmpDeriveTheSameMainnetAccountXpub() {
        // Mainnet uses coin type 0 rather than 1, so it exercises a different
        // derivation path through both implementations. No mainnet key material is
        // involved: this is a throwaway test mnemonic and nothing is persisted or
        // connected to a node.
        val fromBdk = bdkAccountXpub(Mnemonics.IOS_VECTOR, Network.BITCOIN)
        val fromBitcoinKmp = Bip84Account.accountXpub(Mnemonics.IOS_VECTOR, mainnet = true)

        assertNotNull(fromBdk)
        assertEquals(
            "BDK and bitcoin-kmp disagree on the mainnet account xpub (m/84'/0'/0').",
            fromBitcoinKmp,
            fromBdk,
        )
    }

    @Test
    fun theDerivedSignetXpubCarriesTheBip32Prefix() {
        // Earns `IosDerivationVectorTest`'s tpub assertion, which pins the prefix
        // on the bitcoin-kmp side and asserts in its comment that BDK agrees —
        // a claim no JVM test can check.
        val fromBdk = bdkAccountXpub(Mnemonics.IOS_VECTOR, Network.SIGNET)
        assertTrue(
            "BDK's descriptor should embed a tpub, not a vpub. Was: $fromBdk",
            fromBdk!!.startsWith("tpub"),
        )
    }

    @Test
    fun differentMnemonicsProduceDifferentBdkAccounts() {
        // The negative control. Without it, a bug returning a constant — or the
        // same cached descriptor twice — would pass every assertion above.
        val first = bdkAccountXpub(Mnemonics.IOS_VECTOR, Network.SIGNET)
        val second = bdkAccountXpub(Mnemonics.OTHER, Network.SIGNET)

        assertNotNull(first)
        assertNotNull(second)
        assertTrue(
            "Two different mnemonics produced the same account xpub, so the " +
                "derivation is ignoring its input.",
            first != second,
        )
    }
}
