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

/**
 * The two primitives the Android design canvas adds, and the only two.
 *
 * They come from `workspaces/…/design/screens.jsx` — the Material 3 adaptation of the
 * arc, which is a design in its own right rather than a transcription of the
 * storyboard, so its values cannot be derived from `Colors.swift`.
 *
 * [Ink] is the canvas's near-black: the fill of every primary pill button, and the
 * content colour on the brand yellow. It is 5 % off `Color.Black` and that is the
 * point — a pure black pill on a saturated yellow reads as a hole.
 *
 * [Cream] is the tonal container: PIN cells, secondary buttons, editorial chips. It is
 * yellow desaturated far enough to sit *on* yellow and still be seen (1.27 : 1 is not
 * a contrast claim — these are fills that carry their own content, never a border that
 * has to be perceived against the canvas).
 */
private val Ink = Color(0xFF0D0D0D)
private val Cream = Color(0xFFF8EEC6)

/**
 * The mock's `switchAccent`, `#1F8A5B` — a green that is neither the profit green nor
 * the brand. The "on" state of the consent toggle, and nothing else.
 *
 * **It used to be a `private val` in `Canvas.kt`, and BIT-95 is what that cost.** The
 * reasoning was that a colour used by one control belongs beside that control — but the
 * rule at the top of this file is the one that applies: *a colour that only exists
 * inside a composable is a colour the designer cannot change*, and it is also a colour
 * `TokenContrastTest` cannot measure. It shipped at **1.65 : 1 against the dark canvas
 * and 1.32 : 1 against the card the switch is actually on** for exactly as long as it
 * was invisible to the guard. Both schemes hold the same value today, which is a fact
 * worth being able to see rather than a field worth saving.
 */
private val SwitchAccent = Color(0xFF1F8A5B)

// ---------------------------------------------------------------------------
// Material 3 schemes — §1.3
// ---------------------------------------------------------------------------

/**
 * Light scheme.
 *
 * `yellow` is a **surface** in this app, not an accent: 56 storyboard fills against
 * 61 text uses. That is why it is `primary` *and* `primaryContainer` and why
 * `onPrimary` is black.
 *
 * **So a filled Material `Button` is wrong in light mode and always was.** It would
 * paint itself `primary`, which here is 1.42 : 1 against `surface` — the brand colour
 * against the brand page. That is not a bug to fix by moving `primary`; moving it
 * would unpick the 56 fills and every test that measures against it. It is a rule:
 * the primary call to action on this canvas is [BittrColors.actionFill], which
 * [BittrPrimaryButton] paints, at 17.35 : 1. Dark mode had the same collision at
 * 1.00 : 1 and could be fixed in the slot, so it was — see [BittrDarkColors].
 * `TokenContrastTest` holds both halves of that. BIT-94.
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
 *
 * **A11Y-22 moved `primary` off `surface`.** A11Y-02 promoted `blue1` into `surface`
 * while `primary` was already `blue1`, so the two slots collided at **1.00 : 1** and
 * every Material control that paints itself `primary` — a filled `Button`, a `Switch`
 * track, a `Slider`, a focused `TextField`'s indicator — became the page it sits on.
 * The label still rendered, so a button read as floating text rather than as a control,
 * which is exactly the failure WCAG 1.4.11 is about. The two schemes are asymmetric
 * here and that is the point: see [BittrLightColors] for why `primary` is a *surface*
 * in light mode and cannot be moved there. BIT-94.
 */
