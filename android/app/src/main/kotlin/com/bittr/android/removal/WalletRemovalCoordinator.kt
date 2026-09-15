package com.bittr.android.removal

import com.bittr.android.core.wallet.PinLockout
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.ldk.lightning.ChannelView
import com.bittr.android.core.wallet.ldk.lightning.WalletNodeReading
import com.bittr.android.core.wallet.ldk.lightning.WipeSafety
import com.bittr.android.core.wallet.ldk.lightning.activeChannel
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Where a removal was asked for. iOS tells these apart with two `CoreViewController` flags. */
enum class RemovalOrigin {
    /** Device details → Remove wallet (`device.row.restore`). Signed in, node running. */
    Settings,

    /** The forgot-PIN phrase screen's "Remove wallet from device" (`resettingPin`). Locked, no node yet. */
    ForgotPin,
}

/** What a button on a removal alert does next. Null on a [RemovalButton] means it only closes the alert. */
enum class RemovalStep {
    StartInBackground,
    ConfirmCloseChannel,
    CloseChannel,
    ForceClose,
    ConfirmRemove,
    Reset,
    ResumeRemoval,
    CancelResume,
}

data class RemovalButton(val label: String, val step: RemovalStep? = null)

data class RemovalAlert(val title: String, val message: String, val buttons: List<RemovalButton>)

/** iOS's `fullViewCover` + `genericSpinner` ([busy]) and whatever alert the removal is showing. */
data class RemovalUiState(val busy: Boolean = false, val alert: RemovalAlert? = null)

/**
 * The node questions a removal asks — narrow on purpose, so the decision logic below can be
 * tested without a node and the production binding is a page of forwarding.
 *
 * The blocking calls are FFI into ldk-node; the coordinator runs them on its IO dispatcher.
 */
interface RemovalNode {

    /** False in a build with no `LdkEnvironment`: there is no channel state that could be lost. */
    val hasNode: Boolean

    /** iOS's `walletHasSynced` — a node is up and the first reading has been published. */
    fun isSynced(): Boolean

    /** `startWalletInBackground` — start the node without unlocking, then sync. True when a node is up. */
    suspend fun startAndSync(): Boolean

    /** One reading of channels and balances, or null when there is no node to ask. */
    fun read(): WalletNodeReading?

    fun isPeerConnected(): Boolean

    /** `connectToLightningPeer()`. True when the connect call succeeded. */
    fun connectPeer(): Boolean

    fun closeChannel(channel: ChannelView)

    fun forceCloseChannel(channel: ChannelView)

    /** `didCloseChannel()` — sync and republish the overview so the closed balance shows. Best effort. */
    fun didCloseChannel()
}

/** `CacheManager.walletRemovalInProgress` — a manual removal that was committed but not finished. */
interface RemovalFlagStore {
    var inProgress: Boolean
}

/**
 * Removing the wallet from the device — the port of `Core/ResetApp.swift`.
 *
 * ### The hard rule
 *
 * The wallet is never erased while a Lightning channel is open or while funds from a closed one
 * are still settling on-chain ([WipeSafety.channelsFullyClosedAndSwept]). The erase deletes the
 * channel monitors that sweep those funds, and a recovery phrase cannot rebuild them — for a
 * force-closed channel that is a permanent loss. Every uncertain case (no node, a failed read)
 * refuses. Only a cooperative close is ever started without the user asking; a force close is
 * the user's choice.
 *
 * ### The three ways in
 *
 * - [removeWalletTapped] with [RemovalOrigin.Settings]: signed in. Confirms twice before erasing,
 *   or walks the user through closing their connection first.
 * - [removeWalletTapped] with [RemovalOrigin.ForgotPin]: locked out of the PIN and without the
 *   phrase. Confirms once, starts the node in the background, then decides.
 * - [lockedOut]: ten wrong PINs. Nothing is asked; an open channel is closed cooperatively and
 *   the user can only tap "Try again" until the funds have settled.
 *
 * A singleton, not a screen's `ViewModel`, because a removal outlives every screen it starts from:
 * erasing the wallet swaps the navigation graph to signup underneath it. [WalletRemovalHost]
 * draws its state over the whole app.
 */
