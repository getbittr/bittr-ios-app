package com.bittr.android.core.wallet.ldk.cache

/**
 * The wallet layer's durable key-value store — the port of `CacheManager`.
 *
 * iOS keeps a dozen small facts in `UserDefaults` through `CacheStore`: which
 * events have been shown, which channel is being watched for its closing
 * transaction, which txids that closure produced. None of it is key material and
 * none of it is chain state; all of it is "what has this app already done", and
 * all of it has to survive the process going away.
 *
 * Android has no `UserDefaults`, and the obvious substitute is wrong twice over:
 *
 * - `SharedPreferences` lives in `<data>/shared_prefs`, which is **inside the
 *   backup set**. There is no no-backup variant of it. BIT-8 rule 4 / BIT-20
 *   rule 5 say nothing wallet-shaped leaves the device, and the whole reason
 *   `WalletPaths` exists is that siting — not a manifest attribute — is what
 *   enforces that. A store that can only be excluded by `allowBackup="false"` is
 *   a store one pull request away from being included.
 * - `Context.getCacheDir()` is evictable by the OS at any moment. See
 *   `WalletPaths.cacheDir` for what each eviction would cost.
 *
 * So this is a file store under `no_backup/wallet/cache`, and the interface is
 * the seam that keeps the two bindings — [CachedEventLedger] and
 * [CachedChannelClosureStore] — provable on the JVM against a fake.
 *
 * ## Everything is a list of strings
 *
 * `CacheStore` stores `String`, `[String]`, `Bool` and `Codable`. Only the list
 * shape is actually needed here, and every caller's value maps onto it without a
 * serialiser: the ledger is a list of event descriptions, the closure txids are
 * a list, and a funding outpoint is a single encoded entry. Adding JSON to a
 * module that has no serialisation dependency, to store three keys, would be a
 * dependency bought for elegance.
 *
 * ## Reads never throw and writes always may
 *
 * A read that cannot answer answers empty — see [FileWalletCache] for why that
 * is the fail-safe direction and what a throwing read would cost the event pump.
 * A write that cannot complete throws, and each binding decides whether that is
 * worth propagating. Neither of those is a detail a caller may guess at, so both
 * are contract rather than implementation.
 */
interface WalletCache {

    /**
     * Everything stored under [key], in insertion order, or empty if there is
     * nothing.
     *
     * Never throws: an unreadable or damaged store reads as empty.
     */
    fun strings(key: String): List<String>

    /**
     * Replace [key] with [values].
     *
     * @throws java.io.IOException if the write cannot be made durable. The
     *   previous value is then still intact — see [FileWalletCache].
     */
    fun put(key: String, values: List<String>) = update(key) { values }

    /**
     * Read, transform and write [key] as one indivisible step.
     *
     * The reason this exists rather than a `strings` / `put` pair at each call
     * site: two of the three writers are read-modify-write — the ledger appends
     * to a bounded list, the closure store appends the txids it does not already
     * have — and both run on the wallet's `Dispatchers.IO` scope where the event
     * pump and a sync can be in flight at the same moment. A lost update in the
     * ledger is an event shown twice; a lost update in the closure txids is a
     * force-close the user cannot see.
     *
     * [transform] runs while the store is locked, so it must not block or call
     * back into the cache.
     *
     * @throws java.io.IOException if the write cannot be made durable.
     */
    fun update(key: String, transform: (List<String>) -> List<String>)

    /**
     * Forget [key] entirely.
     *
     * `CacheStore.remove`. Distinct from storing an empty list only in what is
     * left on disk; both read back as empty.
     *
     * @throws java.io.IOException if the removal cannot be made durable.
     */
    fun remove(key: String)
}
