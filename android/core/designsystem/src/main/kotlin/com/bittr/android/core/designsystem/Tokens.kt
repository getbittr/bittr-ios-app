package com.bittr.android.core.designsystem

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Raw design tokens.
 *
 * **Provenance:** transcribed from `ios/bittr/Colors.swift` so the scaffold renders
 * in Bittr's actual brand rather than Compose's default purple. These are the iOS
 * values, not an Android design system.
 *
 * **This file is the handover point for BIT-4.** When the Mobile Product Designer's
 * token set lands, it replaces the values here and nothing else changes — [BittrTheme]
 * and every call site read through these names. Add tokens rather than hardcoding a
 * literal at a call site; a colour that appears in a composable is a colour the
 * designer cannot change.
 *
 * Caveat worth knowing before trusting these: iOS declares most of them in
 * displayP3. Compose colours are sRGB, so these are the same component values in a
 * narrower space — near-identical on screen, not colorimetrically equal. Where exact
 * match matters, BIT-4 should specify the Android value directly.
 */
object BittrTokens {

    object Palette {
        // General
        val Yellow = Color(0xFFF6C744)
        val Black = Color(0xFF000000)
        val White = Color(0xFFFFFFFF)

        // Blues — the dark-mode accent family on iOS
        val Blue1 = Color(0xFF415880)
        val Blue2 = Color(0xFF4B648D)
        val Blue3 = Color(0xFF5C79A5)

        // Greys
        val Grey1 = Color(0xFFEDF3F7)
        val Grey2 = Color(0xFF9DA1AC)
        val Grey3 = Color(0xFFFCFCFF)

        // Profit
        val Green1 = Color(0xFFE7F8E5)
        val Green2 = Color(0xFF519849)

        // Loss
        val Red1 = Color(0xFFFFEDED)
        val Red2 = Color(0xFFFF3B30)
        val Red3 = Color(0xFFC78E8E)
    }

    /**
     * Spacing scale. Placeholder 4dp grid — BIT-4 confirms or replaces it.
     * Material 3 components bring their own internal padding; this is for layout
     * between them.
     */
    object Spacing {
        val xs = 4.dp
        val sm = 8.dp
        val md = 16.dp
        val lg = 24.dp
        val xl = 32.dp
    }
}
