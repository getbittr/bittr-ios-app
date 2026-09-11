package com.bittr.android.core.lnurl

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-33 §Acceptance 6: a `payRequest` with `minSendable == maxSendable`, from
 * **any** source, raises a confirmation and pays nothing until accepted.
 *
 * ### The bug being ported away from
 *
 * `ios/bittr/Move, Send, Receive/SendVC/SendLNURL.swift:243–247`:
 *
 * ```swift
 * if minSendable == maxSendable {
 *     self.sendPayRequest(callbackURL: …, amount: minSendable, …)
 * }
 * ```
 *
 * The endpoint chooses both values, so any LNURL an attacker controls takes that
 * branch by setting them equal — and that branch fetches the invoice and pays it
 * with no amount entry, no destination shown and no confirmation. The only thing
 * bounding the amount is the wallet's balance.
 *
 * So the assertion is not "the equal case is handled". It is that the equal case
 * cannot reach the payer, and it is checked by counting calls on a fake rather
 * than by reading the code.
 */
class LnurlPayConfirmationTest {

    /** Counts what reaches the network and the wallet. Never expected to be > 1. */
    private class CountingPayer : LnurlInvoicePayer {
        var calls = 0
            private set
        var lastConfirmation: LnurlPayConfirmation? = null
            private set

        override suspend fun fetchAndPay(confirmation: LnurlPayConfirmation): Result<Unit> {
            calls++
            lastConfirmation = confirmation
            return Result.success(Unit)
        }
    }

    private companion object {
        const val CALLBACK = "https://pay.example.com/lnurlp/api/v1/lnurl/cb/abc"

        /** The attacker's shape: min and max equal, so iOS pays without asking. */
        fun fixedAmount(amountMsat: Long = 500_000_000L) = LnurlPayRequest(
            callbackUrl = CALLBACK,
            minSendableMsat = amountMsat,
            maxSendableMsat = amountMsat,
            metadata = """[["text/plain","Payment to tom"]]""",
        )

        fun range() = LnurlPayRequest(
            callbackUrl = CALLBACK,
            minSendableMsat = 1_000L,
            maxSendableMsat = 100_000L,
        )

        /** Every source that can reach the pay path, so "from any source" is literal. */
        val EVERY_SOURCE = listOf(
            LnurlSource.QrScan,
            LnurlSource.Deeplink,
            LnurlSource.FirstPartyWeb(origin = "https://getbittr.com", pageTitle = "Support"),
        )
    }

    @Test
    fun `min equals max still raises a confirmation, from every source`() {
        EVERY_SOURCE.forEach { source ->
            val step = LnurlPay.next(fixedAmount(), source)

            when (source) {
                // Web-originated payment does not merely get a confirmation, it
                // does not get to start at all (R-4, R-5).
                is LnurlSource.FirstPartyWeb -> assertTrue(
                    "A web-originated payRequest must be blocked outright, not " +
                        "confirmed. Got $step",
                    step is LnurlPayStep.Blocked,
                )

                else -> assertTrue(
                    "minSendable == maxSendable from $source must raise a confirmation. " +
                        "This is the iOS branch that pays with no dialog. Got $step",
                    step is LnurlPayStep.Confirm,
                )
            }
        }
    }

    @Test
    fun `the confirmation carries the amount and the destination`() {
        // R-4 names both. A dialog that says "confirm payment?" is not a control.
        val step = LnurlPay.next(fixedAmount(amountMsat = 21_000_000L), LnurlSource.QrScan)

        val confirmation = (step as LnurlPayStep.Confirm).confirmation
        assertEquals(21_000L, confirmation.amountSat)
        assertEquals("pay.example.com", confirmation.destinationHost)
        assertEquals(CALLBACK, confirmation.destinationUrl)
        assertEquals("Payment to tom", confirmation.description)
    }

    @Test
    fun `nothing is paid until the confirmation is accepted`() = runTest {
        val payer = CountingPayer()
        val gate = LnurlPayGate(payer)

        val step = LnurlPay.next(fixedAmount(), LnurlSource.QrScan)
        gate.present((step as LnurlPayStep.Confirm).confirmation)

        assertEquals(
            "Presenting a confirmation must not fetch an invoice or pay anything " +
                "(BIT-33 R-8).",
            0,
            payer.calls,
        )

        val outcome = gate.accept()

        assertEquals(LnurlPayOutcome.Paid, outcome)
        assertEquals("Accepting pays exactly once.", 1, payer.calls)
        assertEquals(500_000L, payer.lastConfirmation?.amountSat)
    }

    @Test
    fun `dismissing the confirmation pays nothing`() = runTest {
        val payer = CountingPayer()
        val gate = LnurlPayGate(payer)

        val step = LnurlPay.next(fixedAmount(), LnurlSource.Deeplink)
        gate.present((step as LnurlPayStep.Confirm).confirmation)

        assertEquals(LnurlPayOutcome.Cancelled, gate.cancel())
        assertEquals(0, payer.calls)
        assertNull(gate.awaitingConfirmation)

        // And a stale accept afterwards finds nothing rather than paying.
        assertEquals(LnurlPayOutcome.NothingPending, gate.accept())
        assertEquals(0, payer.calls)
    }

