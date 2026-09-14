package com.bittr.android.feature.home

import com.bittr.android.core.wallet.FiatPrice
import com.bittr.android.core.wallet.WalletOverview
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MoveBalancesTest {

    @Test
    fun `instant includes funds sweeping back from a closed channel, total is both`() {
        val wallet = WalletOverview(satoshisOnchain = 294_424, satoshisLightning = 10_000, pendingClosureSatoshis = 576, channelCount = 1)
        val balances = moveBalances(wallet, FiatPrice(100_000.0, "€"))

        assertEquals("294 424 sats", balances.regular)
        assertEquals("10 576 sats", balances.instant)
        assertEquals("305 000 sats", balances.total)
        assertEquals("€ 294", balances.regularFiat)
        assertEquals("€ 305", balances.totalFiat)
    }

    @Test
    fun `no price means no fiat figures`() {
        val balances = moveBalances(WalletOverview(satoshisOnchain = 1_000), price = null)
        assertEquals("0 sats", balances.instant)
        assertNull(balances.totalFiat)
    }
}
