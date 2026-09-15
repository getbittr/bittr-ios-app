package com.bittr.android.core.wallet.ldk.lightning

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WalletOverviewPublisherResyncTest {

    private val publisher = WalletOverviewPublisher(hasNode = true)

    private fun publishOnchain(sats: ULong) {
        val reading = reading(balances = balances(totalOnchainBalanceSats = sats))
        publisher.publish(reading, WalletBalanceSnapshot.of(reading.channels, reading.balances, reading.payments))
    }

    @Test
    fun `a refresh hides the synced wallet until the next reading replaces it`() {
        publishOnchain(1_000uL)
        publisher.markResyncing()
        assertFalse(publisher.overview.value.hasSynced)

        publishOnchain(2_000uL)
        publisher.endResync()
        assertTrue(publisher.overview.value.hasSynced)
        assertEquals(2_000L, publisher.overview.value.satoshisOnchain)
    }

    @Test
    fun `a refresh that read nothing puts the previous overview back`() {
        publishOnchain(1_000uL)
        publisher.markResyncing()
        publisher.endResync()
        assertTrue(publisher.overview.value.hasSynced)
        assertEquals(1_000L, publisher.overview.value.satoshisOnchain)
    }

    @Test
    fun `a refresh before the first sync changes nothing`() {
        publisher.markResyncing()
        publisher.endResync()
        assertFalse(publisher.overview.value.hasSynced)
    }
}
