package com.bittr.android.core.designsystem

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * The chrome the ported *screens* share — the modal header, the bottom bar and the
 * settings row — as opposed to [BittrCanvas]'s onboarding components.
 *
 * Everything here carries its test tags as `String` parameters rather than reading
 * them from `TestID`: `:core:designsystem` does not depend on `:core:common`, and
 * that direction is worth keeping. Callers pass the constant.
 */

private val HeaderHeight = 58.dp
private val HeaderIcon = 18.dp
private val RowHeight = 56.dp
private val NavBarHeight = 56.dp

/**
 * The header on a screen presented over another one — iOS's
 * `UIViewController.addHeader(iconLight:iconDark:title:)`.
 *
 * Same three parts in the same places: a brand glyph at the leading edge, the title
 * **lowercased** beside it (iOS calls `.lowercased()` on every caller's string, so
 * the callers here pass normal copy and this does the same), and the down chevron
 * that closes the screen at the trailing edge.
 *
 * The down button is 48 dp rather than iOS's 32 pt asset box. It is the only way back
 * out of Settings, Device details, the website pages and the question card — four
 * screens whose entire escape hatch is this one control — and A11Y-08 already called
 * the 45 pt settings rows out as under-target. Growing the box does not move the
 * glyph; it grows what your thumb can miss by.
 *
 * @param titleTestTag `header.titleLabel`.
 * @param downTestTag `header.downButton` — or `website.downButton`, which is the same
 *   control under a different id on the website pages. iOS gives it its own id there,
 *   so the flows select differently on the two, and passing it in is what lets one
 *   composable serve both.
 */
@Composable
fun BittrModalHeader(
    title: String,
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
    icon: String = BittrIconPaths.PIGGY,
    titleTestTag: String? = null,
    downTestTag: String? = null,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .height(HeaderHeight)
            .padding(start = BittrTokens.Spacing.lg, end = BittrTokens.Spacing.xs),
    ) {
        Image(
            imageVector = rememberFillIcon(icon, LocalContentColor.current),
            contentDescription = null,
            modifier = Modifier.size(HeaderIcon),
        )
        Text(
            text = title.lowercase(),
            style = MaterialTheme.typography.titleMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .padding(start = BittrTokens.Spacing.sm)
                .then(titleTestTag?.let { Modifier.testTag(it) } ?: Modifier),
        )
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(BittrTokens.Size.minTouchTarget)
                .clickable(onClick = onDown)
                .then(downTestTag?.let { Modifier.testTag(it) } ?: Modifier),
        ) {
            Image(
                imageVector = rememberStrokeIcon(
                    BittrIconPaths.ARROW_DOWN,
                    LocalContentColor.current,
                ),
                contentDescription = "Close",
                modifier = Modifier.size(22.dp),
            )
        }
    }
}

/**
 * A row in the Settings or Device-details list: a brand-yellow glyph, a label, and
 * whatever the row puts on its trailing edge.
 *
 * iOS draws these at 45 pt (`SettingsViewController`'s `heightForRowAt`), which
 * A11Y-08 flags as below the touch-target minimum with room to spare. These are
 * [RowHeight], and `minTouchTarget` is the floor rather than the height so a row
 * whose trailing content is taller still grows rather than clipping.
 *
 * **The glyph is [BittrColors.emphasis], not the raw `#F8C744` iOS tints it with.**
 * That yellow on the row's near-white card measures about 1.6 : 1. The icon is
 * redundant with the label on every row here, so it is decoration and WCAG does not
 * require it to pass — but it is also unreadable, which is the same substitution
 * A11Y-15 and A11Y-21 made, and `emphasis` is the token that exists for it.
 */
@Composable
fun BittrListRow(
    label: String,
    icon: String,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    testTag: String? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    // A `Surface` rather than a `background` modifier so the row also swaps
    // `LocalContentColor` to `onSurface`. These rows sit on the brand canvas, where
    // the ambient content colour is `onCanvas` — ink on light, white on dark — and
    // white-on-white is how a row of labels disappears in dark mode.
    androidx.compose.material3.Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        contentColor = MaterialTheme.colorScheme.onSurface,
        shape = BittrCanvasShapes.field,
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (onClick != null) {
                    Modifier.clickable(onClick = onClick)
                } else {
                    Modifier
                },
            )
            .then(testTag?.let { Modifier.testTag(it) } ?: Modifier),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .heightIn(min = RowHeight)
                .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.sm),
        ) {
            Image(
                imageVector = rememberStrokeIcon(
                    icon,
                    BittrTheme.colors.emphasis,
                    strokeWidth = 1.9f,
                ),
                contentDescription = null,
                modifier = Modifier.size(22.dp),
            )
            Text(
                text = label,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = BittrTokens.Spacing.md),
            )
            if (trailing != null) trailing()
        }
    }
}

/** The value on the trailing edge of a Device-details row — "English", "EUR", "Fetch". */
@Composable
fun BittrRowValue(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier,
    )
}

/**
 * The bottom bar — artboard 18's Wallet / Academy / gear.
 *
 * The gear is a square rather than a labelled pill because the mock draws it that
 * way; it still gets the full [BittrTokens.Size.minTouchTarget] because it is the
 * only route into Settings in the whole app.
 *
 * It is drawn by each screen that has one rather than hoisted into a `Scaffold` at
 * the nav host. On iOS the bar belongs to `CoreViewController` and Home is a child of
 * it, which is the `Scaffold` arrangement — but the bar is on exactly one Android
 * destination today (Home), and a scaffold that exists to host one bar for one screen
 * is a layer to reason about for no benefit. When Academy lands and there are two,
 * hoisting it is a small change and this comment is the note that it is the right one.
 */
