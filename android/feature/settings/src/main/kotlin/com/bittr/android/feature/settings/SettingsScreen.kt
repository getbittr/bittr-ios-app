package com.bittr.android.feature.settings

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.IosCardShape
import com.bittr.android.core.designsystem.R as DesignR
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.designsystem.rememberStrokeIcon

/**
 * Settings — `ios/bittr/Settings/SettingsViewController` — the content of the pop-up that springs up
 * over Wallet or Academy (`BittrPopup`, `CoreViewController.showSettings`).
 *
 * Four rows and a version line. The rows are data on iOS (a `settings` array of
 * label / icon / id dictionaries) and data here, for the same reason: the id in each
 * entry is both the segue key and the `settings.row.*` accessibility identifier, and
 * splitting the two apart is how they stop matching.
 *
 * Laid out as the scene is: `addHeader`'s 58 pt header — the settings icon 20 in, "settings" in
 * Gilroy Bold 18 10 after it, both white (yellow in dark), and the down arrow 20 from the end — then
 * from 60 down the rows, 55 apart, and the app version 25 under them and 30 above the bottom.
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
    val colors = BittrTheme.colors

    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .height(58.dp)
                .padding(start = 20.dp),
        ) {
            Image(
                painter = painterResource(DesignR.drawable.menu_settings_white),
                contentDescription = null,
                colorFilter = ColorFilter.tint(colors.homeCardTitle),
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = SettingsStrings.SETTINGS.lowercase(),
                style = MaterialTheme.typography.titleMedium.copy(fontSize = 18.sp, lineHeight = 18.sp),
                color = colors.homeCardTitle,
                maxLines = 1,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 10.dp)
                    .offset(y = 1.dp)
                    .testTag(TestID.Header.titleLabel),
            )
            // `downarrow32`, 20 pt and 20 from the end, in a 48 dp target.
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .padding(end = 6.dp)
                    .size(48.dp)
                    .clickable(role = Role.Button, onClick = onDown)
                    .testTag(TestID.Header.downButton),
            ) {
                Image(
                    painter = painterResource(DesignR.drawable.bittr_down_chevron),
                    contentDescription = "Close",
                    colorFilter = ColorFilter.tint(colors.homeCardTitle),
                    modifier = Modifier.size(20.dp),
                )
            }
        }
        CanvasSpacer(2.dp)

        SettingsRow(
            label = SettingsStrings.GET_SUPPORT,
            icon = BittrIconPaths.SUPPORT,
            onClick = { onOpenWebsite(WebsitePage.Support) },
            testTag = TestID.Settings.Row.support,
        )
        SettingsRow(
            label = SettingsStrings.PRIVACY_POLICY,
            icon = BittrIconPaths.PRIVACY,
            onClick = { onOpenWebsite(WebsitePage.Privacy) },
            testTag = TestID.Settings.Row.privacy,
        )
        SettingsRow(
            label = SettingsStrings.TERMS_AND_CONDITIONS,
            icon = BittrIconPaths.TERMS,
            onClick = { onOpenWebsite(WebsitePage.Terms) },
            testTag = TestID.Settings.Row.terms,
        )
        SettingsRow(
            label = SettingsStrings.DEVICE_DETAILS,
            icon = BittrIconPaths.DEVICE,
            onClick = onOpenDevice,
            testTag = TestID.Settings.Row.device,
        )

        CanvasSpacer(25.dp)
        Text(
            text = "${SettingsStrings.APP_VERSION} $version",
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 16.sp),
            color = colors.onCanvas,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        CanvasSpacer(30.dp)
    }
}

/**
 * `SettingsTableViewCell` in a 55 pt row: `settingsCardView`, 45 tall and 15 from the sides,
 * `whiteorblue2` with 13 pt corners and `setShadow()`; the yellow icon 20 pt and 25 in, the label
 * 12 after it in Gilroy Bold 14. `settingsButton` covers the whole row.
 */
@Composable
private fun SettingsRow(label: String, icon: String, onClick: () -> Unit, testTag: String) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .height(55.dp)
            .clickable(onClick = onClick)
            .testTag(testTag),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .padding(horizontal = 15.dp)
                .fillMaxWidth()
                .height(45.dp)
                .iosShadow(IosCardShape)
                .background(MaterialTheme.colorScheme.surfaceContainer, IosCardShape)
                .padding(start = 25.dp, end = 30.dp),
        ) {
            Image(
                imageVector = rememberStrokeIcon(icon, BittrTheme.colors.brandFixed, strokeWidth = 1.9f),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.sp, lineHeight = 14.sp),
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                modifier = Modifier
                    .padding(start = 12.dp)
                    .offset(y = 1.dp),
            )
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
        SettingsScreen(
            onDown = {},
            onOpenWebsite = {},
            onOpenDevice = {},
            modifier = Modifier.background(BittrTheme.colors.canvas),
        )
    }
}
