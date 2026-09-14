package com.bittr.android.core.wallet.ldk.onchain

import com.bittr.android.core.wallet.ldk.cache.CachedOnchainAddressStore
import com.bittr.android.core.wallet.ldk.cache.FileWalletCache
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** `ReceiveOnchain.swift`, over a derivation where address `n` is `"addr-n"`. */
class OnchainAddressPoolTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var store: CachedOnchainAddressStore

    @Before
    fun setUp() {
        store = CachedOnchainAddressStore(FileWalletCache(temporaryFolder.newFolder("cache")))
    }

    /** BDK: peeks `addr-n`, records the highest reveal. */
    private class FakeDerivation(var available: Boolean = true) : AddressDerivation {
        var revealedTo = -1
        override fun peek(index: Int): String? = if (available) "addr-$index" else null
        override fun revealTo(index: Int) {
            revealedTo = maxOf(revealedTo, index)
        }
    }

    /** ldk-node: hands out `addr-0`, `addr-1`, … in order. */
    private class FakeNode(var next: Int = 0) : NodeAddressSource {
        override fun newAddress(): String = "addr-${next++}"
    }

    private fun pool(
        derivation: AddressDerivation = FakeDerivation(),
        node: NodeAddressSource = FakeNode(),
        used: Set<String> = emptySet(),
        unanswerable: Set<String> = emptySet(),
    ) = OnchainAddressPool(
        store = store,
        derivation = derivation,
        node = node,
        usage = { address -> if (address in unanswerable) null else address in used },
    )

    @Test
    fun `a fresh wallet finds the node's address, tops up to ten unused and aligns the node`() = runTest {
        val derivation = FakeDerivation()
        val node = FakeNode()
        val pool = pool(derivation, node)

        pool.manage()

        assertTrue(pool.verified.value)
        val addresses = store.addresses()
        assertEquals(10, addresses.size)
        assertTrue(addresses.none { it.hasBeenUsed })
        assertEquals("addr-0", store.lastAddress())
        assertEquals("The node was walked up to the top of the pool.", 10, node.next)
        assertTrue("BDK reveals a little beyond the pool.", derivation.revealedTo >= 14)
    }

    @Test
    fun `used addresses push the unused run up and the shown address with it`() = runTest {
        store.storeAddresses((0..9).map { PooledAddress("addr-$it", it) })
        store.storeLastAddress("addr-0")
        val pool = pool(node = FakeNode(next = 10), used = setOf("addr-3"))

        pool.manage()

        val addresses = store.addresses()
        assertTrue(addresses[3].hasBeenUsed)
        assertEquals("Ten unused after index 3.", 14, addresses.size)
        assertEquals("The shown address moves out of the used range.", "addr-4", store.lastAddress())
    }

    @Test
    fun `next walks the unused run and says when it is exhausted`() = runTest {
        store.storeAddresses((0..2).map { PooledAddress("addr-$it", it, hasBeenUsed = it == 0) })
        store.storeLastAddress("addr-1")
        val pool = pool()

        assertEquals("addr-2", pool.nextAddress())
        assertEquals("addr-2", pool.currentAddress())
        assertNull(pool.nextAddress())
    }

    @Test
    fun `an unanswerable check keeps the cached pool and still finishes`() = runTest {
        val cached = (0..9).map { PooledAddress("addr-$it", it) }
        store.storeAddresses(cached)
        val pool = pool(unanswerable = setOf("addr-9"))

        pool.manage()

        assertTrue(pool.verified.value)
        assertEquals(cached, store.addresses())
    }

    @Test
    fun `no open BDK wallet ends management without a pool`() = runTest {
        val pool = pool(derivation = FakeDerivation(available = false))

        pool.manage()

        assertTrue(pool.verified.value)
        assertTrue(store.addresses().isEmpty())
    }
}
