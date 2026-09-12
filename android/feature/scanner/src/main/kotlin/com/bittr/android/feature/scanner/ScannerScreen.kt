package com.bittr.android.feature.scanner

import android.content.pm.PackageManager
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlert
import com.bittr.android.core.designsystem.BittrAlertButton
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.permissions.AppSettings
import com.bittr.android.core.permissions.BittrPermissions
import com.bittr.android.core.permissions.firstResolvable

/**
 * The QR scanner — iOS `ScannerViewController` (S-16), ported.
 *
 * Opened from Send. It reads one code and hands the string back through [onScanned];
 * what that string turns out to be — an address, a BOLT-11 invoice, an LNURL, a
 * BIP-21 URI carrying an amount — is not this screen's business. iOS routes all of
 * them through a single entry point (`handleScannedOrPastedString`,
 * `AddressParsing.swift:15`) and so does the Android Send screen, which is the fact
 * that makes the permanently-denied copy's *"You can also paste an address or an
 * invoice"* true: paste and scan are the same path.
 *
 * ### Shape
 *
 * The scanner frame is present in every state, with the alert over it. That is what
 * iOS does — `fixQrScanner()` fails, the view is still there, and the alert is
 * presented on top — and it is what
 * `shared/flows/features/send_onchain.yaml:78-81` asserts, tapping
 * `scanner.scannerView` and `alert.button.0` in the same step. A version that swaps
 * the frame out for the alert passes every unit test and fails that flow after an
 * emulator boot.
 *
 * ### The camera is not this function
 *
 * [ScannerViewfinder] binds the use cases, and it is the only place that can. This
 * function decides *whether* to show it; what the camera is allowed to do while it
 * is on screen is settled there, and by `CameraCaptureGuardTest`.
 */
