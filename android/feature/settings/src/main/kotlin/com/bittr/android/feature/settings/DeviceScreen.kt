package com.bittr.android.feature.settings

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrBody
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrChoiceDialog
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrListRow
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrRowValue
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.rememberStrokeIcon
import com.bittr.android.core.preferences.Currency
import com.bittr.android.core.preferences.DarkModeSetting

/**
 * Device details — `ios/bittr/Settings/DeviceViewController`.
 *
 * All nine rows, in iOS's order, each carrying its `device.row.*` identifier. Four of
 * them — Public key, Bittr peer, Pending payout, Remove wallet — report facts only a
 * running Lightning node has, and take the `syncingwallet` branch iOS itself takes
 * when there is no node. See [DeviceViewModel.nodeBackedRowTapped].
 *
 * The two that fully work today are the two `features/settings.yaml` asserts a
 * *visible* consequence of: the dark-mode control recolours the whole app, and the
 * currency switch changes what Home displays amounts in. Both persist through a
 * process death, because both are read at launch — the theme before the first frame.
 */
@Composable
fun DeviceScreen(
    onDown: () -> Unit,
    onOpenLightningQuestion: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: DeviceViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val picker by viewModel.openPicker.collectAsState()
    val alert by viewModel.currentAlert.collectAsState()

    /**
     * iOS's `askForPushNotifications()`, in Android's terms.
     *
     * There is no FCM token to fetch until Firebase is provisioned (BIT-39, and only
     * Ruben can do it), so the whole of what this row can honestly do today is the
     * half that does not need it: ask for the notification permission. That is
     * precisely what the iOS row does on a device where authorization is
     * `.notDetermined`, and `features/settings.yaml` already tolerates the branch
     * where no token alert follows — "or nothing (a simulator often can't mint an
     * APNs token)". Showing an invented "no token" alert would be the one behaviour
     * the flow does *not* expect.
     *
     * Below API 33 there is no runtime notification permission and nothing happens,
     * which matches an already-authorized iOS device.
     */
    val notificationPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* Granted or not, there is no token to show until BIT-39. */ }

    DeviceScreen(
        state = state,
        picker = picker,
        alert = alert,
        onDown = onDown,
        onDarkMode = viewModel::setDarkMode,
        onOpenPicker = viewModel::openPicker,
        onDismissPicker = viewModel::dismissPicker,
        onSelectEnglish = viewModel::selectEnglish,
        onSelectCurrency = viewModel::setCurrency,
        onDeviceToken = {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        },
        onNodeBackedRow = viewModel::nodeBackedRowTapped,
        onOpenLightningQuestion = onOpenLightningQuestion,
        onDismissAlert = viewModel::dismissAlert,
        modifier = modifier,
    )
}

