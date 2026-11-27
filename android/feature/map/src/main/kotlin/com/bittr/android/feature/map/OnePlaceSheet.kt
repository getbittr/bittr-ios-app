package com.bittr.android.feature.map

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrPopup
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.iosShadow
import com.bittr.android.core.designsystem.rememberFillIcon
import com.bittr.android.core.designsystem.rememberStrokeIcon

/**
 * One place, over the map. Ported from `OnePlaceViewController`, presented as
 * `MapVCOnePlace.showOnePlace` does: a panel as tall as its content springing up over the
 * map, which dims to 50 % black — [BittrPopup], the motion Settings shares with it — with
 * its top corners at the container's 12.
 *
 * A `Dialog` rather than a sibling composable so it genuinely sits in its own window over
 * the map and takes the system back gesture as a dismissal.
 *
 * Address, website and opening hours each appear only when the place carries them,
 * matching iOS's three `show*` methods. The website row's absence is not cosmetic:
 * `bitcoin_map.yaml` guards its whole website section on `map.onePlace.websiteButton`
 * being visible, so a row that is always present with an empty value would send the
 * flow into an in-app browser with nothing to load.
 *
 * Sizes are the storyboard's: the name 45 below the top and 20 in, the type's 16 pt glyph
 * 10 under it, each detail row 15 in with 10 above it and 45 tall, the maps button 40 tall
 * in a 60 strip and 40 above the safe area, and the close X 15 × 15 at 20 from the corner
 * in a 40 × 40 button. The rows sit 15 under the type, each
 * with its own 10 above it.
 */
@Composable
internal fun OnePlaceSheet(
    place: BitcoinPlace,
    onClose: () -> Unit,
    onOpenWebsite: (String) -> Unit,
    onMapsUnavailable: () -> Unit = {},
) {
    val context = LocalContext.current
    val colors = BittrTheme.colors

    Dialog(onDismissRequest = onClose, properties = PanelDialog) {
        BittrPopup(onDismissed = onClose, cornerRadius = 12.dp) { dismiss ->
            Box(Modifier.fillMaxWidth()) {
                Column(Modifier.fillMaxWidth()) {
                    CanvasSpacer(45.dp)
                    // `placeNameLabel`: Gilroy-Bold 22, `blackoryellow`.
                    Text(
                        text = place.name ?: MapCopy.UNAVAILABLE,
                        style = MaterialTheme.typography.titleLarge.copy(fontSize = 22.sp),
                        color = colors.emphasis,
                        modifier = Modifier
                            .padding(horizontal = 20.dp)
                            .testTag(TestID.Map.OnePlace.nameLabel),
                    )
                    CanvasSpacer(10.dp)
                    // `iconImage` and `typeLabel`: white in both modes, over the canvas.
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(start = 20.dp, end = 20.dp),
                    ) {
                        Image(
                            imageVector = rememberStrokeIcon(placeGlyph(place.icon).path, Color.White, strokeWidth = 2f),
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(Modifier.width(7.dp))
                        Text(
                            text = categoryDescription(place.icon),
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 16.sp),
                            color = Color.White,
                            modifier = Modifier.offset(y = 1.dp),
                        )
                    }
                    CanvasSpacer(15.dp)

                    place.address?.let { address ->
                        DetailRow(glyph = DetailGlyph.ADDRESS, text = address)
                    }
                    place.website?.let { website ->
                        DetailRow(
                            glyph = DetailGlyph.WEBSITE,
                            text = displayWebsite(website),
                            onClick = { onOpenWebsite(website) },
                            modifier = Modifier.testTag(TestID.Map.OnePlace.websiteButton),
                        )
                    }
                    place.openingHours?.let { hours ->
                        DetailRow(glyph = DetailGlyph.HOURS, text = hours)
                    }

                    // The hand-off to a maps app. iOS raises a chooser alert because it
                    // has to ask whether Google Maps is installed; Android's implicit
                    // `geo:` intent is answered by whatever the user has, and the system
                    // runs the chooser — so the alert has no counterpart here.
                    CanvasSpacer(10.dp)
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .padding(horizontal = 15.dp)
                            .fillMaxWidth()
                            .height(40.dp)
                            .iosShadow(PanelRowShape)
                            .clip(PanelRowShape)
                            .background(colors.scrim3)
                            .clickable(role = Role.Button) {
                                if (!place.openInMaps(context)) onMapsUnavailable()
                            }
                            .testTag(TestID.Map.OnePlace.goToMapsButton),
                    ) {
                        Text(
                            text = MapCopy.OPEN_IN_MAPS,
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 15.sp),
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.offset(y = 1.dp),
                        )
                    }
                    CanvasSpacer(50.dp)
                }

                // `iconclosewhite`, 15 × 15 at 20 from the top and right, in a 40 × 40 button.
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = 7.5.dp, end = 7.5.dp)
                        .size(40.dp)
                        .clip(RoundedCornerShape(20.dp))
                        .clickable(role = Role.Button, onClick = dismiss)
                        .semantics { contentDescription = MapCopy.CLOSE }
                        .testTag(TestID.Map.OnePlace.closeButton),
                ) {
                    Image(
                        painter = painterResource(R.drawable.place_close),
                        contentDescription = null,
                        modifier = Modifier.size(15.dp),
                    )
                }
            }
        }
    }
}

