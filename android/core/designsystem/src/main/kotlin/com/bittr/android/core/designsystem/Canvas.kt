package com.bittr.android.core.designsystem

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * The onboarding canvas — the components the Android design
 * (`design/screens.jsx`, artboards 01–20) is built out of.
 *
 * **Why these are not Material's `Button`, `Card` and `TopAppBar` with colours passed
 * in.** The canvas inverts Material's assumption that the *surface* is neutral and the
 * *accent* is coloured: here the screen is the brand colour and the action is the ink.
 * `Button` takes `primary` for its fill, and `primary` in this app is the yellow the
 * button is sitting on — so every call site would have to pass three colours, a shape
 * and a height to undo the default. Wrapping that once is the difference between a
 * screen that reads as the design and a screen that reads as Material 3 wearing it.
 *
 * Everything here composes over [BittrColors.canvas]. On a neutral surface — Settings,
 * the eventual Home list — use Material's own components; that part of the app is not
 * on this canvas.
 */

/** The gutter inside a card. The mock's 22 dp horizontal, 28 dp vertical. */
private val CardPaddingHorizontal = 22.dp
private val CardPaddingVertical = 28.dp

/** Button heights, from the mock: 56 dp normally, 48 dp where a screen is tight. */
private val ButtonHeight = 56.dp
private val ButtonHeightCompact = 48.dp

/**
 * iOS's top bar: `topBarHeight` is the safe area plus 50, with the 30 pt lockup 10 below the
 * safe area — so centred in 50. It was the mock's 56 dp with a 19 dp logo.
 */
private val AppBarHeight = 50.dp
private val AppBarIconBox = 48.dp

/**
 * A screen on the brand canvas: the background, the window insets, and the app bar.
 *
 * The canvas colour is drawn edge to edge — under the status bar and the gesture
 * handle, which is what the mock shows and what `targetSdk 36` enforces anyway — and
 * the *content* is inset. A screen that pads its own background paints a white strip
 * behind the clock.
 *
 * The app bar is iOS's `topBar`, laid over the content rather than above it: translucent
 * (`transparentyellow`), from the top of the screen, with `upperYellowCurve` hanging under it
 * ([BittrAppBarBackground]). What scrolls up under it shows through, as on iOS.
 *
 * @param onBack draws the back arrow when non-null. The arrow is the only affordance
 *   in the bar that does anything; the overflow dots are drawn because the mock has
 *   them and are deliberately inert until there is a menu behind them.
 * @param scrollsUnderAppBar lays [content] out from the top of the screen instead of below the
 *   bar, so a scrolling screen can pass under it. That screen then pads its scrolled content with
 *   [appBarContentPadding], inside the scroll, so it rests below the bar all the same.
 * @param background the page colour. iOS pages are `yelloworblue1` ([BittrColors.canvas]) or
 *   `yelloworblue3` ([BittrColors.primaryHigh]), the same yellow in light and blue1 or blue3 in dark.
 */
@Composable
fun BittrCanvas(
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    appBar: Boolean = true,
    scrollsUnderAppBar: Boolean = false,
    background: Color = BittrTheme.colors.canvas,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = BittrTheme.colors
    CompositionLocalProvider(
        LocalContentColor provides colors.onCanvas,
        LocalPageColor provides background,
    ) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .background(background),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .then(
                        when {
                            !appBar -> Modifier.statusBarsPadding()
                            scrollsUnderAppBar -> Modifier
                            else -> Modifier.appBarContentPadding()
                        },
                    )
                    .navigationBarsPadding(),
                content = content,
            )
            if (appBar) {
                if (LocalAppBarBackgroundVisible.current) BittrAppBarBackground()
                BittrAppBar(onBack = onBack, modifier = Modifier.statusBarsPadding())
            }
        }
    }
}

/**
 * The room the app bar takes at the top of the screen: the status bar and the bar's 50. For the
 * content of a [BittrCanvas] with `scrollsUnderAppBar`, applied inside its scroll.
 */
fun Modifier.appBarContentPadding(): Modifier = statusBarsPadding().padding(top = AppBarContentInset)

/**
 * The colour of the page [BittrCanvas] is drawing, for what composites over it or cuts through to it.
 * Null outside a canvas; read it with [pageColor].
 */
val LocalPageColor = compositionLocalOf<Color?> { null }

/** The page under the caller: [LocalPageColor], or [BittrColors.canvas] outside a [BittrCanvas]. */
@Composable
fun pageColor(): Color = LocalPageColor.current ?: BittrTheme.colors.canvas

/** [appBarContentPadding] below the status bar: the bar's own height. */
val AppBarContentInset: Dp = AppBarHeight

/**
 * Whether [BittrCanvas] draws its app bar's translucent fill and curve. False where one fixed
 * [BittrAppBarLogoOverlay] draws them over pages that slide beneath it, as iOS's `topBar` stays
 * put over the signup page strip — otherwise each page's fill would slide with it, and two
 * translucent fills would stack.
 */
val LocalAppBarBackgroundVisible = compositionLocalOf { true }

/**
 * iOS's `topBar` fill and its `upperYellowCurve`: `transparentyellow` (yellow at 85 %, blue3 at
 * 85 % in dark mode) from the top of the screen to the bottom of the 50 pt bar, then
 * `BottomCurveView` under it — as tall as 0.0375 of the width, its sides 0.15 of that down and its
 * middle sagging towards a control point 1.2 of it down.
 */
