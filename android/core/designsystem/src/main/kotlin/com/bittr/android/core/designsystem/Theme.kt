package com.bittr.android.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import com.bittr.android.core.designsystem.BittrTokens.Palette

/**
 * Light scheme. On iOS, light mode is yellow-accented on white.
 */
private val BittrLightColorScheme = lightColorScheme(
    primary = Palette.Yellow,
    onPrimary = Palette.Black,
    primaryContainer = Palette.Yellow,
    onPrimaryContainer = Palette.Black,
    secondary = Palette.Blue1,
    onSecondary = Palette.White,
    background = Palette.White,
    onBackground = Palette.Black,
    surface = Palette.Grey3,
    onSurface = Palette.Black,
    surfaceVariant = Palette.Grey1,
    onSurfaceVariant = Palette.Blue1,
    outline = Palette.Grey2,
    error = Palette.Red2,
    onError = Palette.White,
    errorContainer = Palette.Red1,
    onErrorContainer = Palette.Black,
)

/**
 * Dark scheme. On iOS, dark mode swaps the yellow accent for the blue family
 * (`yelloworblue1/2/3` in Colors.swift) — that swap is the brand's dark identity,
 * not a tint of the light theme, so it is spelled out rather than derived.
 */
private val BittrDarkColorScheme = darkColorScheme(
    primary = Palette.Blue3,
    onPrimary = Palette.White,
    primaryContainer = Palette.Blue1,
    onPrimaryContainer = Palette.White,
    secondary = Palette.Yellow,
    onSecondary = Palette.Black,
    background = Palette.Black,
    onBackground = Palette.White,
    surface = Palette.Blue1,
    onSurface = Palette.White,
    surfaceVariant = Palette.Blue2,
    onSurfaceVariant = Palette.White,
    outline = Palette.Grey2,
    error = Palette.Red2,
    onError = Palette.White,
    errorContainer = Palette.Red3,
    onErrorContainer = Palette.White,
)

/**
 * App theme.
 *
 * Deliberately **not** using Material You dynamic colour: this is a brand-led
 * financial app and the iOS side has a fixed palette, so letting the wallpaper
 * pick the accent would break parity. If BIT-4 wants dynamic colour it is a
 * design decision, made there.
 *
 * Typography is Material 3's default for now — the iOS app ships Gilroy,
 * Montserrat, Palanquin and Syne (the `.ttf` files at the root of `ios/`), and
 * which of those come across is BIT-4's call, not a scaffold default.
 */
@Composable
fun BittrTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) BittrDarkColorScheme else BittrLightColorScheme,
        content = content,
    )
}
