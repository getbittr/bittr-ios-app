package com.bittr.android.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.preferences.Currency
import com.bittr.android.core.preferences.DarkModeSetting
import com.bittr.android.core.wallet.WalletOverviewSource
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * What Device details shows, and what its rows do.
 *
 * @property channelCount the Lightning-connections row's value — `syncChannels()`: the
 *   channel count once the wallet has a reading, `"Syncing"` before.
 * @property nodeIsUp a node is running and the first reading has been published.
 * @property checkingRow the row whose check is in flight (iOS animates that cell).
 */
data class DeviceUiState(
    val darkMode: DarkModeSetting = DarkModeSetting.Device,
    val currency: Currency = Currency.EUR,
    val channelCount: String = SettingsStrings.SYNCING,
    val nodeIsUp: Boolean = false,
    val checkingRow: DeviceRow? = null,
)

/** Which picker, if any, is open. Both are `BittrChoiceDialog`s. */
enum class DevicePicker { Language, Currency }

/** The rows that make a network or node call when tapped. */
enum class DeviceRow { BittrPeer, PendingPayout }

/** What an alert button does. */
sealed interface DeviceAlertAction {
    data object Dismiss : DeviceAlertAction

    /** Copy [text] to the clipboard (the screen does this), then close. */
    data class Copy(val text: String) : DeviceAlertAction

    data object ReconnectToBittr : DeviceAlertAction

    data class HandlePendingPayout(val payout: PendingPayoutCheck.Available) : DeviceAlertAction
}

data class DeviceAlertButton(val label: String, val action: DeviceAlertAction = DeviceAlertAction.Dismiss)

/** An alert. Buttons in iOS's `buttons:` order, which is the `alert.button.N` order. */
data class DeviceAlert(
    val title: String,
    val message: String,
    val buttons: List<DeviceAlertButton> = listOf(DeviceAlertButton(SettingsStrings.OKAY)),
    /** The message is a key or token to check character by character, not a sentence. */
    val messageIsValue: Boolean = false,
)

