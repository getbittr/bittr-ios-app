package com.bittr.android.core.wallet.ldk.cache

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The store under the ledger, and the three properties the ledger relies on.
 *
 * > It survives the process. It cannot be half-written. It never throws on the
 * > way in to `hasHandled`.
 *
 * "Survives the process" is modelled the only way a JVM test can model it — a
 * second [FileWalletCache] over the same directory, with no shared state — which
 * is exactly the fidelity that matters here, because the in-memory mirror is the
 * thing that would otherwise make a broken file look like a working store.
 */
class FileWalletCacheTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var directory: File

    private fun cache() = FileWalletCache(directory)

    @Before
    fun setUp() {
        directory = temporaryFolder.newFolder("cache")
    }

    @Test
    fun `what one instance writes, the next one reads`() {
        cache().put("handled_events", listOf("one", "two"))

        assertEquals(
            "A second instance is the only model of process death available here, " +
                "and the one the ledger's whole purpose depends on.",
            listOf("one", "two"),
            cache().strings("handled_events"),
        )
    }

    @Test
    fun `an absent key reads as empty`() {
        assertEquals(emptyList<String>(), cache().strings("handled_events"))
    }

    /**
     * The reason entries are encoded rather than written as lines.
     *
     * The ledger's keys are `Event.toString()` renderings from ldk-node. A line
     * break inside one would split a record in two, and from then on the record
     * would never match itself — a deduplication that has silently stopped
     * deduplicating.
     */
    @Test
    fun `a value containing line breaks round-trips intact`() {
        val awkward = "PaymentReceived(\nhash=abc\r\n, amount=1)"

        cache().put("handled_events", listOf(awkward, "after"))

        assertEquals(listOf(awkward, "after"), cache().strings("handled_events"))
    }

    @Test
    fun `update sees what is stored and replaces it`() {
        val cache = cache()
        cache.put("handled_events", listOf("one"))

        cache.update("handled_events") { it + "two" }

        assertEquals(listOf("one", "two"), cache.strings("handled_events"))
        assertEquals("And durably.", listOf("one", "two"), cache().strings("handled_events"))
    }

    @Test
    fun `remove forgets the key on disk, not just in memory`() {
        val cache = cache()
        cache.put("handled_events", listOf("one"))

        cache.remove("handled_events")

        assertEquals(emptyList<String>(), cache.strings("handled_events"))
        assertEquals(emptyList<String>(), cache().strings("handled_events"))
    }

    /**
     * One bad line costs one entry, not the file.
     *
     * A ledger that threw its whole contents away on a single damaged record
     * would re-show every event it had ever suppressed; one that dropped the
     * record re-shows one.
     */
    @Test
    fun `a damaged entry is dropped and the rest survive`() {
        cache().put("handled_events", listOf("one", "two"))
        val stored = File(directory, "handled_events")
        stored.writeText(stored.readLines().joinToString("\n").replaceFirst("\n", "\nnot~base64!\n"))

        assertEquals(listOf("one", "two"), cache().strings("handled_events"))
    }

    /**
     * A read that throws does not fail one event — it unwinds `EventPump.run`,
     * because `hasHandled` is called outside the loop's own try/catch. Trading a
     * duplicate notification for a dead event loop is the wrong way round.
     */
    @Test
    fun `an unreadable store reads as empty rather than throwing`() {
        // A directory where a file is expected: every read of it raises
        // IOException, which is the shape of a store damaged by something
        // outside this class.
        File(directory, "handled_events").mkdirs()

        assertEquals(emptyList<String>(), cache().strings("handled_events"))
    }

    @Test
    fun `a write leaves no temporary file behind`() {
        cache().put("handled_events", listOf("one"))

        val leftovers = directory.listFiles()?.filter { it.name != "handled_events" }.orEmpty()
        assertEquals("Expected only the stored key: $leftovers", emptyList<File>(), leftovers)
    }

    /**
     * The other half of atomicity: a temporary left behind by a process that
     * died mid-write must not read back as a value.
     */
    @Test
    fun `a leftover temporary is not mistaken for a stored value`() {
        cache().put("handled_events", listOf("one"))
        File(directory, "handled_events.writing").writeText("dGhpcyBuZXZlciBsYW5kZWQ=")

        assertEquals(listOf("one"), cache().strings("handled_events"))
    }

    /**
     * The fence. Keys are constants today, and this class deletes and replaces
     * the files it is handed — so the day one arrives from a channel id or a
     * server, it must not be able to name `../seed.bin`.
     */
    @Test
    fun `a key that could name a file outside the directory is refused`() {
        val sibling = File(directory.parentFile, "seed.bin").also { it.writeText("blob") }

        for (key in listOf("../seed.bin", "sub/key", "", "Handled_Events", "key.writing")) {
            assertThrows(IllegalArgumentException::class.java) {
                cache().put(key, listOf("x"))
            }
        }

        assertTrue("The sibling was never touched.", sibling.isFile)
        assertEquals("blob", sibling.readText())
    }

    @Test
    fun `the directory is created on first write if it is missing`() {
        directory = File(temporaryFolder.root, "not-created-yet")
        assertFalse(directory.exists())

        cache().put("handled_events", listOf("one"))

        assertEquals(listOf("one"), cache().strings("handled_events"))
    }
}
