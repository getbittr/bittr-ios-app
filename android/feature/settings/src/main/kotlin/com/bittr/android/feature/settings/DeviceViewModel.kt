package com.bittr.android.feature.settings

import androidx.lifecycle.ViewModel
import com.bittr.android.core.preferences.AppPreferences
import com.bittr.android.core.preferences.Currency
import com.bittr.android.core.preferences.DarkModeSetting
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * What Device details shows, and what its rows do.
 *
 * @property channelCount the Lightning-connections row's value.
 *   `DeviceViewController.syncChannels()` writes `"Syncing"` into it when
 *   `BitcoinManager.shared.ldkNode` is nil and the channel count otherwise; there is
 *   no node on Android yet, so it is `"Syncing"` — iOS's own string for iOS's own
 *   state, not a placeholder.
 * @property nodeIsUp whether the rows that report node facts can report anything.
 *   See [DeviceViewModel.nodeIsUp] — this is the BIT-6 line for this screen, the
 *   counterpart of `walletHasSynced` on Home.
 */
data class DeviceUiState(
    val darkMode: DarkModeSetting = DarkModeSetting.Device,
    val currency: Currency = Currency.EUR,
    val channelCount: String = SettingsStrings.SYNCING,
    val nodeIsUp: Boolean = false,
)

/** Which picker, if any, is open. Both are `BittrChoiceDialog`s. */
enum class DevicePicker { Language, Currency }

/** A one-button alert. `alert.button.0`, as in `AlertManager`. */
data class DeviceAlert(val title: String, val message: String)

@HiltViewModel
class DeviceViewModel @Inject constructor(
    private val preferences: AppPreferences,
    walletService: WalletService,
) : ViewModel() {

    private val picker = MutableStateFlow<DevicePicker?>(null)
    private val alert = MutableStateFlow<DeviceAlert?>(null)

    private val _uiState = MutableStateFlow(
        DeviceUiState(
            darkMode = preferences.darkMode.value,
            currency = preferences.currency.value,
            nodeIsUp = nodeIsUp(walletService.state.value),
        ),
    )
    val uiState: StateFlow<DeviceUiState> = _uiState.asStateFlow()

    val openPicker: StateFlow<DevicePicker?> = picker.asStateFlow()
    val currentAlert: StateFlow<DeviceAlert?> = alert.asStateFlow()

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

    /**
     * Every row whose answer comes from the node: Public key, Bittr peer, Pending
     * payout, and Remove wallet.
     *
     * They share one branch rather than four because iOS's four branches collapse to
     * the same thing when there is no node: `getPublicKey()` falls to its
     * `syncingwallet2` alert when `nodeId()` is nil, and `restoreWalletTapped()`
     * shows the `syncingwallet` alert outright when `walletHasSynced` is false.
     * Reporting "you're not connected to bittr" for the peer row would be worse than
     * this, not better — it claims a connection was attempted.
     *
     * **The Pending-payout row is the one that must not be dropped.** It is the
     * support path BIT-28's playbook sends customers down, and the app's own copy
     * routes them to it. It is here, it is tappable, and when BIT-6 lands it starts
     * signing and calling `/api/notifications` like the iOS one.
     */
    fun nodeBackedRowTapped() {
        alert.value = DeviceAlert(
            title = SettingsStrings.SYNCING_WALLET,
            message = SettingsStrings.SYNCING_WALLET_2,
        )
    }

    fun dismissAlert() {
        alert.value = null
    }

    private companion object {
        /**
         * **The BIT-6 line for this screen.**
         *
         * `WalletState.Ready` says key material is unlocked; these rows need a running
         * Lightning node, which is a strictly stronger claim and one the seam cannot
         * make yet. When BIT-6 widens `WalletService`, this reads the node's state and
         * the rows take their iOS branches.
         */
        @Suppress("UNUSED_PARAMETER")
        fun nodeIsUp(state: WalletState): Boolean = false
    }
}
