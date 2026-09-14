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
 * `swap_notification` — iOS's `SwapViewController.handleSwapNotification` /
 * `handleSwapNotificationFromBackground`. The swaps port binds one; until then swap
 * pushes are logged and dropped.
 */
fun interface SwapPushHandler {
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

    /** iOS `isConnectedToPeer()`: connected to the bittr node right now. */
    fun isConnectedToBittr(): Boolean

    /** iOS `didEstablishPeerConnection()`. */
    suspend fun reconnectToBittr()

    /** A BOLT11 invoice for [amountMsat] with [description], or null when one cannot be made. */
    fun invoice(amountMsat: Long, description: String, expirySecs: Int): String?
}
