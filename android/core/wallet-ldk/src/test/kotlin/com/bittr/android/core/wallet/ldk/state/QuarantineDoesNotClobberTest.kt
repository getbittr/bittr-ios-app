package com.bittr.android.core.wallet.ldk.state

import com.bittr.android.core.wallet.ldk.seedStateDirectory
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * **BIT-20 rule 4 — quarantine never overwrites a prior quarantine.**
 *
 * `LightningStorage.swift:94–97` removes the existing quarantine directory
 * before creating the new one: *"Replace existing quarantined data with the
 * latest"*. On iOS that is safe, because the path is a one-shot legacy
 * migration — `StartLightning.swift:100–105` says so in as many words
 * ("Newer users will never encounter this issue").
 *
 * On Android the same path is routine, because BIT-8 rule 3 makes "blob lost,
 * state intact" a state we expect. So the second quarantine would destroy the
 * first — and the first is the only thing that could sweep funds from a
 * force-closed channel (`LightningStorage.swift:83–84`). That is the comment
 * at `:84` being defeated by the code at `:94`, on Android only.
 */
class QuarantineDoesNotClobberTest {

    @get:Rule val temporaryFolder = TemporaryFolder()

    private lateinit var paths: WalletPaths
    private lateinit var store: LdkStateStore

    @Before
    fun setUp() {
        paths = WalletPaths(temporaryFolder.root)
        paths.createDirectories()
        store = LdkStateStore(paths)
    }

    @Test
    fun `two quarantines both survive, with distinct contents`() {
        seedStateDirectory(paths.ldkStateDir, marker = "first-foreign-state")
        val first = store.quarantineLightningState()
        assertNotNull(first)

        seedStateDirectory(paths.ldkStateDir, marker = "second-foreign-state")
        val second = store.quarantineLightningState()
        assertNotNull(second)

        assertEquals(
            "Both quarantines must still exist. Inheriting iOS's delete-then-create " +
                "would destroy the first, which is the only material that could sweep " +
                "a force-closed channel.",
            2,
            store.quarantines().size,
        )
        assertTrue(first!!.isDirectory)
        assertTrue(second!!.isDirectory)
        assertEquals("first-foreign-state", File(first, "ldk_node_data.sqlite").readText())
        assertEquals("second-foreign-state", File(second, "ldk_node_data.sqlite").readText())
    }

    @Test
    fun `quarantine directories are uniquely named and ordered`() {
        val created = (1..4).map {
            seedStateDirectory(paths.ldkStateDir, marker = "state-$it")
            store.quarantineLightningState()!!
        }

        assertEquals(
            "Names must be unique, or the second quarantine silently lands inside " +
                "the first.",
            created.size,
            created.map { it.name }.toSet().size,
        )
        assertEquals(
            "Quarantines must be enumerable in the order they happened, so support " +
                "can tell a user which one holds the channel they are sweeping.",
            created.map { it.name },
            store.quarantines().map { it.name },
        )
        created.forEachIndexed { index, directory ->
            assertEquals(
                "%04d".format(index + 1),
                directory.name.substringBefore('-'),
            )
        }
    }

    @Test
    fun `the state directory is emptied and nothing is deleted`() {
        seedStateDirectory(paths.ldkStateDir)
        val movedNames = paths.ldkStateDir.listFiles()!!.map { it.name }.sorted()

        val quarantine = store.quarantineLightningState()!!

        assertFalse(
            "State must not remain where a node would pick it up again.",
            store.hasLightningState(),
        )
        assertEquals(
            "Quarantine moves; it never deletes.",
            movedNames,
            quarantine.listFiles()!!.map { it.name }.sorted(),
        )
    }

    @Test
    fun `quarantining an empty state directory is a no-op`() {
        assertNull(
            "An empty state directory must not produce an empty quarantine — that is " +
                "noise indistinguishable from the real event in a log.",
            store.quarantineLightningState(),
        )
        assertFalse(paths.quarantineRoot.exists() && store.quarantines().isNotEmpty())
    }

    @Test
    fun `a discriminator on its own is not lightning state`() {
        paths.ldkStateDir.mkdirs()
        DiscriminatorStore(paths.discriminatorFile).write(ByteArray(32) { 7 })

        assertFalse(
            "A directory holding only a discriminator is one whose state has already " +
                "been quarantined. Counting it would quarantine an empty directory on " +
                "every subsequent import.",
            store.hasLightningState(),
        )
    }

    @Test
    fun `the discriminator travels with the state it describes`() {
        seedStateDirectory(paths.ldkStateDir)
        DiscriminatorStore(paths.discriminatorFile).write(ByteArray(32) { 9 })

        val quarantine = store.quarantineLightningState()!!

        assertFalse(
            "Leaving the discriminator behind would mislabel whatever state arrives " +
                "next as belonging to the quarantined seed.",
            paths.discriminatorFile.exists(),
        )
        assertTrue(File(quarantine, paths.discriminatorFile.name).isFile)
    }
}
