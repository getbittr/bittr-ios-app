package com.bittr.android.buy

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.bittr.android.core.network.BittrCustomerStore
import com.bittr.android.core.network.BittrEnvironment
import com.bittr.android.core.network.BittrRequestSigner
import com.bittr.android.core.network.CustomerRegistration
import com.bittr.android.core.network.CustomerSignup
import com.bittr.android.core.network.DepositCodeFetch
import com.bittr.android.core.network.DeviceTokenSource
import com.bittr.android.core.network.EmailCheck2fa
import com.bittr.android.core.network.EmailVerification
import com.bittr.android.core.network.EmailVerificationAnswer
import com.bittr.android.core.network.HttpClient
import com.bittr.android.core.network.HttpRequest
import com.bittr.android.core.network.HttpResponse
import com.bittr.android.core.network.HttpTransportException
import com.bittr.android.core.network.IbanEntity
import com.bittr.android.core.network.PaymentMode
import com.bittr.android.core.network.PaymentModePatch
import com.bittr.android.core.network.UnixClock
import com.bittr.android.feature.buy.BuySource
import com.bittr.android.feature.buy.CheckCodeResult
import com.bittr.android.feature.buy.DepositRefresh
import com.bittr.android.feature.buy.PaymentModeResult
import com.bittr.android.feature.buy.RegisterResult
import com.bittr.android.feature.buy.VerifyEmailResult
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The on-chain facts `POST /customer` needs, over the wallet the node runs.
 *
 * Separate from [BittrRequestSigner] (the Lightning node key) because these come from the seed
 * and the BDK wallet: the first receive address, the account xpub, and the BIP137 signature by
 * that address's key. Null in a build with no node.
 */
interface BittrRegistrationKeys {

    /** `getBittrAddress()` — external index 0 — waiting for BDK the way iOS does (4 × 3 s). */
    suspend fun bittrAddress(): String?

    /** `BitcoinManager.xpub`. */
    fun xpub(): String?

    /** `signMessageForPath(defaultBip84SigningPath(), message)`. */
    fun signBitcoinMessage(message: String): String?
}

/** iOS's `UNUserNotificationCenter` authorisation, in Android's terms. */
class NotificationAccess(private val context: Context) {

    private val prefs = context.getSharedPreferences("bittr.buy", Context.MODE_PRIVATE)

