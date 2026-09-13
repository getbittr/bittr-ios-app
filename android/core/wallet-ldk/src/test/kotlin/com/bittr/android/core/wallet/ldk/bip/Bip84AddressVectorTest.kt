package com.bittr.android.core.wallet.ldk.bip

import com.bittr.android.core.wallet.ldk.Bip84AddressVectors.IOS_VECTOR_SIGNET_CHANGE_20
import com.bittr.android.core.wallet.ldk.Bip84AddressVectors.IOS_VECTOR_SIGNET_RECEIVE_20
import com.bittr.android.core.wallet.ldk.Mnemonics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * **K4, the address half — our BIP84 derivation against the standard's own vectors.**
 *
 * `wallet-core-spec` §6 states K4 as *"restore-from-mnemonic on a fresh install
 * reproduces the same descriptors, xpub and first 20 addresses as iOS"*. The xpub
 * was covered (`IosDerivationVectorTest`, `BdkAccountXpubParityTest`); the
 * addresses were not covered anywhere, by anything.
 *
 * ## Why the anchor is BIP84 and not a golden file
 *
 * The obvious way to write this test is to derive 20 addresses, paste them into
 * the file, and assert they do not change. That detects a regression and nothing
 * else: if the derivation is wrong today, the golden pins it wrong, and the test
 * passes forever on a wallet whose addresses nobody holds the keys for.
 *
 * So the first three cases here assert against the vectors **BIP84 publishes**,
 * for the mnemonic BIP84 publishes them for. Those constants were not produced by
 * this code and cannot be regenerated from it. Once they hold, the derivation is
 * known-good, and [theFirst20ReceiveAddressesForTheIosVector] can pin a golden for
 * the iOS mnemonic that means something — it is a golden from a checked
 * implementation rather than from an assumed one.
 *
 * The golden is the cross-implementation contract: `BdkAddressParityTest` asserts
 * BDK reproduces those same strings on a device, and BDK is what iOS runs.
 *
 * ## What a failure means
 *
 * Not a display bug. A restored wallet showing addresses derived differently from
 * iOS's looks completely healthy — the account xpub the backend knows is right,
 * the node starts, the balance reads zero because nothing was ever paid to these
 * addresses — while every address handed to a payer belongs to a wallet the user
 * cannot spend from. That failure is silent at every layer above this one, which
 * is why the derivation is anchored rather than pinned.
 */
class Bip84AddressVectorTest {

    private companion object {
        /**
         * From BIP84's "Test vectors" section, for [Mnemonics.BIP84_VECTOR].
         *
         * Mainnet, because that is the chain BIP84 states its vectors on. No
         * mainnet key material is involved: the mnemonic is the published
         * all-`abandon` vector, nothing is persisted, and nothing connects to a
         * network.
         */
        const val FIRST_RECEIVE = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
        const val SECOND_RECEIVE = "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g"
        const val FIRST_CHANGE = "bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el"
    }

    @Test
    fun `the first receive address matches the published BIP84 vector`() {
        assertEquals(
            "m/84'/0'/0'/0/0 diverged from the address BIP84 publishes for this " +
                "mnemonic. Our derivation is wrong, not merely different.",
            FIRST_RECEIVE,
            Bip84Addresses.addressAt(Mnemonics.BIP84_VECTOR, mainnet = true, change = 0, index = 0),
        )
    }

    @Test
    fun `the second receive address matches the published BIP84 vector`() {
        // Index 1 as well as 0: a derivation that ignored the index would satisfy
        // the case above and fail here.
        assertEquals(
            "m/84'/0'/0'/0/1 diverged from the published BIP84 vector.",
            SECOND_RECEIVE,
            Bip84Addresses.addressAt(Mnemonics.BIP84_VECTOR, mainnet = true, change = 0, index = 1),
        )
    }

    @Test
    fun `the first change address matches the published BIP84 vector`() {
        // And the change branch, which is the one a derivation that ignored the
        // change level would get wrong while every receive case passed.
        assertEquals(
            "m/84'/0'/0'/1/0 diverged from the published BIP84 vector. The change " +
                "branch is where a wallet's own change is paid; getting it wrong " +
                "loses the change rather than the payment.",
            FIRST_CHANGE,
            Bip84Addresses.addressAt(Mnemonics.BIP84_VECTOR, mainnet = true, change = 1, index = 0),
        )
    }

