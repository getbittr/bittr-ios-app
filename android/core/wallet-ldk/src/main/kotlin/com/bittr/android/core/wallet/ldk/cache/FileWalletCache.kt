package com.bittr.android.core.wallet.ldk.cache

import com.bittr.android.core.wallet.ldk.state.Fsync
import java.io.File
import java.io.IOException
import java.util.Base64

/**
 * [WalletCache] as one file per key, written atomically and read once.
 *
 * ## Why a file per key and not one file
 *
 * The three keys have different write rates and different costs of loss. The
 * event ledger is written on every event; the channel closure txids are written
 * when a channel closes, which is rarely and matters a great deal. One file
 * holding both means every event rewrites the closure record, so the window in
 * which a power cut can damage it is opened once per payment instead of once per
 * closure. Separate files keep each key's risk proportional to its own traffic.
 *
 * ## The write is atomic, and that is not the same as durable
 *
 * Every write goes to a temporary file, is forced to disk, and is then renamed
 * over the target — `rename(2)` within a directory is atomic, so a reader (or a
 * next launch) sees either the whole previous value or the whole new one, never
 * a half-written list. The directory is forced afterwards, because on POSIX the
 * rename is a directory operation and forcing the file does not persist the
 * link. That is the same sequence, and the same reasoning, as `LdkStateStore`'s
 * quarantine — see [Fsync].
 *
 * The cost is a real `fsync` per write, which is milliseconds of flash latency
 * on the event path. It is paid deliberately: events arrive at human rates,
 * "the ledger says shown but the disk says not" is the exact state that shows a
 * payment to the user twice, and a cache whose durability depends on nothing
 * else crashing is not what this issue asked for.
 *
 * ## Reads never throw. That is a decision about the event pump.
 *
 * [strings] answers empty for a missing file, an unreadable one, and a damaged
 * entry inside a readable one. The alternative — propagating — would surface in
 * `EventLedger.hasHandled`, which `EventPump` calls **outside** its own
 * try/catch, so an `IOException` there does not fail one event: it unwinds the
 * loop and the pump stops until the node next restarts. Trading a duplicate
 * notification for a dead event loop is the wrong way round, and the damaged
 * entry is dropped rather than the whole file so one bad line cannot cost the
 * other 499.
 *
 * ## Entries are Base64 on disk, and the file is not meant to be read by eye
 *
 * The ledger's keys are `Event.toString()` renderings from a library this
 * repository does not control. A newline inside one would split a single record
 * into two lines, and from then on the record would never match itself — a
 * deduplication that silently stops deduplicating, with nothing in any log to
 * say so. Line-per-entry needs the entry to contain no line breaks, and the only
 * way to promise that about a value from elsewhere is to encode it. Base64 costs
 * the ability to `cat` the file during debugging, which is worth strictly less
 * than the guarantee.
 *
 * `java.util.Base64` rather than `android.util.Base64`: it is API 26 and up,
 * which is `minSdk`, and it needs no Robolectric to run in a JVM test.
 *
 * Proved by `FileWalletCacheTest`.
 */
class FileWalletCache(
    /** `WalletPaths.cacheDir`. Created on first write if it is not there. */
    private val directory: File,
) : WalletCache {

    /**
     * Guards both the map and the files.
     *
     * The map is not a performance ornament: the ledger is read once per event
     * and a re-read per read would be a file open per event, on a path that
     * already pays for an `fsync` when it writes. It is authoritative once
     * loaded — this process is the only writer, because the directory is the
     * app's own private storage.
     */
    private val lock = Any()

    private val loaded = mutableMapOf<String, List<String>>()

    override fun strings(key: String): List<String> = synchronized(lock) { entriesOf(key) }

    override fun update(key: String, transform: (List<String>) -> List<String>) {
        synchronized(lock) {
            val current = entriesOf(key)
            val next = transform(current)
            // Not a micro-optimisation: `recordHandled` is called for every
            // event including ones already in the ledger (iOS calls
            // `didHandleEvent` unconditionally), and rewriting an unchanged list
            // would fsync on every duplicate.
            if (next == current) return
            write(key, next)
            loaded[key] = next
        }
    }

    override fun remove(key: String) {
        synchronized(lock) {
            val target = fileFor(key)
            if (target.exists() && !target.delete()) {
                throw IOException("Could not remove cache entry $target")
            }
            Fsync.directory(directory)
            loaded[key] = emptyList()
        }
    }

    private fun entriesOf(key: String): List<String> =
        loaded.getOrPut(key) { read(fileFor(key)) }

    /** Never throws — see the class comment. */
    private fun read(source: File): List<String> = try {
        if (!source.isFile) {
            emptyList()
        } else {
            source.readLines().filter { it.isNotBlank() }.mapNotNull(::decode)
        }
    } catch (_: IOException) {
        emptyList()
    }

    private fun write(key: String, values: List<String>) {
        if (!directory.mkdirs() && !directory.isDirectory) {
            throw IOException("Could not create the wallet cache directory: $directory")
        }

        val target = fileFor(key)
        // Beside the target, so the rename cannot cross a filesystem and stop
        // being atomic.
        val temporary = File(directory, "${target.name}$TEMPORARY_SUFFIX")
        temporary.writeText(values.joinToString(separator = "\n", transform = ::encode))
        Fsync.file(temporary)

        // `renameTo` replaces an existing destination on POSIX, which is the
        // property the whole method rests on. A failure leaves the previous
        // value in place, which is why the temporary is cleaned up and the
        // exception is thrown rather than the map being updated.
        if (!temporary.renameTo(target)) {
            temporary.delete()
            throw IOException("Could not replace cache entry $target")
        }
        Fsync.directory(directory)
    }

    /**
     * The file [key] is stored in, with the key itself fenced.
     *
     * Keys are compile-time constants in this module and there is no path in
     * which one comes from outside it. The fence is here because that sentence
     * is true today: a key that later arrives from a payment, a channel id or a
     * server would otherwise be able to name `../../seed.bin`, and this class
     * deletes and replaces the files it is handed. Same shape as
     * `BdkStore.prepare`'s directory-name check, for the same reason — a comment
     * would not have stopped it.
     */
    private fun fileFor(key: String): File {
        require(key.isNotEmpty() && key.all { it in 'a'..'z' || it == '_' }) {
            "A wallet cache key must be lowercase letters and underscores, so it names " +
                "a file inside ${directory.name} and nothing outside it. Got: '$key'"
        }
        return File(directory, key)
    }

    private fun encode(value: String): String =
        Base64.getEncoder().encodeToString(value.toByteArray(Charsets.UTF_8))

    /** Null for a line that is not valid Base64 — the damaged entry is dropped. */
    private fun decode(line: String): String? = try {
        String(Base64.getDecoder().decode(line), Charsets.UTF_8)
    } catch (_: IllegalArgumentException) {
        null
    }

    private companion object {

        /**
         * Distinguishable from a key: [fileFor] rejects a key containing a dot,
         * so a leftover temporary can never be mistaken for a stored value.
         */
        const val TEMPORARY_SUFFIX = ".writing"
    }
}
