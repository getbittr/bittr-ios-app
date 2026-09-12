package com.bittr.android.core.wallet.ldk.state

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The quarantine's durability rests on `fsync`ing a *directory*, and that call
 * is the one part of it a platform is allowed to refuse.
 *
 * Opening a directory as a `FileChannel` is legal on Linux — and therefore on
 * Android — but not portable, so [Fsync.directory] reports failure instead of
 * throwing: a quarantine that has already happened should not be abandoned
 * because the flush could not be requested. That graceful degradation is
 * correct and it is also exactly how a durability guarantee disappears without
 * anyone noticing.
 *
 * So the fallback gets a test of its own. If `fsync` on a directory ever stops
 * working under us, this goes red and someone reads `QuarantineOrderingCrashTest`'s
 * class comment again, rather than the ordering quietly becoming
 * best-effort.
 *
 * Why a directory at all: on POSIX a rename is a directory operation.
 * `fsync`ing the moved *file* does not persist the *link*, so a quarantine
 * could be buffered and land after a blob write issued later — which is the
 * unrecoverable ordering.
 */
class FsyncDurabilityTest {

    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test
    fun `directories can be fsynced on this platform`() {
        assertTrue(
            "Fsync.directory returned false. It degrades gracefully by design, so " +
                "nothing will fail loudly — but the quarantine-before-blob-write " +
                "ordering is only durable if this works. See QuarantineOrderingCrashTest.",
            Fsync.directory(temporaryFolder.root),
        )
    }

    @Test
    fun `fsyncing a tree touches every file and directory without altering them`() {
        val root = File(temporaryFolder.root, "quarantine/0001-abcd").apply { mkdirs() }
        File(root, "ldk_node_data.sqlite").writeText("state")
        File(root, "nested").mkdirs()
        File(root, "nested/ldk_node_data.sqlite-wal").writeText("wal")

        Fsync.tree(root)

        assertTrue(File(root, "ldk_node_data.sqlite").readText() == "state")
        assertTrue(File(root, "nested/ldk_node_data.sqlite-wal").readText() == "wal")
    }

    @Test
    fun `fsyncing something that is not there is not an error`() {
        // The quarantine path calls these after moves that may legitimately
        // have left nothing behind. Throwing here would turn a completed
        // quarantine into a failed import.
        Fsync.file(File(temporaryFolder.root, "absent"))
        assertTrue(!Fsync.directory(File(temporaryFolder.root, "absent-dir")))
    }
}
