package com.bittr.android.navigation

import com.bittr.android.core.wallet.WalletState
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** [needsPin] — which back stacks a Locked wallet may keep on screen. */
class ScreenLockTest {

    @Test
    fun `a locked wallet with Home restored after process death goes to the PIN`() {
        assertTrue(needsPin(WalletState.Locked, listOf(Routes.HOME)))
    }

    @Test
    fun `a locked wallet goes to the PIN from a sheet or an article over Home`() {
        assertTrue(needsPin(WalletState.Locked, listOf(Routes.HOME, Routes.SEND)))
        assertTrue(needsPin(WalletState.Locked, listOf(Routes.HOME, Routes.ARTICLE)))
        assertTrue(needsPin(WalletState.Locked, listOf(Routes.SIGNUP_BITTR)))
    }

    @Test
    fun `onboarding passes through Locked without being sent to the PIN`() {
        assertFalse(needsPin(WalletState.Locked, listOf(Routes.SIGNUP_START)))
        assertFalse(needsPin(WalletState.Locked, listOf(Routes.SIGNUP_START, Routes.SIGNUP_RESTORE)))
    }

    @Test
    fun `the PIN pad and an article over it stay`() {
        assertFalse(needsPin(WalletState.Locked, listOf(Routes.PIN_UNLOCK)))
        assertFalse(needsPin(WalletState.Locked, listOf(Routes.PIN_UNLOCK, Routes.ARTICLE)))
    }

    @Test
    fun `an unlocked wallet or none is never sent to the PIN`() {
        assertFalse(needsPin(WalletState.Ready, listOf(Routes.HOME, Routes.SEND)))
        assertFalse(needsPin(WalletState.Uninitialized, listOf(Routes.HOME)))
        assertFalse(needsPin(WalletState.Locked, emptyList()))
    }
}
