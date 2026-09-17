package com.bittr.android.push

import com.bittr.android.core.push.PushEnvelope

/**
 * The bittr account's first non-empty deposit code — iOS's
 * `bittrWallet.ibanEntities.first(where: { !$0.yourUniqueCode.isEmpty })`.
 *
 * Null until the Buy/signup port supplies a store: bind one with `@Binds` in any
 * Hilt module and [PushHandlingModule]'s `@BindsOptionalOf` picks it up.
 */
fun interface DepositCodeSource {
    suspend fun firstDepositCode(): String?
}

/**
 * `swap_notification` — iOS's `handleSwapNotificationFromBackground`. [PushCoordinator] decides
 * when (sign-in, sync); this knows whether a swap screen is showing and opens the latest swap's
 * status. It never claims or refunds — iOS does that from the swap screens, not from a push.
 * Unbound, swap pushes are logged and dropped.
 */
interface SwapPushHandler {

    /** A swap screen or status card is already open, so the push is ignored. */
    fun swapScreenOpen(): Boolean

    /** `handleSwapNotificationImmediately`: open the latest swap's status, if the app is active. */
    suspend fun onSwapPush(push: PushEnvelope.Swap)
}

/**
 * `lightning_address_notification` — iOS's `handleLightningAddressNotification`: make the
 * invoice and post it to the pushed endpoint. [PushCoordinator] shows the alerts around it;
 * `LnurlPushHooksModule` binds it.
 *
 * @return true when the invoice was posted.
 */
fun interface LnurlPushHandler {
    suspend fun answer(push: PushEnvelope.LightningAddress): Boolean
}

/**
 * "Swap & Instant Receive" on the channel-full payout alert — iOS's
 * `swapAndPayForNotification` (`CoreToSwap`).
 *
 * @return false when no swap screen can be opened, so the caller can say so.
 */
fun interface PayoutSwapLauncher {
    fun startSwapForPayout(notificationId: String, suggestedSwapSats: Long): Boolean
}

/** What the payout handler needs from the Lightning node, beyond the request signer. */
interface PushNode {

    /**
     * Connected to the bittr node, connecting first when it isn't — up to three attempts, one
     * and two seconds apart ([com.bittr.android.core.wallet.ldk.lightning.BittrPeerConnection]).
     * False only once those have failed.
     */
    suspend fun ensureConnectedToBittr(): Boolean

    /** A BOLT11 invoice for [amountMsat] with [description], or null when one cannot be made. */
    fun invoice(amountMsat: Long, description: String, expirySecs: Int): String?
}
