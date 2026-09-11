package com.bittr.android.core.designsystem

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * Colour, from BIT-4 `design-system` §1.1–§1.3, revision 7.
 *
 * **These are sRGB conversions, not the iOS hexes.** Thirteen of the fourteen
 * primitives in `Colors.swift` are declared in Display P3; Compose renders sRGB, so
 * the P3 numbers cannot be pasted across — they would render a duller, different
 * colour than iOS does. The values here are the P3-D65 → XYZ → sRGB conversion, and
 * six of them were checked against flat fills in the captured screenshots (§1.1a).
 * `yellow` moves `#F6C744` → `#FFC502`, `green2` `#519849` → `#319A3D`,
 * `red3` `#C78E8E` → `#D18B8D`. DEV-01.
 *
 * Two primitives are sRGB already on iOS and port byte-for-byte: [Red2] and the
 * dimmed balance pair in [BittrColors.balanceDimmed].
 *
 * **Alpha needs no special handling.** iOS composites in the device colour space; the
 * measured pixels say the app's translucent tokens match an *sRGB* blend of the
 * converted values to within 1/255 (§1.1a). So `copy(alpha = …)` on these constants
 * is correct — no pre-multiplied constants, no colour-space plumbing.
 *
 * Do not add a literal `Color(0x…)` at a call site. A colour that only exists inside
 * a composable is a colour the designer cannot change.
 */

// ---------------------------------------------------------------------------
// Primitives — §1.1. Private on purpose: call sites use the semantic layer below.
// ---------------------------------------------------------------------------

private val Yellow = Color(0xFFFFC502)
private val Blue1 = Color(0xFF3A5983)
private val Blue2 = Color(0xFF446591)
private val Blue3 = Color(0xFF547AA9)
private val Grey1 = Color(0xFFECF3F8)
private val Grey2 = Color(0xFF9CA1AD)

/**
 * `grey2` darkened at constant hue (222.4°) and saturation until it clears the 3 : 1
 * non-text floor on every neutral surface it borders — 3.61 on white, 3.52 on `grey3`,
 * 3.22 on `surface`. iOS ships `grey2` itself at **2.59 : 1** and uses it for the
 * placeholder text in the Send address field and the Swap amount field, where it falls
 * to 2.23 and 2.16. A11Y-21, DEV-58.
 */
private val Grey2Outline = Color(0xFF828791)
private val Grey3 = Color(0xFFFCFCFF)
private val Green1 = Color(0xFFE3F9E3)
private val Green2 = Color(0xFF319A3D)
private val Red1 = Color(0xFFFFECED)

/** iOS `systemRed`, declared sRGB on iOS — the one primitive that needs no conversion. DEV-02. */
private val Red2 = Color(0xFFFF3B30)
private val Red3 = Color(0xFFD18B8D)

/**
 * The fifteenth primitive. Declared inline in `Main.storyboard` on the Question
 * screen's `barView` and nowhere in `Colors.swift`, which is why four revisions of
 * this system missed it. A 6 dp × 308 dp flat fill — a real surface, not drift. §1.1.
 */
private val BarTrack = Color(0xFFC5A03A)

// ---------------------------------------------------------------------------
// Material 3 schemes — §1.3
// ---------------------------------------------------------------------------

/**
 * Light scheme.
 *
 * `yellow` is a **surface** in this app, not an accent: 56 storyboard fills against
 * 61 text uses. That is why it is `primary` *and* `primaryContainer` and why
 * `onPrimary` is black.
 */
val BittrLightColors: ColorScheme = lightColorScheme(
    primary = Yellow,
    onPrimary = Color.Black,
    primaryContainer = Yellow,
    onPrimaryContainer = Color.Black,
    surface = Grey1,
    onSurface = Color.Black,
    surfaceContainer = Color.White,
    surfaceContainerHigh = Color.White,
    surfaceBright = Grey3,
    // A11Y-01: iOS `transparentblack` is black @50 % → 3.95 : 1, a fail. 60 % → 5.74 : 1.
    // Also lifts the three escape-hatch controls on yellow from 3.63 to 4.93 (A11Y-15).
    onSurfaceVariant = Color.Black.copy(alpha = 0.60f),
    // A11Y-21 / DEV-58. **Nothing that must be perceivable on the brand yellow uses
    // `outline`** — no grey that still reads as grey clears 3 : 1 there (this one is
    // 2.27). Borders and placeholders on a yellow surface use `onSurfaceVariant`,
    // which is 4.93. Same rule A11Y-15 already set for text.
    outline = Grey2Outline,
    outlineVariant = Grey2,
    error = Red2,
    onError = Color.White,
    scrim = Color.Black,
)

