package com.bittr.android.feature.scanner

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.ObjectInputStream
import java.io.ObjectOutputStream
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * `ScannerScreen` keeps its state in `rememberSaveable`, whose default saver only takes
 * what a `Bundle` can hold. A state that is not `Serializable` crashes the app the moment
 * the scanner opens — which it did, on the first device run of `send_onchain.yaml`.
 */
class ScannerUiStateSaveTest {

    @Test
    fun `every scanner state survives being saved and restored`() {
        listOf(ScannerUiState.Scanning, ScannerUiState.Rationale, ScannerUiState.PermanentlyDenied, ScannerUiState.NoCamera)
            .forEach { state -> assertSame("$state should restore as itself", state, roundTrip(state)) }
    }

    private fun roundTrip(state: ScannerUiState): Any? {
        val bytes = ByteArrayOutputStream().also { out -> ObjectOutputStream(out).use { it.writeObject(state) } }.toByteArray()
        return ObjectInputStream(ByteArrayInputStream(bytes)).use { it.readObject() }
    }
}
