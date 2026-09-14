package com.bittr.android.core.wallet.ldk.onchain

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * One address in the receive pool — iOS's `OnchainAddress`.
 *
 * @property index the BIP84 external index BDK derived it at.
 * @property hasBeenUsed the chain has seen a transaction to it. Only ever goes false → true.
 */
data class PooledAddress(val address: String, val index: Int, val hasBeenUsed: Boolean = false)

/** Where the pool and the address on screen are remembered — `CacheManager`'s two keys. */
interface OnchainAddressStore {
    fun addresses(): List<PooledAddress>
    fun storeAddresses(addresses: List<PooledAddress>)
    fun lastAddress(): String?
    fun storeLastAddress(address: String)
}

/**
 * BDK's external keychain: `getAddress(atIndex:doReveal:)` and `revealAddresses(toIndex:)`
 * (`BDKManager.swift:522–550`).
 */
interface AddressDerivation {

    /** The address at [index], without revealing it. Null when no wallet is open. */
    fun peek(index: Int): String?

    /** Reveal (and persist) every address up to [index], so light syncs watch them. */
    fun revealTo(index: Int)
}

/** ldk-node's `onchainPayment().newAddress()`. Null when there is no node. */
fun interface NodeAddressSource {
    fun newAddress(): String?
}

/** `String.checkHasBeenUsed()` — Esplora's `chain_stats.tx_count > 0`, or null if it could not tell. */
fun interface AddressUsageCheck {
    suspend fun hasBeenUsed(address: String): Boolean?
}

/**
 * The on-chain receive pool — `ReceiveOnchain.swift`, the half iOS keeps on
 * `CoreViewController`.
 *
 * ## Why Receive does not simply ask the node for an address
 *
 * Two wallets share the seed: BDK's, which syncs and shows the on-chain history, and
 * ldk-node's, which funds channels. A fresh `newAddress()` on every Receive would walk
 * ldk-node's index ever upward, past BDK's stop gap, into addresses BDK never scans — money
 * that arrives and never shows. So iOS keeps a pool of BDK-derived addresses, reveals them
 * in BDK so light syncs watch them, checks which have been used, keeps ten unused ones
 * ahead, and drags ldk-node's revealed index along behind ([alignNode]) so both wallets
 * agree on what has been handed out. This is that, with the same numbers.
 *
 * ## The sequence
 *
 * 1. **No pool yet** ([manage] on a fresh install): ask ldk-node for its latest address,
 *    find it in BDK's derivation by walking up from index 0 (at most
 *    [maxSearchIndex]), reveal that range in BDK, and cache it as the pool.
 * 2. **Check usage**, newest batch of ten first, stopping at the first used address —
 *    everything below it is treated as used.
 * 3. **Top up** to ten unused addresses past the highest used one, align ldk-node, and
 *    check again. Otherwise reveal a little beyond the pool (a channel closure reveals
 *    the next node address) and make sure the address on screen is an unused one.
 *
 * Whatever happens, [verified] becomes true at the end — including when a check fails
 * and the cached pool is kept. Receive waits on it, and iOS's rule is that an unverifiable
 * pool is still better than a spinner that never stops.
 */