@Composable
fun BittrBottomNavBar(
    onWallet: () -> Unit,
    onAcademy: () -> Unit,
    onSettings: () -> Unit,
    modifier: Modifier = Modifier,
    selected: BittrNavTab = BittrNavTab.Wallet,
    walletTestTag: String? = null,
    academyTestTag: String? = null,
    settingsTestTag: String? = null,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm),
        modifier = modifier
            .fillMaxWidth()
            .padding(
                horizontal = BittrTokens.Spacing.md,
                vertical = BittrTokens.Spacing.sm,
            ),
    ) {
        NavTab(
            label = "Wallet",
            icon = BittrIconPaths.WALLET,
            active = selected == BittrNavTab.Wallet,
            onClick = onWallet,
            testTag = walletTestTag,
            modifier = Modifier.weight(1f),
        )
        NavTab(
            label = "Academy",
            icon = BittrIconPaths.ACADEMY,
            active = selected == BittrNavTab.Academy,
            onClick = onAcademy,
            testTag = academyTestTag,
            modifier = Modifier.weight(1f),
        )
        NavTab(
            label = null,
            icon = BittrIconPaths.SETTINGS,
            active = selected == BittrNavTab.Settings,
            onClick = onSettings,
            testTag = settingsTestTag,
            contentDescription = "Settings",
            modifier = Modifier.width(64.dp),
        )
    }
}

/** Which bottom-bar tab is lit. */
enum class BittrNavTab { Wallet, Academy, Settings }

@Composable
private fun NavTab(
    label: String?,
    icon: String,
    active: Boolean,
    onClick: () -> Unit,
    testTag: String?,
    modifier: Modifier = Modifier,
    contentDescription: String? = null,
) {
    val colors = BittrTheme.colors
    val content = if (active) colors.onCanvas else MaterialTheme.colorScheme.onSurface
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.sm, Alignment.CenterHorizontally),
        modifier = modifier
            .height(NavBarHeight)
            .background(
                if (active) colors.canvas else MaterialTheme.colorScheme.surfaceContainer,
                BittrCanvasShapes.field,
            )
            .clickable(onClick = onClick)
            .then(testTag?.let { Modifier.testTag(it) } ?: Modifier),
    ) {
        Image(
            imageVector = rememberStrokeIcon(icon, content, strokeWidth = 2f),
            contentDescription = contentDescription,
            modifier = Modifier.size(21.dp),
        )
        if (label != null) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                color = content,
            )
        }
    }
}

/**
 * The picker behind the language and currency rows — iOS's `UIAlertController`
 * action sheet, which [BittrAlertDialog] cannot be because it has three choices
 * rather than two.
 *
 * **Ordering is the opposite of the iOS sheet's and that is deliberate.** iOS puts
 * Cancel first in the `buttons:` array and UIKit floats it to the bottom of the
 * sheet; Compose has no such convention, so Cancel is drawn last, where the user
 * looking for it will be. `features/settings.yaml` selects these by *text*
 * (`tapOn: text: "CHF"`, `text: "Cancel"`) rather than by index, so the order is
 * free — unlike the two-button alerts, where `alert.button.0` pins it.
 *
 * The options carry no test ids for the same reason: on iOS they are a native alert
 * with none, and giving the Android ones ids the flow cannot use on iOS would put
 * the two platforms on different selectors for the same tap.
 */
@Composable
fun BittrChoiceDialog(
    title: String,
    message: String,
    options: List<String>,
    onSelect: (Int) -> Unit,
    onCancel: () -> Unit,
    cancelLabel: String,
    modifier: Modifier = Modifier,
) {
    val colors = BittrTheme.colors
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onCancel,
        shape = BittrCanvasShapes.card,
        containerColor = colors.tonalFill,
        titleContentColor = colors.onTonalFill,
        textContentColor = colors.onTonalFill,
        title = { Text(title, style = MaterialTheme.typography.titleMedium) },
        text = {
            Column {
                Text(message, style = MaterialTheme.typography.bodyMedium)
                CanvasSpacer(BittrTokens.Spacing.md)
                options.forEachIndexed { index, option ->
                    ChoiceRow(
                        label = option,
                        onClick = { onSelect(index) },
                        background = colors.actionFill,
                        contentColor = colors.onActionFill,
                    )
                    CanvasSpacer(BittrTokens.Spacing.xs)
                }
                ChoiceRow(
                    label = cancelLabel,
                    onClick = onCancel,
                    background = Color.Transparent,
                    contentColor = colors.onTonalFill,
                )
            }
        },
        // Material insists on a confirm slot; the choices are the buttons here, so
        // there is nothing to put in it.
        confirmButton = {},
        modifier = modifier,
    )
}

@Composable
private fun ChoiceRow(
    label: String,
    onClick: () -> Unit,
    background: Color,
    contentColor: Color,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = BittrTokens.Size.minTouchTarget)
            .background(background, BittrCanvasShapes.pill)
            .clickable(onClick = onClick),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = contentColor,
        )
    }
}

/**
 * The muted footnote a screen ends on — the Settings app-version line.
 */
@Composable
fun BittrFootnote(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Normal),
        color = BittrTheme.colors.mutedOnCanvas,
        modifier = modifier,
    )
}
