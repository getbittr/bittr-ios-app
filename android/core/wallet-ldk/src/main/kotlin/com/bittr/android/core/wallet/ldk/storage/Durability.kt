package com.bittr.android.core.wallet.ldk.storage

import java.io.File
import java.io.IOException
import java.nio.channels.FileChannel
import java.nio.file.StandardOpenOption

/**
 * `fsync` helpers for the one ordering in this module that is crash-critical.
 *
 * iOS quarantines foreign LDK state *before* it persists a mnemonic
 * (`CacheManager.swift:351-359`) and throws out of the whole function if the
 * quarantine fails, so no mnemonic is stored. On iOS that reads as tidy error
 * handling. On Android, where process death mid-operation is routine rather than
 * exceptional, the ordering is load-bearing:
 *
 * - Crash **after** quarantine, **before** the blob write -> next launch sees no
 *   mnemonic and no state. Clean; the user restores again.
 * - Crash **after** the blob write, **before** quarantine -> a mnemonic now
 *   exists, so the guard's first branch returns early on *every* subsequent
 *   launch. Foreign state is live under a new seed and the guard can never fire
 *   again. This one is unrecoverable.
 *
 * Sequencing the two calls is not enough to get the good case: a rename is
 * metadata, and unsynced metadata can reach the disk after a later write. So the
 * quarantine has to be durable before the blob write *begins*.
 *
 * Covered by `QuarantineOrderingCrashTest`.
 */
internal object Durability {

    /**
     * Flushes a directory's metadata — the rename itself, not the file contents.
     *
     * Opening a directory as a channel is POSIX behaviour that Linux (and
     * therefore Android) supports and the JDK does not specify. If a platform
     * refuses, that is reported rather than swallowed: a silent no-op here would
     * leave the ordering above merely sequential while reading as durable, which
     * is the exact failure this object exists to prevent.
     */
    fun fsyncDir(dir: File) {
        try {
            FileChannel.open(dir.toPath(), StandardOpenOption.READ).use { it.force(true) }
        } catch (e: IOException) {
            throw IOException(
                "Could not fsync directory $dir. The quarantine-before-persist ordering " +
                    "depends on this; without it a crash can leave the mnemonic written and " +
                    "the quarantine lost, which the guard can never recover from.",
                e,
            )
        }
    }

    /** Flushes a file's contents and metadata. */
    fun fsyncFile(file: File) {
        FileChannel.open(file.toPath(), StandardOpenOption.READ, StandardOpenOption.WRITE)
            .use { it.force(true) }
    }

    /** Recursively fsyncs every file under [dir], then [dir] itself. */
    fun fsyncTree(dir: File) {
        dir.walkBottomUp().forEach { entry ->
            if (entry.isFile) fsyncFile(entry) else fsyncDir(entry)
        }
    }
}
