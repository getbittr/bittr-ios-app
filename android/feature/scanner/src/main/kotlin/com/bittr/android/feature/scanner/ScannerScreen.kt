package com.bittr.android.feature.scanner

import android.content.pm.PackageManager
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import com.bittr.android.core.designsystem.BittrInlineAlert
import com.bittr.android.core.designsystem.BittrTheme
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.rememberStrokeIcon
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
        val cameraCount = runCatching {
            context.getSystemService(android.hardware.camera2.CameraManager::class.java)?.cameraIdList?.size ?: 0
        }.getOrDefault(0)
        ScannerPermissionFlow.hasCamera(
            declaresFeature = context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
            cameraCount = cameraCount,
        )
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
    // As `ScannerViewController` lays it out: `addHeader` with `qrcode` over a block centred in the
    // whole sheet — the camera view 25 in and 400 tall with 13 corners, and 20 under it the black
    // Close. No brackets and no helper line: iOS has neither.
    Box(modifier = modifier.fillMaxSize()) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .background(BittrTheme.colors.canvas),
        ) {
            val sheetHeight = maxHeight
            // 400 as on iOS, but never at Close's expense: on a sheet too short for both, the
            // camera view gives up the difference (down to a floor) instead of pushing Close
            // below the edge.
            val previewHeight = (sheetHeight - SheetInset * 2 - 20.dp - 40.dp).coerceIn(MinPreviewHeight, PreviewHeight)
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .heightIn(min = sheetHeight)
                    .padding(horizontal = 25.dp, vertical = SheetInset),
            ) {
                // The frame. Always composed, in every state — see the class doc.
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(previewHeight)
                        .clip(RoundedCornerShape(PreviewCornerRadius))
                        // Black, as iOS's `scannerView` is: where the camera image goes, and a
                        // camera that has not started is black in both schemes.
                        .background(Color.Black)
                        .testTag(TestID.Scanner.scannerView),
                ) {
                    if (state is ScannerUiState.Scanning) {
                        viewfinder()
                    }
                }

                CloseButton(onClick = onClose, modifier = Modifier.padding(top = 20.dp))
            }

            BittrSheetHeader(
                icon = rememberVectorPainter(rememberStrokeIcon(QR_ICON_PATH, Color.White, strokeWidth = 1.6f)),
                title = ScannerCopy.HEADER,
                onDown = onClose,
                titleTestTag = TestID.Header.titleLabel,
                downTestTag = TestID.Header.downButton,
            )
        }

        // Inline, not dialog, alerts: `send_onchain.yaml` asserts `scanner.scannerView` and
        // `alert.button.0` together, and a dialog window hides the frame from Maestro. With
        // no dialog, back is handled here — to the way out, as the dialog's back press did.
        androidx.activity.compose.BackHandler(enabled = state != ScannerUiState.Scanning) {
            if (state == ScannerUiState.NoCamera) onClose() else onCancel()
        }

        when (state) {
            ScannerUiState.Scanning -> Unit

            ScannerUiState.Rationale -> BittrInlineAlert(
                title = ScannerCopy.PERMISSION_TITLE,
                message = ScannerCopy.RATIONALE_BODY,
                buttons = listOf(
                    BittrAlertButton(ScannerCopy.CANCEL, dismissesAlert = true, onClick = onCancel),
                    BittrAlertButton(ScannerCopy.CONTINUE, onClick = onContinue),
                ),
            )

            ScannerUiState.PermanentlyDenied -> BittrInlineAlert(
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
            ScannerUiState.NoCamera -> BittrInlineAlert(
                title = ScannerCopy.NO_CAMERA_TITLE,
                message = ScannerCopy.NO_CAMERA_BODY,
                buttons = listOf(
                    BittrAlertButton(ScannerCopy.OKAY, dismissesAlert = true, onClick = onClose),
                ),
            )
        }
    }
}

/**
 * `closeView`: 40 tall and black with 8 corners, "Close" in white Gilroy-Bold 14, 17 from either
 * end. Black is `actionFill`, which lightens in dark mode where black would not read on blue.
 */
@Composable
private fun CloseButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = BittrTheme.colors
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(40.dp)
            .clip(CloseShape)
            .background(colors.actionFill)
            .clickable(role = Role.Button, onClick = onClick)
            .testTag(TestID.Scanner.closeButton)
            .padding(horizontal = 17.dp),
    ) {
        Text(
            text = ScannerCopy.CLOSE,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, lineHeight = 14.sp),
            color = colors.onActionFill,
            modifier = Modifier.offset(y = 1.dp),
        )
    }
}

private val PreviewHeight = 400.dp
private val MinPreviewHeight = 200.dp

/** The header's 58 above the block, and the same below so it centres on the whole sheet. */
private val SheetInset = 58.dp
private val PreviewCornerRadius = 13.dp
private val CloseShape = RoundedCornerShape(8.dp)

/** SF Symbols' `qrcode`, the header's icon: three finder squares and the scattered modules. */
private const val QR_ICON_PATH =
    "M3.5 3.5h7v7h-7z M13.5 3.5h7v7h-7z M3.5 13.5h7v7h-7z M6.5 6.5h1v1h-1z M16.5 6.5h1v1h-1z M6.5 16.5h1v1h-1z " +
        "M14 14h2 M19 14h1.5 M14 17.5v3 M17.5 17.5h3v3"

@Preview(showBackground = true)
@Composable
private fun ScannerNoCameraPreview() {
    BittrTheme {
        ScannerScreenContent(
            state = ScannerUiState.NoCamera,
            onClose = {},
            onCancel = {},
            onContinue = {},
            onOpenSettings = {},
        )
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
