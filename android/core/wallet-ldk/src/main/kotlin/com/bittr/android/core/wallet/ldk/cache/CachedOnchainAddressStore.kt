package com.bittr.android.core.wallet.ldk.cache

import com.bittr.android.core.wallet.ldk.onchain.OnchainAddressStore
import com.bittr.android.core.wallet.ldk.onchain.PooledAddress

/**
 * [OnchainAddressStore] over a [WalletCache] — `CacheManager.getOnchainAddresses` /
 * `storeOnchainAddresses` and `getLastAddress` / `storeLastAddress`.
 *
 * Each pooled address is one entry, `<index>|<used>|<address>`. A bech32 address has no
 * `|` in its alphabet, so the split cannot be fooled by the value it splits. An entry that
 * does not parse is dropped rather than guessed at: the pool is rebuilt from the chain on
 * the next management pass, so a missing row costs a network call, and a misread row could
 * hand out an address as unused when it is not.
 *
 * Writes propagate [java.io.IOException], as [WalletCache] allows; the pool treats a failed
 * write like any other interruption and re-derives next time.
 */
class CachedOnchainAddressStore(
    private val cache: WalletCache,
) : OnchainAddressStore {

    override fun addresses(): List<PooledAddress> =
        cache.strings(KEY_ADDRESSES).mapNotNull(::decode).sortedBy { it.index }

    override fun storeAddresses(addresses: List<PooledAddress>) {
        cache.put(KEY_ADDRESSES, addresses.map { "${it.index}$SEPARATOR${it.hasBeenUsed}$SEPARATOR${it.address}" })
    }

    override fun lastAddress(): String? = cache.strings(KEY_LAST_ADDRESS).firstOrNull()

    override fun storeLastAddress(address: String) {
        cache.put(KEY_LAST_ADDRESS, listOf(address))
    }

    private fun decode(entry: String): PooledAddress? {
        val parts = entry.split(SEPARATOR, limit = 3)
        if (parts.size != 3) return null
        val index = parts[0].toIntOrNull() ?: return null
        val used = parts[1].toBooleanStrictOrNull() ?: return null
        val address = parts[2].takeIf { it.isNotEmpty() } ?: return null
        return PooledAddress(address = address, index = index, hasBeenUsed = used)
    }

    companion object {
        /** `CacheKeys.onchainAddresses`. */
        const val KEY_ADDRESSES = "onchain_addresses"

        /** `CacheKeys.lastAddress`. */
        const val KEY_LAST_ADDRESS = "last_address"

        private const val SEPARATOR = "|"
    }
}
