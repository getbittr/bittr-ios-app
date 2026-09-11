package com.bittr.android.core.designsystem

import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Spacing, elevation and the layout minimums, from BIT-4 `design-system` §1.5 and §1.7.
 *
 * Colour lives in [BittrColors] and the two `ColorScheme`s; type in [BittrTypography];
 * shape in [BittrShapes]. This file is what is left over — the numbers that are not a
 * Material slot.
 */
object BittrTokens {

    /**
     * The layout scale. **It is a 5dp grid, not Material's 4dp one** — measured across
     * 4,199 storyboard constraints, where the clusters land on 5, 10, 15, 20, 25, 30
     * and 40 rather than 4, 8, 16, 24.
     *
     * | Token | Value | Evidence |
     * |---|---|---|
     * | [xxs] | 2dp | 21× |
     * | [xs] | 5dp | 12× |
     * | [sm] | 10dp | 153× height, 207 + 112× margin — the base unit |
     * | [md] | 15dp | 207× leading/trailing — **the screen gutter** |
     * | [lg] | 20dp | 54× |
     * | [xl] | 25dp | 23× |
     * | [xxl] | 30dp | 46× |
     * | [section] | 40dp | 36× |
     *
     * Material's default gutter is 16dp. Keeping 15 preserves the port's fidelity and
     * costs nothing — DEV-07 records that as a decision rather than an oversight.
     */
    object Spacing {
        val xxs = 2.dp
        val xs = 5.dp
        val sm = 10.dp
        val md = 15.dp
        val lg = 20.dp
        val xl = 25.dp
        val xxl = 30.dp
        val section = 40.dp

        /** The screen gutter. Same value as [md]; named so call sites read as intent. */
        val gutter = 15.dp
    }

    /**
     * Elevation.
     *
     * The iOS app has exactly **one** shadow — `UIView.setShadow()`, black at
     * offset (0, 7), radius 10, opacity 0.10. An offset-heavy, low-opacity, wide-blur
     * shadow is an iOS idiom; Material 3 uses tonal elevation plus a much tighter
     * shadow. [level3] is the closest honest match. Anything higher over-darkens
     * against `surface`.
     *
     * In dark mode iOS keeps the same black shadow, which is invisible against `blue1`.
     * Do not compensate with a bigger shadow — `surfaceContainer` (`blue2`) already
     * reads as raised against `surface` (`blue1`), which is how Material carries
     * dark-mode elevation. DEV-08.
     */
    object Elevation {
        val level0 = 0.dp
        val level1 = 1.dp

        /** The `setShadow()` equivalent — cards, the balance card, page sheets. */
        val level3 = 6.dp

        /** Bottom sheets and dialogs. */
        val level4 = 8.dp
    }

    /**
     * Minimum sizes that are accessibility requirements, not style.
     *
     * iOS ships below [minTouchTarget] in several places and the port does not inherit
     * it: the Receive action row is 35 dp (A11Y-07), settings rows are 45 dp (A11Y-08),
     * and 55 storyboard constraints sit at 45 (DEV-10). Every one of those had the
     * space to grow.
     */
    object Size {
        /** WCAG 2.5.8 / Material's minimum. */
        val minTouchTarget = 48.dp

        /**
         * The floor the Home balance shrinks to. iOS uses 16pt; at 16 the label leaves
         * the large-text band and the contrast bar on the dimmed digits jumps from 3:1
         * to 4.5:1, which no longer reads as *dimmed* at all. 20sp is what keeps the
         * two-tone balance intact. DEV-23, A11Y-06.
         */
        val balanceMinTextSize = 20.sp
    }
}