/**
 * Dark scheme.
 *
 * Dark mode on iOS is not a tint of light mode — it swaps the yellow accent for the
 * blue family outright, so it is spelled out rather than derived.
 *
 * **A11Y-02 moved two slots.** iOS uses `blue3` as the dark surface; white on `blue3`
 * is 4.44 : 1, which misses AA for body text. `blue1` (7.15) and `blue2` (5.97) are
 * promoted and `blue3` demoted to `surfaceContainerHigh`, where it still clears
 * AA-large for accents. **This changes the dark-mode look — founder sign-off, BIT-15.**
 */
val BittrDarkColors: ColorScheme = darkColorScheme(
    primary = Blue1,
    onPrimary = Color.White,
    primaryContainer = Blue2,
    onPrimaryContainer = Color.White,
    surface = Blue1,
    onSurface = Color.White,
    surfaceContainer = Blue2,
    surfaceContainerHigh = Blue3,
    surfaceBright = Blue3,
    // A11Y-01: iOS is white @50 % → 2.29 : 1. 70 % only reaches 3.87 on blue2, so 80 %
    // is the floor rather than a preference — 4.50 on blue2, 5.28 on blue1.
    onSurfaceVariant = Color.White.copy(alpha = 0.80f),
    outline = Color.White.copy(alpha = 0.70f), // non-text, 3.87 on blue2 clears 1.4.11
    outlineVariant = Color.White,
    error = Red2,
    onError = Color.White,
    scrim = Blue1,
)

// ---------------------------------------------------------------------------
// The Bittr extension — §1.3. M3 has no honest slot for these.
// ---------------------------------------------------------------------------

/**
 * The tokens Material 3 cannot carry.
 *
 * `profit`/`loss` deliberately do **not** map to `tertiary`/`error`. Profit is not a
 * tertiary accent and a loss is not an error — the user has not done anything wrong,
 * and mapping loss onto `error` would inherit error's screen-reader announcements.
 * DEV-04.
 *
 * Colour alone never carries meaning here (WCAG 1.4.1): `profit`/`loss` are always
 * paired with a sign or arrow, and `unconfirmed` is always paired with an explicit
 * *"Pending"* label. A11Y-03, A11Y-04.
 */
@Immutable
data class BittrColors(
    /** `profittext`. Profit figures. Always with a `+`. */
    val profit: Color,
    /** `profitbackground`. The profit pill's fill. */
    val profitBg: Color,
    /**
     * `profitbackground0.8` — which applies **0.7** in light mode and is byte-identical
     * to [profitBg] in dark. The iOS name is wrong; renamed here rather than ported.
     * DEV-11.
     */
    val profitBgMuted: Color,
    /** `losstext`. Loss figures. Always with a `−`. */
    val loss: Color,
    /** `lossbackground`. */
    val lossBg: Color,
    /** `lossbackground0.8` — see [profitBgMuted]. DEV-11. */
    val lossBgMuted: Color,
    /**
     * `blackoryellow`, and — after DEV-47 — `whiteoryellow` too. Screen titles, alert
     * titles, Academy level headers. See the note on [BittrLightColorsExtended].
     */
    val emphasis: Color,
    /** `yellow`. The seven sites that stay brand-yellow in both modes. */
    val brandFixed: Color,
    /** `unconfirmed`. Pending transactions. Never the only signal — A11Y-03. */
    val unconfirmed: Color,
    /** `appversion`. Decorative only; it does not and cannot clear AA. */
    val footnote: Color,
    /** The insignificant leading zeros of the Home balance. §3 S-09, DEV-24. */
    val balanceDimmed: Color,
    /**
     * `white0.7orblue1`. **The fill of every amount/address input field in the wallet** —
     * Send address, Send amount, Receive amount, Receive note, and, after DEV-61, Swap
     * amount. Dark is `blue1`, which carries the placeholder at 5.28 and the typed value
     * at 7.15. A11Y-22.
     */
    val scrim1: Color,
    /** `white0.7orblue2`. */
    val scrim2: Color,
    /**
     * `white0.7orblue3`. **A card fill, not a field fill.** Dark is `blue3`, where pure
     * white — the ceiling — is 4.44, so nothing on this surface can be AA body text. Its
     * five call sites are all ≥ 14sp-bold labels (the four Receive action cards and the
     * map's *Go to maps* button), which are large text at a 3.0 floor and clear it.
     *
     * The Swap amount field used to fill with this and does not any more: its placeholder
     * and its typed value are 16sp regular, and no white-based token can carry them here.
     * A11Y-22, DEV-61 — see [scrim1].
     */
    val scrim3: Color,
    /** `transparentyellow`. */
    val scrimBrand: Color,
    /** `yelloworblue3`. */
    val primaryHigh: Color,
    /** The Question screen's channel bar track. §1.1, A11Y-14, DEV-42. */
    val barTrack: Color,
)

