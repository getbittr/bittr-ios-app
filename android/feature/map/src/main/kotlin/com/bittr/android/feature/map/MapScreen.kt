package com.bittr.android.feature.map

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.exposeTestTags
import com.bittr.android.core.designsystem.BittrCanvas
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.rememberFillIcon
import com.bittr.android.core.designsystem.rememberStrokeIcon
import com.bittr.android.feature.website.WebsiteScreen
import kotlinx.coroutines.launch

/**
 * BTCMap's `website` values are inconsistent — some carry a scheme, some do not.
 * A `WebView` handed `example.com` treats it as a relative reference and shows
 * nothing, so the scheme is supplied here, at the edge where the untrusted place
 * data enters, rather than in the browser.
 *
 * `https`, never `http`: an upgrade the site refuses is a page that fails to
 * load, which is the safe direction, and `mixedContentMode` in
 * `HardenedWebView` is set on the assumption that the top-level load is secure.
 */
private fun String.withScheme(): String =
    if (startsWith("http://") || startsWith("https://")) this else "https://$this"

/**
 * The Bitcoin map — a basemap with the nearby places on it, and the list of the same
 * places under it.
 *
 * Ported from `MapViewController` and its four extensions. What carries across:
 *
 * - **The sync sequence.** Cached places first so a second visit is never blank,
 *   then the network sync, then the merge. `map.mapSpinner` stops when the sync
 *   returns, whichever way it returned.
 * - **The debounce.** The list refreshes when the camera goes idle after a pan
 *   (`MapVCLocations.swift:82-88` waits 0.6 s); panning does not re-filter the whole
 *   dataset on every frame.
 * - **The proximity filter runs here, on the device.** That is the property the
 *   approved copy rests on — see [bitcoinMapUrl].
 * - **One position fix, taken on the my-location button and on arrival.** See
 *   [UserLocationFix].
 *
 * What does not: the Google Maps chooser alert, which exists because iOS cannot know
 * whether Google Maps is installed without asking. On Android the hand-off is an
 * implicit `geo:` intent and the system's own chooser does that job — see
 * [OnePlaceSheet] for what happens when nothing answers it.
 *
 * The camera frames the places rather than following the region; [CameraMove] says why,
 * and why that is what made the pins visible.
 */
@Composable
fun MapScreen(onBack: () -> Unit, modifier: Modifier = Modifier) =
    MapScreen(onBack = onBack, modifier = modifier, repository = null)

/**
 * What the screen hands its basemap. One value rather than four parameters so the
 * stub in the flow tests does not change shape every time the map learns something.
 */