@Composable
fun BittrAppBarBackground(modifier: Modifier = Modifier) {
    val fill = BittrTheme.colors.scrimBrand
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val curveHeight = maxWidth * AppBarCurveRatio
        Spacer(
            Modifier
                .fillMaxWidth()
                .drawBehind {
                    val curve = curveHeight.toPx()
                    val barBottom = size.height - curve
                    val path = Path().apply {
                        moveTo(0f, 0f)
                        lineTo(size.width, 0f)
                        lineTo(size.width, barBottom + curve * 0.15f)
                        quadraticTo(size.width / 2, barBottom + curve * 1.2f, 0f, barBottom + curve * 0.15f)
                        close()
                    }
                    drawPath(path, fill)
                }
                .statusBarsPadding()
                .height(AppBarHeight + curveHeight),
        )
    }
}

/** `upperYellowCurve`'s height, as a share of the screen's width. */
private const val AppBarCurveRatio = 0.0375f

/**
 * The app bar's fill, curve and logo, where [BittrCanvas] draws them, for screens whose pages slide
 * under a bar that stays put. On iOS the top bar sits above the signup page strip, so it never
 * moves while the pages do; here each page has its own app bar, so the pages hide theirs
 * (`LocalAppBarLogoVisible`, [LocalAppBarBackgroundVisible]) and this one is laid over them. The
 * logo follows `LocalAppBarLogoVisible` as it is where it is composed, so it stays hidden under the
 * launch animation's cover too.
 *
 * @param background false draws the logo alone, for pages that keep their own bar fill — Home,
 *   whose header is its own and has no translucent bar to hand over to this one.
 */
@Composable
fun BittrAppBarLogoOverlay(modifier: Modifier = Modifier, background: Boolean = true) {
    Box(modifier.fillMaxWidth()) {
        if (background) BittrAppBarBackground()
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .height(AppBarHeight),
        ) {
            BittrLogo(
                height = BittrAppBarLogoHeight,
                modifier = Modifier.alpha(if (LocalAppBarLogoVisible.current) 1f else 0f),
            )
        }
    }
}

/** Back arrow and logo — iOS's 50 dp top bar. */
@Composable
fun BittrAppBar(onBack: (() -> Unit)? = null, modifier: Modifier = Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .height(AppBarHeight),
    ) {
        Box(Modifier.size(AppBarIconBox), contentAlignment = Alignment.Center) {
            if (onBack != null) {
                Image(
                    imageVector = rememberFillIcon(BittrIconPaths.BACK, LocalContentColor.current),
                    contentDescription = "Back",
                    modifier = Modifier
                        .size(AppBarIconBox)
                        .clickable(role = Role.Button, onClick = onBack)
                        .padding(12.dp),
                )
            }
        }
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            BittrLogo(
                height = BittrAppBarLogoHeight,
                modifier = Modifier.alpha(if (LocalAppBarLogoVisible.current) 1f else 0f),
            )
        }
        // Balances the back arrow so the logo stays centred. The mock drew an overflow
        // `⋮` here; it opened nothing, and the design review asked for it to go from every
        // screen without secondary actions — the PIN screens above all (2026-09-18, S21).
        Box(Modifier.size(AppBarIconBox))
    }
}

/**
 * The card a step's content sits in — iOS's `centerCard`: `yelloworblue1` (which is
 * [BittrColors.canvas] exactly, so the card is the page's own colour), 13 pt corners and
 * `setShadow()`. Every iOS card in the app has those corners, and the signup screens, Swap and
 * Value all give it that fill and shadow. It was the mock's translucent white wash at 28 dp, no
 * shadow; decision 52.
 *
 * A [Box] with a background rather than a `Surface`, because `Surface` applies tonal elevation
 * and the result is not the canvas colour.
 *
 * @param shadow iOS's `setShadow()` under the card — see [iosShadow]. A translucent [fill] is
 *   filled pre-composited over the page, the same pixels made opaque, because a shadow drawn
 *   behind a translucent card would show through it.
 * @param shape the card's corners.
 * @param contentPadding the gutter inside the card; the mock's 22/28 dp by default. A screen
 *   matched to its storyboard passes that screen's own.
 * @param fill the card's colour.
 */
@Composable
fun BittrCard(
    modifier: Modifier = Modifier,
    horizontalAlignment: Alignment.Horizontal = Alignment.CenterHorizontally,
    shadow: Boolean = true,
    shape: Shape = IosCardShape,
    contentPadding: PaddingValues = PaddingValues(horizontal = CardPaddingHorizontal, vertical = CardPaddingVertical),
    fill: Color = BittrTheme.colors.canvas,
    content: @Composable ColumnScope.() -> Unit,
) {
    val page = pageColor()
    Column(
        horizontalAlignment = horizontalAlignment,
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (shadow) {
                    Modifier
                        .iosShadow(shape)
                        .background(fill.compositeOver(page), shape)
                } else {
                    Modifier.background(fill, shape)
                },
            )
            .padding(contentPadding),
        content = content,
    )
}

/**
 * iOS's `UIView.setShadow()` (`Extensions/UIView.swift`): black at 10 %, offset 7 pt down,
 * `shadowRadius` 10 — the shadow under most of the app's cards.
 *
 * **The radius is not 10 dp.** Core Animation's `shadowRadius` is the Gaussian's sigma;
 * fitting the edge of Signup1's card shadow in an iOS screenshot gives sigma = 10 pt
 * (rms 0.45 against 2.03 for sigma = 5). Compose hands its radius to `BlurMaskFilter`,
 * where Skia turns a radius r into sigma = 0.57735 r + 0.5 px, so sigma 10 is r ≈ 17.3.
 */