/**
 * Light values.
 *
 * **[emphasis] is black, and that is the whole of DEV-47.** iOS has two tokens here —
 * `whiteoryellow` (white/yellow) and `blackoryellow` (black/yellow) — differing only
 * in light mode. `whiteoryellow`'s light value is white on a yellow surface: **1.59 : 1**,
 * on 16 call sites including every screen title and all 55 alert titles (A11Y-16).
 * The two tokens merge onto the black value. Light goes to 13.24 : 1, dark is
 * byte-identical, and the theme loses a field. **Founder sign-off — BIT-15.**
 */
val BittrLightColorsExtended = BittrColors(
    profit = Green2,
    profitBg = Green1,
    profitBgMuted = Green1.copy(alpha = 0.70f),
    // A11Y-04: iOS `red3` is 2.37 : 1 on its own pill — below the 3 : 1 floor that applies
    // even to large text. Darkened at constant hue (358.3°) and saturation until it
    // matches profit's margin: 3.22 on the pill, 3.66 on white. DEV-60 — founder sign-off, BIT-15.
    loss = Color(0xFFB17678),
    lossBg = Red1,
    lossBgMuted = Red1.copy(alpha = 0.70f),
    emphasis = Color.Black,
    brandFixed = Yellow,
    unconfirmed = Color(0xFFB1B1B1),
    footnote = Color.Black.copy(alpha = 0.25f),
    balanceDimmed = Color(0xFFB08600), // darkened from iOS #C99A00 (2.59 → 3.36). DEV-24, A11Y-06.
    scrim1 = Color.White.copy(alpha = 0.70f),
    scrim2 = Color.White.copy(alpha = 0.70f),
    scrim3 = Color.White.copy(alpha = 0.70f),
    scrimBrand = Yellow.copy(alpha = 0.85f),
    primaryHigh = Yellow,
    barTrack = BarTrack,
)

/**
 * Dark values.
 *
 * Nothing here changes under DEV-47 or A11Y-04 — both fixes are light-mode-only, which
 * is what makes them cheap.
 *
 * **[scrim3] stays `blue3` — A11Y-22 / DEV-61.** Moving it to `blue2` the way A11Y-02
 * moved `surface` was the obvious reading of the Swap placeholder failure, and it is
 * wrong: the Swap amount field sits *inside* `centerCard`, which is `yelloworblue2` =
 * `blue2`, so a `blue2` fill is **1.00 : 1** against the card it lives in — the field
 * stops being visible at all. The fix is at the call site instead: the Swap field fills
 * with [scrim1] like every other field in the wallet, and `scrim3` keeps `blue3` for the
 * five card surfaces that are large text and clear their floor there.
 */
val BittrDarkColorsExtended = BittrColors(
    profit = Green1,
    profitBg = Green2.copy(alpha = 0.60f),
    profitBgMuted = Green2.copy(alpha = 0.60f),
    loss = Red1,
    lossBg = Red2.copy(alpha = 0.30f),
    lossBgMuted = Red2.copy(alpha = 0.30f),
    emphasis = Yellow,
    brandFixed = Yellow,
    unconfirmed = Color.White.copy(alpha = 0.50f),
    footnote = Color.White.copy(alpha = 0.50f),
    balanceDimmed = Color(0xFFAABED9), // sRGB on iOS; unchanged. 3.15 : 1 once A11Y-02 lands.
    scrim1 = Blue1,
    scrim2 = Blue2,
    scrim3 = Blue3,
    scrimBrand = Blue3.copy(alpha = 0.85f),
    primaryHigh = Blue3,
    barTrack = BarTrack,
)

/**
 * Read with `BittrTheme.colors`. Defaults to light so a preview that forgets
 * [BittrTheme] renders in brand rather than throwing.
 */
val LocalBittrColors = staticCompositionLocalOf { BittrLightColorsExtended }
