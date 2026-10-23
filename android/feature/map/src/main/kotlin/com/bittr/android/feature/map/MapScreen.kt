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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.rememberRetained
import com.bittr.android.core.designsystem.BittrAlertDialog
import com.bittr.android.core.designsystem.BittrSheetHeader
import com.bittr.android.core.designsystem.BittrSpinner
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.core.designsystem.BittrTokens
import com.bittr.android.core.designsystem.CanvasSpacer
import com.bittr.android.core.designsystem.exposeTestTags
import com.bittr.android.core.designsystem.iosShadow
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

    // Kept on the sheet's back-stack entry, not this composition, so the map and an open place
    // are as they were when the app comes back from "Go to maps" — see [rememberRetained].
    val retained = rememberRetained("map") { RetainedMap() }
    var state by retained::state

    // Cached places, then the sync. Two effects rather than one so the cached set
    // paints without waiting on the network. Once per opening: the effects run again when the
    // app comes back to the screen, and the places are already there.
    LaunchedEffect(places) {
        if (retained.loaded) return@LaunchedEffect
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
        retained.loaded = true
    }

    // The arrival fix. iOS asks in `viewDidAppear` and centres once if it gets one;
    // with no permission and no fix the default region is what stays on screen.
    // Once too: again on the way back, it would re-centre a map the user has moved.
    LaunchedEffect(Unit) {
        if (retained.located) return@LaunchedEffect
        val fix = UserLocationFix.current(context)
        retained.located = true
        if (fix == null) return@LaunchedEffect
        state = state.copy(
            region = MapRegion(fix.latitude, fix.longitude, MapRegion.USER_SPAN_DEGREES),
            hasFix = true,
        ).withPlacesForRegion().framed()
    }

    // `MapViewController` in its page sheet: `addHeader`'s map icon and "pay with bitcoin", the
    // line 7 under it in Gilroy Regular 16, centred and 30 from the sides, and the map 25 below.
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvas)
            .navigationBarsPadding(),
    ) {
        BittrSheetHeader(
            icon = painterResource(R.drawable.map_header_icon),
            title = MapCopy.HEADING,
            onDown = onBack,
            titleTestTag = TestID.Header.titleLabel,
            downTestTag = TestID.Header.downButton,
        )
        CanvasSpacer(7.dp)
        Text(
            text = MapCopy.TOP_LABEL,
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 19.sp),
            color = colors.onCanvas,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 30.dp),
        )
        CanvasSpacer(25.dp)

        // `mapBackground`: 15 from the sides and 400 tall, with 12 pt corners and `setShadow()` —
        // the shadow drawn outside the clip, which the renderer honours because it draws in
        // texture mode (see BasemapController).
        Box(
            modifier = Modifier
                .padding(horizontal = 15.dp)
                .fillMaxWidth()
                .height(MapCardHeight)
                .iosShadow(MapCardShape)
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
                    color = colors.onCanvas,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .testTag(TestID.Map.mapSpinner),
                )
            }

            // The basemap's credit, which the tile licences require wherever the map is drawn:
            // behind an ⓘ in the map's corner, where MapLibre draws its own and iOS's map has
            // Apple's "Legal", rather than as a line under the map (Tom, 2026-09-29). The alert
            // shows [MapCopy.BASEMAP_ATTRIBUTION] as written — plain text, so the `.org` in the
            // OpenMapTiles credit stays load-bearing (`BasemapAttributionGuardTest`).
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(6.dp)
                    .size(32.dp)
                    .clip(CircleShape)
                    .clickable(role = Role.Button) {
                        state = state.copy(alert = MapAlert(MapCopy.MAP_CREDITS, MapCopy.BASEMAP_ATTRIBUTION))
                    },
            ) {
                // Ink on the basemap, which is a fixed light surface in both schemes.
                Image(
                    imageVector = rememberFillIcon(
                        MapIconPaths.INFO,
                        colors.onChartSurface.copy(alpha = 0.6f),
                        evenOdd = true,
                    ),
                    contentDescription = MapCopy.MAP_CREDITS,
                    modifier = Modifier.size(18.dp),
                )
            }

            // The my-location button. Tapping it takes a fresh fix and frames the places
            // around it; with no permission or no fix it says so, which is iOS's
            // `locationunavailable` path rather than a silent no-op.
            //
            // `userLocationView`: a 40 pt circle, `whiteorblue3` with `setShadow()`, 15 in from the
            // map's corner, the 20 pt glyph yellow in light and white in dark.
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(15.dp)
                    .size(40.dp)
                    .iosShadow(CircleShape)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
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
                    imageVector = rememberFillIcon(
                        MapIconPaths.MY_LOCATION,
                        if (BittrTheme.isDark) Color.White else colors.brandFixed,
                    ),
                    contentDescription = "Show places near me",
                    modifier = Modifier.size(20.dp),
                )
            }
        }

        // Everything under the map: the places list from the map's bottom edge, starting its first
        // card 60 down (`contentInset.top`), and over its top `poweredByFade` — 60 of the canvas
        // fading to clear, which the cards scroll up behind — with the BTCMap credit 22 below the map.
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        ) {
            PlacesList(
                places = state.visiblePlaces,
                onOpen = { state = state.copy(openPlace = it) },
                modifier = Modifier.fillMaxSize(),
            )

            // `noPlacesLabel`, 50 below the map and 60 from the sides.
            if (state.showsNoPlaces) {
                Text(
                    text = MapCopy.NO_PLACES,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .fillMaxWidth()
                        .padding(start = 60.dp, end = 60.dp, top = 50.dp),
                )
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(PlacesTopInset)
                    .background(Brush.verticalGradient(listOf(colors.canvas, colors.canvas.copy(alpha = 0f)))),
            )

            // The BTCMap credit. Reading it is the only way the approved alert is seen,
            // which is why `shared/strings/README.md` is emphatic that it is good
            // practice rather than disclosure.
            //
            // Bold 14, which is what `poweredByLabel` is on iOS — the storyboard sets
            // Gilroy-Bold 14 on `Maz-HE-siC` and no code in `ios/bittr/Map/` overrides a
            // font, so the storyboard is the whole story here. BIT-151.
            Text(
                text = MapCopy.POWERED_BY,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(start = BittrTokens.Spacing.gutter, end = BittrTokens.Spacing.gutter, top = 22.dp)
                    .clickable(role = Role.Button) {
                        state = state.copy(
                            alert = MapAlert(MapCopy.TITLE, MapCopy.POWERED_BY_ALERT),
                        )
                    }
                    .testTag(TestID.Map.poweredByButton),
            )
        }
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