fun Modifier.iosShadow(shape: Shape): Modifier = dropShadow(
    shape,
    Shadow(
        radius = 17.3.dp,
        color = Color.Black,
        offset = DpOffset(0.dp, 7.dp),
        alpha = 0.10f,
    ),
)

/** iOS's card corners: 13 pt on every card in the app. */
val IosCardShape = RoundedCornerShape(13.dp)

/**
 * The primary action — iOS's `createWalletView` / `buttonView`: an ink plate 40 pt high with 8 pt
 * corners, sized to its content (17 pt, the label in Gilroy Bold 14 set 1 pt below centre as the
 * storyboards' `centerY` constant has it, 10 pt, the 11 pt `arrowrightwhite`, 17 pt) and centred
 * in the width it is given. At least 80 pt wide, as the storyboards pin it. Decision 52.
 *
 * @param fullWidth the mock's full-width pill instead, for the buttons iOS does not draw this way:
 *   the ones in alerts and dialogs, which fill the dialog's width.
 * @param enabled false draws the disabled pill, [BittrColors.actionFillDisabled] under
 *   [BittrColors.onActionFillDisabled], and stops clicks.
 * @param dimmed the disabled look without the disabled behaviour, for an action whose tap
 *   explains what is missing (Buy signup's "please fill in" alert). Follows [enabled].
 * @param arrow the forward chevron. Present on every "carry on" action in the mock and
 *   absent on the ones that complete something in place (`Confirm` on the PIN pad).
 * @param fill the plate when it is not dimmed; [BittrColors.actionFill] unless iOS colours this
 *   button otherwise.
 */
@Composable
fun BittrPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    arrow: Boolean = true,
    compact: Boolean = false,
    dimmed: Boolean = !enabled,
    wrapLabel: Boolean = false,
    fullWidth: Boolean = false,
    fill: Color = BittrTheme.colors.actionFill,
    content: (@Composable () -> Unit)? = null,
) {
    val colors = BittrTheme.colors
    if (!fullWidth) {
        val shape = RoundedCornerShape(8.dp)
        val labelColor = if (dimmed) colors.onActionFillDisabled else colors.onActionFill
        Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxWidth()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                modifier = modifier
                    .then(if (wrapLabel) Modifier.heightIn(min = 40.dp) else Modifier.height(40.dp))
                    .widthIn(min = 80.dp)
                    .clip(shape)
                    .background(if (dimmed) colors.actionFillDisabled else fill, shape)
                    .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
                    .padding(horizontal = 17.dp, vertical = if (wrapLabel) 10.dp else 0.dp),
            ) {
                if (content != null) {
                    content()
                } else {
                    Text(
                        text = text,
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.sp, lineHeight = 14.sp),
                        color = labelColor,
                        textAlign = TextAlign.Center,
                        // iOS centres the label 1 pt below the plate's centre (`centerY` constant 1).
                        modifier = Modifier.offset(y = 1.dp),
                    )
                    if (arrow) {
                        Image(
                            painter = painterResource(R.drawable.bittr_arrow_right),
                            contentDescription = null,
                            colorFilter = ColorFilter.tint(labelColor),
                            modifier = Modifier.size(11.dp),
                        )
                    }
                }
            }
        }
        return
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
        modifier = modifier
            .fillMaxWidth()
            // A sentence-long label — the exclusive-initiative confirmation — needs the pill to
            // grow: at a fixed height it overflowed its own background and drew over the text
            // above it (Ruben, 2026-09-22). Every other label is two or three words.
            .then(
                if (wrapLabel) {
                    Modifier.heightIn(min = if (compact) ButtonHeightCompact else ButtonHeight)
                } else {
                    Modifier.height(if (compact) ButtonHeightCompact else ButtonHeight)
                },
            )
            // Clipped before `clickable`, so the press and focus highlight follows the pill
            // instead of drawing a rectangle around it.
            .clip(BittrCanvasShapes.pill)
            .background(
                if (dimmed) colors.actionFillDisabled else fill,
                BittrCanvasShapes.pill,
            )
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
    ) {
        val labelColor = if (dimmed) colors.onActionFillDisabled else colors.onActionFill
        if (content != null) {
            content()
        } else {
            Text(
                text = text,
                style = MaterialTheme.typography.labelLarge,
                color = labelColor,
                textAlign = TextAlign.Center,
                modifier = if (wrapLabel) Modifier.padding(horizontal = 20.dp, vertical = 14.dp) else Modifier,
            )
            if (arrow) {
                Image(
                    imageVector = rememberStrokeIcon(
                        BittrIconPaths.ARROW_FORWARD,
                        labelColor,
                    ),
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}

/** The cream tonal action — the mock's secondary button. */
@Composable
fun BittrTonalButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
) {
    val colors = BittrTheme.colors
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .fillMaxWidth()
            .height(if (compact) ButtonHeightCompact else ButtonHeight)
            .clip(BittrCanvasShapes.pill)
            .background(colors.tonalFill, BittrCanvasShapes.pill)
            .clickable(role = Role.Button, onClick = onClick),
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge, color = colors.onTonalFill)
    }
}

