package com.bittr.android.core.wallet

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The two thresholds, pinned against `PinViewController.confirmPinButtonTapped`.
 *
 * These are worth a test that looks this obvious because the failure mode is silent
 * and expensive: a lockout that fires at nine erases wallets that were one correct
 * entry from being fine, and one that fires at eleven gives an attacker a free guess.
 * The numbers below are the iOS literals, and if someone changes them this test is
 * where they have to say so out loud.
 */
class PinLockoutTest {

    @Test
    fun `the thresholds are the iOS ones`() {
        assertEquals(3, PinLockout.WARN_AT)
        assertEquals(10, PinLockout.WIPE_AT)
    }

    @Test
    fun `nine failures is not a lockout and ten is`() {
        assertFalse(PinLockout.isLockedOut(9))
        assertTrue(PinLockout.isLockedOut(10))
    }

    @Test
    fun `a count read back above the threshold is still a lockout`() {
        // The counter comes out of secure storage, so it is whatever is on the device
        // rather than whatever this process last wrote. `>=` is what stops an
        // overshoot — a double-increment, a restored backup — reading as "not yet".
        assertTrue(PinLockout.isLockedOut(11))
        assertTrue(PinLockout.isLockedOut(400))
    }

    @Test
    fun `a fresh wallet is neither warned nor locked out`() {
        assertFalse(PinLockout.isLockedOut(0))
        assertFalse(PinLockout.isWarning(0))
        assertEquals(10, PinLockout.attemptsLeft(0))
    }

    @Test
    fun `the warning fires once, on the third failure`() {
        // `==`, not `>=`. Attempts 4–9 go back to the plain incorrect-PIN alert; a
        // two-button alert on every attempt would put the Forgot PIN button between
        // the user and simply retrying.
        (0..9).forEach { failures ->
            assertEquals(
                "failures = $failures",
                failures == 3,
                PinLockout.isWarning(failures),
            )
        }
    }

    @Test
    fun `attempts left counts down to the wipe`() {
        assertEquals(7, PinLockout.attemptsLeft(3))
        assertEquals(1, PinLockout.attemptsLeft(9))
        assertEquals(0, PinLockout.attemptsLeft(10))
    }

    @Test
    fun `attempts left never goes negative`() {
        // The warning copy interpolates this number. "-3 attempts left" is a bug the
        // user reads.
        assertEquals(0, PinLockout.attemptsLeft(13))
    }
}
