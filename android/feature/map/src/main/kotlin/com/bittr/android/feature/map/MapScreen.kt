package com.bittr.android.feature.map

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrCanvasShapes
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import kotlinx.coroutines.launch

/**
 * The Bitcoin map — a basemap with the nearby places on it, and the list of the same
 * places under it.
 *
 * Ported from `MapViewController` and its four extensions. What carries across:
 *
 * - **The sync sequence.** Cached places first so a second visit is never blank,
 *   then the network sync, then the merge. `map.mapSpinner` stops when the sync
 *   returns, whichever way it returned.
 * - **The debounce.** A camera move schedules a refresh 0.6 s later
 *   (`MapVCLocations.swift:82-88`); panning does not re-filter the whole dataset on
 *   every frame.
 * - **The proximity filter runs here, on the device.** That is the property the
 *   approved copy rests on — see [bitcoinMapUrl].
 * - **One position fix, taken on the my-location button and on arrival.** See
 *   [UserLocationFix].
 *
 * What does not: iOS's swipe-to-dismiss on the place sheet, and the Google Maps
 * chooser alert, which exists because iOS cannot know whether Google Maps is
 * installed without asking. On Android the hand-off is an implicit `geo:` intent and
 * the system's own chooser does that job, which is why there is no alert here.
 */
@Composable
fun MapScreen(onBack: () -> Unit, modifier: Modifier = Modifier) =
    MapScreen(onBack = onBack, modifier = modifier, repository = null)

/**
 * The same screen with its places source and its basemap supplied.
 *
 * Both seams exist for the same reason: the renderer cannot compose on the JVM. It
 * loads a native library and wants a GL surface, so a Robolectric test that composed
 * [BasemapView] would fail at `MapLibre.getInstance` — and everything else on this
 * screen, which is every identifier `bitcoin_map.yaml` drives except `map.mapView`
 * itself, composes perfectly well. Passing a stub basemap is what lets the flow's
 * steps be checked in seconds rather than only on an emulator.
 *
 * Internal because [PlacesRepository] is: BTCMap's response shape is a detail of
 * this module.
 */
@Composable
internal fun MapScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    repository: PlacesRepository? = null,
    basemap: @Composable (
        region: MapRegion,
        places: List<BitcoinPlace>,
        onRegionChanged: (MapRegion) -> Unit,
        modifier: Modifier,
    ) -> Unit = { region, places, onRegionChanged, basemapModifier ->
        BasemapView(region, places, onRegionChanged, basemapModifier)
    },
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val places = remember(repository) { repository ?: HttpPlacesRepository(context) }

    var state by remember { mutableStateOf(MapUiState()) }

    // Cached places, then the sync. Two effects rather than one so the cached set
    // paints without waiting on the network.
    LaunchedEffect(places) {
        val cached = places.cached()
        if (cached.isNotEmpty()) {
            state = state.copy(allPlaces = cached).withPlacesForRegion()
        }
        val synced = runCatching { places.sync() }
        state = synced.fold(
            onSuccess = { state.copy(allPlaces = it, isSyncing = false).withPlacesForRegion() },
            onFailure = {
                // iOS only raises the alert when there is nothing cached to fall back
                // on (`BitcoinPlace.swift:82-91`) — a failed refresh over a good
                // cache is not worth interrupting anyone for.
                state.copy(isSyncing = false).let { failed ->
                    if (failed.allPlaces.isEmpty()) {
                        failed.copy(alert = MapAlert(MapCopy.OOPS, MapCopy.PLACES_ERROR))
                    } else {
                        failed
                    }
                }
            },
        )
    }

    // The arrival fix. iOS asks in `viewDidAppear` and centres once if it gets one;
    // with no permission and no fix the default region is what stays on screen.
    LaunchedEffect(Unit) {
        val fix = UserLocationFix.current(context) ?: return@LaunchedEffect
        state = state.copy(
            region = MapRegion(fix.latitude, fix.longitude, MapRegion.USER_SPAN_DEGREES),
        ).withPlacesForRegion()
    }

    BittrCanvas(modifier = modifier, onBack = onBack) {
        Text(
            text = MapCopy.TITLE,
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(horizontal = BittrTokens.Spacing.gutter),
        )
        CanvasSpacer(BittrTokens.Spacing.xs)
        Text(
            text = MapCopy.TOP_LABEL,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(horizontal = BittrTokens.Spacing.gutter),
        )
        CanvasSpacer(BittrTokens.Spacing.sm)

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(280.dp)
                .padding(horizontal = BittrTokens.Spacing.gutter),
        ) {
            basemap(
                state.region,
                state.visiblePlaces,
                { moved -> state = state.copy(region = moved).withPlacesForRegion() },
                Modifier.fillMaxSize().testTag(TestID.Map.mapView),
            )

            if (state.isSyncing) {
                CircularProgressIndicator(
                    color = BittrTheme.colors.onCanvas,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .testTag(TestID.Map.mapSpinner),
                )
            }

            // The my-location button. Tapping it takes a fresh fix and recentres;
            // with no permission or no fix it says so, which is iOS's
            // `locationunavailable` path rather than a silent no-op.
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(BittrTokens.Spacing.sm)
                    .size(44.dp)
                    .background(BittrTheme.colors.scrim1, CircleShape)
                    .clickable(role = Role.Button) {
                        scope.launch {
                            val fix = UserLocationFix.current(context)
                            state = if (fix == null) {
                                state.copy(
                                    alert = MapAlert(
                                        MapCopy.OOPS,
                                        MapCopy.LOCATION_UNAVAILABLE,
                                    ),
                                )
                            } else {
                                state.copy(
                                    region = MapRegion(
                                        fix.latitude,
                                        fix.longitude,
                                        MapRegion.USER_SPAN_DEGREES,
                                    ),
                                ).withPlacesForRegion()
                            }
                        }
                    }
                    .testTag(TestID.Map.userLocationButton),
            ) {
                Text("◎", style = MaterialTheme.typography.titleMedium)
            }
        }

        CanvasSpacer(BittrTokens.Spacing.sm)

        // The BTCMap credit. Reading it is the only way the approved alert is seen,
        // which is why `shared/strings/README.md` is emphatic that it is good
        // practice rather than disclosure.
        Text(
            text = MapCopy.POWERED_BY,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier
                .padding(horizontal = BittrTokens.Spacing.gutter)
                .clickable(role = Role.Button) {
                    state = state.copy(
                        alert = MapAlert(MapCopy.TITLE, MapCopy.POWERED_BY_ALERT),
                    )
                }
                .testTag(TestID.Map.poweredByButton),
        )

        CanvasSpacer(BittrTokens.Spacing.sm)

        if (state.showsNoPlaces) {
            Text(
                text = MapCopy.NO_PLACES,
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = BittrTokens.Spacing.gutter),
            )
        }

        PlacesList(
            places = state.visiblePlaces,
            onOpen = { state = state.copy(openPlace = it) },
            modifier = Modifier.weight(1f),
        )
    }

    state.openPlace?.let { place ->
        OnePlaceSheet(
            place = place,
            onClose = { state = state.copy(openPlace = null) },
            onOpenWebsite = { state = state.copy(openWebsite = it) },
        )
    }

    state.openWebsite?.let { url ->
        WebsiteScreen(url = url, onClose = { state = state.copy(openWebsite = null) })
    }

    state.alert?.let { alert ->
        BittrAlertDialog(
            title = alert.title,
            message = alert.message,
            confirmLabel = if (alert.message == MapCopy.POWERED_BY_ALERT) {
                MapCopy.CLOSE
            } else {
                MapCopy.OKAY
            },
            onConfirm = { state = state.copy(alert = null) },
            confirmTestTag = TestID.Alert.buttonAt(0),
        )
    }
}