/**
 * The quiet action below the primary one — "Restore wallet", "Back", "Skip".
 *
 * Full-width and 48 dp tall so it keeps its touch target even though it reads as text.
 */
@Composable
fun BittrTextButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    color: Color = BittrTheme.colors.mutedOnCanvas,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = BittrTokens.Size.minTouchTarget)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge,
            color = color,
            textAlign = TextAlign.Center,
        )
    }
}

/**
 * A round icon button: a 48 dp touch target with a circular press layer, so the highlight
 * never draws as a square (review S10). [pathData] is a filled path from [BittrIconPaths].
 */
@Composable
fun BittrIconButton(
    pathData: String,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = LocalContentColor.current,
    iconSize: Dp = 20.dp,
    filled: Boolean = true,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(BittrTokens.Size.minTouchTarget)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = onClick),
    ) {
        Image(
            imageVector = if (filled) rememberFillIcon(pathData, tint) else rememberStrokeIcon(pathData, tint),
            contentDescription = contentDescription,
            modifier = Modifier.size(iconSize),
        )
    }
}

/** Copy this row's value — `content_copy`, ink, at a row's trailing edge (review S4). */
@Composable
fun BittrCopyButton(onClick: () -> Unit, modifier: Modifier = Modifier, contentDescription: String = "Copy") =
    BittrIconButton(
        pathData = BittrIconPaths.COPY,
        contentDescription = contentDescription,
        onClick = onClick,
        modifier = modifier,
        tint = MaterialTheme.colorScheme.onSurface,
    )

/**
 * The inline "what is this?" control — `help_outline` at 70 % of the content colour, in
 * place of a literal "?" in body type (review S5).
 */
@Composable
fun BittrHelpButton(onClick: () -> Unit, modifier: Modifier = Modifier, contentDescription: String = "More information") =
    BittrIconButton(
        pathData = BittrIconPaths.HELP,
        contentDescription = contentDescription,
        onClick = onClick,
        modifier = modifier,
        tint = LocalContentColor.current.copy(alpha = 0.70f),
    )

/**
 * The selected partner above "Next" on the signup's ready page — Signup7's white bittr row,
 * which the port had dropped, so the user confirmed a partner they could not see (review,
 * `signup7`). bittr is the only partner, so the row is a statement rather than a picker: it
 * is drawn selected and takes no taps.
 *
 * iOS's `partnerView`: [BittrPartnerRowWidth] by 40 with 8 pt corners, the yellow
 * `checkmark.circle.fill` 20 pt and 20 in, the 18 pt lockup centred. Next under it is as wide.
 */
@Composable
fun BittrPartnerRow(modifier: Modifier = Modifier) {
    val colors = BittrTheme.colors
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(width = BittrPartnerRowWidth, height = 40.dp)
            .background(Color.White, RoundedCornerShape(8.dp))
            .padding(horizontal = 20.dp),
    ) {
        // `checkmark.circle.fill`: the tick is cut out of the disc, so it shows the white row.
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(20.dp)
                .background(colors.brandFixed, CircleShape),
        ) {
            Image(
                imageVector = rememberStrokeIcon(BittrIconPaths.CHECK, Color.White, strokeWidth = 3f),
                contentDescription = "Selected",
                modifier = Modifier.size(13.dp),
            )
        }
        // Ink and brand yellow, fixed: the row is white in both schemes.
        BittrLogo(height = 18.dp, ink = Ink, arc = colors.brandFixed)
    }
}

/** `partnerView`'s width, which `continueView` under it matches. */
val BittrPartnerRowWidth = 200.dp

/**
 * The app's one indeterminate spinner (review S11): round caps and a faint track in its own
 * colour, so a still frame reads as "working" rather than as a stray arc. Ink by default;
 * pass [color] on a filled button.
 */
@Composable
fun BittrSpinner(
    modifier: Modifier = Modifier,
    color: Color = BittrTheme.colors.onCanvas,
    strokeWidth: Dp = 3.dp,
) {
    androidx.compose.material3.CircularProgressIndicator(
        modifier = modifier,
        color = color,
        strokeWidth = strokeWidth,
        trackColor = color.copy(alpha = 0.20f),
        strokeCap = StrokeCap.Round,
    )
}

/**
 * The label on a white detail row — "Amount", "Fees", "Status" — in 13 sp semibold gold, so
 * a row reads as a label and a value rather than two values (review S15). Gold is
 * [BittrColors.rowLabel], the darkened one that holds 5 : 1 on white (DEV-40).
 */
@Composable
fun BittrRowLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.2.sp),
        color = BittrTheme.colors.rowLabel,
        modifier = modifier,
    )
}

/** A white value row — the mock's field, and the container for a phrase word. */
@Composable
fun BittrValueRow(
    modifier: Modifier = Modifier,
    height: Dp = 56.dp,
    content: @Composable (androidx.compose.foundation.layout.RowScope.() -> Unit),
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        contentColor = MaterialTheme.colorScheme.onSurface,
        shape = BittrCanvasShapes.field,
        modifier = modifier.fillMaxWidth(),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .heightIn(min = height)
                .padding(horizontal = BittrTokens.Spacing.lg),
            content = content,
        )
    }
}

/**
 * The ink disc with a white tick — the mock's confirmation mark on Ready.
 *
 * Drawn rather than shipped as an asset: it is a circle and two strokes, and the
 * alternative is a PNG that has to exist at four densities.
 *
 * @param checkSize the tick's icon box; the tick itself spans 14/24 of it.
 * @param strokeWidth the tick's stroke, in the icon's 24-unit viewport.
 */
