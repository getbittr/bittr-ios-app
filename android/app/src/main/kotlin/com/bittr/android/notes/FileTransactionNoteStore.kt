package com.bittr.android.notes

import android.content.Context
import com.bittr.android.core.wallet.TransactionNoteStore
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.io.File
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * [TransactionNoteStore] as one JSON object in a file — iOS keeps the same dictionary in
 * `UserDefaults` under `transactionnotes`.
 *
 * In the app's files directory, not `no_backup`: a note is the user's own writing about their
 * history, and like iOS's it should come back with a restored phone. It holds no key material.
 * Writes go to a temporary file and are renamed over the old one, so a crash mid-write leaves
 * the previous notes rather than half a file.
 */
class FileTransactionNoteStore(private val file: File) : TransactionNoteStore {

    private val _notes = MutableStateFlow(load())
    override val notes: StateFlow<Map<String, String>> = _notes.asStateFlow()

    @Synchronized
    override fun store(transactionId: String, note: String) {
        val trimmed = note.trim()
        _notes.update { current -> if (trimmed.isEmpty()) current - transactionId else current + (transactionId to trimmed) }
        runCatching { write(_notes.value) }
    }

    private fun load(): Map<String, String> = runCatching {
        if (!file.exists()) return emptyMap()
        Json.parseToJsonElement(file.readText()).jsonObject
            .mapNotNull { (id, value) -> value.jsonPrimitive.contentOrNull?.let { id to it } }
            .toMap()
    }.getOrDefault(emptyMap())

    private fun write(notes: Map<String, String>) {
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(JsonObject(notes.mapValues { JsonPrimitive(it.value) }).toString())
        if (!temporary.renameTo(file)) {
            file.delete()
            temporary.renameTo(file)
        }
    }
}

@Module
@InstallIn(SingletonComponent::class)
object NotesModule {

    @Provides
    @Singleton
    fun provideTransactionNoteStore(@ApplicationContext context: Context): TransactionNoteStore =
        FileTransactionNoteStore(File(context.filesDir, "transaction_notes.json"))
}
