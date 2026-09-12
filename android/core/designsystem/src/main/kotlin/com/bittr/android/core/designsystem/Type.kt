package com.bittr.android.core.designsystem

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Typography, from BIT-4 `design-system` §1.4.
 *
 * **Two weights, nothing between.** `UIAppFonts` registers Gilroy-Regular and
 * Gilroy-Bold only — the app has no medium or semibold and never had one. Do not
 * substitute a variable font to fill the gap; it will not match.
 *
 * Four other `.ttf` files ship in the IPA and are never loaded (Syne, both
 * Montserrats, Palanquin — the last has no file reference in the Xcode project at
 * all). They are not ported. DEV-25.
 *
 * **Every size in the app comes from this scale.** A hard-coded `.sp` at a call site
 * breaks dynamic type, which is in scope for this port.
 */

/** The only font family in the app. */
val Gilroy = FontFamily(
    Font(R.font.gilroy_regular, FontWeight.Normal),
    Font(R.font.gilroy_bold, FontWeight.Bold),
)

/**
 * The scale, sized by storyboard frequency across 287 `fontDescription` nodes.
 *
 * Line heights are **new** — the iOS storyboard sets none and rides Gilroy's natural
 * leading. Compose needs them explicit or dynamic type collapses the lines into each
 * other. The 1.4–1.5× ratios here are the Android reading default. DEV-06.
 *
 * Sizes 15 and 17 are merged into 16 and 18 (18 uses against 119 at 16 — drift, not
 * intent). DEV-05.
 *
 * **Three slots carry both weights.** M3 has one `TextStyle` per slot and the app has
 * two weights at 14, 16 and 18, so the less common weight is a `copy` at the call
 * site — spelled out here so it is a convention rather than an improvisation:
 *
 * | You want | Use |
 * |---|---|
 * | Bold 16 — row titles, values, buttons (119 uses, the workhorse) | [Typography.labelLarge] |
 * | Regular 16 — body copy | [Typography.bodyLarge] |
 * | Bold 14 — secondary buttons, chips | `bodyMedium.copy(fontWeight = FontWeight.Bold)` |
 * | Regular 14 — helper text | [Typography.bodyMedium] |
 * | Bold 18 — section headers, screen titles, alert titles | [Typography.titleMedium] |
 * | Regular 18 — screen intro copy | `titleMedium.copy(fontWeight = FontWeight.Normal)` |
 */
val BittrTypography = Typography(
    /**
     * The Home balance. Gilroy-Bold at a 40pt base, set in code
     * (`LoadWalletData.swift:278`), not in the storyboard — the storyboard's
     * `Syne-Regular 38` on that label is overwritten before it is ever visible.
     * Shrinks to fit; the floor is 20sp, not iOS's 16 (DEV-23, A11Y-06).
     */
    displayMedium = TextStyle(
        fontFamily = Gilroy, fontWeight = FontWeight.Bold,
        fontSize = 40.sp, lineHeight = 48.sp,
    ),
    /** Hero amounts. */
    displaySmall = TextStyle(
        fontFamily = Gilroy, fontWeight = FontWeight.Bold,
        fontSize = 36.sp, lineHeight = 40.sp,
    ),
    /** Screen titles (10 uses). */
    headlineSmall = TextStyle(
        fontFamily = Gilroy, fontWeight = FontWeight.Bold,
        fontSize = 26.sp, lineHeight = 32.sp,
    ),
    /**
     * Move / Receive totals — the doc's `headlineXSmall`. Mapped onto `titleLarge`
     * because M3's own default for that slot is already 22sp, so this costs no
     * custom token.
     */
    titleLarge = TextStyle(
        fontFamily = Gilroy, fontWeight = FontWeight.Bold,
        fontSize = 22.sp, lineHeight = 28.sp,
    ),
    /**
     * Section headers — **and the screen title in `addHeader`, and every one of the 55
     * alert titles.** At Gilroy-Bold 18 these are large text, which is why A11Y-16's
     * floor is 3 : 1 rather than 4.5. They still missed it at 1.59; see DEV-47.
     */
    titleMedium = TextStyle(
        fontFamily = Gilroy, fontWeight = FontWeight.Bold,
        fontSize = 18.sp, lineHeight = 26.sp,
    ),
    /** Body copy. */
    bodyLarge = TextStyle(
        fontFamily = Gilroy, fontWeight = FontWeight.Normal,
        fontSize = 16.sp, lineHeight = 24.sp,
    ),
    /** Helper text. */
    bodyMedium = TextStyle(
        fontFamily = Gilroy, fontWeight = FontWeight.Normal,
        fontSize = 14.sp, lineHeight = 20.sp,
    ),
    /** The bold-16 workhorse: button labels, row titles, values. */
    labelLarge = TextStyle(
        fontFamily = Gilroy, fontWeight = FontWeight.Bold,
        fontSize = 16.sp, lineHeight = 24.sp,
    ),
    /** Captions and footnotes. */
    labelMedium = TextStyle(
        fontFamily = Gilroy, fontWeight = FontWeight.Normal,
        fontSize = 13.sp, lineHeight = 18.sp,
    ),
)
