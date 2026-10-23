package com.bittr.android.feature.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.os.Build
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlert
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrChoiceDialog
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.R as DesignR
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.rememberFillIcon
import com.bittr.android.core.designsystem.rememberStrokeIcon
import com.bittr.android.core.preferences.Currency
import com.bittr.android.core.preferences.DarkModeSetting

/**
 * Device details — `ios/bittr/Settings/DeviceViewController`.
 *
 * All nine rows, in iOS's order, each carrying its `device.row.*` identifier. Public key,
 * Bittr peer and Pending payout ask the node and bittr through [DeviceNode]; Lightning
 * connections shows the channel count once the wallet has a reading; Remove wallet is the
 * app's removal coordinator.
 */
@Composable
fun DeviceScreen(
    onDown: () -> Unit,
    onOpenLightningQuestion: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: DeviceViewModel = hiltViewModel(),
    onRemoveWallet: () -> Unit = viewModel::nodeBackedRowTapped,
) {
    val state by viewModel.uiState.collectAsState()
    val picker by viewModel.openPicker.collectAsState()
    val alert by viewModel.currentAlert.collectAsState()
    val context = LocalContext.current

    /**
     * iOS's `askForPushNotifications()`, in Android's terms: ask for the notification
     * permission. Below API 33 there is no runtime notification permission and nothing
     * happens, which matches an already-authorized iOS device.
     */
    val notificationPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { viewModel.deviceTokenTapped() }

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
                // The launcher answers even when the permission is already granted, and the
                // token alert follows from its result.
                notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                viewModel.deviceTokenTapped()
            }
        },
        onPublicKey = viewModel::publicKeyTapped,
        onBittrPeer = viewModel::bittrPeerTapped,
        onPendingPayout = viewModel::pendingPayoutTapped,
        onOpenLightningQuestion = onOpenLightningQuestion,
        onAlertButton = { button ->
            (button.action as? DeviceAlertAction.Copy)?.let { copy ->
                context.getSystemService(ClipboardManager::class.java)
                    ?.setPrimaryClip(ClipData.newPlainText(SettingsStrings.PUBLIC_KEY, copy.text))
            }
            viewModel.onAlertButton(button)
        },
        onRemoveWallet = onRemoveWallet,
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
    onPublicKey: () -> Unit,
    onBittrPeer: () -> Unit,
    onPendingPayout: () -> Unit,
    onOpenLightningQuestion: () -> Unit,
    onAlertButton: (DeviceAlertButton) -> Unit,
    onRemoveWallet: () -> Unit,
    modifier: Modifier = Modifier,
) {
    alert?.let {
        BittrAlert(
            title = it.title,
            message = it.message,
            messageIsValue = it.messageIsValue,
            valueWraps = true,
            identity = it,
            buttons = it.buttons.map { button ->
                BittrAlertButton(
                    label = button.label,
                    dismissesAlert = button.action == DeviceAlertAction.Dismiss,
                    onClick = { onAlertButton(button) },
                )
            },
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

    // `DeviceViewController`, as its scene is: `addHeader`'s piggy and "device details", then one
    // group centred in what is left — the line in Gilroy Regular 16, centred and 40 from the sides,
    // and 35 under it the rows, 30 from the sides.
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(BittrTheme.colors.canvas)
            .dismissOnPullDown(onDown)
            .navigationBarsPadding(),
    ) {
        BittrSheetHeader(
            icon = painterResource(DesignR.drawable.bittr_piggy_icon),
            title = SettingsStrings.DEVICE_DETAILS,
            onDown = onDown,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )

        BoxWithConstraints(modifier = Modifier.weight(1f).fillMaxWidth()) {
            Column(
                verticalArrangement = Arrangement.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .heightIn(min = maxHeight)
                    .padding(vertical = 30.dp),
            ) {
                Text(
                    text = SettingsStrings.ACCESS_DETAILS,
                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 19.sp),
                    color = BittrTheme.colors.onCanvas,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 40.dp),
                )
                CanvasSpacer(35.dp)

                Column(modifier = Modifier.padding(horizontal = 30.dp)) {
                    // 1. Dark mode. The only row whose trailing content is a control rather
                    //    than a value — iOS swaps the row's button for the segmented one
                    //    (`showDarkMode()` / `hideDarkMode()`).
                    DeviceRow(
                        label = SettingsStrings.DARK_MODE,
                        icon = BittrIconPaths.DARK_MODE,
                        iconFilled = true,
                        testTag = TestID.Device.Row.darkmode,
                    ) {
                        DarkModeControl(selected = state.darkMode, onSelect = onDarkMode)
                    }

                    // 2. Language.
                    DeviceRow(
                        label = SettingsStrings.LANGUAGE,
                        icon = BittrIconPaths.LANGUAGE,
                        onClick = { onOpenPicker(DevicePicker.Language) },
                        testTag = TestID.Device.Row.language,
                    ) {
                        DeviceValue(SettingsStrings.ENGLISH)
                    }

                    // 3. Currency.
                    DeviceRow(
                        label = SettingsStrings.CURRENCY,
                        icon = BittrIconPaths.CURRENCY,
                        onClick = { onOpenPicker(DevicePicker.Currency) },
                        testTag = TestID.Device.Row.currency,
                    ) {
                        DeviceValue(state.currency.code)
                    }

                    // 4. Device token.
                    DeviceRow(
                        label = SettingsStrings.DEVICE_TOKEN,
                        icon = BittrIconPaths.PHONE,
                        onClick = onDeviceToken,
                        testTag = TestID.Device.Row.devicetoken,
                    ) {
                        DeviceValue(SettingsStrings.FETCH)
                    }

                    // 5. Public key.
                    DeviceRow(
                        label = SettingsStrings.PUBLIC_KEY,
                        icon = BittrIconPaths.KEY,
                        onClick = onPublicKey,
                        testTag = TestID.Device.Row.publickey,
                    ) {
                        DeviceValue(SettingsStrings.FETCH)
                    }

                    // 6. Bittr peer.
                    DeviceRow(
                        label = SettingsStrings.BITTR_PEER,
                        icon = BittrIconPaths.PEER,
                        onClick = onBittrPeer,
                        testTag = TestID.Device.Row.bittrpeer,
                    ) {
                        CheckValue(checking = state.checkingRow == DeviceRow.BittrPeer)
                    }

                    // 7. Pending payout — the support path BIT-28's playbook sends customers down.
                    DeviceRow(
                        label = SettingsStrings.PENDING_PAYOUT,
                        icon = BittrIconPaths.HOURGLASS,
                        onClick = onPendingPayout,
                        testTag = TestID.Device.Row.pendingpayouts,
                    ) {
                        CheckValue(checking = state.checkingRow == DeviceRow.PendingPayout)
                    }

                    // 8. Lightning connections: the count once the wallet has a reading.
                    DeviceRow(
                        label = SettingsStrings.LIGHTNING_CONNECTIONS,
                        icon = BittrIconPaths.BOLT,
                        onClick = onOpenLightningQuestion,
                        testTag = TestID.Device.Row.lightningchannels,
                    ) {
                        DeviceValue(state.channelCount)
                    }

                    // 9. Remove wallet. The app's `WalletRemovalCoordinator`: it refuses to
                    //    wipe until it can see whether a channel is open, because the wipe
                    //    destroys the channel state a seed alone cannot rebuild.
                    DeviceRow(
                        label = SettingsStrings.REMOVE_WALLET,
                        icon = BittrIconPaths.TRASH,
                        onClick = onRemoveWallet,
                        testTag = TestID.Device.Row.restore,
                    )
                }
            }
        }
    }
}