    @Test
    fun `a double accept pays once`() = runTest {
        val payer = CountingPayer()
        val gate = LnurlPayGate(payer)

        val step = LnurlPay.next(fixedAmount(), LnurlSource.QrScan)
        gate.present((step as LnurlPayStep.Confirm).confirmation)

        gate.accept()
        val second = gate.accept()

        assertEquals(
            "A second tap on Confirm must not pay a second time.",
            LnurlPayOutcome.NothingPending,
            second,
        )
        assertEquals(1, payer.calls)
    }

    @Test
    fun `a range asks for an amount before confirming`() {
        val step = LnurlPay.next(range(), LnurlSource.QrScan)

        assertEquals(
            LnurlPayStep.NeedsAmount(
                minSat = 1L,
                maxSat = 100L,
                destinationHost = "pay.example.com",
                description = null,
            ),
            step,
        )
    }

    @Test
    fun `an amount outside the endpoint's range is sent back for re-entry`() {
        val tooMuch = LnurlPay.next(range(), LnurlSource.QrScan, enteredAmountSat = 1_000L)
        val tooLittle = LnurlPay.next(range(), LnurlSource.QrScan, enteredAmountSat = 0L)

        assertTrue("1000 sat exceeds a 100 sat maximum. Got $tooMuch", tooMuch is LnurlPayStep.NeedsAmount)
        assertTrue("0 sat is below a 1 sat minimum. Got $tooLittle", tooLittle is LnurlPayStep.NeedsAmount)
    }

    @Test
    fun `an amount inside the range confirms it, and still does not pay`() = runTest {
        val payer = CountingPayer()
        val gate = LnurlPayGate(payer)

        val step = LnurlPay.next(range(), LnurlSource.QrScan, enteredAmountSat = 50L)
        val confirmation = (step as LnurlPayStep.Confirm).confirmation
        assertEquals(50L, confirmation.amountSat)

        gate.present(confirmation)
        assertEquals(0, payer.calls)
    }

    @Test
    fun `an amount the user entered earlier is not consent to a fixed amount`() {
        // The endpoint picks the amount in the min == max case, so a number the
        // user typed for something else must not double as approval of it. The
        // confirmation is raised either way — this asserts the amount shown is the
        // endpoint's, so the dialog cannot claim the user chose it.
        val step = LnurlPay.next(
            fixedAmount(amountMsat = 900_000_000L),
            LnurlSource.QrScan,
            enteredAmountSat = 10L,
        )

        assertEquals(900_000L, (step as LnurlPayStep.Confirm).confirmation.amountSat)
    }

    @Test
    fun `an endpoint on a private address is unusable, not confirmable`() {
        // R-7 applies to the callback too: it is a URL from a remote server that
        // we are about to request.
        val step = LnurlPay.next(
            LnurlPayRequest(
                callbackUrl = "http://169.254.169.254/lnurlp/cb",
                minSendableMsat = 1_000L,
                maxSendableMsat = 1_000L,
            ),
            LnurlSource.QrScan,
        )

        assertTrue("Got $step", step is LnurlPayStep.Unusable)
    }

    @Test
    fun `an impossible range is unusable`() {
        val inverted = LnurlPay.next(
            LnurlPayRequest(CALLBACK, minSendableMsat = 10_000L, maxSendableMsat = 1_000L),
            LnurlSource.QrScan,
        )
        val zero = LnurlPay.next(
            LnurlPayRequest(CALLBACK, minSendableMsat = 0L, maxSendableMsat = 0L),
            LnurlSource.QrScan,
        )

        assertTrue("Got $inverted", inverted is LnurlPayStep.Unusable)
        assertTrue("Got $zero", zero is LnurlPayStep.Unusable)
    }

    @Test
    fun `a hostile description cannot fill the dialog`() {
        val step = LnurlPay.next(
            fixedAmount().copy(metadata = """[["text/plain","${"A".repeat(500)}"]]"""),
            LnurlSource.QrScan,
        )

        assertEquals(
            "Remote description text is truncated so it cannot push the amount and " +
                "destination off the dialog.",
            140,
            (step as LnurlPayStep.Confirm).confirmation.description?.length,
        )
    }

    @Test
    fun `a hostile description cannot smuggle control characters`() {
        // A newline in remote text is how it fakes a second line of dialog copy —
        // "Tip" on one line and "Sending to getbittr.com" under it, while the real
        // destination is pay.example.com. Stripped, not escaped: there is no line
        // for a second line to be on.
        val step = LnurlPay.next(
            fixedAmount().copy(
                metadata = "[[\"text/plain\",\"Tip\nSending to getbittr.com\u0007\"]]",
            ),
            LnurlSource.QrScan,
        )

        val description = (step as LnurlPayStep.Confirm).confirmation.description
        assertEquals("TipSending to getbittr.com", description)
    }

    @Test
    fun `metadata without a text-plain entry yields no description`() {
        val step = LnurlPay.next(
            fixedAmount().copy(metadata = """[["image/png;base64","iVBOR"]]"""),
            LnurlSource.QrScan,
        )

        assertNull((step as LnurlPayStep.Confirm).confirmation.description)
    }

    @Test
    fun `unparseable metadata is a missing description, never a failed payment`() {
        val step = LnurlPay.next(
            fixedAmount().copy(metadata = """[["text/plain","unterminated"""),
            LnurlSource.QrScan,
        )

        assertTrue(
            "A metadata parse failure must not block the flow — the description is a " +
                "label, not a control. Got $step",
            step is LnurlPayStep.Confirm,
        )
        assertNull((step as LnurlPayStep.Confirm).confirmation.description)
    }
}