class OnchainAddressPool(
    private val store: OnchainAddressStore,
    private val derivation: AddressDerivation,
    private val node: NodeAddressSource,
    private val usage: AddressUsageCheck,
    private val maxSearchIndex: Int = MAX_SEARCH_INDEX,
    private val log: (String) -> Unit = {},
) {

    private val _verified = MutableStateFlow(false)

    /** `onchainAddressesVerified`. */
    val verified: StateFlow<Boolean> = _verified.asStateFlow()

    private val managing = Mutex()

    /** `getCachedOnchainAddress()` — the address Receive is showing. */
    fun currentAddress(): String? = store.lastAddress()

    /**
     * `getNextUnusedAddress()` — the address after the one on screen, within the unused
     * run, made current. Null when the pool has none left.
     */
    fun nextAddress(): String? {
        val pool = store.addresses()
        if (pool.isEmpty()) return null

        val cached = store.lastAddress()
        val firstUnused = pool.indexOfLast { it.hasBeenUsed } + 1
        val cachedIndex = pool.indexOfFirst { it.index >= firstUnused && it.address == cached }
        val nextIndex = if (cachedIndex >= 0) cachedIndex + 1 else firstUnused

        if (nextIndex >= pool.size) {
            log("No unused onchain address left to reveal.")
            return null
        }
        return pool[nextIndex].address.also(store::storeLastAddress)
    }

    /**
     * `manageOnchainAddresses()`. A second call while one is running returns at once, as
     * iOS's `isManagingOnchainAddresses` guard does.
     */
    suspend fun manage() {
        if (!managing.tryLock()) {
            log("Onchain address management is already running.")
            return
        }
        try {
            val cached = store.addresses()
            if (cached.isEmpty()) reveal() else check(cached)
        } finally {
            _verified.value = true
            managing.unlock()
        }
    }

    private suspend fun reveal() {
        val latest = node.newAddress() ?: return log("Could not derive an address (no node).")

        val peeked = mutableListOf<String>()
        var latestIndex: Int? = null
        for (index in 0..maxSearchIndex) {
            val address = derivation.peek(index) ?: return log("BDK wallet unavailable while identifying revealed addresses.")
            peeked += address
            if (address == latest) {
                latestIndex = index
                break
            }
        }
        if (latestIndex == null) {
            // BDK and ldk-node derive different addresses from the same seed.
            return log("Could not match the node's address within $maxSearchIndex derived addresses.")
        }

        derivation.revealTo(latestIndex)
        val pool = peeked.mapIndexed { index, address -> PooledAddress(address, index) }
        store.storeAddresses(pool)
        check(pool)
    }

    private suspend fun check(initial: List<PooledAddress>) {
        var pool = initial.toMutableList()
        while (true) {
            if (pool.isEmpty()) return

            val highestUsed = highestUsedIndex(pool) ?: return
            val firstUnused = highestUsed.value + 1
            var unused = pool.size - firstUnused

            if (unused >= POOL_UNUSED_TARGET) {
                // Reveal a little beyond the pool: a channel closure reveals the next node
                // address, and BDK should already be watching it.
                derivation.revealTo(pool.size + REVEAL_BEYOND_POOL)
                val cached = store.lastAddress()
                val cachedInUnusedRun = pool.any { it.index >= firstUnused && it.address == cached }
                if (!cachedInUnusedRun && firstUnused < pool.size) {
                    store.storeLastAddress(pool[firstUnused].address)
                }
                log("Onchain address management successful.")
                return
            }

            var index = pool.size
            while (unused < POOL_UNUSED_TARGET) {
                derivation.revealTo(index)
                val address = derivation.peek(index) ?: return log("BDK wallet unavailable while revealing more addresses.")
                pool += PooledAddress(address, index)
                index++
                unused++
            }
            alignNode(pool.size - 1)
            store.storeAddresses(pool)
        }
    }

    /**
     * Walk the pool from the top in batches of ten and return the index of the highest used
     * address, or `Found(-1)` when none is. Null when a check could not be answered, which
     * ends management with the cached pool kept.
     */
    private suspend fun highestUsedIndex(pool: MutableList<PooledAddress>): Found? {
        var batchTop = pool.size - 1
        while (batchTop >= 0) {
            val batchBottom = maxOf(0, batchTop - (CHECK_BATCH - 1))
            val toCheck = (batchBottom..batchTop).filterNot { pool[it].hasBeenUsed }
            val outcomes: Map<Int, Boolean?> = coroutineScope {
                toCheck.map { index -> async { index to usage.hasBeenUsed(pool[index].address) } }.awaitAll().toMap()
            }

            for (index in batchTop downTo batchBottom) {
                if (pool[index].hasBeenUsed) return Found(index)
                val used = outcomes[index] ?: run {
                    log("Could not verify onchain address at index $index; keeping the cached pool.")
                    return null
                }
                if (used) {
                    pool[index] = pool[index].copy(hasBeenUsed = true)
                    store.storeAddresses(pool)
                    return Found(index)
                }
            }
            batchTop = batchBottom - 1
        }
        return Found(-1)
    }

    /** `alignLDKNodeRevealedAddresses(toIndex:)`. */
    private fun alignNode(targetIndex: Int) {
        val indexByAddress = HashMap<String, Int>()
        for (index in 0..(targetIndex + ALIGN_LOOKAHEAD)) {
            val address = derivation.peek(index) ?: return log("BDK wallet unavailable; could not align the node.")
            indexByAddress[address] = index
        }

        val first = node.newAddress() ?: return log("Node unavailable; its revealed addresses may lag the pool.")
        var nodeIndex = indexByAddress[first] ?: return log("The node returned an address outside our derivation.")

        while (nodeIndex < targetIndex) {
            val next = node.newAddress() ?: return log("The node stopped handing out addresses at $nodeIndex.")
            val nextIndex = indexByAddress[next]
            if (nextIndex == null || nextIndex <= nodeIndex) {
                return log("The node did not advance past $nodeIndex; leaving its reveals where they are.")
            }
            nodeIndex = nextIndex
        }
    }

    @JvmInline
    private value class Found(val value: Int)

    companion object {
        /** `CoreViewController.maxOnchainAddressSearchIndex`. */
        const val MAX_SEARCH_INDEX = 2_500

        /** Unused addresses kept ahead of the highest used one. */
        const val POOL_UNUSED_TARGET = 10

        /** Addresses checked per batch of Esplora calls. */
        const val CHECK_BATCH = 10

        /** `revealAddresses(toIndex: onchainAddresses.count + 4)`. */
        const val REVEAL_BEYOND_POOL = 4

        /** `for index in 0...(targetIndex + 20)`. */
        const val ALIGN_LOOKAHEAD = 20
    }
}