/**
 * `DeviceTableViewCell` in its 55 pt row: `cellCard`, 45 tall, `white0.7orblue2` with 13 pt corners
 * and no shadow; the icon 20 pt and 20 in, in the brand yellow; the title 12 after it in Gilroy
 * Bold 14; the value or control 15 from the end. `cellButton` covers the whole row.
 */
@Composable
private fun DeviceRow(
    label: String,
    icon: String,
    testTag: String,
    onClick: (() -> Unit)? = null,
    iconFilled: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
) {
    val colors = BittrTheme.colors
    Box(
        contentAlignment = Alignment.TopCenter,
        modifier = Modifier
            .fillMaxWidth()
            .height(55.dp)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .testTag(testTag),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .height(45.dp)
                .background(colors.homeAction, DeviceCardShape)
                .padding(start = 20.dp, end = 15.dp),
        ) {
            Image(
                imageVector = if (iconFilled) {
                    rememberFillIcon(icon, colors.settingsIcon)
                } else {
                    rememberStrokeIcon(icon, colors.settingsIcon, strokeWidth = 2f)
                },
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.sp, lineHeight = 14.sp),
                color = colors.onCanvas,
                maxLines = 1,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 12.dp)
                    .offset(y = 1.dp),
            )
            if (trailing != null) trailing()
        }
    }
}

