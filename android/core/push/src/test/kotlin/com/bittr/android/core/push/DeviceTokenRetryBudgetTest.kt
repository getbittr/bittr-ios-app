package com.bittr.android.core.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** §2.3 rule 2: ≤3 attempts in one app session, then ≤1 per app foreground. */
class DeviceTokenRetryBudgetTest {

    @Test
    fun `three attempts are allowed in the first session`() {
        val budget = DeviceTokenRetryBudget()

        assertTrue(budget.tryConsume())
        assertTrue(budget.tryConsume())
        assertTrue(budget.tryConsume())
        assertEquals(3, budget.attemptsInSession)
        assertTrue(budget.isSessionAllowanceSpent())
    }

    @Test
    fun `the fourth attempt in the same foreground is refused`() {
        val budget = DeviceTokenRetryBudget()
        repeat(3) { budget.tryConsume() }

        assertFalse(budget.tryConsume())
        assertEquals(3, budget.attemptsInSession)
    }

    @Test
    fun `each later foreground grants exactly one attempt`() {
        val budget = DeviceTokenRetryBudget()
        repeat(3) { budget.tryConsume() }

        budget.onAppForegrounded()
        assertTrue(budget.tryConsume())
        assertFalse(budget.tryConsume())

        budget.onAppForegrounded()
        assertTrue(budget.tryConsume())
        assertFalse(budget.tryConsume())

        assertEquals(5, budget.attemptsInSession)
    }

    @Test
    fun `foregrounding does not top the session allowance back up`() {
        // The failure this guards against is the opposite of starvation: a customer who
        // backgrounds and foregrounds the app repeatedly during an FCM outage must not be able
        // to walk past the ceiling §2.3 rule 2 requires the backend's rate limit to sit above.
        val budget = DeviceTokenRetryBudget()

        repeat(10) {
            budget.onAppForegrounded()
            budget.tryConsume()
            budget.tryConsume()
        }

        // Two granted in the first foreground and the third in the second, which exhausts the
        // session allowance; every foreground after that grants exactly one. 2 + 1 + 8 = 11.
        // Without the ceiling this loop would have taken 20.
        assertEquals(11, budget.attemptsInSession)
    }

    @Test
    fun `foregrounding before the allowance is spent does not cost an attempt`() {
        // A quiet app start: nothing has failed, so nothing has been consumed.
        val budget = DeviceTokenRetryBudget()
        repeat(5) { budget.onAppForegrounded() }

        assertEquals(0, budget.attemptsInSession)
        assertFalse(budget.isSessionAllowanceSpent())
        assertTrue(budget.tryConsume())
    }

    @Test
    fun `concurrent callers cannot exceed the allowance`() {
        // onNewToken arrives on FCM's executor while the app-start rotation check runs on the
        // registration scope; the two race precisely when a rotation is detected at launch.
        val budget = DeviceTokenRetryBudget()
        val granted = java.util.concurrent.atomic.AtomicInteger()

        val threads = (1..16).map {
            Thread { if (budget.tryConsume()) granted.incrementAndGet() }
        }
        threads.forEach { it.start() }
        threads.forEach { it.join() }

        assertEquals(3, granted.get())
        assertEquals(3, budget.attemptsInSession)
    }
}