internal data class BasemapInputs(
    val places: List<BitcoinPlace>,
    val camera: CameraMove,
    val onRegionChanged: (MapRegion) -> Unit,
    val onPlaceTapped: (Int) -> Unit,
)

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
    basemap: @Composable (inputs: BasemapInputs, modifier: Modifier) -> Unit = { inputs, basemapModifier ->
        BasemapView(inputs, basemapModifier)
    },
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val places = remember(repository) { repository ?: HttpPlacesRepository(context) }
    val colors = BittrTheme.colors

    var state by remember { mutableStateOf(MapUiState()) }

    // Cached places, then the sync. Two effects rather than one so the cached set
    // paints without waiting on the network.
    LaunchedEffect(places) {
        val cached = places.cached()
        if (cached.isNotEmpty()) {
            state = state.copy(allPlaces = cached).withPlacesForRegion().framedIfUntouched()
        }
        val synced = runCatching { places.sync() }
        state = synced.fold(
            onSuccess = {
                state.copy(allPlaces = it, isSyncing = false).withPlacesForRegion().framedIfUntouched()
            },
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
            hasFix = true,
        ).withPlacesForRegion().framed()
    }

    BittrCanvas(modifier = modifier, onBack = onBack) {
        Text(
            text = MapCopy.HEADING,
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(horizontal = BittrTokens.Spacing.gutter),
        )
        CanvasSpacer(BittrTokens.Spacing.xs)
        Text(
            text = MapCopy.TOP_LABEL,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(horizontal = BittrTokens.Spacing.gutter),
        )
        CanvasSpacer(BittrTokens.Spacing.md)

        // The map card (review pass 3): the gutter on both sides *before* the width, so
        // the card is the screen less two equal margins; clipped to its radius, which
        // the renderer honours because it draws in texture mode (see BasemapController).
        Box(
            modifier = Modifier
                .padding(horizontal = BittrTokens.Spacing.gutter)
                .fillMaxWidth()
                .height(MapCardHeight)
                .clip(MapCardShape)
                // On the frame, not on the basemap. MapLibre is an AndroidView, and an
                // embedded View takes over the accessibility of its node — a testTag on
                // that modifier never reached Maestro, so `map.mapView` was not found on
                // a device while every JVM test (with a stub basemap) found it.
                .testTag(TestID.Map.mapView),
        ) {
            basemap(
                BasemapInputs(
                    places = state.visiblePlaces,
                    camera = state.camera,
                    onRegionChanged = { moved ->
                        state = state.copy(region = moved, userMoved = true).withPlacesForRegion()
                    },
                    onPlaceTapped = { id ->
                        state.allPlaces.firstOrNull { it.id == id }?.let { tapped ->
                            state = state.copy(openPlace = tapped)
                        }
                    },
                ),
                Modifier.fillMaxSize(),
            )

            if (state.isSyncing) {
                BittrSpinner(
                    color = colors.onChartSurface,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .testTag(TestID.Map.mapSpinner),
                )
            }

            // The my-location button. Tapping it takes a fresh fix and frames the places
            // around it; with no permission or no fix it says so, which is iOS's
            // `locationunavailable` path rather than a silent no-op.
            //
            // Brand yellow with an ink glyph in both schemes: it sits on the basemap,
            // which is a fixed light surface (see BasemapPalette), not on the canvas.
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp)
                    .size(BittrTokens.Size.minTouchTarget)
                    .clip(CircleShape)
                    .background(colors.brandFixed)
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
                                    hasFix = true,
                                ).withPlacesForRegion().framed()
                            }
                        }
                    }
                    .testTag(TestID.Map.userLocationButton),
            ) {
                Image(
                    imageVector = rememberFillIcon(MapIconPaths.MY_LOCATION, colors.onChartSurface),
                    contentDescription = "Show places near me",
                    modifier = Modifier.size(24.dp),
                )
            }
        }

        CanvasSpacer(12.dp)

        // The BTCMap credit. Reading it is the only way the approved alert is seen,
        // which is why `shared/strings/README.md` is emphatic that it is good
        // practice rather than disclosure.
        //
        // Bold 14, which is what `poweredByLabel` is on iOS — the storyboard sets
        // Gilroy-Bold 14 on `Maz-HE-siC` and no code in `ios/bittr/Map/` overrides a
        // font, so the storyboard is the whole story here. BIT-151. Centred under the
        // card since review pass 3.
        Text(
            text = MapCopy.POWERED_BY,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
            textAlign = TextAlign.Center,
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .padding(horizontal = BittrTokens.Spacing.gutter)
                .clickable(role = Role.Button) {
                    state = state.copy(
                        alert = MapAlert(MapCopy.TITLE, MapCopy.POWERED_BY_ALERT),
                    )
                }
                .testTag(TestID.Map.poweredByButton),
        )
        // The basemap's credit, which the tile licences require wherever the map is drawn.
        // Plain text, not a link — `BasemapAttributionGuardTest` explains why that makes the
        // `.org` in the OpenMapTiles credit load-bearing.
        //
        // Review pass 3 asked for this to move into MapLibre's ⓘ sheet. That sheet does show
        // the tile source's own attribution, as links, which would meet the OpenMapTiles
        // notice's other alternative — but only after a tap on an unlabelled glyph, and the
        // guard pins the on-screen line. So it stays, as one small centred line.
        Text(
            text = MapCopy.BASEMAP_ATTRIBUTION,
            style = MaterialTheme.typography.labelMedium,
            color = colors.mutedOnCanvas,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = BittrTokens.Spacing.gutter),
        )

        CanvasSpacer(BittrTokens.Spacing.md)

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
            onMapsUnavailable = {
                state = state.copy(alert = MapAlert(MapCopy.OOPS, MapCopy.MAPS_UNAVAILABLE))
            },
        )
    }

    state.openWebsite?.let { url ->
        // `:feature:website`'s screen — the one WebView in the app, built by
        // `HardenedWebView.create` with the BIT-33 R-11 baseline and the
        // navigation policy on it. A merchant's `website` is whatever an
        // OpenStreetMap contributor typed, so this is the call site that most
        // needs it (BIT-112).
        //
        // The Dialog stays here rather than moving into the screen: iOS presents
        // `WebsiteViewController` modally from `OnePlaceViewController`, whereas
        // the screen's other call site is a navigation destination that must not
        // be wrapped in one. The insets are the Dialog's to supply for the same
        // reason — a full-bleed dialog has none of the host window's padding.
        Dialog(
            onDismissRequest = { state = state.copy(openWebsite = null) },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            WebsiteScreen(
                url = url.withScheme(),
                onClose = { state = state.copy(openWebsite = null) },
                // Its own window: expose test tags so `website.*` ids reach Maestro.
                modifier = Modifier.exposeTestTags().statusBarsPadding().navigationBarsPadding(),
            )
        }
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

/** Review pass 3: a 24 dp card, ~320 dp tall. Not a design-system shape; only the map is one. */
private val MapCardShape = RoundedCornerShape(24.dp)
private val MapCardHeight = 320.dp
private val PlaceRowShape = RoundedCornerShape(16.dp)

@Composable
private fun PlacesList(
    places: List<BitcoinPlace>,
    onOpen: (BitcoinPlace) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(
            start = BittrTokens.Spacing.gutter,
            end = BittrTokens.Spacing.gutter,
            bottom = BittrTokens.Spacing.md,
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
 * **The tap target is a sibling of the labels, drawn under them.** `Modifier.clickable` sets
 * `mergeDescendants`, so a clickable row *containing* the name label collapses the two into one
 * node carrying only the row's tag. A sibling drawn *over* them is no better: a later sibling that
 * covers a node entirely takes it off the accessibility tree, which is how `map.placeName` went
 * missing while the screen looked exactly right. Under the labels, both identifiers stay
 * addressable and the taps still land, because the labels handle no touches. iOS has the same
 * shape for a different reason: a transparent `cellButton` over the labels.
 *
 * Review pass 3's row: a white card (the scheme's `surfaceContainer`, which is white in
 * light mode and follows dark mode rather than staying white on blue), a cream disc with
 * the category glyph in `rowLabel` gold, and the name allowed a second line.
 */
@Composable
private fun PlaceRow(place: BitcoinPlace, onOpen: (BitcoinPlace) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val colors = BittrTheme.colors
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 72.dp)
            .background(scheme.surfaceContainer, PlaceRowShape),
    ) {
        // Drawn first, under the labels. A later sibling that covers a node entirely takes that node
        // off the accessibility tree, so a tap layer on top removed `map.placeName` — which
        // bitcoin_map.yaml asserts. The labels handle no touches, so taps reach this layer anyway.
        Box(
            modifier = Modifier
                .matchParentSize()
                .clip(PlaceRowShape)
                .clickable(role = Role.Button) { onOpen(place) }
                .testTag(TestID.Map.placeCellButton),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(40.dp)
                    .background(colors.tonalFill, CircleShape),
            ) {
                Image(
                    imageVector = rememberStrokeIcon(placeGlyph(place.icon).path, colors.rowLabel, strokeWidth = 2f),
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                // `PlaceTableViewCell`'s two labels: `placeName` is Gilroy-Bold 16
                // (`gYc-Qy-tZC`) and `placeAddress` Gilroy-Regular 15 (`r0k-xV-iLu`).
                // The address is 14 here since review pass 3, and steps back at 70 %.
                Text(
                    text = place.name ?: MapCopy.PLACE_FALLBACK_NAME,
                    style = MaterialTheme.typography.labelLarge,
                    color = scheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.testTag(TestID.Map.placeName),
                )
                // iOS collapses the address row to zero height when there is none
                // (`MapVCTable.swift:49-56`) rather than leaving a gap.
                place.address?.let { address ->
                    Text(
                        text = address,
                        style = MaterialTheme.typography.bodyMedium,
                        color = scheme.onSurface.copy(alpha = 0.70f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

/**
 * Keeps the renderer's lifecycle attached to the composition.
 *
 * `MapView` is an Android `View` with its own `onStart`/`onStop`/`onDestroy` that
 * must be driven by hand — it holds a GL surface and a native map instance, and
 * skipping `onDestroy` leaks both. [DisposableEffect] is where that happens.
 *
 * The marker colours are resolved here, from tokens, because the controller has no
 * theme: brand yellow, a white ring and ink, all fixed across schemes like the basemap
 * they sit on.
 */
@Composable
private fun BasemapView(inputs: BasemapInputs, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val colors = BittrTheme.colors
    val controller = remember {
        BasemapController(
            context,
            MarkerColors(
                fill = colors.brandFixed.toArgb(),
                stroke = colors.chartSurface.toArgb(),
                ink = colors.onChartSurface.toArgb(),
            ),
        )
    }

    DisposableEffect(Unit) {
        controller.start()
        onDispose { controller.destroy() }
    }

    LaunchedEffect(inputs.camera) { controller.move(inputs.camera) }
    LaunchedEffect(inputs.places) { controller.show(inputs.places) }

    androidx.compose.ui.viewinterop.AndroidView(
        factory = { controller.view },
        modifier = modifier,
        update = {
            controller.onRegionChanged = inputs.onRegionChanged
            controller.onPlaceTapped = inputs.onPlaceTapped
        },
    )
}
