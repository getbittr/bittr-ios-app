package com.bittr.android.core.wallet.stub

import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class StubWalletServiceTest {

    @Test
    fun `starts uninitialized so the app lands on signup`() {
        assertEquals(WalletState.Uninitialized, StubWalletService().state.value)
    }

    @Test
    fun `lifecycle calls are inert and idempotent`() = runTest {
        val service = StubWalletService()
        service.start()
        service.start()
        service.stop()
        service.stop()
        assertEquals(WalletState.Uninitialized, service.state.value)
    }
}