val BittrDarkColors: ColorScheme = darkColorScheme(
    // A11Y-22. Not a new colour and not a new decision: this is the value
    // [BittrDarkColorsExtended]'s `actionFill` already carries, for the same reason and
    // with the same numbers (6.38 : 1 on `surface`, and a 17.35 : 1 ink label). The
    // dark primary action had already inverted to `grey1` on the canvas; this is the
    // Material slot catching up, so the two cannot drift apart. `TokenContrastTest`
    // asserts they stay equal. BIT-94.
    primary = Grey1,
    onPrimary = Ink,
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
    /**
     * The `DetailRow` label — the **key half only** of a key/value row. The value half is
     * already `blackorwhite` on iOS and ports to the scheme's `onSurface`.
     *
     * iOS draws the key in the brand yellow, which is **1.59 : 1 on white**: the app's
     * worst contrast failure, on the screens where a user reads back an address, an
     * amount or a deposit code before acting on it.
     *
     * Read the provenance before you go looking for it in the source — it is **not** a
     * `Colors.getColor` token. It is a static Display-P3 literal in `Main.storyboard`
     * (`red="0.9647" green="0.7804" blue="0.2667"`, i.e. `#FFC502` in sRGB), so it does
     * not switch on dark mode: it is yellow in *both*, and in light mode it sits on the
     * white card. **61 labels carry it** — 49 with outlets plus the 12 Academy step
     * digits — and only three are ever recoloured in code (`labelRegular`/`labelInstant`
     * to `blackorwhite`, `profitLabel` to profit/loss). **46 outlet-bound labels ship the
     * yellow**, 39 of them on Swap status, Transaction detail, Confirm send, Buy and
     * Transfer4. Grepping `Colors.swift` finds none of this and turns up only the value
     * halves, which look fine — that is the trap.
     *
     * **Not** Settings › Device details: `DeviceTableViewCell.swift:117-118` gives those
     * rows their own contract (`blackorwhite`, 21.00 : 1 light / 5.97 : 1 dark) and they
     * stay on `onSurface`. This token would lower both. Logged as an exclusion on BIT-4.
     *
     * Not [brandFixed] and not [emphasis]: this is body text that owes AA, so it takes
     * its own token rather than borrowing one whose floor is 3 : 1. Both values stay
     * recognisably in the brand hue — the light one is the yellow itself darkened at
     * constant hue (46.2° → 46.1°). **DEV-40 — founder sign-off, BIT-15 §A3.**
     */
    val rowLabel: Color,
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

    // -----------------------------------------------------------------------
    // The Android design canvas — `design/screens.jsx`, the onboarding artboards.
    //
    // Material has no slot for "the screen is the brand colour and the button is
    // the ink". Yellow is already `primary` *and* `primaryContainer` because it is
    // a surface (see [BittrLightColors]); if the pill button also took `primary`
    // it would be invisible. So the canvas's four roles are named here instead.
    // -----------------------------------------------------------------------

    /** The full-bleed screen background the onboarding arc is drawn on. */
    val canvas: Color,
    /** Primary content on [canvas] — headings, body copy, icons. */
    val onCanvas: Color,
    /**
     * Secondary content on [canvas] and on [cardWash] — the text-button labels.
     *
     * **70 %, where the mock says 42 % and `onSurfaceVariant` says 60 %.** 42 % is
     * 2.4 : 1 and fails outright. 60 % is the value A11Y-01 measured *against the
     * yellow itself* (4.95 : 1) — but these labels sit inside the card, where the
     * white wash lifts the background and drops the same ink to 3.51 : 1. 70 % is
     * what clears AA on both: 4.88 : 1 on the card, 6.83 : 1 on the bare canvas.
     */
    val mutedOnCanvas: Color,
    /**
     * The card fill over [canvas] — white at 9 %, straight from the mock.
     *
     * Translucent on purpose: it is the canvas, lifted, not a second surface. Do not
     * substitute `surfaceContainer` here; white-on-yellow is a different design.
     */
    val cardWash: Color,
    /** The primary pill button's fill. */
    val actionFill: Color,
    /** The primary pill button's label. */
    val onActionFill: Color,
    /**
     * The primary pill when its precondition is not met — the mock's `dim` state.
     *
     * A dimmed fill rather than Material's disabled treatment, because on this canvas
     * Material's `onSurface @ 12 %` is a pale yellow smear. Translucent, so it
     * composites over whatever canvas it lands on. [onActionFill] on it is 4.64 : 1
     * light, 5.44 : 1 dark.
     */
    val actionFillDisabled: Color,
    /** The tonal container — PIN cells, secondary buttons. The mock's cream. */
    val tonalFill: Color,
    /** Content on [tonalFill]. */
    val onTonalFill: Color,
    /**
     * The checked consent switch's track — the mock's `switchAccent`.
     *
     * **This fill does not carry the control's boundary, and in dark mode it cannot.**
     * It is 1.65 : 1 on the dark canvas and 1.32 : 1 on the card the switch is really
     * drawn on. The reason that is not fixed by darkening or swapping the green is
     * arithmetic rather than taste: a track clearing 3 : 1 against the dark card needs a
     * relative luminance of at least 0.501, and a track keeping a **white** thumb at
     * 3 : 1 cannot exceed 0.300. The band is empty — no green, and no colour of any hue,
     * satisfies both. A fill-only fix therefore means an ink thumb on a pale track,
     * which is a different control from the one the mock draws.
     *
     * So the boundary is carried by the border instead — [mutedOnCanvas], which is what
     * the *unchecked* state already used and which clears 3 : 1 in both schemes on both
     * backgrounds. The outline then stays put across the state change and the fill and
     * the thumb position are what move, which is what a switch is supposed to look like.
     *
     * [mutedOnCanvas] is translucent and Material strokes the border inside the track, so
     * the rendered border is it composited over this green. Sampled off the card in
     * `arc-2-confirm-on*.png`: `#133225` on `#FFCA19` — **9.08 : 1** light, `#DEEEE7` on
     * `#4C688E` — **4.76 : 1** dark, against 1.32 : 1 for the bare fill it replaces.
     * `TokenContrastTest` holds all of it, including the empty band. BIT-95.
     */
    val switchOn: Color,
    /**
     * The checked switch's thumb. White, from the mock — 4.33 : 1 on [switchOn], which is
     * the pair that says where the thumb is within its travel.
     */
    val onSwitchOn: Color,
    /**
     * The open arc of the bittr mark, which is the one part of the logo that is not
     * ink. The shipped SVG draws it `#FDBE10` for a white page; on the brand canvas
     * the mock draws it white, because brand-on-brand would disappear. See [BittrLogo].
     */
    val canvasArc: Color,
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
    rowLabel = Color(0xFF8A6A00), // 5.07 : 1 on white. DEV-40 — founder sign-off, BIT-15.
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
    // The canvas *is* the brand yellow — the mock's `#FFC107` is Material amber and
    // sits in a tweak panel beside three alternates, so it reads as a placeholder for
    // the real one. `Yellow` here is the sRGB conversion of the iOS asset-catalogue
    // Display P3 value, signed off as DEV-01.
    canvas = Yellow,
    onCanvas = Ink,
    mutedOnCanvas = Ink.copy(alpha = 0.70f),
    cardWash = Color.White.copy(alpha = 0.09f),
    actionFill = Ink,
    onActionFill = Color.White,
    actionFillDisabled = Ink.copy(alpha = 0.45f),
    tonalFill = Cream,
    onTonalFill = Ink,
    switchOn = SwitchAccent,
    onSwitchOn = Color.White,
    canvasArc = Color.White,
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
    rowLabel = Color(0xFFFFE28A), // 4.69 : 1 on blue2. DEV-40 — founder sign-off, BIT-15.
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
    // The mock has no dark artboards. Dark mode on this app is not a tint of light
    // mode — it swaps the yellow family for the blue one — so the canvas tokens
    // follow the same swap the schemes already make, rather than being invented.
    //
    // [actionFill] is the one that cannot be mechanical: ink-on-blue1 is 2.98 : 1,
    // under the 3 : 1 floor a button's own edge has to clear (WCAG 1.4.11), so the
    // pill inverts instead — grey1 on blue1 is 6.12 : 1 and its ink label 16.3 : 1.
    canvas = Blue1,
    onCanvas = Color.White,
    mutedOnCanvas = Color.White.copy(alpha = 0.85f),
    cardWash = Color.White.copy(alpha = 0.09f),
    actionFill = Grey1,
    onActionFill = Ink,
    actionFillDisabled = Color.White.copy(alpha = 0.30f),
    tonalFill = Blue3,
    onTonalFill = Color.White,
    // Not swapped for the blue family, unlike `actionFill`. Green means "yes, I
    // understand" on a consent control; there is no blue that says that. It is allowed
    // to stay because it is not what makes the control perceivable — see [switchOn].
    switchOn = SwitchAccent,
    onSwitchOn = Color.White,
    // White would vanish into the ink strokes beside it on a blue canvas; the brand
    // yellow is the one colour that reads on both, and dark mode keeps exactly seven
    // brand-yellow sites already (see `brandFixed`). This is the eighth.
    canvasArc = Yellow,
)

/**
 * Read with `BittrTheme.colors`. Defaults to light so a preview that forgets
 * [BittrTheme] renders in brand rather than throwing.
 */
val LocalBittrColors = staticCompositionLocalOf { BittrLightColorsExtended }