@Composable
fun ScannerScreen(
    onScanned: (String) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val activity = LocalActivity.current

    val hasCamera = remember(context) {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    }
    val granted = remember(context) {
        ContextCompat.checkSelfPermission(context, BittrPermissions.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    }

    // Survives rotation. Without this, turning the phone while the rationale is up
    // re-runs the opening decision, and the user is told why the camera is needed a
    // second time — having already said continue.
    var state by rememberSaveable { mutableStateOf(ScannerPermissionFlow.initial(hasCamera, granted)) }

    val currentOnScanned by rememberUpdatedState(onScanned)
    val currentOnClose by rememberUpdatedState(onClose)

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { isGranted ->
        // Read shouldShowRequestPermissionRationale *here*, after the answer. Before
        // the first ask it is false for a reason that has nothing to do with a
        // permanent denial — see ScannerPermissionFlow.afterRequest.
        val canAskAgain = activity
            ?.shouldShowRequestPermissionRationale(BittrPermissions.CAMERA)
            ?: false
        state = ScannerPermissionFlow.afterRequest(isGranted, canAskAgain)
    }

    // Resolved once, up front, because it decides whether the button exists at all.
    // AppSettings is explicit that an unresolvable intent means leaving the button
    // out rather than shipping one that throws — it is the button whose whole job is
    // to be the way out of a dead end.
    val settingsIntent = remember(context) {
        context.firstResolvable(AppSettings.applicationDetails(context.packageName))
    }

    ScannerScreenContent(
        state = state,
        onClose = { currentOnClose() },
        onCancel = { currentOnClose() },
        onContinue = { permissionLauncher.launch(BittrPermissions.CAMERA) },
        onOpenSettings = settingsIntent?.let { intent -> { context.startActivity(intent) } },
        modifier = modifier,
        viewfinder = { ScannerViewfinder(onCode = { code -> currentOnScanned(code) }) },
    )
}

/**
 * The scanner with its state handed to it, so every state can be rendered without a
 * camera, a permission grant or an emulator.
 *
 * [onOpenSettings] is null when no activity on this device can open the app's
 * settings page; the Settings button is then left out rather than shown and dead.
 * That shifts the Cancel button's test ID from `alert.button.0` to the only button
 * there is, which is still `alert.button.0` — Cancel is position 0 in both layouts,
 * deliberately.
 */
@Composable
internal fun ScannerScreenContent(
    state: ScannerUiState,
    onClose: () -> Unit,
    onCancel: () -> Unit,
    onContinue: () -> Unit,
    onOpenSettings: (() -> Unit)?,
    modifier: Modifier = Modifier,
    viewfinder: @Composable () -> Unit = {},
) {
    Surface(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(BittrTokens.Spacing.lg),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.lg),
        ) {
            Text(
                text = ScannerCopy.HEADER,
                style = MaterialTheme.typography.headlineSmall,
            )

            // The frame. Always composed, in every state — see the class doc.
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    // 13dp, matching the iOS scannerView's corner radius
                    // (ScannerViewController.swift:37).
                    .clip(RoundedCornerShape(13.dp))
                    // Black behind the viewfinder, so the frame reads as a camera
                    // that has not started rather than as a gap in the layout while
                    // the first surface is still being handed over.
                    .background(Color.Black)
                    .testTag(TestID.Scanner.scannerView),
            ) {
                if (state is ScannerUiState.Scanning) {
                    viewfinder()
                }
            }

            // The label colour is spelled out for the reason `BittrAlert`'s way-out
            // button spells it out: a Material `TextButton` paints its text `primary`,
            // and in light mode `primary` is the brand yellow, which is a surface in
            // this app — 1.42 : 1 on the `grey1` page. A11Y-22, BIT-94.
            TextButton(
                onClick = onClose,
                modifier = Modifier.testTag(TestID.Scanner.closeButton),
                colors = ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
            ) {
                Text(ScannerCopy.CLOSE)
            }
        }

        when (state) {
            ScannerUiState.Scanning -> Unit

            ScannerUiState.Rationale -> BittrAlert(
                title = ScannerCopy.PERMISSION_TITLE,
                message = ScannerCopy.RATIONALE_BODY,
                buttons = listOf(
                    BittrAlertButton(ScannerCopy.CANCEL, dismissesAlert = true, onClick = onCancel),
                    BittrAlertButton(ScannerCopy.CONTINUE, onClick = onContinue),
                ),
            )

            ScannerUiState.PermanentlyDenied -> BittrAlert(
                title = ScannerCopy.PERMISSION_TITLE,
                message = ScannerCopy.PERMANENTLY_DENIED_BODY,
                buttons = listOfNotNull(
                    BittrAlertButton(ScannerCopy.CANCEL, dismissesAlert = true, onClick = onCancel),
                    onOpenSettings?.let { BittrAlertButton(ScannerCopy.SETTINGS, onClick = it) },
                ),
            )

            // One button, and it closes the scanner — matching iOS, where the Okay
            // action on this alert calls closeScannerView()
            // (ScannerViewController.swift:53). There is nothing to do on this
            // screen without a camera, so leaving the user on it would be a dead end
            // with a view of a black square.
            ScannerUiState.NoCamera -> BittrAlert(
                title = ScannerCopy.NO_CAMERA_TITLE,
                message = ScannerCopy.NO_CAMERA_BODY,
                buttons = listOf(
                    BittrAlertButton(ScannerCopy.OKAY, dismissesAlert = true, onClick = onClose),
                ),
            )
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun ScannerRationalePreview() {
    BittrTheme {
        ScannerScreenContent(
            state = ScannerUiState.Rationale,
            onClose = {},
            onCancel = {},
            onContinue = {},
            onOpenSettings = {},
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun ScannerPermanentlyDeniedPreview() {
    BittrTheme {
        ScannerScreenContent(
            state = ScannerUiState.PermanentlyDenied,
            onClose = {},
            onCancel = {},
            onContinue = {},
            onOpenSettings = {},
        )
    }
}