@Composable
fun BittrCheckBadge(
    modifier: Modifier = Modifier,
    size: Dp = 76.dp,
    checkSize: Dp = size * 0.45f,
    strokeWidth: Float = 2.6f,
) {
    val colors = BittrTheme.colors
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(size)
            .background(colors.actionFill, CircleShape),
    ) {
        Image(
            imageVector = rememberStrokeIcon(
                BittrIconPaths.CHECK,
                colors.onActionFill,
                strokeWidth = strokeWidth,
            ),
            contentDescription = null,
            modifier = Modifier.size(checkSize),
        )
    }
}

/**
 * The switch on the consent step.
 *
 * Material's `Switch` with the canvas's colours rather than a hand-drawn one — the
 * thumb animation, the ripple and the accessibility role are all behaviour worth
 * keeping, and only the palette differs from the mock.
 *
 * **The border is the same in both states, and that is the fix for BIT-95.** The checked
 * track used to take the green for its border as well as its fill, which left the
 * control with no edge it did not supply itself: 1.65 : 1 against the dark canvas,
 * 1.32 : 1 against the card it is actually drawn on. The thumb was still visible, so
 * what the user lost was not the switch but the *travel* — you could see a white dot and
 * not the slot it had moved along, which is the state. See [BittrColors.switchOn] for
 * why darkening or swapping the green cannot fix that and a border can.
 *
 * The unchecked state was always fine and is unchanged; it is the one this borrows from.
 *
 * Dark mode draws UIKit's stock switch instead, as iOS does: no border, a white thumb and a grey
 * track when off ([BittrColors.switchBorder] and its neighbours).
 */
@Composable
fun bittrSwitchColors(): androidx.compose.material3.SwitchColors {
    val colors = BittrTheme.colors
    return androidx.compose.material3.SwitchDefaults.colors(
        checkedThumbColor = colors.onSwitchOn,
        checkedTrackColor = colors.switchOn,
        checkedBorderColor = colors.switchBorder,
        uncheckedThumbColor = colors.switchOffThumb,
        uncheckedTrackColor = colors.switchOffTrack,
        uncheckedBorderColor = colors.switchBorder,
    )
}

/**
 * The one- or two-button alert: [BittrAlert] with the cancelling button, when there is one, as
 * `alert.button.0` on the left and the action as `alert.button.1` — iOS's `buttons:` order, which
 * every flow driving a two-button alert selects by. Back and the X resolve to the cancelling
 * action, or to the lone button: an alert asking "reset your PIN?" must not be answerable with
 * "yes" by accident.
 *
 * @param confirmTestTag, dismissTestTag kept for callers; the ids come from the index rule.
 * @param dismissLabel the left-hand, cancelling button. Null for a one-button alert.
 */
@Composable
fun BittrAlertDialog(
    title: String,
    message: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    modifier: Modifier = Modifier,
    confirmTestTag: String? = null,
    dismissLabel: String? = null,
    onDismiss: () -> Unit = onConfirm,
    dismissTestTag: String? = null,
    messageIsValue: Boolean = false,
) {
    // The ids are the index rule [BittrAlert] applies — `alert.button.0` the way out, the action
    // after it — which is what every caller passes; the parameters stay for them.
    BittrAlert(
        title = title,
        message = message,
        buttons = listOfNotNull(
            dismissLabel?.let { BittrAlertButton(label = it, dismissesAlert = true, onClick = onDismiss) },
            // A lone button is the way out as well: Back and the X do what it does.
            BittrAlertButton(label = confirmLabel, dismissesAlert = dismissLabel == null, onClick = onConfirm),
        ),
        modifier = modifier,
        messageIsValue = messageIsValue,
    )
}

// ---------------------------------------------------------------------------
// Icons
// ---------------------------------------------------------------------------

/**
 * The icon paths the canvas uses, as SVG path data lifted from `design/screens.jsx`.
 *
 * Kept as data rather than as `androidx.compose.material.icons` because that artifact
 * is not a dependency of this module and pulling in the whole Material icon set — a
 * five-figure method count — to draw four glyphs would be a poor trade.
 */
object BittrIconPaths {
    const val ARROW_FORWARD = "M5 12h13m-6-6l6 6-6 6"
    const val BACK = "M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20z"
    const val CHECK = "M5 12.5l4.5 4.5L19 7"
    const val BACKSPACE_BODY = "M22 5H9.5L2 12l7.5 7H22V5z"
    const val BACKSPACE_CROSS = "M13 10l5 4m0-4l-5 4"

    /**
     * The down chevron that closes a sheet — iOS's `downarrow32` asset, and the
     * glyph behind `header.downButton` and `website.downButton`.
     */
    const val ARROW_DOWN = "M12 5v13m0 0l-6-6m6 6l6-6"

    // Home, from `design/screens.jsx` artboard 18 — the three header entry points
    // and the three actions. Lifted from the mock rather than redrawn.
    const val MAP = "M3 6l6-2.5L15 6l6-2.5v15L15 21l-6-2.5L3 21z"
    const val CURRENCY =
        "M20 12a8 8 0 11-16 0 8 8 0 0116 0z M9.5 8.5h4a2 2 0 010 4h-4m0 0h4.5a2 2 0 010 4H9.5" +
            "m0-8v8M11 6v2m0 8v2"
    const val SEND = "M12 19V5m0 0l-6 6m6-6l6 6"
    const val RECEIVE = "M12 5v14m0 0l-6-6m6 6l6-6"
    const val BUY = "M3 10h18M5 6h14a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2z"

