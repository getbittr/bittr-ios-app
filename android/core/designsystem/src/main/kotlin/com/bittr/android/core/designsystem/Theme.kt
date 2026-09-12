package com.bittr.android.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable

/**
 * The Bittr Compose theme.
 *
 * Carries BIT-4 `design-system` revision 7: colour (§1.1–§1.3), typography (§1.4),
 * spacing (§1.5), shape (§1.6) and elevation (§1.7). The document is the spec; this
 * is the transcription of it, and where the two disagree the document wins.
 *
 * **Deliberately not Material You.** This is a brand-led financial app whose iOS side
 * ships a fixed palette; letting the wallpaper pick the accent would break parity on
 * the first screenshot comparison. Dynamic colour is not a default we are declining
 * to override — it is a design decision, made here, against the port.
 *
 * **Dark mode follows the system, and the in-app toggle overrides it.** iOS gates dark
 * mode on `CacheManager.darkModeIsOn()` alone and ignores the system setting. Android
 * users expect `isSystemInDarkTheme()`; ignoring it is a bug report waiting to happen.
 * Keeping the toggle preserves the Device screen's `Darkmode dark` / `Darkmode light`
 * states and the Maestro flow that walks them. DEV-03 — **founder sign-off, BIT-15**.
 *
 * ### Reading the custom tokens
 *
 * Material's slots carry what Material can carry honestly. Everything else — profit,
 * loss, the 70 % scrims, the merged emphasis token — is on [BittrTheme.colors]:
 *
 * ```kotlin
 * Text(
 *     text = "+ 2.4 %",
 *     color = BittrTheme.colors.profit,
 *     style = MaterialTheme.typography.labelLarge,
 * )
 * ```
 *
 * @param darkTheme system dark mode by default. Pass the user's stored preference here
 *   when the Settings toggle is wired up; do not read it inside this function.
 */
@Composable
fun BittrTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val extended = if (darkTheme) BittrDarkColorsExtended else BittrLightColorsExtended
    CompositionLocalProvider(LocalBittrColors provides extended) {
        MaterialTheme(
            colorScheme = if (darkTheme) BittrDarkColors else BittrLightColors,
            typography = BittrTypography,
            shapes = BittrShapes,
            content = content,
        )
    }
}

/**
 * Accessor for the tokens Material 3 has no slot for. See [BittrColors].
 */
object BittrTheme {
    val colors: BittrColors
        @Composable @ReadOnlyComposable
        get() = LocalBittrColors.current
}