/** `mapBackground`: 12 pt corners, 400 tall. */
private val MapCardShape = RoundedCornerShape(12.dp)
private val MapCardHeight = 400.dp

/** `PlaceTableViewCell`: the card's 13 pt corners and the icon square's 7. */
private val PlaceRowShape = RoundedCornerShape(13.dp)
private val PlaceIconShape = RoundedCornerShape(7.dp)

/** The places list's `contentInset.top`, and the height of the fade over it. */
private val PlacesTopInset = 60.dp

@Composable
private fun PlacesList(
    places: List<BitcoinPlace>,
    onOpen: (BitcoinPlace) -> Unit,
    modifier: Modifier = Modifier,
) {
    // `placesTableView`: rows 85 apart — a 70 pt card and 15 under it — 15 from the sides.
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(15.dp),
        contentPadding = PaddingValues(start = 15.dp, end = 15.dp, top = PlacesTopInset, bottom = 15.dp),
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
 * `PlaceTableViewCell`: `cellCard` 70 tall, `whiteorblue2` with
 * 13 pt corners and `setShadow()`; `imageContainer` 50 pt square with 7 pt corners, 10 in,
 * `grey1orblue3`, with the category's 24 pt icon in the brand yellow; the name in Gilroy Bold 16
 * and the address 6 under it in Gilroy Regular 15, 15 after the square and 20 from the end.
 */
@Composable
private fun PlaceRow(place: BitcoinPlace, onOpen: (BitcoinPlace) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val colors = BittrTheme.colors
    Box(
        modifier = Modifier
            .fillMaxWidth()
            // Fixed, as iOS's is, so the 50 pt square sits 10 from the top, bottom and leading
            // edge alike; the lines are set tight enough for a two-line name and its address.
            .height(70.dp)
            .iosShadow(PlaceRowShape)
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
                .fillMaxSize()
                .padding(start = 10.dp, end = 20.dp),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(50.dp)
                    .background(colors.placeIconBox, PlaceIconShape),
            ) {
                Image(
                    imageVector = rememberStrokeIcon(placeGlyph(place.icon).path, colors.brandFixed, strokeWidth = 2f),
                    contentDescription = null,
                    modifier = Modifier.size(24.dp),
                )
            }
            Spacer(Modifier.width(15.dp))
            Column(
                modifier = Modifier
                    .weight(1f)
                    .offset(y = 1.dp),
            ) {
                Text(
                    text = place.name ?: MapCopy.PLACE_FALLBACK_NAME,
                    style = MaterialTheme.typography.labelLarge.copy(fontSize = 16.sp, lineHeight = 17.sp),
                    color = scheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.testTag(TestID.Map.placeName),
                )
                // iOS collapses the address row to zero height when there is none
                // (`MapVCTable.swift:49-56`) rather than leaving a gap.
                place.address?.let { address ->
                    CanvasSpacer(4.dp)
                    Text(
                        text = address,
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp, lineHeight = 15.sp),
                        color = scheme.onSurface,
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

/** What [MapScreen] keeps across the app's stop: its state, and which arrival effects have run. */
private class RetainedMap {
    var state by mutableStateOf(MapUiState())
    var loaded = false
    var located = false
}
