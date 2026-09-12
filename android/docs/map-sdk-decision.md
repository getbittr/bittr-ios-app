# Map SDK decision (BIT-53)

**Decision:** the Android map is built on **MapLibre Native**
(`org.maplibre.gl:android-sdk:11.11.0`), rendering **tiles bittr serves itself**, with
`ACCESS_COARSE_LOCATION` as the only location permission and the places sync kept on
iOS's whole-dataset-download design.

**Status:** both axes decided. The renderer is enforced in the build; the tile host was
signed off by Ruben on 2026-09-11 and is the stronger of the two options that were on the
table — see [Who serves the tiles](#who-serves-the-tiles). What remains is implementation,
not choice: the pipeline that actually serves those tiles does not exist yet and is
[BIT-73](/BIT/issues/BIT-73). Until it does, no map screen should point at a vendor's
tiles, because the shipped copy is written for an architecture with no third party in it.

---

## Why this is a constraint and not a preference

bittr ships this sentence today (`ios/bittr/Helpers/Language.swift:595`, BTCMap
explainer), and it is a factual claim about the app rather than marketing:

> we don't share your location with third parties

Security's read (BIT-45 → BIT-53) is that the sentence as written is not defensible on
either platform, because **any renderer that fetches tiles over the network sends the
viewport — tile x/y/z or a bounding box, plus zoom — together with the client IP, on
every pan and every zoom.** When the map centres on the user, the first viewport request
*is* their approximate position: ~100 m accurate, timestamped, attached to an IP. That is
what a tile request is; no app-side care prevents it.

So the copy is being corrected (BIT-53 → Growth & Content, Compliance), and the SDK
choice is what decides how much the corrected sentence has to concede.

## What each candidate actually transmits

Every candidate leaks the viewport to whoever serves the tiles. The column that
separates them is the **second** channel: what goes to the SDK vendor, separately from
the tile host.

| Candidate | Tile host receives | Separate telemetry to the SDK vendor | My-location position source |
|---|---|---|---|
| Google Maps SDK for Android | Google — viewport + IP, every pan/zoom | **Yes, documented by Google:** device metadata, crash stack traces and metrics, **IP address**, a **pseudonymous Maps-SDK identifier used to count daily active users**, and **"interaction data, such as panning and zooming the map when the Map Camera APIs are used"** | Play services; Google's docs steer integrators to the Play services Location API |
| Mapbox Maps SDK | Mapbox | Yes — vendor telemetry ships in the SDK. This is the specific thing MapLibre forked to remove | configurable |
| **MapLibre Native + a named tile host** | that tile host | **None.** The telemetry class was removed in the fork; nothing goes to Mapbox or to MapLibre | `MapLibreFusedLocationEngineImpl`, on the platform `LocationManager`. Play services is opt-in, not the default |
| MapLibre Native + tiles bittr controls | **bittr only** | None | same |
| osmdroid + OSM tile servers | OSM Foundation | None from the library | platform `LocationManager` |

**Google Maps SDK is excluded on the third column.** It is the only candidate that
additionally transmits pan/zoom interaction data *and* IP *and* a stable pseudonymous
identifier to the same vendor. Those three composed are not incidental metadata; they
are a record of where this install looked, keyed to a persistent ID. Choosing it would
turn "a third party sees a viewport" into "a documented, ID-linked record of where this
user looked" — and all four data types would have to be declared by bittr in the Play
Console data-safety form (BIT-15), where Google puts the responsibility on the app and
not on the SDK.

**Mapbox is excluded on the same column**, one rung less severe.

**osmdroid is excluded on grounds that are not privacy at all**: it is a raster tile
viewer, the OSM Foundation's tile servers have a usage policy that a consumer app is not
entitled to lean on, and it has no vector-style equivalent to what iOS renders.

## Two things that were verified against the artefacts, not the documentation

Both of these were checked by downloading the published AARs on 2026-09-11 and reading
the manifests inside them, because the answer inverts what the documentation implies.

**1. MapLibre's own AAR declares `ACCESS_FINE_LOCATION`.**
`org.maplibre.gl:android-sdk:11.11.0` ships this manifest:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

The manifest merger unions permissions across dependencies, so adding this one line to
`app/build.gradle.kts` is enough to put **precise location** in the merged manifest, on
the Play listing's permission list, and in the runtime dialog as a *Precise / Approximate*
toggle preselected on precise — with no Kotlin change for anyone to review, and invisible
to any source scan. The `tools:node="remove"` directive that BIT-57 put in
`app/src/main/AndroidManifest.xml` before any SDK existed is what stops it, and as of this
commit it is load-bearing rather than precautionary.

**2. Google's `play-services-maps` AAR declares no location permission at all** — only
`INTERNET` and `ACCESS_NETWORK_STATE` (checked at 20.0.0). The `FINE` risk BIT-53 named
for Google is real but it lives in the *sample code*: Google's My Location sample requests
`ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` together, so the permission arrives by
copy-paste rather than by merge.

The practical lesson is that the risk was in the opposite place from where either of us
would have guessed, which is the argument for the guards being tests: the merged manifest
is asserted, so it does not matter which mechanism tries to put `FINE` there.

`app/build/outputs/logs/manifest-merger-debug-report.txt` records the outcome verbatim:

```
uses-permission#android.permission.ACCESS_FINE_LOCATION
ADDED from .../app/src/main/AndroidManifest.xml:37:5-99
REJECTED from [org.maplibre.gl:android-sdk:11.11.0] .../AndroidManifest.xml:15:5-79
```

**What MapLibre does add to the merged manifest**, and therefore to the Play listing
(BIT-51) and the data-safety form (BIT-15): `INTERNET`, `ACCESS_NETWORK_STATE` and
`ACCESS_WIFI_STATE`, plus `<uses-feature android:name="android.hardware.wifi"
android:required="false" />`. None is a runtime permission and none carries a location
claim, but `ACCESS_WIFI_STATE` renders on the listing as "view Wi-Fi connections", so
whoever writes the listing should not be surprised by it. The full merged permission set
of the debug APK after this change is `ACCESS_COARSE_LOCATION`, `INTERNET`,
`ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`.

## Coarse location only

`ACCESS_COARSE_LOCATION`, and no precise-location permission, is the faithful port of
iOS's `kCLLocationAccuracyHundredMeters` (`Map/MapViewController.swift:80`) and is bound
by the approved permission copy (DEV-54, BIT-36):

> To centre the map on where you are, bittr needs your approximate location.

Requesting `FINE` and rounding the coordinate afterwards does **not** satisfy this. The
permission changes the dialog the user reads and the listing a non-user reads, before any
code runs. Coarse alone can only ever grant approximate, whatever the user taps.

MapLibre works under coarse-only: `LocationEngineDefault` returns
`MapLibreFusedLocationEngineImpl`, which drives the platform `LocationManager`'s network
provider, and `PermissionsManager.areLocationPermissionsGranted` is satisfied by the
coarse grant. Nothing in the my-location path needs Play services, and
`play-services-location` is banned by `MapSdkGuardTest` so it cannot arrive quietly.

## The places sync stays whole-dataset

iOS requests `fields`, `include_deleted` and `updated_since` and nothing else
(`BitcoinPlace.swift:37-55`), then filters the cached set in-process against the *map's*
centre coordinate rather than the user's fix (`MapVCLocations.swift:91-110`).

That design is the reason bittr's surviving claim is stronger than "we don't share it":
**against bittr's backend and against BTCMap, the user's location never leaves the
device.** A bounding-box query is cheaper, renders identically and passes every flow, and
would end that property silently — the first request after the map centres on the user
*is* their approximate position. Do not switch to one. `MapSdkGuardTest` fails the build
if a BTCMap request in this repo ever carries viewport keys — **but no Kotlin file matches
its places-source markers yet, so that check passes vacuously until the map screen lands.**
It is in place ahead of time so the commit that writes the first BTCMap request is already
covered; it is not evidence that anything is being checked today.

## What the build enforces

| Property | Where |
|---|---|
| No precise-location permission in the merged manifest | `LocationPrecisionGuardTest` (source scan, manifest scan, removal directive, and the merged result read back through `PackageManager`) |
| Coarse location **is** in the merged manifest | `MapSdkGuardTest` — an app requesting no location at all would pass the test above |
| Google Maps / Mapbox / osmdroid / `play-services-location` off the dependency graph | `MapSdkGuardTest` |
| MapLibre still *is* the renderer | `MapSdkGuardTest` — the shipped copy names no provider, so a swap is not a copy change and nothing outside the build would flag one; a renderer that also reports to its own vendor is a regression the wording would not reveal |
| No bounding-box BTCMap request | `MapSdkGuardTest` — **latent**: nothing matches its places-source markers until the map screen lands, so a green run is not yet evidence here |

All of these run on the JVM in `./gradlew test`, which is the `Unit tests` step of
`.github/workflows/android-maestro.yml` — it runs on every push and pull request touching
`android/**`. No emulator needed.

## Who serves the tiles

**bittr serves them.** Ruben's call on 2026-09-11, choosing the stronger option over the
cheaper one that was recommended here.

Three options were put up: MapTiler (recommended at the time, as the cheapest path that
keeps the remaining third party Swiss), bittr hosting the tiles, or deferring until the
map screen is built. The choice was the second.

### Why it matters more than a vendor line-item

Every renderer that fetches tiles tells the tile host which area the user is looking at,
plus the client IP. That is unavoidable for an online map, so the only question was ever
*who* learns it. With a vendor in the path, the copy has to concede a third party. With
tiles bittr serves, **there is no third party in the path at all** — which is what was
bought here, and it is worth being precise about what it is not.

**It is not "nobody sees it".** A bittr-operated tile server receives viewport plus IP on
every pan for the same mechanical reason any tile host does; the requests land in bittr's
logs rather than a vendor's. Whether they are retained is now bittr's decision instead of
a vendor's, which is the whole gain — and it makes tile-request logging a privacy
property of [BIT-73](/BIT/issues/BIT-73), not an ops preference. If that pipeline lands
with logging off or IPs truncated at the edge, tell the Growth & Content Lead: it changes
what the copy is allowed to say.

**It is not a two-platform claim either.** iOS still renders with `MKMapView` against
Apple's tile servers (`ios/bittr/Map/MapViewController.swift:18`, `:77`, verified at the
head of `android`), so Apple receives the viewport on every pan there, and on first open
that viewport is the user's approximate position. This decision covered the Android tile
host and touched nothing on iOS. Restoring an unqualified "bittr does not share your
location with third parties" would be true on the platform that does not ship yet and
false on the one in the App Store. Getting there needs iOS off MapKit, which nobody has
scoped.

