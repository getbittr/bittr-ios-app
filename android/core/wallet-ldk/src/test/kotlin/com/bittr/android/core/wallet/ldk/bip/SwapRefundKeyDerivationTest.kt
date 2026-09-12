package com.bittr.android.core.wallet.ldk.bip

import com.bittr.android.core.wallet.ldk.Mnemonics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * **K6 / BIT-8 rule 1 — the mnemonic is the single root of recovery.**
 *
 * Rule 1 bans a second irreplaceable secret that is not derivable from the
 * seed. The Boltz swap refund keys look like exactly that: iOS keeps them in
 * the Keychain as `swapkey_<boltzID>` items, and losing a refund key while a
 * swap is in flight loses the refund.
 *
 * They are not, and this is the test that says so rather than the comment.
 * `SwapManager.swift:196–203` derives them at `m/503'/0'/0'/0/<swapIndex>`,
 * with the index kept in the cache — so given the index, the key comes back
 * from the mnemonic alone. The Keychain copy is a cache like the seed blob.
 *
 * This is load-bearing for "restore onto a fresh device": that path has to
 * reason about in-flight swaps, and this is what makes it tractable. Had this
 * come back the other way, rule 1 would already be violated by the shipping
 * iOS app and BIT-8 would need re-opening.
 */
class SwapRefundKeyDerivationTest {

    @Test
    fun `refund keys are re-derivable from the mnemonic given the swap index`() {
        val indices = 0..8

        val first = indices.associateWith {
            Bip84Account.swapRefundKey(Mnemonics.IOS_VECTOR, it).privateKey.toHex()
        }
        // "After data loss" is exactly this: nothing but the mnemonic and the
        // index survives, and the same keys come back.
        val second = indices.associateWith {
            Bip84Account.swapRefundKey(Mnemonics.IOS_VECTOR, it).privateKey.toHex()
        }

        assertEquals(
            "Swap refund keys must be reproducible from the mnemonic and the cached " +
                "swap index alone. If they are not, they are a second irreplaceable " +
                "secret and BIT-8 rule 1 does not hold.",
            first,
            second,
        )
        assertEquals(
            "Each swap index must yield a distinct key.",
            indices.count(),
            first.values.toSet().size,
        )
    }

    @Test
    fun `the refund path is the iOS path, not the wallet path`() {
        // m/503'/0'/0'/0/<i>, per SwapManager.swift:198 — a purpose-503 tree,
        // deliberately disjoint from the BIP84 wallet at m/84'. Deriving refund
        // keys inside the wallet's own account would reuse keys the wallet also
        // spends from.
        assertEquals(
            Bip84Account.derive(Mnemonics.IOS_VECTOR, "m/503'/0'/0'/0/3").privateKey.toHex(),
            Bip84Account.swapRefundKey(Mnemonics.IOS_VECTOR, 3).privateKey.toHex(),
        )
        assertNotEquals(
            Bip84Account.derive(Mnemonics.IOS_VECTOR, "m/84'/1'/0'/0/3").privateKey.toHex(),
            Bip84Account.swapRefundKey(Mnemonics.IOS_VECTOR, 3).privateKey.toHex(),
        )
    }
}
