package com.bittr.android.core.wallet.ldk.state

import java.io.File
import java.io.IOException
import java.security.SecureRandom

/**
 * The LDK state directory and the quarantine path — the Android port of
 * `LightningStorage.swift`.
 *
 * Two things carry over unchanged, and both are load-bearing:
 *
 * 1. **Quarantine, never delete.** `LightningStorage.swift:83–84`: the state
 *    file "is the only thing that could help sweep funds from a force-closed
 *    channel". Nothing in this class removes state.
 * 2. **The state directory never leaves the device.** Handled by siting, in
 *    [WalletPaths].
 *
 * One thing deliberately does *not* carry over — BIT-20 rule 4.
 * `LightningStorage.swift:94–97` deletes any existing quarantine before
 * creating the new one ("Replace existing quarantined data with the latest").
 * That is safe on iOS only because the path is a one-shot legacy migration
 * (`StartLightning.swift:100–105`: "Newer users will never encounter this
 * issue"). On Android, BIT-8 rule 3 makes the guard a routine path that can
 * fire repeatedly, so the second event would destroy the first quarantine —
 * destroying exactly the material the iOS comment exists to protect. Each
 * quarantine therefore gets its own subdirectory and nothing is ever replaced.
 *
 * Proved by `QuarantineDoesNotClobberTest`.
 */
class LdkStateStore(
    private val paths: WalletPaths,
    private val random: SecureRandom = SecureRandom(),
) {

    /**
     * Whether there is LDK state worth reasoning about.
     *
     * The discriminator file alone is not state: it is metadata *about* state,
     * and a directory holding only a discriminator is one whose state has
     * already been quarantined. Counting it would make the guard quarantine an
     * empty directory on every subsequent import — noise that looks exactly
     * like the real event in the logs.
     */
    fun hasLightningState(): Boolean {
        val entries = paths.ldkStateDir.listFiles() ?: return false
        return entries.any { it.name != paths.discriminatorFile.name }
    }

    /**
     * Move everything in the state directory into a fresh quarantine
     * subdirectory, durably, without touching any prior quarantine.
     *
     * The discriminator goes with it. It describes the state being quarantined,
     * so leaving it behind would mislabel whatever state arrives next — and
     * `absent` is the fail-safe reading for a directory whose owner we no
     * longer know.
     *
     * @return the directory the state was moved into, or `null` if there was
     *   nothing to quarantine.
     * @throws IOException if the quarantine cannot be completed. The caller
     *   **must** treat that as fatal to the seed import: `storeMnemonic`
     *   (`CacheManager.swift:351–359`) throws out of the whole function for the
     *   same reason, and on Android the consequence of continuing is worse —
     *   see [Fsync].
     */
    @Throws(IOException::class)
    fun quarantineLightningState(): File? {
        val entries = (paths.ldkStateDir.listFiles() ?: emptyArray()).sortedBy { it.name }
        if (entries.isEmpty()) return null

        val destination = allocateQuarantineDirectory()
        if (!destination.mkdirs()) {
            throw IOException("Could not create quarantine directory $destination")
        }

        for (entry in entries) {
            val target = File(destination, entry.name)
            if (!entry.renameTo(target)) {
                // A rename can fail across mount points; a copy is still a
                // quarantine as long as the original goes away afterwards. It
                // does not, if the copy did not complete.
                entry.copyRecursively(target, overwrite = false)
                if (!entry.deleteRecursively()) {
                    throw IOException("Quarantined $entry by copy but could not remove the original")
                }
            }
        }

        // Durability, in the order that makes the sequence meaningful: the
        // moved bytes, then the directory that now links them, then the
        // directory they left. Only after all three has the quarantine actually
        // happened as far as a power cut is concerned — see Fsync.
        Fsync.tree(destination)
        Fsync.directory(paths.quarantineRoot)
        Fsync.directory(paths.ldkStateDir)
        return destination
    }

    /** Every quarantine on the device, oldest first. Nothing here prunes them. */
    fun quarantines(): List<File> =
        (paths.quarantineRoot.listFiles() ?: emptyArray())
            .filter { it.isDirectory }
            .sortedBy { indexOf(it.name) }

    /**
     * `<monotonic-index>-<short-random>`.
     *
     * The index makes the order recoverable by reading the directory, which
     * matters when support has to tell a user which of three quarantines holds
     * the channel they are trying to sweep. The random suffix means two
     * quarantines in the same run cannot collide even if the index is somehow
     * stale.
     *
     * Deliberately not a timestamp: `System.currentTimeMillis()` is
     * user-settable and not monotonic, so two quarantines could sort backwards
     * or collide outright.
     */
    private fun allocateQuarantineDirectory(): File {
        paths.quarantineRoot.mkdirs()
        val nextIndex = ((paths.quarantineRoot.listFiles() ?: emptyArray())
            .mapNotNull { indexOf(it.name) }
            .maxOrNull() ?: 0) + 1
        val suffix = ByteArray(4).also(random::nextBytes).joinToString("") { "%02x".format(it) }
        return File(paths.quarantineRoot, "%04d-%s".format(nextIndex, suffix))
    }

    private fun indexOf(name: String): Int? = name.substringBefore('-').toIntOrNull()
}
