package com.bittr.android.navigation

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import com.bittr.android.feature.swap.SwapLaunch
import com.bittr.android.feature.swap.SwapRoute
import com.bittr.android.swap.SwapLaunchViewModel
import com.bittr.android.swap.SwapViewModel
import java.io.File

/**
 * The swap screen's route — `MoveToSwap`, `SendToSwap` and `CoreToSwap` in one destination, told
 * apart by which optional argument is set.
 */
object SwapRoutes {
    private const val INVOICE = "invoice"
    private const val AMOUNT = "amount"
    private const val ADDRESS = "address"
    private const val BOLTZ_ID = "boltzId"
    private const val PAYOUT_SWAP_SATS = "payoutSwapSats"

    const val SWAP = "swap?$INVOICE={$INVOICE}&$AMOUNT={$AMOUNT}&$ADDRESS={$ADDRESS}&$BOLTZ_ID={$BOLTZ_ID}" +
        "&$PAYOUT_SWAP_SATS={$PAYOUT_SWAP_SATS}"

    /** The Move screen's swap button. */
    fun swap(): String = "swap"

    /** Swap & Pay for an invoice Lightning cannot cover. */
    fun payInvoice(invoice: String, amountSats: Long?): String =
        "swap?$INVOICE=${Uri.encode(invoice)}" + (amountSats?.let { "&$AMOUNT=$it" } ?: "")

    /** Swap & Pay for an on-chain payment the on-chain balance cannot cover. */
    fun payAddress(address: String, amountSats: Long): String = "swap?$ADDRESS=${Uri.encode(address)}&$AMOUNT=$amountSats"

    /** An existing swap's status card. */
    fun status(boltzId: String): String = "swap?$BOLTZ_ID=${Uri.encode(boltzId)}"

    /** "Swap & Instant Receive" on a channel-full payout: a lightning-to-onchain swap of [sats]. */
    fun payoutSwap(sats: Long): String = "swap?$PAYOUT_SWAP_SATS=$sats"

    internal val arguments = listOf(INVOICE, AMOUNT, ADDRESS, BOLTZ_ID, PAYOUT_SWAP_SATS).map { name ->
        navArgument(name) {
            type = NavType.StringType
            nullable = true
            defaultValue = null
        }
    }

    internal fun launch(arguments: android.os.Bundle?): SwapLaunch {
        val amount = arguments?.getString(AMOUNT)?.toLongOrNull()
        return SwapLaunch(
            invoice = arguments?.getString(INVOICE),
            invoiceAmountSats = amount,
            payoutAddress = arguments?.getString(ADDRESS),
            payoutAmountSats = amount,
            boltzId = arguments?.getString(BOLTZ_ID),
            payoutSwapSats = arguments?.getString(PAYOUT_SWAP_SATS)?.toLongOrNull(),
        )
    }
}

internal fun NavGraphBuilder.swapArea(navController: NavHostController) {
    composable(route = SwapRoutes.SWAP, arguments = SwapRoutes.arguments) { entry ->
        val swap: SwapViewModel = hiltViewModel()
        val launches = hiltViewModel<SwapLaunchViewModel>().requests
        val context = LocalContext.current
        // A swap push is ignored while a swap screen is showing (iOS `swapVC != nil`).
        DisposableEffect(launches) {
            launches.setSwapScreenOpen(true)
            onDispose { launches.setSwapScreenOpen(false) }
        }
        SwapRoute(
            coordinator = swap.coordinator,
            fiat = swap.fiat,
            launch = SwapRoutes.launch(entry.arguments),
            onDown = { navController.popBackStack() },
            onOpenTransaction = { id -> navController.openTransaction(id) },
            onRequestNotifications = { openNotificationSettings(context) },
            onShareFile = { file -> shareSwapFile(context, file) },
        )
    }
}

/** `askForPushNotifications()`: the app's notification settings, where the permission is granted. */
private fun openNotificationSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }
}

/**
 * "Download details": the swap file shared as JSON text. iOS shares the file itself; sharing its
 * contents needs no FileProvider and carries the same rescue information.
 */
private fun shareSwapFile(context: Context, file: File) {
    val send = Intent(Intent.ACTION_SEND)
        .setType("application/json")
        .putExtra(Intent.EXTRA_SUBJECT, "Swap ${file.nameWithoutExtension}.json")
        .putExtra(Intent.EXTRA_TEXT, file.readText())
    runCatching { context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}
