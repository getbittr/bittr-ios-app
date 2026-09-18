package com.bittr.android.feature.map

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.dismissOnPullDown
import com.bittr.android.core.designsystem.exposeTestTags
import com.bittr.android.core.designsystem.rememberStrokeIcon

/**
 * One place, over the map. Ported from `OnePlaceViewController`.
 *
 * A `Dialog` rather than a sibling composable so it genuinely sits in its own
 * window over the map and takes the system back gesture as a dismissal.
 *
 * Address, website and opening hours each appear only when the place carries them,
 * matching iOS's three `show*` methods. The website row's absence is not cosmetic:
 * `bitcoin_map.yaml` guards its whole website section on `map.onePlace.websiteButton`
 * being visible, so a row that is always present with an empty value would send the
 * flow into an in-app browser with nothing to load.
 *
 * **Closing (review pass 3).** The top-right back arrow became a centred drag handle, and
 * a pull down on the sheet closes it, as iOS's swipe does. The handle's whole 48 dp strip
 * is the tap target and carries `map.onePlace.closeButton`, which the flow taps after its
 * trip to the maps app — so the id kept its tappable control, only the glyph changed.
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

    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            contentAlignment = Alignment.BottomCenter,
            // The Dialog is its own window, so the app root's testTagsAsResourceId does
            // not reach `map.onePlace.*` — see exposeTestTags.
            modifier = Modifier.fillMaxSize().exposeTestTags(),
        ) {
            // The tap-to-dismiss scrim is a *sibling* of the card, not its parent.
            // `Modifier.clickable` sets `mergeDescendants`, so a clickable wrapper
            // would collapse the whole sheet into one semantics node carrying only
            // the wrapper's identity — every id the flow taps here
            // (`map.onePlace.nameLabel`, `closeButton`, `websiteButton`,
            // `goToMapsButton`) would stop existing while the sheet looked correct.
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(colors.scrim2)
                    .clickable(role = Role.Button, onClick = onClose),
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.canvas, BittrCanvasShapes.card)
                    .dismissOnPullDown(onClose)
                    .verticalScroll(rememberScrollState())
                    .padding(start = BittrTokens.Spacing.lg, end = BittrTokens.Spacing.lg, bottom = BittrTokens.Spacing.lg),
            ) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(BittrTokens.Size.minTouchTarget)
                        .clickable(role = Role.Button, onClick = onClose)
                        .semantics { contentDescription = MapCopy.CLOSE }
                        .testTag(TestID.Map.OnePlace.closeButton),
                ) {
                    Box(
                        Modifier
                            .size(width = 32.dp, height = 4.dp)
                            .background(colors.onCanvas.copy(alpha = 0.25f), RoundedCornerShape(2.dp)),
                    )
                }

                // `placeNameLabel` is Gilroy-Bold **22** (`33m-oo-gb6`,
                // `Main.storyboard:2805`) — the headline of the sheet, not a
                // section header. `titleLarge` is the slot the scale fills at
                // 22; it was reading `titleMedium`'s 18. BIT-152.
                Text(
                    text = place.name ?: MapCopy.UNAVAILABLE,
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.testTag(TestID.Map.OnePlace.nameLabel),
                )
                // `typeLabel` is Gilroy-Bold 16 on iOS (`UqK-Av-YNJ`, wired
                // at `Main.storyboard:3097`) — the same slot as a row title,
                // not a caption. BIT-151.
                Text(
                    text = categoryDescription(place.icon),
                    style = MaterialTheme.typography.labelLarge,
                )

                CanvasSpacer(BittrTokens.Spacing.md)

                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    place.address?.let { address ->
                        DetailRow(icon = MapIconPaths.PIN, text = address)
                    }
                    place.website?.let { website ->
                        DetailRow(
                            icon = BittrIconPaths.LANGUAGE,
                            text = displayWebsite(website),
                            onClick = { onOpenWebsite(website) },
                            modifier = Modifier.testTag(TestID.Map.OnePlace.websiteButton),
                        )
                    }
                    place.openingHours?.let { hours ->
                        DetailRow(icon = MapIconPaths.CLOCK, text = hours)
                    }
                }

                CanvasSpacer(BittrTokens.Spacing.md)

                // The hand-off to a maps app. iOS raises a chooser alert because it
                // has to ask whether Google Maps is installed; Android's implicit
                // `geo:` intent is answered by whatever the user has, and the system
                // runs the chooser — so the alert has no counterpart here.
                //
                // A tonal button since review pass 3, not a fourth data row: it is the
                // one action on the sheet.
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp)
                        .clip(TonalButtonShape)
                        .background(colors.tonalFill)
                        .clickable(role = Role.Button) {
                            if (!place.openInMaps(context)) onMapsUnavailable()
                        }
                        .testTag(TestID.Map.OnePlace.goToMapsButton),
                ) {
                    Image(
                        imageVector = rememberStrokeIcon(BittrIconPaths.MAP, colors.onTonalFill, strokeWidth = 2f),
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = MapCopy.OPEN_IN_MAPS,
                        style = MaterialTheme.typography.labelLarge,
                        color = colors.onTonalFill,
                    )
                }
            }
        }
    }
}

private val DetailRowShape = RoundedCornerShape(16.dp)
private val TonalButtonShape = RoundedCornerShape(26.dp)

/**
 * A data row: white (the scheme's `surfaceContainer`, as the place list's rows), a gold
 * glyph, and the value. The value is Bold 16, standing in for the review's semibold —
 * Gilroy ships in two weights here, and a synthesised 600 would be neither.
 */
@Composable
private fun DetailRow(
    icon: String,
    text: String,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
) {
    val scheme = MaterialTheme.colorScheme
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(DetailRowShape)
            .background(scheme.surfaceContainer)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = BittrTokens.Spacing.sm),
    ) {
        Image(
            imageVector = rememberStrokeIcon(icon, BittrTheme.colors.rowLabel, strokeWidth = 2f),
            contentDescription = null,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.width(12.dp))
        Text(text = text, style = MaterialTheme.typography.labelLarge, color = scheme.onSurface)
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
