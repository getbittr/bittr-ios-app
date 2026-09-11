package com.bittr.android.core.designsystem

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The bittr mark and wordmark, as vectors.
 *
 * Path data is the shipped `design/bittr-logo.svg` verbatim — the same three paths the
 * design canvas draws with. It is built as an [ImageVector] in Kotlin rather than a
 * `res/drawable` XML for one reason: **the mark is two-tone and one of the two tones
 * changes with the surface.** On the brand yellow the arc is white; on a white surface
 * it is the brand yellow; in dark mode the ink strokes have to become light. A vector
 * drawable can be tinted, singular — it cannot carry two independently themed fills
 * without a colour-state-list per fill and a theme attribute to hang it on.
 *
 * The SVG's viewBox starts at y = 308.156, which `ImageVector` has no equivalent for,
 * so the paths sit in a group translated by that much. Do not "simplify" it away —
 * without it the logo draws entirely outside its own bounds and nothing appears.
 */
private const val MARK_INK =
    "M2.995,373.411c-8.792,32.451,1.945,68.461,30.086,90.485c22.26,17.421,50.392,22.179," +
        "75.729,15.33L2.995,373.411z"

private const val MARK_ARC =
    "M139.379,328.104c-37.491-29.355-91.69-22.753-121.045,14.737c-2.52,3.214-4.757,6.565," +
        "-6.748,10.007l17.741,17.741l0,0c2.027-4.538,4.629-8.912,7.834-13.002c21.21-27.1," +
        "60.372-31.866,87.472-10.656c27.1,21.211,31.866,60.372,10.656,87.472c-6.492,8.291," +
        "-14.664,14.481-23.658,18.48l17.75,17.75c9.286-5.359,17.723-12.536,24.735-21.493c29.355," +
        "-37.5,22.753-91.69-14.737-121.045V328.104z"

private const val WORDMARK =
    "M329.512,375.865c11.088,12.032,16.514,26.659,16.514,44.116c0,17.458-5.426,32.321-16.514," +
        "44.353c-11.088,12.032-24.299,17.93-39.87,17.93c-15.099,0-26.895-4.718-35.151-14.391v11.088" +
        "h-35.387V313.819h35.387v58.271c8.257-9.672,20.053-14.391,35.151-14.391C305.212,357.699," +
        "318.424,363.833,329.512,375.865z M282.565,448.763c8.257,0,14.862-2.595,20.053-7.785c5.425," +
        "-5.19,8.021-12.268,8.021-20.997c0-8.729-2.596-15.806-8.021-20.996c-5.19-5.19-11.796-7.785," +
        "-20.053-7.785c-8.257,0-14.863,2.595-20.289,7.785c-5.19,5.19-7.785,12.268-7.785,20.996c0," +
        "8.729,2.595,15.807,7.785,20.997C267.702,446.168,274.308,448.763,282.565,448.763z " +
        "M361.591,344.488c-8.257-8.493-8.257-21.704,0-29.961c8.493-8.493,21.704-8.493,29.962,0c8.492," +
        "8.257,8.492,21.468,0,29.961C383.295,352.745,370.084,352.745,361.591,344.488z M358.996," +
        "478.96V361.002h35.388V478.96H358.996z " +
        "M467.183,394.974h-24.299v41.758c0,9.437,7.078,11.088,24.299,10.144v32.085c-22.412,2.359," +
        "-37.981,0.236-46.71-6.37c-8.729-6.841-12.976-18.637-12.976-35.858v-41.758v-33.972V338.59l35.387," +
        "-10.616v33.028h24.299V394.974z " +
        "M539.835,394.974h-24.299v41.758c0,9.437,7.077,11.088,24.299,10.144v32.085c-22.412,2.359," +
        "-37.982,0.236-46.711-6.37c-8.729-6.841-12.976-18.637-12.976-35.858v-41.758v-33.972V338.59l35.388," +
        "-10.616v33.028h24.299V394.974z " +
        "M588.183,381.999c4.482-15.099,19.345-23.356,35.387-23.356v40.105c-8.729-1.415-16.75,0-24.299," +
        "4.482c-7.313,4.247-11.088,11.796-11.088,22.412v53.317h-35.388V361.002h35.388V381.999z"

/** The SVG's viewBox y-origin. See the note above on why this is a group translation. */
private const val VIEWBOX_TOP = 308.156f
private const val VIEWBOX_HEIGHT = 174.106f
private const val MARK_WIDTH = 170.0f
private const val LOGO_WIDTH = 623.568f

private fun logoVector(ink: Color, arc: Color, wordmark: Boolean): ImageVector {
    val width = if (wordmark) LOGO_WIDTH else MARK_WIDTH
    val height = VIEWBOX_HEIGHT
    return ImageVector.Builder(
        name = if (wordmark) "BittrLogo" else "BittrMark",
        defaultWidth = width.dp,
        defaultHeight = height.dp,
        viewportWidth = width,
        viewportHeight = height,
    ).apply {
        addGroup(translationY = -VIEWBOX_TOP)
        addPath(PathParser().parsePathString(MARK_INK).toNodes(), fill = SolidColor(ink))
        addPath(PathParser().parsePathString(MARK_ARC).toNodes(), fill = SolidColor(arc))
        if (wordmark) {
            addPath(PathParser().parsePathString(WORDMARK).toNodes(), fill = SolidColor(ink))
        }
        clearGroup()
    }.build()
}

/**
 * The full lockup — mark plus wordmark — as it sits in the app bar.
 *
 * @param height the wordmark's cap height. The width follows the artwork's 3.58 : 1.
 */
@Composable
fun BittrLogo(
    modifier: Modifier = Modifier,
    height: Dp = 26.dp,
    ink: Color = BittrTheme.colors.onCanvas,
    arc: Color = BittrTheme.colors.canvasArc,
) {
    val vector = remember(ink, arc) { logoVector(ink, arc, wordmark = true) }
    Image(
        imageVector = vector,
        contentDescription = "bittr",
        modifier = modifier.size(width = height * (LOGO_WIDTH / VIEWBOX_HEIGHT), height = height),
    )
}

/** The mark on its own — the piggy-bank arc, without the word. */
@Composable
fun BittrMark(
    modifier: Modifier = Modifier,
    size: Dp = 30.dp,
    ink: Color = BittrTheme.colors.onCanvas,
    arc: Color = BittrTheme.colors.canvasArc,
) {
    val vector = remember(ink, arc) { logoVector(ink, arc, wordmark = false) }
    Image(
        imageVector = vector,
        contentDescription = null,
        modifier = modifier.size(width = size * (MARK_WIDTH / VIEWBOX_HEIGHT), height = size),
    )
}
