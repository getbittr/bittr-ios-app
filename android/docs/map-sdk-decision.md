# Map SDK decision (BIT-53)

**Decision:** the Android map is built on **MapLibre Native**
(`org.maplibre.gl:android-sdk:11.11.0`), rendering tiles served by **MapTiler**, with
`ACCESS_COARSE_LOCATION` as the only location permission and the places sync kept on
iOS's whole-dataset-download design.

**Status:** decided and enforced in the build. The one part still open is commercial,
not technical — see [What is not decided here](#what-is-not-decided-here).

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
if a BTCMap request in this repo ever carries viewport keys.

## What the build enforces

| Property | Where |
|---|---|
| No precise-location permission in the merged manifest | `LocationPrecisionGuardTest` (source scan, manifest scan, removal directive, and the merged result read back through `PackageManager`) |
| Coarse location **is** in the merged manifest | `MapSdkGuardTest` — an app requesting no location at all would pass the test above |
| Google Maps / Mapbox / osmdroid / `play-services-location` off the dependency graph | `MapSdkGuardTest` |
| MapLibre still *is* the renderer | `MapSdkGuardTest` — so replacing it is a deliberate act, since the shipped copy names the provider |
| No bounding-box BTCMap request | `MapSdkGuardTest` |

All of these run on the JVM in `./gradlew test`, which is the `Unit tests` step of
`.github/workflows/android-maestro.yml` — it runs on every push and pull request touching
`android/**`. No emulator needed.

## What is not decided here

**The tile host is a commercial decision and needs Ruben's sign-off**, so this section is
a recommendation with the technical facts attached rather than a decision already taken.

*Recommended for launch: MapTiler.* MapTiler AG is registered at Zugerstrasse 22, 6314
Unterägeri, Zug, Switzerland (CHE-345.466.193). For a Swiss company, that keeps the one
third party left in the path inside the same jurisdiction, with no adequacy-decision
question about where viewport requests land — which is a materially easier sentence to
write in the corrected copy than a US vendor would be.

*Upgrade path, if the claim is ever worth more than the hosting bill:* MapLibre Native
ships an `MBTilesFileSource` (confirmed present in the 11.11.0 native library), so a
basemap can be served from a file on the device or from a host bittr controls, with **no
third party in the path at all**. That is the only configuration in which the original
sentence becomes literally true again. It is a real cost — basemap extract, storage,
update cadence — and it is not needed to ship.

Nothing in the code names the tile vendor yet; the style URL will be a single
configuration point when the map screen lands, so this choice is reversible in one place.
The copy is not reversible in one place, which is why the Growth & Content Lead is told
the provider name before the screen ships rather than after.
