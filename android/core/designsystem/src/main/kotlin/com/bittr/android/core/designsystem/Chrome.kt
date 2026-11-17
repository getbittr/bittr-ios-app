package com.bittr.android.core.designsystem

import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.runtime.getValue
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.CircleShape
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
private val RowHeight = 64.dp
/** The menu plates: 45 pt, and the Settings plate as wide as it is tall. */
private val NavBarHeight = 45.dp

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
                // Round, so the press and focus layer is the proposal's circle rather than
                // a grey square (review S10).
                .clip(CircleShape)
                .clickable(role = Role.Button, onClick = onDown)
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
    iconFilled: Boolean = false,
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
            // Gold glyph and a bold label, as the proposal draws a settings row (review,
            // pass 3). Gold is `rowLabel`, the darkened one that holds 5 : 1 on the white row
            // — the raw iOS `#F8C744` measured 1.6 : 1, which is why these were ink before.
            Image(
                imageVector = if (iconFilled) {
                    rememberFillIcon(icon, BittrTheme.colors.rowLabel)
                } else {
                    rememberStrokeIcon(icon, BittrTheme.colors.rowLabel, strokeWidth = 1.9f)
                },
                contentDescription = null,
                modifier = Modifier.size(24.dp),
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
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
 * iOS's `addHeader(iconLight:iconDark:title:)` — the header of the pop-ups and sheets over the
 * canvas (Settings, a lesson): 58 tall, the 18 pt icon 20 in, the title lower-cased in Gilroy
 * Bold 18 10 after it, and `downarrow32`, 20 pt, 20 from the end — all white, yellow in dark
 * (`whiteoryellow`).
 *
 * @param icon the header's icon as drawn; it is tinted to the header's colour.
 */
@Composable
fun BittrSheetHeader(
    icon: Painter,
    title: String,
    onDown: () -> Unit,
    modifier: Modifier = Modifier,
    titleTestTag: String? = null,
    downTestTag: String? = null,
) {
    val tint = BittrTheme.colors.homeCardTitle
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .height(58.dp)
            .padding(start = 20.dp),
    ) {
        Image(
            painter = icon,
            contentDescription = null,
            colorFilter = ColorFilter.tint(tint),
            modifier = Modifier.size(18.dp),
        )
        Text(
            text = title.lowercase(),
            style = MaterialTheme.typography.titleMedium.copy(fontSize = 18.sp, lineHeight = 18.sp),
            color = tint,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .padding(start = 10.dp)
                .offset(y = 1.dp)
                .then(titleTestTag?.let { Modifier.testTag(it) } ?: Modifier),
        )
        // The 20 pt chevron 20 from the end, in a 48 dp target.
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .padding(end = 6.dp)
                .size(48.dp)
                .clickable(role = Role.Button, onClick = onDown)
                .then(downTestTag?.let { Modifier.testTag(it) } ?: Modifier),
        ) {
            Image(
                painter = painterResource(R.drawable.bittr_down_chevron),
                contentDescription = "Close",
                colorFilter = ColorFilter.tint(tint),
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

/**
 * The bottom bar — `CoreViewController`'s menu bar: Wallet and Academy as two labelled plates
 * sharing the width, and Settings as a square plate with its icon alone.
 *
 * As the storyboard has it: 15 from the screen's sides, the plates 45 tall, 10 apart and ending at
 * the bottom of the safe area; each `grey3orblue1` with 8 pt corners and `setShadow()`, with iOS's
 * black-or-white icons (`menuwalletblack` …) and a dark grey label, white in dark. Labels in Gilroy
 * Bold 14, 8 after the icon — wallet 13 pt, academy 16, settings 15.
 *
 * The selection is `selectedView`: one brand-yellow plate that slides between Wallet and Academy
 * in 0.3 s ease-in-out as [selected] changes, in step with the pages sliding above it. It reveals
 * the plates' white icons and labels as it passes over them, which is how iOS masks its white
 * copies with it. Settings opens a pop-up rather than a page, so it is never the one selected.
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
    val colors = BittrTheme.colors
    val dark = BittrTheme.isDark
    val walletIcon = if (dark) R.drawable.menu_wallet_white else R.drawable.menu_wallet_black
    val academyIcon = if (dark) R.drawable.menu_academy_white else R.drawable.menu_academy_black
    val progress by animateFloatAsState(
        targetValue = if (selected == BittrNavTab.Academy) 1f else 0f,
        animationSpec = MenuSlideSpec,
        label = "menuSelection",
    )
    Row(
        horizontalArrangement = Arrangement.spacedBy(MenuGap),
        modifier = modifier
            .fillMaxWidth()
            .padding(start = 15.dp, end = 15.dp, top = 10.dp),
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .weight(1f)
                .height(NavBarHeight),
        ) {
            val rowWidth = maxWidth
            val plateWidth = (rowWidth - MenuGap) / 2
            val selectionX = (plateWidth + MenuGap) * progress
            Row(horizontalArrangement = Arrangement.spacedBy(MenuGap), modifier = Modifier.fillMaxSize()) {
                NavPlate(onClick = onWallet, testTag = walletTestTag, modifier = Modifier.weight(1f)) {
                    NavTabContent("Wallet", walletIcon, 13.dp, iconTint = null, labelColor = colors.menuLabel)
                }
                NavPlate(onClick = onAcademy, testTag = academyTestTag, modifier = Modifier.weight(1f)) {
                    NavTabContent("Academy", academyIcon, 16.dp, iconTint = null, labelColor = colors.menuLabel)
                }
            }
            // `selectedView`, over the plates: the white copies are laid out exactly as the plates
            // are and shifted against the selection, so only what lies under it shows.
            Box(
                modifier = Modifier
                    .offset(x = selectionX)
                    .width(plateWidth)
                    .fillMaxHeight()
                    .clip(NavTabShape)
                    .background(colors.brandFixed)
                    .clearAndSetSemantics {},
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(MenuGap),
                    modifier = Modifier
                        .wrapContentWidth(Alignment.Start, unbounded = true)
                        .width(rowWidth)
                        .fillMaxHeight()
                        .offset(x = -selectionX),
                ) {
                    NavTabContent("Wallet", walletIcon, 13.dp, iconTint = Color.White, labelColor = Color.White, Modifier.weight(1f))
                    NavTabContent("Academy", academyIcon, 16.dp, iconTint = Color.White, labelColor = Color.White, Modifier.weight(1f))
                }
            }
        }
        NavPlate(
            onClick = onSettings,
            testTag = settingsTestTag,
            modifier = Modifier
                .width(NavBarHeight)
                .height(NavBarHeight),
        ) {
            Image(
                painter = painterResource(if (dark) R.drawable.menu_settings_white else R.drawable.menu_settings_black),
                contentDescription = "Settings",
                modifier = Modifier.size(15.dp),
            )
        }
    }
}

/** Which bottom-bar tab is lit. */
enum class BittrNavTab { Wallet, Academy, Settings }

/**
 * The selection's slide between Wallet and Academy, and the pages' above it — shared so the two
 * move as one. iOS's `menuButtonTapped` is a plain 0.3 s ease-in-out; this is a spring with a
 * little bounce, as the other page slides in the app have (Tom, 2026-09-29): damping 0.75,
 * settling in about 0.5 s by [PageSlideSpec]'s rule.
 */
val MenuSlideSpec: AnimationSpec<Float> = spring(dampingRatio = 0.75f, stiffness = 110f)

private val MenuGap = 10.dp

/** One menu plate: `grey3orblue1`, 8 pt corners, `setShadow()`, its content centred. */
@Composable
private fun NavPlate(
    onClick: () -> Unit,
    testTag: String?,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .fillMaxHeight()
            .iosShadow(NavTabShape)
            // Clipped before `clickable`, or the press layer is a square behind the plate —
            // the same rule BittrPrimaryButton states.
            .clip(NavTabShape)
            .background(BittrTheme.colors.homeBackground)
            .clickable(role = Role.Button, onClick = onClick)
            .then(testTag?.let { Modifier.testTag(it) } ?: Modifier),
    ) {
        content()
    }
}

/** A plate's icon and label, centred: the icon, 8, the label 1 pt below the icon's centre. */
@Composable
private fun NavTabContent(
    label: String,
    icon: Int,
    iconSize: Dp,
    iconTint: Color?,
    labelColor: Color,
    modifier: Modifier = Modifier,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        modifier = modifier.fillMaxHeight(),
    ) {
        Image(
            painter = painterResource(icon),
            contentDescription = null,
            colorFilter = iconTint?.let { ColorFilter.tint(it) },
            modifier = Modifier.size(iconSize),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.sp, lineHeight = 14.sp),
            color = labelColor,
            modifier = Modifier.offset(y = 1.dp),
        )
    }
}

private val NavTabShape = RoundedCornerShape(8.dp)

/**
 * The picker behind the language and currency rows — `DeviceViewController`'s `showAlert` with
 * Cancel first and a button per choice, so [BittrAlert]'s card: Cancel and one choice side by
 * side, or stacked with Cancel at the bottom once there are more. Cancel is `alert.button.0` and
 * the choices follow it; `features/settings.yaml` selects them by text, which is the same on both
 * platforms.
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
    BittrAlert(
        title = title,
        message = message,
        buttons = listOf(BittrAlertButton(label = cancelLabel, dismissesAlert = true, onClick = onCancel)) +
            options.mapIndexed { index, option -> BittrAlertButton(label = option, onClick = { onSelect(index) }) },
        modifier = modifier,
    )
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