/** The stateless half — see [com.bittr.android.feature.home.HomeScreen] for why. */
@Composable
internal fun DeviceScreen(
    state: DeviceUiState,
    picker: DevicePicker?,
    alert: DeviceAlert?,
    onDown: () -> Unit,
    onDarkMode: (DarkModeSetting) -> Unit,
    onOpenPicker: (DevicePicker) -> Unit,
    onDismissPicker: () -> Unit,
    onSelectEnglish: () -> Unit,
    onSelectCurrency: (Currency) -> Unit,
    onDeviceToken: () -> Unit,
    onNodeBackedRow: () -> Unit,
    onOpenLightningQuestion: () -> Unit,
    onDismissAlert: () -> Unit,
    modifier: Modifier = Modifier,
) {
    alert?.let {
        BittrAlertDialog(
            title = it.title,
            message = it.message,
            confirmLabel = SettingsStrings.OKAY,
            onConfirm = onDismissAlert,
            confirmTestTag = TestID.Alert.buttonAt(0),
        )
    }

    when (picker) {
        DevicePicker.Language -> BittrChoiceDialog(
            title = SettingsStrings.SELECT_LANGUAGE,
            message = SettingsStrings.SELECT_LANGUAGE_MESSAGE,
            options = listOf(SettingsStrings.ENGLISH_US),
            onSelect = { onSelectEnglish() },
            onCancel = onDismissPicker,
            cancelLabel = SettingsStrings.CANCEL,
        )

        DevicePicker.Currency -> BittrChoiceDialog(
            title = SettingsStrings.SELECT_CURRENCY,
            message = SettingsStrings.SELECT_CURRENCY_MESSAGE,
            options = Currency.entries.map { it.label },
            onSelect = { onSelectCurrency(Currency.entries[it]) },
            onCancel = onDismissPicker,
            cancelLabel = SettingsStrings.CANCEL,
        )

        null -> Unit
    }

    BittrCanvas(modifier = modifier, appBar = false) {
        BittrModalHeader(
            title = SettingsStrings.DEVICE_DETAILS,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )

        Column(
            verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(
                    horizontal = BittrTokens.Spacing.md,
                    vertical = BittrTokens.Spacing.sm,
                ),
        ) {
            BittrBody(
                text = SettingsStrings.ACCESS_DETAILS,
                textAlign = TextAlign.Start,
                modifier = Modifier.fillMaxWidth(),
            )
            CanvasSpacer(BittrTokens.Spacing.xs)

            // 1. Dark mode. The only row whose trailing content is a control rather
            //    than a value — iOS swaps the row's button for the segmented one
            //    (`showDarkMode()` / `hideDarkMode()`).
            BittrListRow(
                label = SettingsStrings.DARK_MODE,
                icon = BittrIconPaths.MOON,
                testTag = TestID.Device.Row.darkmode,
            ) {
                DarkModeControl(selected = state.darkMode, onSelect = onDarkMode)
            }

            // 2. Language.
            BittrListRow(
                label = SettingsStrings.LANGUAGE,
                icon = BittrIconPaths.LANGUAGE,
                onClick = { onOpenPicker(DevicePicker.Language) },
                testTag = TestID.Device.Row.language,
            ) {
                BittrRowValue(SettingsStrings.ENGLISH)
            }

            // 3. Currency.
            BittrListRow(
                label = SettingsStrings.CURRENCY,
                icon = BittrIconPaths.CURRENCY,
                onClick = { onOpenPicker(DevicePicker.Currency) },
                testTag = TestID.Device.Row.currency,
            ) {
                BittrRowValue(state.currency.code)
            }

            // 4. Device token.
            BittrListRow(
                label = SettingsStrings.DEVICE_TOKEN,
                icon = BittrIconPaths.PHONE,
                onClick = onDeviceToken,
                testTag = TestID.Device.Row.devicetoken,
            ) {
                BittrRowValue(SettingsStrings.FETCH)
            }

            // 5. Public key. Node-backed.
            BittrListRow(
                label = SettingsStrings.PUBLIC_KEY,
                icon = BittrIconPaths.KEY,
                onClick = onNodeBackedRow,
                testTag = TestID.Device.Row.publickey,
            ) {
                BittrRowValue(SettingsStrings.FETCH)
            }

            // 6. Bittr peer. Node-backed.
            BittrListRow(
                label = SettingsStrings.BITTR_PEER,
                icon = BittrIconPaths.PEER,
                onClick = onNodeBackedRow,
                testTag = TestID.Device.Row.bittrpeer,
            ) {
                BittrRowValue(SettingsStrings.CHECK)
            }

            // 7. Pending payout. Node-backed — and the row BIT-7's thread asked
            //    specifically not to lose. BIT-28's support playbook ends here.
            BittrListRow(
                label = SettingsStrings.PENDING_PAYOUT,
                icon = BittrIconPaths.HOURGLASS,
                onClick = onNodeBackedRow,
                testTag = TestID.Device.Row.pendingpayouts,
            ) {
                BittrRowValue(SettingsStrings.CHECK)
            }

            // 8. Lightning connections. The row's *value* needs the node; the card
            //    behind it does not, so the tap works and the count reads "Syncing".
            BittrListRow(
                label = SettingsStrings.LIGHTNING_CONNECTIONS,
                icon = BittrIconPaths.BOLT,
                onClick = onOpenLightningQuestion,
                testTag = TestID.Device.Row.lightningchannels,
            ) {
                BittrRowValue(state.channelCount)
            }

            // 9. Remove wallet. Node-backed: iOS refuses to wipe until it can see
            //    whether a channel is open, because the wipe destroys the channel
            //    state a seed alone cannot rebuild. Its `walletHasSynced` guard is
            //    the same one, and it is a hard rule rather than a convenience.
            BittrListRow(
                label = SettingsStrings.REMOVE_WALLET,
                icon = BittrIconPaths.TRASH,
                onClick = onNodeBackedRow,
                testTag = TestID.Device.Row.restore,
            )
        }
    }
}