**Where BIT-56 landed, having been told the premise changed.** The Growth & Content Lead
took the neutral hedge and moved it, on `feature/bit-56-btcmap-location-copy`
(`d610cac`, `shared/strings/en.json` and `ios/bittr/Language.swift:595`): the strong claim
is now scoped to the places lookup, where it is unconditionally true and untouched by the
tile decision, and the map sentence owns the tile fetch separately without naming anyone —
"whoever serves them sees the area you are looking at". That survives both architectures
and both platforms. The upgrade to "we serve those map images ourselves" is recorded in
`shared/strings/README.md` against BIT-73 shipping, because it is a fact worth more than
the hedge only once it is a fact.

Two consequences for the Android side. The copy names no provider, so a renderer swap is
not a copy change and `MapSdkGuardTest` is the only thing that will catch one. And no map
screen should be pointed at a vendor's tiles while that sentence is in the app.

### What it costs, and what is now implementation rather than choice

MapLibre Native ships an `MBTilesFileSource` (confirmed present in the 11.11.0 native
library), so a basemap can come from a file on the device or from a host bittr controls.
The renderer already supports this; nothing about the SDK decision changes. The real work
is the hosting pipeline, and it is not free:

| Piece | Why it is not trivial |
|---|---|
| Basemap extract | An OSM-derived vector basemap for the regions bittr serves, not the whole planet, or the artefact is hundreds of GB |
| Storage and serving | PMTiles on a CDN, or MBTiles shipped in-app for a fixed region — different tradeoffs in size and freshness |
| Update cadence | A stale basemap is a visibly wrong map; this needs an owner and a schedule, not a one-off build |
| Attribution | OSM's licence requires credit regardless of who serves the tiles |

None of this blocks the SDK work, and none of it is needed before the map screen is laid
out. It does need to land before the map ships, which is why it is tracked as its own
issue rather than left in this document as a footnote.

### Still reversible, but the default has moved

No source file names a tile vendor — verified across `android/` at the time of this
decision, and the style URL stays a single configuration point when the map screen lands.
So this remains reversible in one place *in the code*. The copy is the part that is not
cheaply reversible: if tile hosting is ever abandoned for a vendor, the shipped sentence
stops being true and has to change on **both** platforms, which is a Growth & Content Lead
decision and not an infrastructure one.
