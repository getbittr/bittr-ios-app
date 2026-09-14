package com.bittr.android.feature.buy

import com.bittr.android.core.network.IbanEntity
import kotlinx.coroutines.flow.StateFlow

/**
 * Everything Buy and the bittr signup need from outside the screen: the customer records, the
 * five bittr endpoints behind signed requests, and the notification permission state.
 *
 * Implemented in `:app` (`AppBuySource`), which is where the network client, the node key and
 * the seed are composed; [BuyController] holds the screen logic and is tested against a fake.
 */
interface BuySource {

    /** iOS's `bittrWallet.ibanEntities`. Every mutation below is reflected here. */
    val entities: StateFlow<List<IbanEntity>>

    /** `getDepositCodeData` — refresh the partner details behind each deposit code. */
    suspend fun refreshDepositCodes(): DepositRefresh

    /** `proceedWithApiCall` — signed `PATCH /customer/payment-mode`, with one expired-timestamp retry. */
    suspend fun setPaymentMode(entityId: String, mode: String): PaymentModeResult

    /** Whether the app may post notifications right now — iOS's `.authorized`. */
    fun notificationsAuthorized(): Boolean

    /**
     * Whether the runtime permission has been asked for before — iOS's `.notDetermined`, negated.
     * Always true where there is no runtime permission (below API 33).
     */
    fun notificationPermissionRequested(): Boolean

    fun markNotificationPermissionRequested()

    /**
     * `gatherIbanDetails` — update the entity [currentId] or create one, and return its id.
     */
    fun saveIbanDetails(currentId: String?, email: String, iban: String, initiativeConfirmedAt: String?): String

    /** `POST /verify/email`. */
    suspend fun verifyEmail(email: String, iban: String): VerifyEmailResult

    /** `POST /verify/email/check2fa`, storing the email token on success. */
    suspend fun checkCode(entityId: String, code: String): CheckCodeResult

    /**
     * `gatherParameters` + `createBittrAccount` — sign and `POST /customer`, storing the partner
     * details on success.
     */
    suspend fun register(
        entityId: String,
        notificationsDenied: Boolean,
        restoreDepositCode: String?,
        restoreMessage: String?,
    ): RegisterResult

    /** ISO-8601 UTC, second precision — `Transfer1ViewController.confirmationTimestamp()`. */
    fun nowIsoUtc(): String

    /** Milliseconds, for the resend cooldown. */
    fun nowMillis(): Long = System.currentTimeMillis()
}

enum class DepositRefresh { NoNode, Unchanged, DetailsChanged, PaymentModeChanged, Failed }

sealed interface PaymentModeResult {
    data class Confirmed(val mode: String) : PaymentModeResult
    data object NotReady : PaymentModeResult
    data class Error(val message: String) : PaymentModeResult
}

sealed interface VerifyEmailResult {
    data object Accepted : VerifyEmailResult
    data class Rejected(val message: String) : VerifyEmailResult
    data object Unreachable : VerifyEmailResult
}

sealed interface CheckCodeResult {
    data class Verified(val restoreDepositCode: String?, val restoreMessage: String?) : CheckCodeResult
    data object InvalidCode : CheckCodeResult
    data class Error(val message: String?) : CheckCodeResult
    data object Unreachable : CheckCodeResult
}

sealed interface RegisterResult {
    data object Created : RegisterResult
    data object InvalidIban : RegisterResult
    data class Message(val message: String) : RegisterResult
    /** No node or no on-chain wallet yet — `syncingwallet2`. */
    data object WalletNotReady : RegisterResult
    /** The registration message could not be signed — `verificationfail`. */
    data object SigningFailed : RegisterResult
    data object Unreachable : RegisterResult
    /** A JSON body with neither details nor a message. iOS shows nothing. */
    data object Unrecognised : RegisterResult
}
