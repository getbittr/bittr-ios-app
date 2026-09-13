package com.bittr.android.core.wallet.ldk.onchain

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.wallet.ldk.Bip84AddressVectors.IOS_VECTOR_SIGNET_CHANGE_20
import com.bittr.android.core.wallet.ldk.Bip84AddressVectors.IOS_VECTOR_SIGNET_RECEIVE_20
import com.bittr.android.core.wallet.ldk.Mnemonics
import org.bitcoindevkit.Connection
import org.bitcoindevkit.Descriptor
import org.bitcoindevkit.DescriptorSecretKey
import org.bitcoindevkit.KeychainKind
import org.bitcoindevkit.Mnemonic
import org.bitcoindevkit.Network
import org.bitcoindevkit.Wallet
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * **K4, the parity half — BDK derives the addresses the golden pins.**
 *
 * `wallet-core-spec` §6 states K4 as *"restore-from-mnemonic on a fresh install
 * reproduces the same descriptors, xpub and first 20 addresses as iOS"*.
 * `Bip84AddressVectorTest` covers the first clause on the JVM: bitcoin-kmp
 * reproduces the vectors BIP84 publishes, and the golden in
 * [com.bittr.android.core.wallet.ldk.Bip84AddressVectors] is pinned downstream of
 * that check. This test covers the clause that says **iOS**.
 *
 * ## Why this is the iOS claim and not a second Android claim
 *
 * iOS pins `bdk-swift 1.2.0`; this module pins `bdk-android 1.2.0`. Both are
 * UniFFI bindings over the same Rust core at the same version, so an address BDK
 * produces here is the address BDK produces there — the bindings differ in
 * language, not in derivation. That is what makes "BDK agrees with the golden"
 * equivalent to "iOS agrees with the golden" without a Swift toolchain in CI,
 * and it is the same argument `BdkAccountXpubParityTest` already rests on for
 * the account xpub.
 *
 * It is also why the comparison is against the **shared** golden rather than
 * against a copy: `androidTest` cannot see `test`, and a copied expectation would
 * turn this into BDK-vs-a-stale-snapshot-of-bitcoin-kmp, which is the failure a
 * parity test exists to catch.
 *
 * ## What a failure means
 *
 * That a restored wallet on Android shows the user different addresses from the
 * ones iOS would show for the same mnemonic. Nothing above this layer reports it:
 * the account xpub the backend registered is still right, the node still starts,
 * and the balance still reads correctly for the addresses BDK is actually
 * watching. The damage is that the address handed to a payer is derived from a
 * path the user's other device never scans, so a restore that looked successful
 * silently splits the wallet in two.
 *
 * Instrumented because `bdk-android` is a UniFFI wrapper over a native `.so`.
 * Runs in CI on every push — BIT-59's `wallet-instrumented` job, API 34 emulator —
 * and is named in `check-wallet-instrumented-results.py`'s `REQUIRED` set by
 * method, so a rename or a filter cannot make it vanish inside a green run.
 */
@RunWith(AndroidJUnit4::class)
class BdkAddressParityTest {

    /**
     * Peek the first [count] addresses of [keychain], the way the product does:
     * a BIP84 wallet built from the mnemonic, addresses read by index.
     *
     * `peekAddress` rather than `revealNextAddress` because peeking is a pure
     * function of the descriptor and the index — revealing mutates the wallet's
     * next-index state, which would make the second case in this class depend on
     * the first having run.
     *
     * The connection is in-memory: nothing here should touch the real wallet
     * database, and `Connection.newInMemory()` is the only factory bdk-android
     * 1.2.0 offers that does not open a file (see `BdkStore`).
     */
    private fun bdkAddresses(
        mnemonic: String,
        keychain: KeychainKind,
        count: Int,
        network: Network = Network.SIGNET,
    ): List<String> =
        Mnemonic.fromString(mnemonic).use { bdkMnemonic ->
            // `password: nil` on iOS is the empty passphrase; the Kotlin binding
            // takes a nullable String in the same position.
            DescriptorSecretKey(network, bdkMnemonic, null).use { rootKey ->
                Descriptor.newBip84(rootKey, KeychainKind.EXTERNAL, network).use { external ->
                    Descriptor.newBip84(rootKey, KeychainKind.INTERNAL, network).use { internal ->
                        Connection.newInMemory().use { connection ->
                            Wallet(external, internal, network, connection).use { wallet ->
                                (0 until count).map { index ->
                                    wallet.peekAddress(keychain, index.toUInt()).address.toString()
                                }
                            }
                        }
                    }
                }
            }
        }

    @Test
    fun bdkDerivesTheSameFirst20SignetReceiveAddresses() {
        assertEquals(
            "BDK's receive addresses diverged from the derivation this module proves " +
                "against the published BIP84 vectors. iOS runs the same BDK version, so " +
                "a divergence here is a restored wallet showing the user addresses iOS " +
                "would never show them — and nothing above this layer reports it.",
            IOS_VECTOR_SIGNET_RECEIVE_20,
            bdkAddresses(Mnemonics.IOS_VECTOR, KeychainKind.EXTERNAL, count = 20),
        )
    }

    @Test
    fun bdkDerivesTheSameFirst20SignetChangeAddresses() {
        assertEquals(
            "BDK's change addresses diverged from the JVM derivation. The change " +
                "branch is where the wallet pays itself, so a divergence loses change " +
                "rather than payments — quieter, and equally unrecoverable.",
            IOS_VECTOR_SIGNET_CHANGE_20,
            bdkAddresses(Mnemonics.IOS_VECTOR, KeychainKind.INTERNAL, count = 20),
        )
    }

    @Test
    fun peekingIsStableAcrossWallets() {
        // Each call above builds a fresh Wallet over a fresh in-memory connection.
        // If peekAddress depended on wallet state rather than on the descriptor,
        // the golden would be pinning whatever the first run happened to produce.
        assertEquals(
            bdkAddresses(Mnemonics.IOS_VECTOR, KeychainKind.EXTERNAL, count = 5),
            bdkAddresses(Mnemonics.IOS_VECTOR, KeychainKind.EXTERNAL, count = 5),
        )
    }

    @Test
    fun differentMnemonicsProduceDifferentBdkAddresses() {
        // The negative control. A binding that returned a constant, or that
        // silently ignored the descriptor, would satisfy both golden comparisons
        // the moment the golden was generated from it.
        assertNotEquals(
            bdkAddresses(Mnemonics.IOS_VECTOR, KeychainKind.EXTERNAL, count = 5),
            bdkAddresses(Mnemonics.OTHER, KeychainKind.EXTERNAL, count = 5),
        )
    }

    @Test
    fun receiveAndChangeKeychainsDoNotCollide() {
        // Proves the keychain argument reaches the derivation. Without this, a
        // binding that ignored KeychainKind would pass the receive case and fail
        // the change case in a way that reads as a golden problem.
        val receive = bdkAddresses(Mnemonics.IOS_VECTOR, KeychainKind.EXTERNAL, count = 20).toSet()
        val change = bdkAddresses(Mnemonics.IOS_VECTOR, KeychainKind.INTERNAL, count = 20)

        assertEquals(emptyList<String>(), change.filter { it in receive })
    }
}
