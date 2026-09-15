package com.bittr.android.navigation

import androidx.navigation.NavHostController
import com.bittr.android.feature.home.TransactionViewModel

/**
 * Open a transaction after it completed — Send, a swap, a payment arriving, or a bittr payout or
 * purchase ([confetti], iOS's `showConfetti`).
 *
 * Two of those can name the same transaction at nearly the same moment (Send's own result and the
 * node's `paymentSuccessful`, or the swap screen and the swap coordinator), so a transaction that is
 * already the screen on top is not opened again. Receive is closed first, as iOS dismisses
 * `ReceiveViewController` before presenting the transaction.
 */
internal fun NavHostController.openTransaction(id: String, confetti: Boolean = false) {
    val current = currentBackStackEntry
    if (current?.destination?.route == Routes.TRANSACTION && current.arguments?.getString(TransactionViewModel.ID_ARG) == id) return
    val fromReceive = current?.destination?.route == Routes.RECEIVE
    navigate(Routes.transaction(id, confetti)) {
        if (fromReceive) popUpTo(Routes.RECEIVE) { inclusive = true }
    }
}
