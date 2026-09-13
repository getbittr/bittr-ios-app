package com.bittr.android.core.wallet.stub

import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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

    /** A flow has to be able to drive the whole arc and know what to type. */
    @Test
    fun `the create arc is deterministic`() = runTest {
        val service = StubWalletService()

        val mnemonic = service.createWallet()

        assertEquals(StubWalletService.PHRASE, mnemonic)
        assertEquals(StubWalletService.PHRASE, StubWalletService().createWallet())
        assertEquals(12, mnemonic.words.size)
    }

    @Test
    fun `setting a PIN locks and the right PIN unlocks`() = runTest {
        val service = StubWalletService()
        service.createWallet()
        service.setPin("1234")

        assertEquals(WalletState.Locked, service.state.value)
        assertFalse(service.unlock("4321"))
        assertEquals(WalletState.Locked, service.state.value)
        assertTrue(service.unlock("1234"))
        assertEquals(WalletState.Ready, service.state.value)
    }

    /**
     * Nothing is written down, so a new instance is a fresh install. That is what
     * makes a flow repeatable without a device wipe between runs.
     */
    @Test
    fun `state does not survive a new instance`() = runTest {
        StubWalletService().apply {
            createWallet()
            setPin("1234")
        }

        assertEquals(WalletState.Uninitialized, StubWalletService().state.value)
    }
}
