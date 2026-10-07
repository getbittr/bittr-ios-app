package com.bittr.android.core.designsystem

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * A button runs once its card has slid away, and a newer alert can replace the card meanwhile —
 * a push, a status. The tap belonged to the alert that is gone: it must neither act on the newer
 * one (the handlers clear whatever alert is current, as PushCoordinator's does) nor hide it.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class AlertReplacementTest {

    @get:Rule
    val composeRule = createComposeRule()

    /** A model's alert: a plain class, so two with the same words are still two. */
    private class Alert(val title: String, val message: String)

    private var alert by mutableStateOf<Alert?>(null)
    private val pressed = mutableListOf<Alert>()

    private fun show(first: Alert) {
        alert = first
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            BittrTheme {
                alert?.let { shown ->
                    BittrInlineAlert(
                        title = shown.title,
                        message = shown.message,
                        buttons = listOf(
                            BittrAlertButton(label = "Okay", dismissesAlert = true) {
                                pressed += shown
                                alert = null
                            },
                        ),
                        identity = shown,
                    )
                }
            }
        }
        composeRule.mainClock.advanceTimeBy(2_000)
    }

    @Test
    fun `a tap on a replaced alert neither acts nor clears the newer one`() {
        val first = Alert("bittr payout", "You're receiving a new payment!")
        show(first)
        composeRule.onNodeWithText("Okay").performClick()

        // The card is sliding away; the newer alert lands before it is gone.
        val second = Alert("incoming payment", "Tap Okay to receive it.")
        alert = second
        composeRule.mainClock.advanceTimeBy(2_000)

        assertTrue("The replaced alert's button ran: $pressed", pressed.isEmpty())
        assertSame(second, alert)
        composeRule.onNodeWithText("Tap Okay to receive it.").assertIsDisplayed()
    }

    @Test
    fun `a newer alert with the same words gets its own card`() {
        val first = Alert("incoming payment", "Tap Okay to receive it.")
        show(first)
        composeRule.onNodeWithText("Okay").performClick()

        val second = Alert("incoming payment", "Tap Okay to receive it.")
        alert = second
        composeRule.mainClock.advanceTimeBy(2_000)

        assertTrue(pressed.isEmpty())
        assertSame(second, alert)
        composeRule.onNodeWithText("Tap Okay to receive it.").assertIsDisplayed()

        // And its own button works.
        composeRule.onNodeWithText("Okay").performClick()
        composeRule.mainClock.advanceTimeBy(2_000)
        assertSame(second, pressed.single())
    }

    /**
     * The LNURL withdraw amount: Confirm with an amount out of range asks again — a new alert, the
     * same title, an empty field — from inside the button that closed the first. Keyed on its
     * words, the field alert took the card that had just slid away and drew nothing, and the
     * withdrawal stalled.
     */
    @Test
    fun `a text field alert asked again from its own button is drawn again`() {
        var asked by mutableStateOf<Alert?>(null)
        val saved = mutableListOf<String>()
        fun ask() {
            asked = Alert("withdraw request", "Enter an amount")
        }
        ask()
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            BittrTheme {
                asked?.let { shown ->
                    BittrTextFieldAlert(
                        title = shown.title,
                        message = shown.message,
                        initialText = "",
                        placeholder = "Amount in satoshis",
                        cancelLabel = "Cancel",
                        saveLabel = "Confirm",
                        onCancel = { asked = null },
                        onSave = { text ->
                            asked = null
                            if (text == "5") ask() else saved += text
                        },
                        identity = shown,
                    )
                }
            }
        }
        composeRule.mainClock.advanceTimeBy(2_000)

        composeRule.onNode(hasSetTextAction()).performTextInput("5")
        composeRule.onNodeWithText("Confirm").performClick()
        composeRule.mainClock.advanceTimeBy(2_000)

        // Out of range: asked again, and drawn — with an empty field, ready for the next amount.
        composeRule.onNodeWithText("Enter an amount").assertIsDisplayed()
        composeRule.onNode(hasSetTextAction()).performTextInput("5000")
        composeRule.onNodeWithText("Confirm").performClick()
        composeRule.mainClock.advanceTimeBy(2_000)
        assertEquals(listOf("5000"), saved)
    }
}
