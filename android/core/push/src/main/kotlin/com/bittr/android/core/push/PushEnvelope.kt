package com.bittr.android.core.push

/**
 * A decoded push payload — the Android equivalent of iOS's `BittrNotification`
 * (`ios/bittr/Notifications/NotificationManager.swift:297-388`).
 *
 * One type per thing the app does in response, rather than one type with every field
 * nullable: `htlc_notification` with `expired: true` and the same object with `expired`
 * absent drive different code paths on iOS, so they are different types here.
 *
 * Every field inside the payload types stays nullable. That is deliberate and it is the
 * BIT-30 sign-off's §2(c) commitment to the backend: the server can add fields to any of
 * the five objects, and can omit any field it has nothing to say about, without an Android
 * release. The only hard requirement is that the discriminator's value be a JSON *object*.
 */
sealed interface PushEnvelope {

    /**
     * `bittr_specific_data` — the lightning payout. The silent path that BIT-9 DoD item 7
     * is about, and the one that must work with `POST_NOTIFICATIONS` denied.
     *
     * [amountMsats] is already converted from the wire's BTC-denominated decimal string;
     * see [BitcoinAmount.btcStringToMsats] for what that conversion does with garbage.
     */
    data class LightningPayout(
        val notificationId: String?,
        val amountMsats: Long,
    ) : PushEnvelope

    /** `bittr_notification` — free-form information for the user. */
    data class Information(
        val headerText: String?,
        val bodyText: String?,
    ) : PushEnvelope

    /** `swap_notification` — a Boltz swap changed state. */
    data class Swap(
        val swapId: String?,
        val status: String?,
    ) : PushEnvelope

    /**
     * `htlc_notification` with `expired` false or absent.
     *
     * Carries nothing on purpose: iOS reads no fields on this branch
     * (`NotificationManager.swift:344-352`), so nothing else in the object is load-bearing
     * yet, and inventing fields Android reads and iOS ignores is how the two clients start
     * to diverge.
     */
    data object HtlcIncoming : PushEnvelope

    /** `htlc_notification` with `expired: true`. */
    data class HtlcExpired(
        val headerText: String?,
        val bodyText: String?,
        val timeSent: String?,
    ) : PushEnvelope

    /**
     * `lightning_address_notification` — an LNURL request.
     *
     * [amountMsats] is `Long`, not `Int`. The contract's §3.1 field table says `Int`, which
     * is 64-bit in Swift and 32-bit in Kotlin; taking it literally would overflow every
     * lightning-address payment above ~0.0215 BTC on Android while iOS handled it fine.
     * BIT-30 §2(a) is the sign-off that made `int64` binding.
     */
    data class LightningAddress(
        val amountMsats: Long?,
        val metadata: String?,
        val timeSent: String?,
        val username: String?,
        val endpoint: String?,
    ) : PushEnvelope

    /**
     * Nothing actionable. [reason] exists so the FCM service can log *why* and is not part
     * of any behaviour — the app does the same nothing for all three cases.
     */
    data class Unknown(val reason: Reason) : PushEnvelope {

        enum class Reason {
            /** No discriminator key in `data`. A push for a type this build predates. */
            NO_DISCRIMINATOR,

            /** The discriminator's value is not parseable JSON at all. */
            MALFORMED_JSON,

            /**
             * Parseable JSON, but an array or a scalar rather than an object.
             *
             * Worth keeping distinct from [MALFORMED_JSON] in the log: this is the shape a
             * dispatcher bug produces (double-encoding, or sending the APNS body to FCM),
             * whereas malformed JSON is a truncation or an encoding fault.
             */
            NOT_AN_OBJECT,
        }
    }
}