    fun authorized(): Boolean {
        val permitted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        return permitted && NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** Below API 33 there is nothing to ask for, so it counts as asked. */
    fun requested(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || prefs.getBoolean(KEY_REQUESTED, false)

    fun markRequested() = prefs.edit().putBoolean(KEY_REQUESTED, true).apply()

    private companion object {
        const val KEY_REQUESTED = "notificationPermissionRequested"
    }
}

/**
 * [BuySource] over the bittr API, the node key, the seed and the customer store.
 *
 * Each method is the network half of one iOS view-controller method, named in its KDoc on
 * [BuySource]; the decisions that differ from iOS are in `android/docs/port-specs/buy-decisions.md`.
 */
class AppBuySource(
    private val store: BittrCustomerStore,
    private val environment: BittrEnvironment,
    private val http: HttpClient,
    private val signer: BittrRequestSigner,
    private val keys: BittrRegistrationKeys?,
    private val tokens: DeviceTokenSource,
    private val notifications: NotificationAccess,
    private val clock: UnixClock = UnixClock.System,
) : BuySource {

    override val entities: StateFlow<List<IbanEntity>> = store.entities

    override suspend fun refreshDepositCodes(): DepositRefresh {
        if (store.depositCodes().isEmpty()) return DepositRefresh.Unchanged
        val signed = io { signer.signRequest(clock.nowSeconds()) { pk, ts -> DepositCodeFetch.message(pk, ts) } }
            ?: return DepositRefresh.NoNode
        // iOS delays a second "to keep the spinner visible for a moment".
        delay(1_000)
        val response = execute(DepositCodeFetch.request(environment, signed)) ?: return DepositRefresh.Failed
        val details = DepositCodeFetch.parse(response) ?: return DepositRefresh.Failed

        var detailsChanged = false
        var modeChanged = false
        store.entities.value.filter { it.yourUniqueCode == details.depositCode }.forEach { entity ->
            val usernameChanged = details.lightningAddressUsername != null &&
                details.lightningAddressUsername != entity.lightningAddressUsername
            if (details.ourIban != entity.ourIbanNumber || details.ourSwift != entity.ourSwift || usernameChanged) {
                detailsChanged = true
                store.update(entity.id) {
                    it.copy(
                        ourIbanNumber = details.ourIban,
                        ourSwift = details.ourSwift,
                        lightningAddressUsername = details.lightningAddressUsername ?: it.lightningAddressUsername,
                    )
                }
            }
            if (details.paymentMode != null && details.paymentMode != entity.paymentMode) {
                modeChanged = true
                store.update(entity.id) { it.copy(paymentMode = details.paymentMode!!) }
            }
        }
        return when {
            detailsChanged -> DepositRefresh.DetailsChanged
            modeChanged -> DepositRefresh.PaymentModeChanged
            else -> DepositRefresh.Unchanged
        }
    }

    override suspend fun setPaymentMode(entityId: String, mode: String): PaymentModeResult =
        setPaymentMode(entityId, mode, isRetry = false)

    private suspend fun setPaymentMode(entityId: String, mode: String, isRetry: Boolean): PaymentModeResult {
        val entity = entity(entityId) ?: return PaymentModeResult.Error("Unknown error")
        val signed = io {
            signer.signRequest(clock.nowSeconds()) { pk, ts -> PaymentModePatch.message(pk, entity.yourUniqueCode, mode, ts) }
        } ?: return PaymentModeResult.NotReady
        val response = try {
            http.execute(PaymentModePatch.request(environment, entity.yourUniqueCode, mode, signed))
        } catch (e: HttpTransportException) {
            return PaymentModeResult.Error(e.message ?: "The request could not be completed.")
        }
        return when (val outcome = PaymentModePatch.parse(response)) {
            is PaymentModePatch.Outcome.Confirmed -> {
                store.update(entityId) { it.copy(paymentMode = outcome.mode) }
                PaymentModeResult.Confirmed(outcome.mode)
            }
            is PaymentModePatch.Outcome.ServerError ->
                if (outcome.isExpiredTimestamp && !isRetry) {
                    setPaymentMode(entityId, mode, isRetry = true)
                } else {
                    PaymentModeResult.Error(outcome.message)
                }
            null -> PaymentModeResult.Error("Unknown error")
        }
    }

    override fun notificationsAuthorized(): Boolean = notifications.authorized()

    override fun notificationPermissionRequested(): Boolean = notifications.requested()

    override fun markNotificationPermissionRequested() = notifications.markRequested()

    override fun saveIbanDetails(currentId: String?, email: String, iban: String, initiativeConfirmedAt: String?): String {
        val existing = currentId?.let(::entity)
        if (existing != null) {
            store.update(existing.id) {
                it.copy(
                    yourEmail = email,
                    yourIbanNumber = iban,
                    initiativeConfirmedAt = initiativeConfirmedAt ?: it.initiativeConfirmedAt,
                )
            }
            return existing.id
        }
        val created = IbanEntity(
            id = UUID.randomUUID().toString().uppercase(),
            order = store.entities.value.size,
            yourEmail = email,
            yourIbanNumber = iban,
            initiativeConfirmedAt = initiativeConfirmedAt,
        )
        store.upsert(created)
        return created.id
    }

    override suspend fun verifyEmail(email: String, iban: String): VerifyEmailResult {
        val response = execute(EmailVerification.request(environment, email, iban)) ?: return VerifyEmailResult.Unreachable
        return when (val outcome = EmailVerificationAnswer.parse(response)) {
            is EmailVerification.Outcome.Rejected -> VerifyEmailResult.Rejected(outcome.message.orEmpty())
            EmailVerification.Outcome.Accepted -> VerifyEmailResult.Accepted
            null -> VerifyEmailResult.Unreachable
        }
    }

    override suspend fun checkCode(entityId: String, code: String): CheckCodeResult {
        val entity = entity(entityId) ?: return CheckCodeResult.Error(null)
        val pubkey = io { signer.pubkey() }
        val response = execute(EmailCheck2fa.request(environment, entity.yourEmail, code, pubkey))
            ?: return CheckCodeResult.Unreachable
        return when (val outcome = EmailCheck2fa.parse(response)) {
            is EmailCheck2fa.Outcome.Verified -> {
                store.update(entityId) { it.copy(emailToken = outcome.emailToken) }
                CheckCodeResult.Verified(outcome.restoreDepositCode, outcome.restoreMessage)
            }
            EmailCheck2fa.Outcome.InvalidCode -> CheckCodeResult.InvalidCode
            is EmailCheck2fa.Outcome.Error -> CheckCodeResult.Error(outcome.message)
            null -> CheckCodeResult.Unreachable
        }
    }

    override suspend fun register(
        entityId: String,
        notificationsDenied: Boolean,
        restoreDepositCode: String?,
        restoreMessage: String?,
    ): RegisterResult {
        val entity = entity(entityId) ?: return RegisterResult.Unrecognised
        val keys = keys ?: return RegisterResult.WalletNotReady
        val message = restoreMessage ?: registrationMessage(entity)

        val bitcoinSignature = io { runCatching { keys.signBitcoinMessage(message) }.getOrNull() }
            ?: return RegisterResult.SigningFailed
        val lightningSignature = io { signer.sign(message) } ?: return RegisterResult.WalletNotReady
        val address = keys.bittrAddress() ?: return RegisterResult.WalletNotReady
        val pubkey = io { signer.pubkey() } ?: return RegisterResult.WalletNotReady
        val xpub = io { keys.xpub() } ?: return RegisterResult.WalletNotReady
        // BIT-46 decision 1: a bounded wait for the FCM token, and no token is a normal
        // registration — DeviceTokenLifecycle patches it in later.
        val token = withTimeoutOrNull(TOKEN_WAIT_MS) { runCatching { tokens.current() }.getOrNull() }

        val request = CustomerRegistration.request(
            environment = environment,
            fields = CustomerRegistration.Fields(
                email = entity.yourEmail,
                emailToken = entity.emailToken,
                bitcoinAddress = address,
                bitcoinMessage = message,
                bitcoinSignature = bitcoinSignature,
                iban = entity.yourIbanNumber,
                lightningPubkey = pubkey,
                lightningSignature = lightningSignature,
                xpubKey = xpub,
                paymentMode = if (notificationsDenied) PaymentMode.ONCHAIN else null,
                exclusiveInitiativeConfirmedAt = entity.initiativeConfirmedAt?.takeIf { it.isNotEmpty() },
                depositCode = restoreDepositCode,
            ),
            androidDeviceToken = token,
        )
        val response = execute(request) ?: return RegisterResult.Unreachable
        return when (val outcome = CustomerSignup.parse(response)) {
            is CustomerSignup.Outcome.Created -> {
                store.update(entityId) {
                    it.copy(
                        ourIbanNumber = outcome.ourIban,
                        ourSwift = outcome.ourSwift,
                        yourUniqueCode = outcome.depositCode,
                        lightningAddressUsername = outcome.lightningAddressUsername,
                        paymentMode = if (notificationsDenied) PaymentMode.ONCHAIN else it.paymentMode,
                    )
                }
                RegisterResult.Created
            }
            CustomerSignup.Outcome.InvalidIban -> RegisterResult.InvalidIban
            is CustomerSignup.Outcome.Message -> RegisterResult.Message(outcome.message)
            CustomerSignup.Outcome.Unrecognised -> RegisterResult.Unrecognised
            null -> RegisterResult.Unreachable
        }
    }

    override fun nowIsoUtc(): String = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()

    private fun entity(id: String): IbanEntity? = store.entities.value.firstOrNull { it.id == id }

    private suspend fun execute(request: HttpRequest): HttpResponse? = try {
        http.execute(request)
    } catch (e: HttpTransportException) {
        null
    }

    private suspend fun <T> io(block: suspend () -> T): T = withContext(Dispatchers.IO) { block() }

    companion object {
        private const val TOKEN_WAIT_MS = 15_000L

        /** `gatherParameters`' message, verbatim, with the first 32 characters of the email token. */
        fun registrationMessage(entity: IbanEntity): String =
            "I confirm I'm the sole owner of the bitcoin address I provided and I will be sending my own funds to " +
                "bittr. Order: ${entity.emailToken.take(32)}. IBAN: ${entity.yourIbanNumber}"
    }
}
