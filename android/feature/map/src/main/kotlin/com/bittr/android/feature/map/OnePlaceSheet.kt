package com.bittr.android.feature.map

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrIconPaths
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.rememberFillIcon

/**
 * One place, over the map. Ported from `OnePlaceViewController`.
 *
 * A `Dialog` rather than a sibling composable so it genuinely sits in its own
 * window over the map — the renderer draws through a `SurfaceView`, and anything
 * merely composed after it can end up beneath the GL surface.
 *
 * Address, website and opening hours each appear only when the place carries them,
 * matching iOS's three `show*` methods. The website row's absence is not cosmetic:
 * `bitcoin_map.yaml` guards its whole website section on `map.onePlace.websiteButton`
 * being visible, so a row that is always present with an empty value would send the
 * flow into an in-app browser with nothing to load.
 */
@Composable
internal fun OnePlaceSheet(
    place: BitcoinPlace,
    onClose: () -> Unit,
    onOpenWebsite: (String) -> Unit,
) {
    val context = LocalContext.current
    val colors = BittrTheme.colors

    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            contentAlignment = Alignment.BottomCenter,
            modifier = Modifier.fillMaxSize(),
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
                    .padding(BittrTokens.Spacing.lg)
                    .verticalScroll(rememberScrollState()),
            ) {
                Row(
                    verticalAlignment = Alignment.Top,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            text = place.name ?: MapCopy.UNAVAILABLE,
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.testTag(TestID.Map.OnePlace.nameLabel),
                        )
                        Text(
                            text = categoryDescription(place.icon),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(BittrTokens.Size.minTouchTarget)
                            .clickable(role = Role.Button, onClick = onClose)
                            .testTag(TestID.Map.OnePlace.closeButton),
                    ) {
                        androidx.compose.foundation.Image(
                            imageVector = rememberFillIcon(BittrIconPaths.BACK, colors.onCanvas),
                            contentDescription = "Close",
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }

                place.address?.let { address ->
                    CanvasSpacer(BittrTokens.Spacing.md)
                    DetailBlock(text = address)
                }

                place.website?.let { website ->
                    CanvasSpacer(BittrTokens.Spacing.sm)
                    DetailBlock(
                        text = displayWebsite(website),
                        modifier = Modifier
                            .clickable(role = Role.Button) { onOpenWebsite(website) }
                            .testTag(TestID.Map.OnePlace.websiteButton),
                    )
                }

                place.openingHours?.let { hours ->
                    CanvasSpacer(BittrTokens.Spacing.sm)
                    DetailBlock(text = hours)
                }

                CanvasSpacer(BittrTokens.Spacing.md)

                // The hand-off to a maps app. iOS raises a chooser alert because it
                // has to ask whether Google Maps is installed; Android's implicit
                // `geo:` intent is answered by whatever the user has, and the system
                // runs the chooser — so the alert has no counterpart here.
                DetailBlock(
                    text = MapCopy.OPEN_IN_MAPS,
                    modifier = Modifier
                        .clickable(role = Role.Button) {
                            place.openInMapsIntent()?.let { intent ->
                                runCatching { context.startActivity(intent) }
                                    .onFailure { if (it !is ActivityNotFoundException) throw it }
                            }
                        }
                        .testTag(TestID.Map.OnePlace.goToMapsButton),
                )
            }
        }
    }
}

@Composable
private fun DetailBlock(text: String, modifier: Modifier = Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Start,
        modifier = modifier
            .fillMaxWidth()
            .background(BittrTheme.colors.scrim1, BittrCanvasShapes.field)
            .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.sm),
    ) {
        Text(text = text, style = MaterialTheme.typography.bodyMedium)
    }
}

/**
 * `geo:lat,lon?q=lat,lon(Name)` — the standard hand-off.
 *
 * The name is in the query so the destination app shows the shop rather than a bare
 * pin, which is what `MKMapItem.name` does on iOS.
 */
private fun BitcoinPlace.openInMapsIntent(): Intent? {
    if (!hasPosition) return null
    val label = Uri.encode(name ?: MapCopy.PLACE_FALLBACK_NAME)
    return Intent(Intent.ACTION_VIEW, Uri.parse("geo:$lat,$lon?q=$lat,$lon($label)"))
}
