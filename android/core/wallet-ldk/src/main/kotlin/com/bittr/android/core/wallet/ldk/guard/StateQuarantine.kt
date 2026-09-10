package com.bittr.android.core.wallet.ldk.guard

import com.bittr.android.core.wallet.ldk.storage.Durability
import com.bittr.android.core.wallet.ldk.storage.WalletPaths
import java.io.File
import java.io.IOException
import java.security.SecureRandom

/**
 * Moves foreign LDK state out of the way, without ever destroying what it moved.
 *
 * ## Why quarantine rather than delete
 *
 * `LightningStorage.swift:83-84` is explicit: the quarantined file "is the only
 * thing that could help sweep funds from a force-closed channel". Deleting it is
 * the one thing iOS refuses to do, and this port keeps that refusal — including
 * refusing to prune quarantines automatically later.
 *
 * ## The defect this fixes
 *
 * `LightningStorage.swift:94-97` removes any existing quarantine directory before
 * creating the new one ("Replace existing quarantined data with the latest"). On
 * iOS that is harmless, because the guard is a one-shot legacy migration
 * (`StartLightning.swift:100-105`: "Newer users will never encounter this issue")
 * so there is never a prior quarantine to destroy.
 *
 * On Android the guard fires in normal use and can fire repeatedly, so the second
 * event would destroy the first quarantine — the exact material the comment at
 * `:84` exists to protect. Hence: quarantine into a uniquely-named subdirectory,
 * never replacing. Proven by `QuarantineDoesNotClobberTest`.
 *
 * Because the parent sits under `no_backup`, each new subdirectory inherits the
 * backup exclusion without a per-directory call — the Android equivalent of the
 * explicit re-exclusion iOS performs at `LightningStorage.swift:99-105`.
 */
class StateQuarantine(
    private val paths: WalletPaths,
    private val random: SecureRandom = SecureRandom(),
) {

    /**
     * Moves [WalletPaths.ldkStateDir] into a fresh subdirectory and returns it.
     *
     * The move is made **durable before returning** — files, subdirectories and
     * the quarantine root are all fsync'd. That is what lets the caller order the
     * mnemonic write after this call and mean it. See [Durability] for why merely
     * sequencing the two is not enough.
     *
     * @return the directory the state was moved to, or null if there was no state
     * to quarantine.
     */
    fun quarantine(): File? {
        val source = paths.ldkStateDir
        if (!source.exists()) return null

        val root = paths.quarantineRoot.apply { mkdirs() }
        val destination = File(root, nextName())

        if (!source.renameTo(destination)) {
            // A rename across the same filesystem should not fail. If it does,
            // copy rather than proceed — but never delete the source until the
            // copy is durable, because a half-moved quarantine is worse than no
            // quarantine at all.
            source.copyRecursively(destination, overwrite = false)
            Durability.fsyncTree(destination)
            if (!source.deleteRecursively()) {
                throw IOException(
                    "Copied LDK state to $destination but could not remove the original at " +
                        "$source. Refusing to continue: the node would start against state " +
                        "that has already been declared foreign.",
                )
            }
        }

        Durability.fsyncTree(destination)
        Durability.fsyncDir(root)
        Durability.fsyncDir(paths.root)
        return destination
    }

    /** Existing quarantines, oldest first. Never pruned automatically. */
    fun existing(): List<File> =
        paths.quarantineRoot.listFiles()?.filter(File::isDirectory)?.sortedBy { indexOf(it.name) }
            ?: emptyList()

    /**
     * `<monotonic-index>-<short-random>`.
     *
     * The index makes ordering recoverable for support ("send us the newest
     * one"); the random suffix means a same-second second fire cannot collide
     * with the first even if the index were somehow miscomputed. Belt and braces
     * on a directory name is cheap; a collision here silently merges two
     * quarantines, which is the clobber this class exists to prevent.
     */
    private fun nextName(): String {
        val next = (existing().maxOfOrNull { indexOf(it.name) } ?: 0) + 1
        val suffix = ByteArray(4).also(random::nextBytes).joinToString("") { "%02x".format(it) }
        return "%04d-%s".format(next, suffix)
    }

    private fun indexOf(name: String): Int =
        name.substringBefore('-').toIntOrNull() ?: 0
}
