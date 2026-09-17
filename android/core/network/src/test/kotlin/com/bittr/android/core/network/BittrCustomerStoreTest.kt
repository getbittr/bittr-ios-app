package com.bittr.android.core.network

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BittrCustomerStoreTest {

    private fun tempFile(): File = File(Files.createTempDirectory("bittr-store").toFile(), "customer.json")

    @Test
    fun `finished payouts survive a reload`() {
        val file = tempFile()
        val store = FileBittrCustomerStore(file)
        store.addProcessedPayout("n1")
        store.addProcessedPayout("n1")
        store.addProcessedPayout("n2")

        assertEquals(setOf("n1", "n2"), FileBittrCustomerStore(file).processedPayouts())
    }

    @Test
    fun `entities survive a reload and keep their order`() {
        val file = tempFile()
        val store = FileBittrCustomerStore(file)
        store.upsert(IbanEntity(id = "b", order = 1, yourEmail = "b@x"))
        store.upsert(IbanEntity(id = "a", order = 0, yourEmail = "a@x", initiativeConfirmedAt = "2026-09-14T00:00:00Z"))
        store.update("b") { it.copy(yourUniqueCode = "DC-B", paymentMode = "onchain") }
        store.addSentToBittr(listOf("tx1"))
        store.addPurchases(listOf(BittrTransactionInfo("tx1", null, null, null, "EUR", 0.001, 95.0, 100.0)))

        val reloaded = FileBittrCustomerStore(file)
        assertEquals(listOf("a", "b"), reloaded.entities.value.map { it.id })
        assertEquals("2026-09-14T00:00:00Z", reloaded.entities.value[0].initiativeConfirmedAt)
        assertEquals(IbanEntity.DEFAULT_PARTNER_NAME, reloaded.entities.value[0].ourName)
        assertEquals("onchain", reloaded.entities.value[1].paymentMode)
        assertEquals(setOf("tx1"), reloaded.sentToBittr())
        assertEquals(95.0, reloaded.purchases.value.getValue("tx1").fiatAmountNet!!, 0.0)
    }

    @Test
    fun `first deposit code skips entities that have not finished signup`() {
        val store = InMemoryBittrCustomerStore(
            listOf(
                IbanEntity(id = "a", order = 0),
                IbanEntity(id = "b", order = 1, yourUniqueCode = "DC-B"),
                IbanEntity(id = "c", order = 2, yourUniqueCode = "DC-C"),
            ),
        )
        assertEquals("DC-B", store.firstDepositCode())
        assertEquals(listOf("DC-B", "DC-C"), store.depositCodes())
        assertNull(InMemoryBittrCustomerStore().firstDepositCode())
    }

    @Test
    fun `a corrupt file reads as empty`() {
        val file = tempFile().apply { parentFile.mkdirs(); writeText("not json") }
        assertTrue(FileBittrCustomerStore(file).entities.value.isEmpty())
    }

    /** `deleteClientInfo()` removes `device`; `senttobittr` is kept, as on iOS. */
    @Test
    fun `clearing the account drops the accounts and purchases and keeps the sent ids`() {
        val file = tempFile()
        val store = FileBittrCustomerStore(file)
        store.upsert(IbanEntity(id = "a", order = 0, yourUniqueCode = "DC-A", lightningAddressUsername = "me@staging.getbittr.com"))
        store.addPurchases(listOf(BittrTransactionInfo("tx1", null, null, null, "EUR", 0.001, 60.0, 61.0)))
        store.addSentToBittr(listOf("tx1"))
        store.addFundingTransaction("tx1")

        store.clearAccount()
        val reloaded = FileBittrCustomerStore(file)
        assertTrue(reloaded.entities.value.isEmpty())
        assertTrue(reloaded.purchases.value.isEmpty())
        assertNull(reloaded.firstDepositCode())
        assertEquals(setOf("tx1"), reloaded.sentToBittr())
        assertTrue(reloaded.fundingTransactions.value.isEmpty())
    }

    @Test
    fun `funding transactions survive a reload`() {
        val file = tempFile()
        FileBittrCustomerStore(file).addFundingTransaction("funding")
        assertEquals(setOf("funding"), FileBittrCustomerStore(file).fundingTransactions.value)
    }
}