    /** The balance-details bars. Filled in the mock, unlike its neighbours. */
    const val DETAILS = "M3 12h4v8H3z M10 6h4v14h-4z M17 9h4v11h-4z"

    /**
     * Material's `content_copy`, `help_outline` and outlined `settings` (Apache 2.0), as
     * the design review asked for them by name (2026-09-18, S4, S5, S9). Filled paths:
     * draw them with [rememberFillIcon].
     */
    const val COPY =
        "M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"
    const val HELP =
        "M11 18h2v-2h-2v2zm1-16C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm0-14c-2.21 0-4 1.79-4 4h2c0-1.1.9-2 2-2s2 .9 2 2c0 2-3 1.75-3 5h2c0-2.25 3-2.5 3-5 0-2.21-1.79-4-4-4z"
    const val SETTINGS_OUTLINE =
        "M19.43 12.98c.04-.32.07-.64.07-.98 0-.34-.03-.66-.07-.98l2.11-1.65c.19-.15.24-.42.12-.64l-2-3.46c-.09-.16-.26-.25-.44-.25-.06 0-.12.01-.17.03l-2.49 1c-.52-.4-1.08-.73-1.69-.98l-.38-2.65C14.46 2.18 14.25 2 14 2h-4c-.25 0-.46.18-.49.42l-.38 2.65c-.61.25-1.17.59-1.69.98l-2.49-1c-.06-.02-.12-.03-.18-.03-.17 0-.34.09-.43.25l-2 3.46c-.13.22-.07.49.12.64l2.11 1.65c-.04.32-.07.65-.07.98 0 .33.03.66.07.98l-2.11 1.65c-.19.15-.24.42-.12.64l2 3.46c.09.16.26.25.44.25.06 0 .12-.01.17-.03l2.49-1c.52.4 1.08.73 1.69.98l.38 2.65c.03.24.24.42.49.42h4c.25 0 .46-.18.49-.42l.38-2.65c.61-.25 1.17-.59 1.69-.98l2.49 1c.06.02.12.03.18.03.17 0 .34-.09.43-.25l2-3.46c.12-.22.07-.49-.12-.64l-2.11-1.65zm-1.98-1.71c.04.31.05.52.05.73 0 .21-.02.43-.05.73l-.14 1.13.89.7 1.08.84-.7 1.21-1.27-.51-1.04-.42-.9.68c-.43.32-.84.56-1.25.73l-1.06.43-.16 1.13-.2 1.35h-1.4l-.19-1.35-.16-1.13-1.06-.43c-.43-.18-.83-.41-1.23-.71l-.91-.7-1.06.43-1.27.51-.7-1.21 1.08-.84.89-.7-.14-1.13c-.03-.31-.05-.54-.05-.74s.02-.43.05-.73l.14-1.13-.89-.7-1.08-.84.7-1.21 1.27.51 1.04.42.9-.68c.43-.32.84-.56 1.25-.73l1.06-.43.16-1.13.2-1.35h1.39l.19 1.35.16 1.13 1.06.43c.43.18.83.41 1.23.71l.91.7 1.06-.43 1.27-.51.7 1.21-1.07.85-.89.7.14 1.13zM12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm0 6c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z"

    /**
     * Material's filled `dark_mode`, `light_mode` and `computer` (Apache 2.0), for the theme
     * toggle (review S23). The hand-written [MOON] and [SUN] used compressed SVG arc flags
     * (`0 019.5 4`) and rendered as a sliver and a ring of loose rays.
     */
    const val DARK_MODE =
        "M12 3c-4.97 0-9 4.03-9 9s4.03 9 9 9 9-4.03 9-9c0-.46-.04-.92-.1-1.36-.98 1.37-2.58 2.26-4.4 2.26-2.98 0-5.4-2.42-5.4-5.4 0-1.81.89-3.42 2.26-4.4-.44-.06-.9-.1-1.36-.1z"
    const val LIGHT_MODE =
        "M12 7c-2.76 0-5 2.24-5 5s2.24 5 5 5 5-2.24 5-5-2.24-5-5-5zM2 13h2c.55 0 1-.45 1-1s-.45-1-1-1H2c-.55 0-1 .45-1 1s.45 1 1 1zm18 0h2c.55 0 1-.45 1-1s-.45-1-1-1h-2c-.55 0-1 .45-1 1s.45 1 1 1zM11 2v2c0 .55.45 1 1 1s1-.45 1-1V2c0-.55-.45-1-1-1s-1 .45-1 1zm0 18v2c0 .55.45 1 1 1s1-.45 1-1v-2c0-.55-.45-1-1-1s-1 .45-1 1zM5.99 4.58c-.39-.39-1.03-.39-1.41 0-.39.39-.39 1.03 0 1.41l1.06 1.06c.39.39 1.03.39 1.41 0s.39-1.03 0-1.41L5.99 4.58zm12.37 12.37c-.39-.39-1.03-.39-1.41 0-.39.39-.39 1.03 0 1.41l1.06 1.06c.39.39 1.03.39 1.41 0 .39-.39.39-1.03 0-1.41l-1.06-1.06zm1.06-10.96c.39-.39.39-1.03 0-1.41-.39-.39-1.03-.39-1.41 0l-1.06 1.06c-.39.39-.39 1.03 0 1.41s1.03.39 1.41 0l1.06-1.06zM7.05 18.36c.39-.39.39-1.03 0-1.41-.39-.39-1.03-.39-1.41 0l-1.06 1.06c-.39.39-.39 1.03 0 1.41s1.03.39 1.41 0l1.06-1.06z"
    const val COMPUTER =
        "M20 18c1.1 0 1.99-.9 1.99-2L22 6c0-1.1-.9-2-2-2H4c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2H0v2h24v-2h-4zM4 6h16v10H4V6z"

