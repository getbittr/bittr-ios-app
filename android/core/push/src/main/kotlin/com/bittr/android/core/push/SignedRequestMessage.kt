package com.bittr.android.core.push

/**
 * The strings this API signs — BIT-9 `api-contract` §2.3.
 *
 * Both signed mutations use one construction,
 * `<prefix>:<pubkey>:<deposit_code>:<value>:<timestamp>`:
 *
 * ```
 * device_token:<pubkey>:<deposit_code>:<device_token>:<timestamp>
 * payment_mode:<pubkey>:<deposit_code>:<mode>:<timestamp>
 * ```
 *
 * The second is what the shipping iOS client already sends
 * (`BuyViewController.swift:337-362`); the first was shaped to match it so that Android writes
 * **one** signer rather than two, which is the reason §2.3 copied the layout in the first
 * place.
 *
 * Both live here rather than in the networking layer because they are the exact bytes a
 * signature covers. A message built one way at the call site and verified another way on the
 * server fails as a `401`, which is indistinguishable from a wrong key and sends the
 * investigation to the wallet. Keeping the construction in one pure, tested place is what makes
 * that class of bug impossible rather than merely unlikely.
 *
 * Pure Kotlin and no signing: producing the signature needs the node key, which lives behind
 * the `:core:wallet` seam. This module builds the message; the caller signs it.
 */
object SignedRequestMessage {

    /**
     * The message covered by the `signature` field of `PATCH /customer/device-token`.
     *
     * @param deviceToken the raw FCM registration token, exactly as
     *   `FirebaseMessaging.getToken()` returned it. Not trimmed, not hashed, not truncated —
     *   §2.3's column-width note and `SwapManager.swift:77-80` both compare this value
     *   byte-for-byte against what the backend echoes back, so any normalisation here becomes
     *   a permanent false "stale token" warning there.
     * @param timestamp unix **seconds**, inside §2.3 rule 3's ±300s skew window.
     */
    fun deviceToken(
        pubkey: String,
        depositCode: String,
        deviceToken: String,
        timestamp: Long,
    ): String = "device_token:$pubkey:$depositCode:$deviceToken:$timestamp"

    /**
     * The message covered by the `signature` field of `PATCH /customer/payment-mode`.
     *
     * Present so the §4.3 downgrade — the endpoint the client calls when the customer chooses
     * to continue without notifications — goes through the same construction as the token
     * refresh instead of a second, separately-drifting one.
     *
     * @param mode `"instant"` or `"onchain"`, the value being written.
     */
    fun paymentMode(
        pubkey: String,
        depositCode: String,
        mode: String,
        timestamp: Long,
    ): String = "payment_mode:$pubkey:$depositCode:$mode:$timestamp"
}