/**
 * The sun / moon / device segmented control.
 *
 * iOS tints the selected glyph yellow and the other two `blackorwhite`. On the
 * brand canvas that yellow measures about 1.6 : 1 — the same A11Y-15 pair the numeral
 * substitution already fixed — and "which of three glyphs is selected" is not
 * decoration, it is the entire state of the control. So selection is carried by the
 * ink/white content colour at full strength against the other two at 45 %, which is a
 * 2.2× luminance-contrast step rather than a hue change, and the selected button also
 * announces itself to a screen reader.
 */
@Composable
private fun DarkModeControl(
    selected: DarkModeSetting,
    onSelect: (DarkModeSetting) -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.xs)) {
        DarkModeButton(
            path = BittrIconPaths.SUN,
            label = "Light",
            active = selected == DarkModeSetting.Light,
            onClick = { onSelect(DarkModeSetting.Light) },
            testTag = TestID.Device.Darkmode.sunButton,
        )
        DarkModeButton(
            path = BittrIconPaths.MOON,
            label = "Dark",
            active = selected == DarkModeSetting.Dark,
            onClick = { onSelect(DarkModeSetting.Dark) },
            testTag = TestID.Device.Darkmode.moonButton,
        )
        DarkModeButton(
            path = BittrIconPaths.PHONE,
            label = "Follow the device",
            active = selected == DarkModeSetting.Device,
            onClick = { onSelect(DarkModeSetting.Device) },
            testTag = TestID.Device.Darkmode.deviceButton,
        )
    }
}

@Composable
private fun DarkModeButton(
    path: String,
    label: String,
    active: Boolean,
    onClick: () -> Unit,
    testTag: String,
) {
    val tint = androidx.compose.material3.MaterialTheme.colorScheme.onSurface
        .copy(alpha = if (active) 1f else 0.45f)
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(40.dp)
            .clickable(onClick = onClick)
            .testTag(testTag)
            .semantics { contentDescription = if (active) "$label, selected" else label },
    ) {
        Image(
            imageVector = rememberStrokeIcon(path, tint, strokeWidth = 1.9f),
            contentDescription = null,
            modifier = Modifier.size(22.dp),
        )
    }
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun DeviceScreenPreview() {
    BittrTheme {
        DeviceNoNode()
    }
}

/** Device details as this build renders it. Shared by the preview and the captures. */
@Composable
fun DeviceNoNode(modifier: Modifier = Modifier) {
    DeviceScreen(
        state = DeviceUiState(),
        picker = null,
        alert = null,
        onDown = {},
        onDarkMode = {},
        onOpenPicker = {},
        onDismissPicker = {},
        onSelectEnglish = {},
        onSelectCurrency = {},
        onDeviceToken = {},
        onNodeBackedRow = {},
        onOpenLightningQuestion = {},
        onDismissAlert = {},
        modifier = modifier,
    )
}
