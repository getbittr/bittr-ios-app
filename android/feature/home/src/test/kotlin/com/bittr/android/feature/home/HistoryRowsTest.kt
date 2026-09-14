package com.bittr.android.feature.home

import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.WalletActivity
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HistoryRowsTest {

    private val utc = TimeZone.getTimeZone("UTC")

    private fun activity(
        received: Long = 0,
        sent: Long = 0,
        fee: Long = 0,
        timestamp: Long = 1_757_808_000, // 2025-09-14
        lightning: Boolean = false,
        height: Int? = 100,
    ) = WalletActivity("tx", received, sent, fee, timestamp, lightning, height)

    @Test
    fun `a send is signed minus and includes its fee`() {
        val row = historyRows(listOf(activity(sent = 9_000, fee = 653)), price = null, currentHeight = 100, timeZone = utc).single()
        assertEquals("- 9 653 sats", row.sats)
        assertEquals("Sep 14", row.day)
        assertNull(row.fiat)
    }

    @Test
    fun `the fiat figure is rounded to whole units with no sign`() {
        val row = historyRows(listOf(activity(sent = 500_000)), FiatPrice(100_000.0, "€"), 100, utc).single()
        assertEquals("500 €", row.fiat)
    }

    @Test
    fun `the year shows only where it changes from the row above`() {
        val rows = historyRows(
            listOf(activity(received = 1), activity(received = 1, timestamp = 1_700_000_000), activity(received = 1, timestamp = 1_699_000_000)),
            price = null,
            currentHeight = 100,
            timeZone = utc,
        )
        assertEquals(listOf(null, "2023", null), rows.map { it.year })
    }

    @Test
    fun `the balance conversion puts the symbol first and rounds to whole units`() {
        // settings.yaml switches to CHF and then looks for "CHF" on Home — this label.
        assertEquals("CHF 190", balanceFiat(294_424, FiatPrice(64_625.2, "CHF")))
        assertEquals("€ 1 000", balanceFiat(100_000_000, FiatPrice(1_000.0, "€")))
        assertNull(balanceFiat(294_424, price = null))
    }

    @Test
    fun `an on-chain transaction without a height is unconfirmed, a lightning payment never is`() {
        val rows = historyRows(listOf(activity(height = null), activity(lightning = true, height = null), activity(height = 90)), null, 100, utc)
        assertTrue(rows[0].unconfirmed)
        assertFalse(rows[1].unconfirmed)
        assertFalse(rows[2].unconfirmed)
    }
}