/** Edge to edge, with the window's own dim, animation and Back handling left to [BittrPopup]. */
private val PanelDialog = DialogProperties(
    usePlatformDefaultWidth = false,
    decorFitsSystemWindows = false,
    dismissOnBackPress = false,
    dismissOnClickOutside = false,
)

/** The rows' and the maps button's 8. */
private val PanelRowShape = RoundedCornerShape(8.dp)

/**
 * The rows' SF Symbols — `mappin.circle.fill`, `link.circle.fill`, `clock.fill` — as a yellow
 * disc with the mark cut out of it in the row's own colour. [fill] draws the mark filled,
 * otherwise it is stroked; [turn] rotates it (the link's two links lie at 45°).
 */
private enum class DetailGlyph(val mark: String, val fill: Boolean, val turn: Float = 0f) {
    ADDRESS("M12 5.6a3.4 3.4 0 110 6.8 3.4 3.4 0 110-6.8z M11.1 11h1.8v7.4h-1.8z", fill = true),
    WEBSITE(
        "M8.4 10.2h2.8a1.8 1.8 0 010 3.6H8.4a1.8 1.8 0 010-3.6z M12.8 10.2h2.8a1.8 1.8 0 010 3.6h-2.8a1.8 1.8 0 010-3.6z",
        fill = false,
        turn = -45f,
    ),
    HOURS("M12 6.5V12l3.5 2.2", fill = false),
}

private const val DISC = "M12 2a10 10 0 100 20 10 10 0 000-20z"

/**
 * A detail row: `whiteorblue3` at 8 dp corners, 15 in from the panel's sides with 10 above
 * it, 45 tall for one line; the 18 dp yellow glyph 15 in and the Gilroy-Bold 16 value 12
 * after it, 12 from the top and 9 from the bottom as it wraps.
 */
@Composable
private fun DetailRow(
    glyph: DetailGlyph,
    text: String,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
) {
    val scheme = MaterialTheme.colorScheme
    val rowColor = scheme.surfaceContainerHigh
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .padding(start = 15.dp, end = 15.dp, top = 10.dp)
            .fillMaxWidth()
            .heightIn(min = 45.dp)
            .clip(PanelRowShape)
            .background(rowColor)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .padding(start = 15.dp, end = 15.dp, top = 12.dp, bottom = 9.dp),
    ) {
        Box(Modifier.size(18.dp)) {
            Image(
                imageVector = rememberFillIcon(DISC, BittrTheme.colors.brandFixed),
                contentDescription = null,
                modifier = Modifier.matchParentSize(),
            )
            Image(
                imageVector = if (glyph.fill) {
                    rememberFillIcon(glyph.mark, rowColor)
                } else {
                    rememberStrokeIcon(glyph.mark, rowColor, strokeWidth = 2f)
                },
                contentDescription = null,
                modifier = Modifier.matchParentSize().rotate(glyph.turn),
            )
        }
        Spacer(Modifier.width(12.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge.copy(fontSize = 16.sp),
            color = scheme.onSurface,
        )
    }
}

/**
 * Hands the place to a maps app; false when nothing on the device would take it.
 *
 * 1. `geo:0,0?q=lat,lon(Name)` — the standard hand-off. The `0,0` plus a query is the
 *    form that drops a labelled pin rather than just centring; the name is in it so the
 *    destination shows the shop, as `MKMapItem.name` does on iOS.
 * 2. Google Maps' search URL in whatever browser there is. The test emulator has Google
 *    Maps disabled and nothing else answers `geo:`, which is how "Open in Maps" came to
 *    do nothing at all (review pass 3). What leaves the device is the *place's*
 *    coordinate, after a tap asking for exactly that — never the user's.
 * 3. Neither: the caller says so rather than doing nothing.
 *
 * `startActivity` and its exception rather than `resolveActivity`: since API 30 the
 * latter needs a `<queries>` entry to see anything, and without one it reports "no
 * handler" for intents that would have launched.
 */
private fun BitcoinPlace.openInMaps(context: Context): Boolean {
    if (!hasPosition) return false
    val label = Uri.encode(name ?: MapCopy.PLACE_FALLBACK_NAME)
    val attempts = listOf(
        "geo:0,0?q=$lat,$lon($label)",
        "https://www.google.com/maps/search/?api=1&query=$lat,$lon",
    )
    return attempts.any { uri ->
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
