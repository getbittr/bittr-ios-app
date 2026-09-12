package com.bittr.android.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrFootnote
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrListRow
import com.bittr.android.core.designsystem.BittrModalHeader
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer

/**
 * Settings — `ios/bittr/Settings/SettingsViewController`.
 *
 * Four rows and a version line. The rows are data on iOS (a `settings` array of
 * label / icon / id dictionaries) and data here, for the same reason: the id in each
 * entry is both the segue key and the `settings.row.*` accessibility identifier, and
 * splitting the two apart is how they stop matching.
 *
 * ### It is a destination here and a pop-up there
 *
 * On iOS, Settings is a child view controller that springs up over Home
 * (`CoreViewController.showSettings`) and is dismissed by
 * `UIViewController.dismissVC`. On Android it is a navigation destination and the
 * header's down button pops the back stack.
 *
 * The difference is invisible to `features/settings.yaml`, which only ever taps
 * `nav.settingsButton` to get in and `header.downButton` to get out, and it buys the
 * system Back gesture for free — a pop-up would have had to intercept it. The one
 * thing it costs is the pan-to-dismiss gesture iOS attaches to the container; that is
 * not in any flow and not worth a custom modal to reproduce.
 */
@Composable
fun SettingsScreen(
    onDown: () -> Unit,
    onOpenWebsite: (WebsitePage) -> Unit,
    onOpenDevice: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val version = remember(context) { appVersion(context) }

    BittrCanvas(modifier = modifier, appBar = false) {
        BittrModalHeader(
            title = SettingsStrings.SETTINGS,
            onDown = onDown,
            icon = BittrIconPaths.SETTINGS,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )

        Column(
            verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = BittrTokens.Spacing.md),
        ) {
            BittrListRow(
                label = SettingsStrings.GET_SUPPORT,
                icon = BittrIconPaths.SUPPORT,
                onClick = { onOpenWebsite(WebsitePage.Support) },
                testTag = TestID.Settings.Row.support,
            )
            BittrListRow(
                label = SettingsStrings.PRIVACY_POLICY,
                icon = BittrIconPaths.PRIVACY,
                onClick = { onOpenWebsite(WebsitePage.Privacy) },
                testTag = TestID.Settings.Row.privacy,
            )
            BittrListRow(
                label = SettingsStrings.TERMS_AND_CONDITIONS,
                icon = BittrIconPaths.TERMS,
                onClick = { onOpenWebsite(WebsitePage.Terms) },
                testTag = TestID.Settings.Row.terms,
            )
            BittrListRow(
                label = SettingsStrings.DEVICE_DETAILS,
                icon = BittrIconPaths.DEVICE,
                onClick = onOpenDevice,
                testTag = TestID.Settings.Row.device,
            )

            CanvasSpacer(BittrTokens.Spacing.lg)
            BittrFootnote("${SettingsStrings.APP_VERSION} $version")
        }
    }
}

/**
 * `AppVersion.displayString` — `versionName (versionCode)`, read from the installed
 * package rather than hard-coded.
 *
 * iOS reads the bundle for the same reason: a number typed into a layout is a number
 * that is wrong one release later, and this line is the first thing support asks a
 * customer to read out.
 *
 * A version that cannot be read is reported as `?` rather than crashing Settings. The
 * only way `getPackageInfo` fails for the running package is a package manager in a
 * state where the app is already gone.
 */
private fun appVersion(context: android.content.Context): String = try {
    val info = context.packageManager.getPackageInfo(context.packageName, 0)
    val code = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
        info.longVersionCode
    } else {
        @Suppress("DEPRECATION")
        info.versionCode.toLong()
    }
    "${info.versionName} ($code)"
} catch (e: android.content.pm.PackageManager.NameNotFoundException) {
    "?"
}

@Preview(showBackground = true, widthDp = 412, heightDp = 892)
@Composable
private fun SettingsScreenPreview() {
    BittrTheme {
        SettingsScreen(onDown = {}, onOpenWebsite = {}, onOpenDevice = {})
    }
}
