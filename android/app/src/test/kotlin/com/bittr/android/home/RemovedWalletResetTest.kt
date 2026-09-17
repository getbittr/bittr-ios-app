package com.bittr.android.home

import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

class RemovedWalletResetTest {

    private val state = MutableStateFlow(WalletState.Ready)
    private val scope = CoroutineScope(Dispatchers.Unconfined)
    private val calls = mutableListOf<String>()

    private val reset = RemovedWalletReset(
        walletState = state,
        scope = scope,
        resets = listOf(
            { calls += "overview" },
            { error("one failing reset must not stop the rest") },
            { calls += "profits" },
        ),
    )

    @After
    fun tearDown() = scope.cancel()

    @Test
    fun `every reset runs when the wallet is removed, and not before`() {
        reset.start()
        state.value = WalletState.Locked
        assertEquals(emptyList<String>(), calls)

        state.value = WalletState.Uninitialized
        assertEquals(listOf("overview", "profits"), calls)
    }

    @Test
    fun `starting twice does not reset twice`() {
        reset.start()
        reset.start()
        state.value = WalletState.Uninitialized
        assertEquals(listOf("overview", "profits"), calls)
    }
}