@Composable
private fun PlacesList(
    places: List<BitcoinPlace>,
    onOpen: (BitcoinPlace) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(BittrTokens.Spacing.xs),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            horizontal = BittrTokens.Spacing.gutter,
            vertical = BittrTokens.Spacing.xs,
        ),
        modifier = modifier
            .fillMaxWidth()
            .testTag(TestID.Map.placesTableView),
    ) {
        items(places, key = { place -> place.id }) { place ->
            PlaceRow(place = place, onOpen = onOpen)
        }
    }
}

/**
 * One place cell.
 *
 * Every row carries `map.placeCellButton` **and** `map.placeName`, matching iOS
 * where both identifiers are set on every cell (`MapVCTable.swift:44-47`) — the flow
 * taps `index: 0`, so they repeat rather than being unique.
 *
 * **The tap target is a sibling of the labels, not their parent**, which is the only
 * arrangement that keeps both identifiers addressable. `Modifier.clickable` sets
 * `mergeDescendants`, so a clickable row *containing* the name label collapses the
 * two into one node carrying only the row's tag — `map.placeName` then does not
 * exist, on the semantics tree or on the accessibility tree Maestro reads, while the
 * screen looks exactly right. iOS has the same shape for a different reason: a
 * transparent `cellButton` over the labels.
 */
@Composable
private fun PlaceRow(place: BitcoinPlace, onOpen: (BitcoinPlace) -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(BittrTheme.colors.scrim1, BittrCanvasShapes.field),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = BittrTokens.Spacing.md, vertical = BittrTokens.Spacing.sm),
        ) {
            Text(
                text = place.name ?: MapCopy.PLACE_FALLBACK_NAME,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.testTag(TestID.Map.placeName),
            )
            // iOS collapses the address row to zero height when there is none
            // (`MapVCTable.swift:49-56`) rather than leaving a gap.
            place.address?.let { address ->
                Text(
                    text = address,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Box(
            modifier = Modifier
                .matchParentSize()
                .clickable(role = Role.Button) { onOpen(place) }
                .testTag(TestID.Map.placeCellButton),
        )
    }
}

/**
 * Keeps the renderer's lifecycle attached to the composition.
 *
 * `MapView` is an Android `View` with its own `onStart`/`onStop`/`onDestroy` that
 * must be driven by hand — it holds a GL surface and a native map instance, and
 * skipping `onDestroy` leaks both. [DisposableEffect] is where that happens.
 */
@Composable
private fun BasemapView(
    region: MapRegion,
    places: List<BitcoinPlace>,
    onRegionChanged: (MapRegion) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val controller = remember { BasemapController(context) }

    DisposableEffect(Unit) {
        controller.start()
        onDispose { controller.destroy() }
    }

    LaunchedEffect(region) { controller.centre(region) }
    LaunchedEffect(places) { controller.show(places) }

    androidx.compose.ui.viewinterop.AndroidView(
        factory = { controller.view },
        modifier = modifier,
        update = { controller.onRegionChanged = onRegionChanged },
    )
}