    // The bottom bar, also artboard 18.
    const val WALLET = "M3 7.5A2.5 2.5 0 015.5 5H18a2 2 0 012 2v10a2 2 0 01-2 2H5.5A2.5 2.5 0 013 16.5z M16 12h2"
    const val ACADEMY = "M3 9l9-4.5L21 9l-9 4.5z M6.5 11v4.5c0 1 2.5 2.5 5.5 2.5s5.5-1.5 5.5-2.5V11"
    const val SUPPORT = "M3 7h18v10H3z M3 7l9 6 9-6"

    // Settings' rows, filled as iOS's SF Symbols are, for [rememberFillIcon] with `evenOdd`: each
    // inner subpath is a hole. `envelope.fill` with its fold, `checkmark.shield.fill` with its
    // tick, `book.pages.fill` with its lines, `ipad.and.iphone` as a framed tablet and a phone.
    const val SUPPORT_FILLED =
        "M4.5 5.5h15a1.5 1.5 0 011.5 1.5v10a1.5 1.5 0 01-1.5 1.5h-15A1.5 1.5 0 013 17V7a1.5 1.5 0 011.5-1.5z " +
            "M4 7.2L12 13l8-5.8v1.8L12 14.8 4 9z"
    const val PRIVACY_FILLED =
        "M12 2.5l8 3.2v5.8c0 4.6-3.3 8.4-8 10-4.7-1.6-8-5.4-8-10V5.7z " +
            "M8.1 12l1.4-1.4 1.9 1.9 3.9-3.9 1.4 1.4-5.3 5.3z"
    const val TERMS_FILLED =
        "M6 2.5h11a2 2 0 012 2v15a2 2 0 01-2 2H6a2 2 0 01-2-2v-15a2 2 0 012-2z " +
            "M7.5 6.5h8V8h-8z M7.5 10h8v1.5h-8z M7.5 13.5h5.5V15H7.5z"
    const val DEVICE_FILLED =
        "M3.5 4h9a1.5 1.5 0 011.5 1.5v13a1.5 1.5 0 01-1.5 1.5h-9A1.5 1.5 0 012 18.5v-13A1.5 1.5 0 013.5 4z " +
            "M3.6 5.6v12.8h8.8V5.6z " +
            "M16.5 9h4a1.5 1.5 0 011.5 1.5v8a1.5 1.5 0 01-1.5 1.5h-4a1.5 1.5 0 01-1.5-1.5v-8A1.5 1.5 0 0116.5 9z"
    const val PRIVACY = "M12 3l7 3v5.5c0 4-3 7.2-7 8.5-4-1.3-7-4.5-7-8.5V6z M9 12l2 2 4-4"
    const val TERMS = "M5 4h10a2 2 0 012 2v14H7a2 2 0 01-2-2z M17 8h2v12h-2"
    const val DEVICE =
        "M4 3h9a1 1 0 011 1v16a1 1 0 01-1 1H4a1 1 0 01-1-1V4a1 1 0 011-1z " +
            "M16 8h4a1 1 0 011 1v11a1 1 0 01-1 1h-4a1 1 0 01-1-1V9a1 1 0 011-1z"
    const val MOON = "M20 14.5A8.5 8.5 0 019.5 4 8.5 8.5 0 1020 14.5z"
    const val SUN =
        "M12 7a5 5 0 100 10 5 5 0 000-10z M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5" +
            "M17.5 17.5L19 19M19 5l-1.5 1.5M6.5 17.5L5 19"
    const val PHONE = "M7 2h10a1 1 0 011 1v18a1 1 0 01-1 1H7a1 1 0 01-1-1V3a1 1 0 011-1z M10 18.5h4"
    const val LANGUAGE =
        "M12 3a9 9 0 100 18 9 9 0 000-18z M3 12h18 " +
            "M12 3c2.5 2.5 3.8 5.5 3.8 9S14.5 18.5 12 21c-2.5-2.5-3.8-5.5-3.8-9S9.5 5.5 12 3z"
    const val KEY = "M4.5 12a3.5 3.5 0 107 0 3.5 3.5 0 10-7 0z M11.5 12H21m-3 0v3m-3-3v2"
    const val PEER =
        "M10 14a4 4 0 005.7 0l2.8-2.8a4 4 0 10-5.7-5.7l-1 1 " +
            "M14 10a4 4 0 00-5.7 0l-2.8 2.8a4 4 0 105.7 5.7l1-1"
    const val HOURGLASS = "M7 3h10v3l-5 6 5 6v3H7v-3l5-6-5-6z"
    const val BOLT = "M13 2L4 14h6l-1 8 9-12h-6z"
    const val TRASH =
        "M4 7h16 M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2 M6 7l1 13a1 1 0 001 1h8a1 1 0 001-1l1-13"