@HiltViewModel
class DeviceViewModel @Inject constructor(
    private val preferences: AppPreferences,
    overview: WalletOverviewSource,
    private val node: DeviceNode,
) : ViewModel() {

    private val picker = MutableStateFlow<DevicePicker?>(null)
    private val alert = MutableStateFlow<DeviceAlert?>(null)

    private val _uiState = MutableStateFlow(
        DeviceUiState(
            darkMode = preferences.darkMode.value,
            currency = preferences.currency.value,
        ),
    )
    val uiState: StateFlow<DeviceUiState> = _uiState.asStateFlow()

    val openPicker: StateFlow<DevicePicker?> = picker.asStateFlow()
    val currentAlert: StateFlow<DeviceAlert?> = alert.asStateFlow()

    init {
        viewModelScope.launch {
            overview.overview.collect { wallet ->
                _uiState.update {
                    it.copy(
                        channelCount = if (wallet.hasSynced) wallet.channelCount.toString() else SettingsStrings.SYNCING,
                        nodeIsUp = wallet.hasNode && wallet.hasSynced,
                    )
                }
            }
        }
    }

    fun setDarkMode(setting: DarkModeSetting) {
        preferences.setDarkMode(setting)
        _uiState.value = _uiState.value.copy(darkMode = setting)
    }

    fun setCurrency(currency: Currency) {
        preferences.setCurrency(currency)
        _uiState.value = _uiState.value.copy(currency = currency)
        picker.value = null
    }

    fun openPicker(which: DevicePicker) {
        picker.value = which
    }

    fun dismissPicker() {
        picker.value = null
    }

    /**
     * The language picker's only option.
     *
     * iOS offers exactly one — `changeLanguage()` builds the sheet from Cancel and
     * `"English (US)"` — because the fourteen-language dictionary in `Language.swift`
     * is not yet exposed in the UI. Selecting it is a no-op there (it writes the
     * language that is already set) and a no-op here.
     */
    fun selectEnglish() {
        picker.value = null
    }

    /** `getPublicKey()`: the key with [Copy, Close], or `syncingwallet2` while there is no node. */
    /**
     * `showToken`: the FCM token, with Copy and Close. The row used to ask for the
     * notification permission and stop there, so on a device that had already answered it
     * did nothing at all (Ruben, 2026-09-22). The permission request stays with the screen,
     * which has the launcher; this runs after it.
     */
    fun deviceTokenTapped() {
        viewModelScope.launch {
            val token = node.deviceToken()
            alert.value = if (token == null) {
                DeviceAlert(SettingsStrings.DEVICE_TOKEN, SettingsStrings.DEVICE_TOKEN_UNAVAILABLE)
            } else {
                DeviceAlert(
                    title = SettingsStrings.DEVICE_TOKEN,
                    message = token,
                    messageIsValue = true,
                    buttons = listOf(
                        DeviceAlertButton(SettingsStrings.COPY, DeviceAlertAction.Copy(token)),
                        DeviceAlertButton(SettingsStrings.CLOSE),
                    ),
                )
            }
        }
    }

    fun publicKeyTapped() {
        val key = node.publicKey()
        alert.value = if (key == null) {
            DeviceAlert(SettingsStrings.PUBLIC_KEY, SettingsStrings.SYNCING_WALLET_2)
        } else {
            DeviceAlert(
                title = SettingsStrings.PUBLIC_KEY,
                message = key,
                messageIsValue = true,
                buttons = listOf(
                    DeviceAlertButton(SettingsStrings.COPY, DeviceAlertAction.Copy(key)),
                    DeviceAlertButton(SettingsStrings.CLOSE),
                ),
            )
        }
    }

    /** `checkPeerConnection()`: connected, or not connected with [Close, Connect]. */
    fun bittrPeerTapped() {
        if (_uiState.value.checkingRow != null) return
        viewModelScope.launch {
            checking(DeviceRow.BittrPeer)
            val connected = runCatching { node.isConnectedToBittr() }.getOrDefault(false)
            checking(null)
            alert.value = if (connected) {
                DeviceAlert(SettingsStrings.BITTR_PEER, SettingsStrings.BITTR_PEER_2)
            } else {
                DeviceAlert(
                    title = SettingsStrings.BITTR_PEER,
                    message = SettingsStrings.BITTR_PEER_3,
                    buttons = listOf(
                        DeviceAlertButton(SettingsStrings.CLOSE),
                        DeviceAlertButton(SettingsStrings.CONNECT, DeviceAlertAction.ReconnectToBittr),
                    ),
                )
            }
        }
    }

    /**
     * `checkPendingPayout()`. iOS force-unwraps `nodeId()` here and crashes without a node;
     * Android shows the `syncingwallet2` alert instead.
     */
    fun pendingPayoutTapped() {
        if (_uiState.value.checkingRow != null) return
        viewModelScope.launch {
            checking(DeviceRow.PendingPayout)
            val check = runCatching { node.pendingPayout() }.getOrDefault(PendingPayoutCheck.NoneAvailable)
            checking(null)
            alert.value = when (check) {
                PendingPayoutCheck.NoNode -> DeviceAlert(SettingsStrings.PENDING_PAYOUT, SettingsStrings.SYNCING_WALLET_2)
                PendingPayoutCheck.NoneAvailable -> DeviceAlert(SettingsStrings.PENDING_PAYOUT, SettingsStrings.PENDING_PAYOUT_2)
                is PendingPayoutCheck.Available -> DeviceAlert(
                    title = SettingsStrings.PENDING_PAYOUT,
                    message = SettingsStrings.PENDING_PAYOUT_3,
                    buttons = listOf(
                        DeviceAlertButton(SettingsStrings.CANCEL),
                        DeviceAlertButton(SettingsStrings.CONFIRM, DeviceAlertAction.HandlePendingPayout(check)),
                    ),
                )
            }
        }
    }

    /**
     * The guard for a row that needs a synced wallet — now only Remove wallet in a build
     * or test that does not supply the removal coordinator.
     */
    fun nodeBackedRowTapped() {
        alert.value = DeviceAlert(
            title = SettingsStrings.SYNCING_WALLET,
            message = SettingsStrings.SYNCING_WALLET_2,
        )
    }

    /** A button on the current alert. [DeviceAlertAction.Copy] is copied by the screen before this. */
    fun onAlertButton(button: DeviceAlertButton) {
        alert.value = null
        when (val action = button.action) {
            DeviceAlertAction.Dismiss, is DeviceAlertAction.Copy -> Unit
            DeviceAlertAction.ReconnectToBittr -> viewModelScope.launch {
                checking(DeviceRow.BittrPeer)
                runCatching { node.reconnectToBittr() }
                checking(null)
                bittrPeerTapped()
            }
            // The payout's own alerts are drawn over every screen, so Device details can stay.
            is DeviceAlertAction.HandlePendingPayout -> node.handlePendingPayout(action.payout)
        }
    }

    fun dismissAlert() {
        alert.value = null
    }

    private fun checking(row: DeviceRow?) {
        _uiState.update { it.copy(checkingRow = row) }
    }
}
