package com.bittr.android.home

import com.bittr.android.core.wallet.CachedProfit
import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.SwapActivity
import com.bittr.android.core.wallet.SwapActivityDirection
import com.bittr.android.core.wallet.SwapActivityStatus
import com.bittr.android.core.wallet.WalletActivity
import com.bittr.android.core.wallet.WalletOverview
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class FileHomeCacheTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val file: File get() = File(folder.root, "bittr/home-cache-development.json")

    private val swapRow = WalletActivity(
        id = "tx-swap",
        receivedSats = 49_094,
        sentSats = 50_000,
        feeSats = 7,
        timestampSecs = 1_789_000_000,
        isLightning = false,
        confirmationHeight = 812,
        paymentHash = "hash",
        description = "Swap onchain to lightning 123",
        swap = SwapActivity(
            dateId = "123",
            boltzId = "boltz-1",
            status = SwapActivityStatus.Succeeded,
            direction = SwapActivityDirection.OnchainToLightning,
            onchainId = "tx-swap",
            lightningId = "preimage",
            amountSats = 49_094,
        ),
    )

    private val overview = WalletOverview(
        hasNode = true,
        hasSynced = true,
        satoshisOnchain = 200_000,
        satoshisLightning = 93_076,
        pendingClosureSatoshis = 1_000,
        transactions = listOf(
            swapRow,
            WalletActivity("tx-2", 7_424, 0, 0, 1_788_000_000, true, null),
            // `cachedHomeTransactions` drops rows with no timestamp.
            WalletActivity("no-time", 1, 0, 0, 0, false, null),
        ),
        currentHeight = 820,
        channelClosureTxIds = setOf("closure-1"),
    )

    @Test
    fun `a saved reading, price and profit come back on the next launch`() {
        val cache = FileHomeCache(file)
        cache.saveOverview(overview)
        cache.savePrice(FiatPrice(64_000.0, "CHF"))
        cache.savePrice(FiatPrice(68_000.0, "€"))
        cache.saveProfit(CachedProfit(12, 100, 112, "CHF"))

        val reopened = FileHomeCache(file).cached.value!!
        assertTrue(reopened.hasReading)
        assertEquals(294_076L, reopened.totalSatoshis)
        assertEquals(listOf(swapRow, overview.transactions[1]), reopened.transactions)
        assertEquals(820, reopened.currentHeight)
        assertEquals(setOf("closure-1"), reopened.channelClosureTxIds)
        assertEquals(FiatPrice(64_000.0, "CHF"), reopened.price("CHF"))
        assertEquals(FiatPrice(68_000.0, "€"), reopened.price("€"))
        assertEquals(CachedProfit(12, 100, 112, "CHF"), reopened.profit)
    }

    @Test
    fun `a new reading keeps the cached prices and profit`() {
        val cache = FileHomeCache(file)
        cache.savePrice(FiatPrice(64_000.0, "CHF"))
        cache.saveProfit(CachedProfit(1, 2, 3, "CHF"))
        cache.saveOverview(overview.copy(satoshisOnchain = 1))

        val cached = cache.cached.value!!
        assertEquals(1L + 93_076 + 1_000, cached.totalSatoshis)
        assertEquals(64_000.0, cached.prices.getValue("CHF"), 0.0)
        assertEquals(CachedProfit(1, 2, 3, "CHF"), cached.profit)
    }

    @Test
    fun `an unsynced overview is never saved`() {
        val cache = FileHomeCache(file)
        cache.saveOverview(overview.copy(hasSynced = false))
        assertNull(cache.cached.value)
        assertFalse(file.exists())
    }

    @Test
    fun `a price alone is no reading to show`() {
        val cache = FileHomeCache(file)
        cache.savePrice(FiatPrice(64_000.0, "CHF"))
        assertFalse(FileHomeCache(file).cached.value!!.hasReading)
    }

    @Test
    fun `clearing removes the file`() {
        val cache = FileHomeCache(file)
        cache.saveOverview(overview)
        cache.clear()
        assertNull(cache.cached.value)
        assertFalse(file.exists())
        assertNull(FileHomeCache(file).cached.value)
    }

    @Test
    fun `an unreadable or foreign file reads as no cache`() {
        file.parentFile!!.mkdirs()
        file.writeText("not json")
        assertNull(FileHomeCache(file).cached.value)
        file.writeText("""{"version":99,"hasReading":true}""")
        assertNull(FileHomeCache(file).cached.value)
    }
}
