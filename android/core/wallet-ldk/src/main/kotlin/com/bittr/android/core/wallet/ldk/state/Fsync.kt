package com.bittr.android.core.wallet.ldk.state

import java.io.File
import java.io.IOException
import java.nio.channels.FileChannel
import java.nio.file.StandardOpenOption

/**
 * Durability helpers for the quarantine path.
 *
 * `seed-storage-security` §7.2: on iOS, quarantining before persisting the
 * mnemonic reads as tidy error handling, because process death mid-operation is
 * exceptional there. On Android it is routine, and the ordering becomes
 * load-bearing:
 *
 * - crash *after* quarantine, *before* the blob write → next launch sees no
 *   mnemonic and no state. Clean; the user restores again.
 * - crash *after* the blob write, *before* quarantine → a mnemonic now exists,
 *   so the guard's first branch returns early on **every** subsequent launch.
 *   Foreign state is live under a new seed and the guard can never fire again.
 *
 * Sequencing alone does not buy the first case: a rename that is only in the
 * page cache can land after a blob write that was issued later. So the
 * quarantine moves are forced to disk — files *and* their containing
 * directories, because on POSIX a rename is a directory operation and
 * `fsync`ing the file does not persist the link.
 */
internal object Fsync {

    /** `fsync` a regular file. */
    fun file(target: File) {
        if (!target.isFile) return
        FileChannel.open(target.toPath(), StandardOpenOption.READ).use { it.force(true) }
    }

    /**
     * `fsync` a directory, so renames into or out of it survive a crash.
     *
     * Opening a directory as a channel is legal on Linux (and therefore
     * Android) but not portable; JVMs on other platforms may refuse. A failure
     * here is not a reason to abandon a quarantine that has already happened,
     * so it is reported rather than thrown — the caller decides.
     */
    fun directory(target: File): Boolean = try {
        FileChannel.open(target.toPath(), StandardOpenOption.READ).use { it.force(true) }
        true
    } catch (_: IOException) {
        false
    } catch (_: UnsupportedOperationException) {
        false
    }

    /** `fsync` every regular file under [root], then [root] itself. */
    fun tree(root: File) {
        root.walkTopDown().filter { it.isFile }.forEach { file(it) }
        root.walkBottomUp().filter { it.isDirectory }.forEach { directory(it) }
    }
}