    @Test
    fun `the bulk helpers agree with the single-address derivation`() {
        // receiveAddresses/changeAddresses derive the account key once and reuse
        // it; addressAt re-derives per call. They are separate code paths and only
        // the second one is checked against BIP84 above.
        val receive = Bip84Addresses.receiveAddresses(Mnemonics.BIP84_VECTOR, mainnet = true, count = 2)
        assertEquals(listOf(FIRST_RECEIVE, SECOND_RECEIVE), receive)

        val change = Bip84Addresses.changeAddresses(Mnemonics.BIP84_VECTOR, mainnet = true, count = 1)
        assertEquals(listOf(FIRST_CHANGE), change)
    }

    @Test
    fun theFirst20ReceiveAddressesForTheIosVector() {
        // The golden K4 names, on the mnemonic iOS pins, on the chain the regtest
        // build runs. Earned by the BIP84 cases above; asserted against BDK on a
        // device by BdkAddressParityTest.
        assertEquals(
            IOS_VECTOR_SIGNET_RECEIVE_20,
            Bip84Addresses.receiveAddresses(Mnemonics.IOS_VECTOR, mainnet = false, count = 20),
        )
    }

    @Test
    fun theFirst20ChangeAddressesForTheIosVector() {
        assertEquals(
            IOS_VECTOR_SIGNET_CHANGE_20,
            Bip84Addresses.changeAddresses(Mnemonics.IOS_VECTOR, mainnet = false, count = 20),
        )
    }

    @Test
    fun `signet addresses carry the testnet prefix and are all distinct`() {
        val receive = Bip84Addresses.receiveAddresses(Mnemonics.IOS_VECTOR, mainnet = false, count = 20)

        assertTrue(
            "Signet P2WPKH addresses should be bech32 with the tb HRP. Was: ${receive.first()}",
            receive.all { it.startsWith("tb1q") },
        )
        assertEquals(
            "Addresses repeat, so the derivation is not varying with the index. " +
                "Reusing one address across a restore is an on-chain privacy leak " +
                "and a sign the index is being dropped.",
            20,
            receive.toSet().size,
        )
    }

    @Test
    fun `receive and change branches never collide`() {
        val receive = Bip84Addresses.receiveAddresses(Mnemonics.IOS_VECTOR, mainnet = false, count = 20).toSet()
        val change = Bip84Addresses.changeAddresses(Mnemonics.IOS_VECTOR, mainnet = false, count = 20)

        assertEquals(
            "A change address matched a receive address, so the change level is " +
                "not reaching the derivation path.",
            emptyList<String>(),
            change.filter { it in receive },
        )
    }

    @Test
    fun `a different mnemonic produces different addresses`() {
        // The negative control. A derivation returning a constant, or silently
        // ignoring the mnemonic, passes every golden above once the golden is
        // written from it.
        assertNotEquals(
            Bip84Addresses.receiveAddresses(Mnemonics.IOS_VECTOR, mainnet = false, count = 5),
            Bip84Addresses.receiveAddresses(Mnemonics.OTHER, mainnet = false, count = 5),
        )
    }

    @Test
    fun `mainnet and signet accounts do not share addresses`() {
        // Different coin types (m/84'/0' vs m/84'/1'). A collision would mean
        // signet-derived state could be adopted by a mainnet wallet.
        val signet = Bip84Addresses.receiveAddresses(Mnemonics.IOS_VECTOR, mainnet = false, count = 5)
        val mainnet = Bip84Addresses.receiveAddresses(Mnemonics.IOS_VECTOR, mainnet = true, count = 5)

        assertEquals(emptyList<String>(), mainnet.filter { it in signet.toSet() })
    }

    @Test
    fun `an out-of-range change level is rejected rather than derived`() {
        // BIP44 defines 0 and 1. Deriving at 2 would produce a real, spendable
        // address off a path no wallet scans — funds paid to it are invisible to
        // BDK's own recovery.
        listOf(-1, 2).forEach { change ->
            try {
                Bip84Addresses.addressAt(Mnemonics.IOS_VECTOR, mainnet = false, change = change, index = 0)
                throw AssertionError("change=$change should have been rejected")
            } catch (expected: IllegalArgumentException) {
                assertTrue(expected.message!!.contains("change level"))
            }
        }
    }
}