class WalletRemovalCoordinator(
    private val scope: CoroutineScope,
    private val wallet: WalletService,
    private val node: RemovalNode,
    private val flag: RemovalFlagStore,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {

    private val _uiState = MutableStateFlow(RemovalUiState())
    val uiState: StateFlow<RemovalUiState> = _uiState.asStateFlow()

    private val _handOff = MutableStateFlow(false)

    /** True once the wallet is gone and the app has to leave for signup. See [consumeHandOff]. */
    val handOff: StateFlow<Boolean> = _handOff.asStateFlow()

    /** iOS's `resettingPin`. */
    private var resettingPin = false

    /** iOS's `removingWalletForIncorrectPin`. */
    private var lockout = false

    /**
     * A 10-wrong-PIN removal is under way. iOS shows no "closed lightning connection" card then
     * (the user is locked out, and the close is the removal's own doing).
     */
    val isLockoutRemoval: Boolean get() = lockout

    /** iOS's `isRemovalInFlight` — one automatic channel close at a time. */
    private var closeInFlight = false

    private var launchChecked = false

    /**
     * `CoreViewController.checkWalletRemoval` — once per process, at launch.
     *
     * A lockout that was already earned resumes without a PIN (so force-quitting on the tenth
     * wrong entry buys nothing), and a manual removal left half-done offers to finish.
     */
    fun checkOnLaunch() {
        if (launchChecked) return
        launchChecked = true
        scope.launch {
            if (wallet.state.value == WalletState.Uninitialized) {
                flag.inProgress = false
                return@launch
            }
            if (PinLockout.isLockedOut(wallet.failedUnlockAttempts())) {
                lockedOut()
            } else if (flag.inProgress) {
                show(
                    RemovalStrings.REMOVE_WALLET,
                    RemovalStrings.REMOVAL_IN_PROGRESS,
                    RemovalButton(RemovalStrings.CANCEL, RemovalStep.CancelResume),
                    RemovalButton(RemovalStrings.REMOVE_WALLET, RemovalStep.ResumeRemoval),
                )
            }
        }
    }

    /** `PinViewController.removeWallet` — the tenth wrong PIN. */
    fun lockedOut() {
        if (lockout) return
        lockout = true
        // iOS shows `pinlock` first and works behind it; the flows wait for this Okay.
        show(RemovalStrings.RESTORE_WALLET, RemovalStrings.PIN_LOCK, RemovalButton(RemovalStrings.OKAY))
        startInBackground()
    }

    /** `restoreWalletTapped()` from Device details or the forgot-PIN screen. */
    fun removeWalletTapped(origin: RemovalOrigin) {
        when (origin) {
            RemovalOrigin.ForgotPin -> {
                resettingPin = true
                // Always asked here, node or not: this is the only confirmation this path gets.
                show(
                    RemovalStrings.REMOVE_WALLET,
                    RemovalStrings.REMOVE_WALLET_1,
                    RemovalButton(RemovalStrings.CANCEL),
                    RemovalButton(RemovalStrings.REMOVE_WALLET, RemovalStep.StartInBackground),
                )
            }

            RemovalOrigin.Settings -> {
                resettingPin = false
                if (!node.isSynced()) {
                    show(RemovalStrings.SYNCING_WALLET, RemovalStrings.SYNCING_WALLET_2, RemovalButton(RemovalStrings.OKAY))
                } else {
                    scope.launch { evaluate() }
                }
            }
        }
    }

    /** A button on the current alert. */
    fun press(button: RemovalButton) {
        _uiState.value = _uiState.value.copy(alert = null)
        when (button.step) {
            null -> Unit
            RemovalStep.StartInBackground -> startInBackground()
            RemovalStep.ConfirmCloseChannel -> show(
                RemovalStrings.CLOSE_CHANNEL,
                RemovalStrings.CLOSE_CHANNEL_2,
                RemovalButton(RemovalStrings.CANCEL),
                RemovalButton(RemovalStrings.CLOSE_CHANNEL, RemovalStep.CloseChannel),
            )
            RemovalStep.CloseChannel -> scope.launch { closeChannelConfirmed() }
            RemovalStep.ForceClose -> scope.launch { forceCloseChannel() }
            RemovalStep.ConfirmRemove -> show(
                RemovalStrings.REMOVE_WALLET,
                RemovalStrings.RESTORE_WALLET_3,
                RemovalButton(RemovalStrings.CANCEL),
                RemovalButton(RemovalStrings.REMOVE, RemovalStep.Reset),
            )
            RemovalStep.Reset -> scope.launch { performWalletReset() }
            RemovalStep.ResumeRemoval -> {
                resettingPin = true
                startInBackground()
            }
            RemovalStep.CancelResume -> flag.inProgress = false
        }
    }

    /** The app has left for signup. */
    fun consumeHandOff() {
        _handOff.value = false
    }

    private fun startInBackground() {
        setBusy(true)
        scope.launch {
            val running = !node.hasNode || withContext(io) { node.startAndSync() }
            if (!running) {
                cannotVerify()
                return@launch
            }
            evaluate()
        }
    }

    /** The body of `restoreWalletTapped()` once the wallet has synced. */
    private suspend fun evaluate() {
        val reading = if (node.hasNode) withContext(io) { node.read() } else null
        if (node.hasNode && reading == null) {
            cannotVerify()
            return
        }
        val safe = !node.hasNode ||
            WipeSafety.channelsFullyClosedAndSwept(reading?.channels, reading?.balances)

        if (safe) {
            closeInFlight = false
            if (resettingPin || lockout) {
                performWalletReset()
            } else {
                setBusy(false)
                show(
                    RemovalStrings.REMOVE_WALLET,
                    RemovalStrings.RESTORE_WALLET_2,
                    RemovalButton(RemovalStrings.CANCEL),
                    RemovalButton(RemovalStrings.REMOVE, RemovalStep.ConfirmRemove),
                )
            }
            return
        }

        if (reading?.channels?.activeChannel() != null) {
            if (lockout) {
                if (closeInFlight) return
                closeInFlight = true
                closeChannelConfirmed()
            } else {
                setBusy(false)
                show(
                    RemovalStrings.REMOVE_WALLET,
                    RemovalStrings.RESTORE_WALLET_4,
                    RemovalButton(RemovalStrings.CANCEL),
                    RemovalButton(RemovalStrings.CLOSE_CHANNEL, RemovalStep.ConfirmCloseChannel),
                )
            }
        } else {
            // Closed, but the funds have not landed on-chain yet.
            closeInFlight = false
            setBusy(false)
            if (lockout) {
                show(
                    RemovalStrings.REMOVE_WALLET,
                    RemovalStrings.STILL_CLOSING,
                    RemovalButton(RemovalStrings.TRY_AGAIN, RemovalStep.StartInBackground),
                )
            } else {
                flag.inProgress = true
                show(RemovalStrings.REMOVE_WALLET, RemovalStrings.STILL_CLOSING, RemovalButton(RemovalStrings.OKAY))
            }
        }
    }

    private suspend fun closeChannelConfirmed() {
        setBusy(true)
        // The user confirmed the close, so the manual removal is committed.
        if (!lockout) flag.inProgress = true

        val connected = withContext(io) { node.isPeerConnected() || (node.connectPeer() && node.isPeerConnected()) }
        if (!connected) {
            if (lockout) {
                closeFailed()
            } else {
                // iOS's `closeChannelConfirmed`: a bittr node that cannot be reached means
                // something is wrong on its side, so the manual removal force-closes straight
                // away rather than asking (decision 12).
                forceCloseChannel()
            }
            return
        }

        val channel = withContext(io) { node.read() }?.channels?.activeChannel()
        if (channel == null) {
            // Nothing left to close: re-check whether the funds have settled.
            evaluate()
            return
        }

        val closed = withContext(io) { runCatching { node.closeChannel(channel) } }
        if (closed.isFailure) {
            closeFailed()
            return
        }

        scope.launch(io) { runCatching { node.didCloseChannel() } }
        // Released here: a terminal alert is going up and only a fresh attempt moves on.
        closeInFlight = false
        setBusy(false)
        show(
            RemovalStrings.RESTORE_WALLET,
            RemovalStrings.STILL_CLOSING,
            if (lockout) {
                RemovalButton(RemovalStrings.TRY_AGAIN, RemovalStep.StartInBackground)
            } else {
                RemovalButton(RemovalStrings.OKAY)
            },
        )
    }

    /**
     * The cooperative close could not happen — no connection to the bittr node, or the close
     * call failed. Locked out, the user can only retry. Signed in, they are offered a force close
     * (iOS force-closes straight away when the peer will not connect; see the decisions log).
     */
    private fun closeFailed() {
        setBusy(false)
        if (lockout) {
            closeInFlight = false
            show(
                RemovalStrings.RESTORE_WALLET,
                RemovalStrings.CLOSE_RETRY_LATER,
                RemovalButton(RemovalStrings.TRY_AGAIN, RemovalStep.StartInBackground),
            )
        } else {
            show(
                RemovalStrings.CLOSE_CHANNEL_6,
                RemovalStrings.CLOSE_CHANNEL_7,
                RemovalButton(RemovalStrings.CANCEL),
                RemovalButton(RemovalStrings.FORCE_CLOSE, RemovalStep.ForceClose),
            )
        }
    }

    /** `forceCloseChannel()` — manual only, never on the lockout path. Never erases. */
    private suspend fun forceCloseChannel() {
        setBusy(true)
        flag.inProgress = true
        val channel = withContext(io) { node.read() }?.channels?.activeChannel()
        if (channel == null) {
            evaluate()
            return
        }
        val closed = withContext(io) { runCatching { node.forceCloseChannel(channel) } }
        setBusy(false)
        if (closed.isFailure) {
            show(RemovalStrings.CLOSE_CHANNEL, RemovalStrings.FORCE_CLOSE_3, RemovalButton(RemovalStrings.OKAY))
            return
        }
        scope.launch(io) { runCatching { node.didCloseChannel() } }
        show(RemovalStrings.FORCE_CLOSE, RemovalStrings.FORCE_CLOSE_4, RemovalButton(RemovalStrings.OKAY))
    }

    /**
     * `performWalletReset()`. [WalletService.removeWallet] takes the node down before erasing,
     * and on failure the removal state is put back so the user is not stranded outside both flows.
     */
    private suspend fun performWalletReset() {
        setBusy(true)
        val wasResettingPin = resettingPin
        val wasLockout = lockout
        resettingPin = false
        lockout = false
        try {
            withContext(io) { wallet.removeWallet() }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (failure: Exception) {
            resettingPin = wasResettingPin
            lockout = wasLockout
            setBusy(false)
            show(
                RemovalStrings.REMOVE_WALLET,
                RemovalStrings.REMOVAL_FAILED,
                // Locked out there is nothing else to do, so the retry is offered here.
                if (wasLockout) {
                    RemovalButton(RemovalStrings.TRY_AGAIN, RemovalStep.StartInBackground)
                } else {
                    RemovalButton(RemovalStrings.OKAY)
                },
            )
            return
        }
        flag.inProgress = false
        setBusy(false)
        _handOff.value = true
    }

    /** No node came up, or it could not be read: nothing is erased. */
    private fun cannotVerify() {
        closeInFlight = false
        setBusy(false)
        show(
            RemovalStrings.REMOVE_WALLET,
            RemovalStrings.REMOVAL_FAILED,
            if (lockout) {
                RemovalButton(RemovalStrings.TRY_AGAIN, RemovalStep.StartInBackground)
            } else {
                RemovalButton(RemovalStrings.OKAY)
            },
        )
    }

    private fun setBusy(busy: Boolean) {
        _uiState.value = _uiState.value.copy(busy = busy)
    }

    private fun show(title: String, message: String, vararg buttons: RemovalButton) {
        _uiState.value = _uiState.value.copy(alert = RemovalAlert(title, message, buttons.toList()))
    }
}
