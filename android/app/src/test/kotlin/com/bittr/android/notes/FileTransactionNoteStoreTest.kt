package com.bittr.android.notes

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class FileTransactionNoteStoreTest {

    private val file = Files.createTempDirectory("notes").resolve("transaction_notes.json").toFile()

    @Test
    fun `notes are trimmed, survive a reload, and a blank note deletes`() {
        val store = FileTransactionNoteStore(file)
        store.store("tx1", "  coffee with \"friends\"  ")
        store.store("tx2", "rent")
        store.store("tx2", "   ")

        val reloaded = FileTransactionNoteStore(file)
        assertEquals(mapOf("tx1" to "coffee with \"friends\""), reloaded.notes.value)
        assertFalse(reloaded.notes.value.containsKey("tx2"))
    }

    @Test
    fun `an unreadable file starts empty rather than crashing`() {
        file.writeText("not json")
        assertEquals(emptyMap<String, String>(), FileTransactionNoteStore(file).notes.value)
    }
}
