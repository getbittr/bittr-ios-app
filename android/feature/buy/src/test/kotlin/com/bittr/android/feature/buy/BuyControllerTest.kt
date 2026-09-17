package com.bittr.android.feature.buy

import com.bittr.android.core.common.TestID
import com.bittr.android.core.network.IbanEntity
import com.bittr.android.core.network.PaymentMode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class BuyControllerTest {

    private class FakeSource : BuySource {
        val store = MutableStateFlow<List<IbanEntity>>(emptyList())
        override val entities: StateFlow<List<IbanEntity>> = store
        var authorized = false
        var requested = false
        var token: String? = "fcm-token"
        var tokenRequests = 0
        var verify: VerifyEmailResult = VerifyEmailResult.Accepted
        var codes = mutableListOf<CheckCodeResult>()
        var registered = mutableListOf<Boolean>()
        var sentTokens = mutableListOf<String?>()
        var verifyCalls = 0
        var now = 1_000L
        var modes = mutableListOf<String>()
        var online = true

        override fun isOnline() = online

        override suspend fun refreshDepositCodes() = DepositRefresh.Unchanged
        override suspend fun setPaymentMode(entityId: String, mode: String): PaymentModeResult {
            modes += mode
            store.update { list -> list.map { if (it.id == entityId) it.copy(paymentMode = mode) else it } }
            return PaymentModeResult.Confirmed(mode)
        }
        override fun notificationsAuthorized() = authorized
        override fun notificationPermissionRequested() = requested
        override fun markNotificationPermissionRequested() { requested = true }
        override suspend fun deviceToken(): String? { tokenRequests++; return token }
        override fun saveIbanDetails(currentId: String?, email: String, iban: String, initiativeConfirmedAt: String?): String {
            val id = currentId ?: "e1"
            store.update { list ->
                list.filterNot { it.id == id } +
                    IbanEntity(id = id, yourEmail = email, yourIbanNumber = iban, initiativeConfirmedAt = initiativeConfirmedAt)
            }
            return id
        }
        override suspend fun verifyEmail(email: String, iban: String): VerifyEmailResult { verifyCalls++; return verify }
        override suspend fun checkCode(entityId: String, code: String) =
            codes.removeFirstOrNull() ?: CheckCodeResult.Verified(null, null)
        override suspend fun register(
            entityId: String,
            notificationsDenied: Boolean,
            deviceToken: String?,
            restoreDepositCode: String?,
            restoreMessage: String?,
        ): RegisterResult {
            registered += notificationsDenied
            sentTokens += deviceToken
            store.update { list ->
                list.map { if (it.id == entityId) it.copy(yourUniqueCode = "DC1", ourIbanNumber = "CH00") else it }
            }
            return RegisterResult.Created
        }
        override fun nowIsoUtc() = "2026-09-14T22:00:00Z"
        override fun nowMillis() = now
    }

    private fun TestScope.controller(source: FakeSource) = BuyController(source, backgroundScope).also { it.start() }

    private fun BuyController.fillStart() {
        onStartSignup()
        onReadyNext()
        onIbanChange("NL27 ABNA 0451 1357 25")
        onEmailChange("e2ebittr@getbittr.com")
    }

    /** Through the IBAN page to the code page. */
    private fun TestScope.toCodePage(c: BuyController) {
        c.fillStart()
        c.onVerify()
        c.onInitiativeConfirm()
        runCurrent()
        assertEquals(SignupPage.Otp, c.state.value.signup!!.page)
    }

    /** `moveToPage(_:)`'s `checkInternetConnection()`: offline, the page stays put and says so. */
    @Test
    fun `offline, a page move stays put and asks to check the connection`() = runTest {
        val source = FakeSource()
        val c = controller(source)
        c.onStartSignup()
        source.online = false
        c.onReadyNext()
        assertEquals(SignupPage.Ready, c.state.value.signup!!.page)
        assertEquals(BuyStrings.CHECK_YOUR_CONNECTION, c.state.value.alert?.title)

        c.onAlertAction(BuyAction.Dismiss)
        source.online = true
        c.onReadyNext()
        assertEquals(SignupPage.Start, c.state.value.signup!!.page)
    }

    @Test
    fun `the happy path asks for the initiative, then notifications, and ends on the cards`() = runTest {
        val source = FakeSource()
        val c = controller(source)
        c.fillStart()
        c.onVerify()
        assertTrue(c.state.value.signup!!.showInitiative)
        c.onInitiativeConfirm()
        runCurrent()
        assertEquals(SignupPage.Otp, c.state.value.signup!!.page)
        assertEquals("NL27ABNA0451135725", source.store.value.single().yourIbanNumber)
        assertEquals("2026-09-14T22:00:00Z", source.store.value.single().initiativeConfirmedAt)

        c.onCodeChange("123456")
        assertEquals(TestID.Alert.receiveNotificationsPrompt, c.state.value.alert!!.id)
        c.onAlertAction(BuyAction.RequestNotifications)
        c.onNotificationPermissionResult(granted = true)
        runCurrent()
        assertEquals(SignupPage.Success, c.state.value.signup!!.page)
        assertEquals(listOf(false), source.registered)
        assertEquals(listOf<String?>("fcm-token"), source.sentTokens)

        c.onSuccessNext()
        c.onLetsGo()
        assertTrue(c.state.value.alert!!.message.contains("CH00"))
        c.onAlertAction(BuyAction.FinishSignup)
        assertNull(c.state.value.signup)
        assertEquals("DC1", c.state.value.cards.single().yourUniqueCode)
    }

    /**
     * Decision 23: no push token halts the signup with `tokenregistrationfail`
     * [Try again, Continue], and Continue registers for on-chain payouts — iOS's
     * `tokenRegistrationFailed()`.
     */
    @Test
    fun `no push token halts the signup, and continue registers on-chain without one`() = runTest {
        val source = FakeSource().apply {
            authorized = true
            token = null
        }
        val c = controller(source)
        toCodePage(c)

        c.onCodeChange("123456")
        runCurrent()
        val alert = c.state.value.alert!!
        assertEquals(BuyStrings.TOKEN_REGISTRATION_FAIL, alert.message)
        assertEquals(listOf(BuyAction.RetryDeviceToken, BuyAction.ContinueWithoutNotifications), alert.buttons.map { it.action })
        assertTrue("nothing is registered while the signup is halted", source.registered.isEmpty())
        assertFalse(c.state.value.signup!!.busy)

        c.onAlertAction(BuyAction.ContinueWithoutNotifications)
        runCurrent()
        assertEquals(SignupPage.Success, c.state.value.signup!!.page)
        assertEquals(listOf(true), source.registered)
        assertEquals(listOf<String?>(null), source.sentTokens)
    }

    @Test
    fun `try again waits for the token once more and registers with it`() = runTest {
        val source = FakeSource().apply {
            authorized = true
            token = null
        }
        val c = controller(source)
        toCodePage(c)
        c.onCodeChange("123456")
        runCurrent()
        assertEquals(BuyStrings.TOKEN_REGISTRATION_FAIL, c.state.value.alert!!.message)

        source.token = "late-token"
        c.onAlertAction(BuyAction.RetryDeviceToken)
        runCurrent()
        assertEquals(2, source.tokenRequests)
        assertEquals(SignupPage.Success, c.state.value.signup!!.page)
        assertEquals(listOf(false), source.registered)
        assertEquals(listOf<String?>("late-token"), source.sentTokens)
    }

    @Test
    fun `an invalid email alerts and a confirmed initiative is not asked twice`() = runTest {
        val source = FakeSource().apply { verify = VerifyEmailResult.Rejected("bad iban") }
        val c = controller(source)
        c.fillStart()
        c.onEmailChange("e2ebittr@getbittr")
        c.onVerify()
        assertEquals(BuyStrings.TRANSFER_1_VC, c.state.value.alert!!.message)
        c.onAlertAction(BuyAction.Dismiss)

        c.onEmailChange("e2ebittr@getbittr.com")
        c.onVerify()
        c.onInitiativeConfirm()
        runCurrent()
        assertEquals("bad iban", c.state.value.alert!!.message)
        c.onAlertAction(BuyAction.Dismiss)

        c.onVerify()
        assertFalse(c.state.value.signup!!.showInitiative)
        runCurrent()
        assertEquals(2, source.verifyCalls)
    }

    @Test
    fun `denied notifications continue on-chain, and a wrong code re-arms auto-submit`() = runTest {
        val source = FakeSource().apply {
            requested = true
            codes += CheckCodeResult.InvalidCode
        }
        val c = controller(source)
        toCodePage(c)

        c.onCodeChange("111111")
        assertEquals(TestID.Alert.receiveNotificationsDenied, c.state.value.alert!!.id)
        c.onAlertAction(BuyAction.ContinueWithoutNotifications)
        runCurrent()
        assertEquals(BuyStrings.VERIFICATION_FAIL, c.state.value.alert!!.message)
        c.onAlertAction(BuyAction.Dismiss)

        c.onCodeChange("")
        c.onCodeChange("123456")
        assertEquals(TestID.Alert.receiveNotificationsDenied, c.state.value.alert!!.id)
        c.onAlertAction(BuyAction.ContinueWithoutNotifications)
        runCurrent()
        assertEquals(SignupPage.Success, c.state.value.signup!!.page)
        assertEquals(listOf(true), source.registered)
        assertEquals(listOf<String?>(null), source.sentTokens)
    }

    @Test
    fun `resend is limited to one per thirty seconds`() = runTest {
        val source = FakeSource()
        val c = controller(source)
        toCodePage(c)

        c.onResendCode()
        runCurrent()
        assertEquals(BuyStrings.EMAIL_RESENT, c.state.value.alert!!.title)
        c.onAlertAction(BuyAction.Dismiss)
        source.now += 5_000
        c.onResendCode()
        assertEquals(TestID.Alert.resendCode, c.state.value.alert!!.id)
        c.onAlertAction(BuyAction.ChangeEmail)
        assertEquals(SignupPage.Start, c.state.value.signup!!.page)
    }

    @Test
    fun `the lightning switch needs notifications and otherwise patches the mode`() = runTest {
        val source = FakeSource()
        source.store.value = listOf(IbanEntity(id = "e1", yourUniqueCode = "DC1", paymentMode = PaymentMode.ONCHAIN))
        val c = controller(source)
        val entity = c.state.value.cards.single()
        assertFalse(c.state.value.lightningOn(entity))

        c.onPaymentModeToggled(entity, lightningOn = true)
        assertEquals(BuyStrings.LIGHTNING_NEEDS_NOTIFICATIONS, c.state.value.alert!!.message)
        assertTrue(source.modes.isEmpty())

        source.authorized = true
        c.onAlertAction(BuyAction.Dismiss)
        c.onPaymentModeToggled(entity, lightningOn = true)
        runCurrent()
        assertEquals(listOf(PaymentMode.LIGHTNING), source.modes)
        assertTrue(c.state.value.lightningOn(c.state.value.cards.single()))
    }

    @Test
    fun `skip offers go to wallet first`() = runTest {
        val c = controller(FakeSource())
        c.fillStart()
        c.onSkip()
        assertEquals(TestID.Alert.onlyIban, c.state.value.alert!!.id)
        assertEquals(BuyAction.GoToWallet, c.state.value.alert!!.buttons[0].action)
        c.onAlertAction(BuyAction.GoToWallet)
        assertNull(c.state.value.signup)
    }

    /** Onboarding's Continue: `signupVC.moveToPage(10)` — the IBAN page, no Buy Ready page. */
    @Test
    fun `onboarding starts the signup on the IBAN page`() = runTest {
        val c = controller(FakeSource())
        c.onStartSignupAtIban()
        assertEquals(SignupPage.Start, c.state.value.signup!!.page)
    }
}