    /**
     * The piggy bank that sits beside "welcome" and "your wallet".
     *
     * This is the asset the scaffold's comment said was missing from `shared/`. It is
     * not missing any more — the design canvas draws it, and this is its path.
     */
    const val PIGGY =
        "M19 9.5c-.4-.8-1-1.5-1.8-2V6l-2 1.1A8.7 8.7 0 0012 6.8c-3.6 0-6.6 2-7.3 4.7H3.2c-.4 " +
            "0-.7.3-.7.7v1.6c0 .4.3.7.7.7h1.3c.4 1 1.1 1.9 2 2.6V19h2.4l.5-1.4c.8.2 1.7.3 " +
            "2.6.3s1.8-.1 2.6-.3l.5 1.4H17v-1.9c1.6-1.1 2.6-2.7 2.6-4.5 0-.4 0-.8-.1-1.2l1.3-.8" +
            "-1.8-1.1zM9 10.6a1 1 0 110-2 1 1 0 010 2z"
}

/**
 * The piggy bank: iOS's own `iconpiggywhite` asset (`res/drawable-*dpi/bittr_piggy_icon.png`,
 * its 1x/2x/3x at mdpi/xhdpi/xxhdpi), tinted with [tint]. iOS ships the same shape a second
 * time as `iconpiggyyellow` for dark mode; a tint covers both.
 */
@Composable
fun BittrPiggy(
    modifier: Modifier = Modifier,
    size: Dp = 30.dp,
    tint: Color = LocalContentColor.current,
) {
    Image(
        painter = painterResource(R.drawable.bittr_piggy_icon),
        contentDescription = null,
        colorFilter = ColorFilter.tint(tint),
        modifier = modifier.size(size),
    )
}

@Composable
fun rememberStrokeIcon(
    pathData: String,
    tint: Color,
    strokeWidth: Float = 2.4f,
): ImageVector = remember(pathData, tint, strokeWidth) {
    ImageVector.Builder(
        name = "stroke",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        addPath(
            pathData = PathParser().parsePathString(normalizeSvgPath(pathData)).toNodes(),
            stroke = SolidColor(tint),
            strokeLineWidth = strokeWidth,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        )
    }.build()
}

@Composable
fun rememberFillIcon(pathData: String, tint: Color, evenOdd: Boolean = false): ImageVector =
    remember(pathData, tint, evenOdd) {
        ImageVector.Builder(
            name = "fill",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            addPath(
                pathData = PathParser().parsePathString(normalizeSvgPath(pathData)).toNodes(),
                fill = SolidColor(tint),
                // Even-odd for a shape with holes cut in it: an inner subpath clears what it covers.
                pathFillType = if (evenOdd) PathFillType.EvenOdd else PathFillType.NonZero,
            )
        }.build()
    }

/** The keypad's delete key: a filled arrow with the page colour cut through it. */
@Composable
fun BittrBackspaceIcon(modifier: Modifier = Modifier, size: Dp = 28.dp) {
    val colors = BittrTheme.colors
    Box(modifier.size(size)) {
        Image(
            imageVector = rememberFillIcon(BittrIconPaths.BACKSPACE_BODY, colors.onCanvas),
            contentDescription = null,
            modifier = Modifier.size(size),
        )
        Image(
            imageVector = rememberStrokeIcon(
                BittrIconPaths.BACKSPACE_CROSS,
                pageColor(),
                strokeWidth = 2f,
            ),
            contentDescription = null,
            modifier = Modifier.size(size),
        )
    }
}

// ---------------------------------------------------------------------------
// Type helpers — the two styles the canvas repeats on every screen
// ---------------------------------------------------------------------------

/** The instruction at the top of a step. Bold 18, centred, on the canvas. */
@Composable
fun BittrStepHeading(
    text: String,
    modifier: Modifier = Modifier,
    textAlign: TextAlign = TextAlign.Center,
) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        textAlign = textAlign,
        modifier = modifier,
    )
}

/** Body copy inside a card. Regular 16. */
@Composable
fun BittrBody(
    text: String,
    modifier: Modifier = Modifier,
    textAlign: TextAlign = TextAlign.Center,
    muted: Boolean = false,
    bold: Boolean = false,
) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyLarge.let { if (bold) it.copy(fontWeight = FontWeight.Bold) else it },
        color = if (muted) BittrTheme.colors.mutedOnCanvas else LocalContentColor.current,
        textAlign = textAlign,
        modifier = modifier,
    )
}

/**
 * A small bold numeral — the word index and the field labels.
 *
 * **Grey, not the mock's dim yellow.** `#EFA900` on the white word row measures
 * 1.7 : 1. In a twelve-word list the number is not decoration: it is how the user
 * checks the order against what they wrote down, and it is the entire content of the
 * label beside a Verify field. This is the same substitution A11Y-15 and A11Y-21 made
 * for the iOS yellow-on-white pairs.
 */
@Composable
fun BittrNumeral(text: String, modifier: Modifier = Modifier, width: Dp = 24.dp) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.ExtraBold),
        // Gold, as iOS numbers its words, but [BittrColors.rowLabel]'s darkened gold
        // (5.07 : 1 on the white row) rather than the proposal's `#EFA900`, which is about
        // 2 : 1 there. It was grey until the design review (2026-09-18).
        color = BittrTheme.colors.rowLabel,
        textAlign = TextAlign.End,
        modifier = modifier.width(width),
    )
}

/** Vertical breathing room, in the canvas's own rhythm. */
@Composable
fun CanvasSpacer(height: Dp) = Spacer(Modifier.height(height))