private val DeviceCardShape = RoundedCornerShape(13.dp)

/** `buttonLabel`: Gilroy Regular 16, 2 pt below the card's centre. */
@Composable
private fun DeviceValue(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 16.sp),
        color = BittrTheme.colors.onCanvas,
        modifier = Modifier.offset(y = 2.dp),
    )
}

/** "Check", or a spinner while the check runs — iOS's `animateCell()`. */
@Composable
private fun CheckValue(checking: Boolean) {
    if (checking) {
        BittrSpinner(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
    } else {
        DeviceValue(SettingsStrings.CHECK)
    }
}

/**
 * `darkModeView`: the device, moon and sun glyphs — 22, 19 and 22 pt, 20 and 18 apart, the sun 15
 * from the card's end — the selected one in the brand yellow and the others `blackorwhite`, each in
 * a 40 pt tap target as iOS's buttons are. The selected button also announces itself to a screen
 * reader.
 */
@Composable
private fun DarkModeControl(
    selected: DarkModeSetting,
    onSelect: (DarkModeSetting) -> Unit,
) {
    // System, dark, light — iOS's order. The 40 pt targets overlap the glyphs' gaps, so they sit
    // edge to edge and the last one reaches 9 past the sun, into the card's 15.
    Row(modifier = Modifier.offset(x = 9.dp)) {
        DarkModeButton(
            path = BittrIconPaths.COMPUTER,
            iconSize = 22.dp,
            label = "Follow the device",
            active = selected == DarkModeSetting.Device,
            onClick = { onSelect(DarkModeSetting.Device) },
            testTag = TestID.Device.Darkmode.deviceButton,
        )
        DarkModeButton(
            path = BittrIconPaths.DARK_MODE,
            iconSize = 19.dp,
            label = "Dark",
            active = selected == DarkModeSetting.Dark,
            onClick = { onSelect(DarkModeSetting.Dark) },
            testTag = TestID.Device.Darkmode.moonButton,
        )
        DarkModeButton(
            path = BittrIconPaths.LIGHT_MODE,
            iconSize = 22.dp,
            label = "Light",
            active = selected == DarkModeSetting.Light,
            onClick = { onSelect(DarkModeSetting.Light) },
            testTag = TestID.Device.Darkmode.sunButton,
        )
    }
}

/** One mode's glyph in its 40 pt target: brand yellow when selected, `blackorwhite` when not. */
@Composable
private fun DarkModeButton(
    path: String,
    iconSize: Dp,
    label: String,
    active: Boolean,
    onClick: () -> Unit,
    testTag: String,
) {
    val colors = BittrTheme.colors
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(40.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick)
            .testTag(testTag)
            .semantics { contentDescription = if (active) "$label, selected" else label },
    ) {
        Image(
            imageVector = rememberFillIcon(path, if (active) colors.brandFixed else colors.onCanvas),
            contentDescription = null,
            modifier = Modifier.size(iconSize),
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

/** Device details before the wallet has synced. Shared by the preview and the captures. */
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
        onPublicKey = {},
        onBittrPeer = {},
        onPendingPayout = {},
        onOpenLightningQuestion = {},
        onAlertButton = {},
        onRemoveWallet = {},
        modifier = modifier,
    )
}
