# The basemap pipeline (BIT-73)

`map-sdk-decision.md` settled *who serves the tiles* — bittr does, Ruben's call on
2026-09-11, over the cheaper recommendation to keep a vendor. This document settles the
four things that decision left open, and records one correction to it that came out of
reading the renderer's artefact rather than its documentation.

It covers the region scope, the serving mechanism, the refresh cadence and its owner, and
the tile-request logging policy. What it does **not** cover is a running service: nothing
here is deployed. `MapBasemap.STYLE_URI` is still `null` and the map still renders a
background-only style, which is the correct state until the archive below exists.

## The correction: PMTiles is the first-class path, not MBTiles

`map-sdk-decision.md` says MapLibre "ships an `MBTilesFileSource` (confirmed present in the
11.11.0 native library), so a basemap can come from a file on the device or from a host
bittr controls". The first half is true and the second half quietly attributes to MBTiles
a capability it does not have. Read out of
`org.maplibre.gl:android-sdk:11.11.0` — `classes.jar` and `jni/arm64-v8a/libmaplibre.so`,
the exact artefact the version catalog pins:

| | `MBTilesFileSource` | `PMTilesFileSource` |
|---|---|---|
| Compiled into `libmaplibre.so` | yes | yes |
| URI scheme string in the binary | **none** | `pmtiles://` |
| Kotlin/Java binding in `classes.jar` | **none** | none needed — reached by URI |
| Remote fetch machinery | none | yes — "Error fetching PMTiles directory / header / tile", i.e. HTTP range requests |
| Constraint stated by the binary | "MBTilesFileSource only supports absolute path urls" | — |

So the two options the decision presented as symmetric are not. **MBTiles is local-file
only**, reachable through no bound API and no URI scheme, addressable only by absolute
path. **PMTiles is a supported source type in the pinned version**, over a URI scheme, with
range-request fetching against a remote host already in the binary. A hosted PMTiles
basemap needs no custom Kotlin, no fork, and no tile-server process.

That is not a small difference, and it points the same way as the app-size arithmetic
below, so the mechanism choice is unusually easy.

## 1. Region scope

**A low-zoom world plus street-level Switzerland with a border buffer.**

| Zooms | Coverage | Why |
|---|---|---|
| z0–z5 | Planet — coastlines, borders, major cities | Orientation. A user who pans out or opens the map abroad sees a map, not a void. Cheap: the whole world at z5 is a few thousand tiles |
| z6–z14 | Switzerland + ~25 km across the DE/FR/IT/AT/LI borders | Where bittr's users are. The buffer is not decoration — Basel, Geneva and Ticino users see across the border at street zoom, and a hard clip at the national outline would be visible in the three cities most likely to be panning |

z14 is the ceiling because the places layer is a `CircleLayer` over points, not a
building-level view: the question the screen answers is "which café near me takes
bitcoin", and z14 is enough to place a café on a street.

**Why not the planet.** Hundreds of GB, as the decision already notes.

**Why not Switzerland alone.** The places sync is whole-dataset and deliberately so
(`map-sdk-decision.md` §"The places sync stays whole-dataset"), so markers draw worldwide.
A CH-only basemap would put BTCMap markers on blank background the moment anyone panned
abroad — markers floating on nothing reads as a bug, and the low-zoom world costs almost
nothing to avoid it.

**Sizing is a measurement, not an estimate.** The first build ran on 2026-09-14 from the
2026-09 Geofabrik extracts, and `ch.pmtiles` is **599,418,720 bytes — 572 MiB**, 37,459
tiles, `pmtiles` spec 3, clustered. Where that goes:

| Band | Tiles | Size | Share |
|---|---|---|---|
| z0–z5, planet | 1,365 | 2.5 MB | 0.4% |
| z6–z12, CH + buffer | 2,419 | 81.1 MB | 13.5% |
| z13–z14, CH + buffer | 33,675 | 515.8 MB | 86.1% |

Two things follow that the table above only guessed at. **The world band is free** — 2.5 MB
to never show a user a void is not a trade-off, it is a rounding error, so the "costs almost
nothing" claim is now measured rather than asserted. And **z14 alone is 401 MB of the 572**,
so the z14 ceiling is not only a usefulness decision. Each level so far has cost roughly
three times the one below it (z12→z13 ×2.5, z13→z14 ×3.5), so adding z15 would put the
archive well past 1.5 GB.

This is a server-side file, not an app download — §2's mechanism is a remote archive read by
range request, so the app ships none of it and the size does not touch the APK. What it does
bound is storage cost and the monthly re-upload in §4.

## 2. Serving mechanism

**One PMTiles archive on bittr-controlled object storage, served under a bittr hostname
(`tiles.getbittr.com`), read directly by MapLibre over HTTP range requests.**

Rejected: **MBTiles shipped in the app**. Two independent reasons, either sufficient.
Google Play caps an app bundle's base install at 200 MB, and the debug APK is currently
about 12.6 MB — a street-level basemap is not an asset that fits that budget, however the
region is scoped. And per the table above, the in-app path is the one the pinned renderer
does *not* expose. It also freezes the basemap to the app's release cadence, which turns
§4 from a schedule into a store submission.

What this mechanism buys operationally: there is no tile server. A PMTiles archive is a
single immutable file and the client does the addressing, so "serving" is object storage
plus an edge — no per-tile compute, no process to keep alive, and a bill that is storage
plus egress rather than a per-request rate card.

**Version the object path; pin it in the style.** `/basemap/<yyyy-mm>/ch.pmtiles`, with
`MapBasemap.STYLE_URI` naming a specific version. A rebuild uploads a new object and the
style URL moves in one commit, so a refresh cannot half-land, the old archive stays
cacheable, and a bad build is a one-line rollback.

### The edge is where this decision can be silently undone

A CDN in front of the bucket is the obvious way to serve this, and it is the one step that
can reverse BIT-53 while looking like plumbing. If a vendor edge terminates TLS for
`tiles.getbittr.com`, **that vendor receives the viewport and the client IP on every
pan** — which is exactly what buying this pipeline was meant to stop, and it would not
show up anywhere:

- `TileHostGuardTest` passes, because it reads hostnames and the hostname is bittr's.
- The BIT-52 proxy capture (done-when item 6) passes, for the same reason — it sees
  `tiles.getbittr.com` and cannot see who operates the machine answering.

So the requirement is a property of the deployment and not of the repo, and it has to be
carried here because nothing in the build can carry it: **the edge for the tiles hostname
is bittr-operated, or it is a processor under contract with access logging configured as
in §5.** A vendor edge with default logging on is a privacy regression whatever the DNS
says, and it would make the copy upgrade in §5 false.

## 3. Attribution

OSM's licence requires credit regardless of who serves the tiles, and the map UI credits
OSM today only for the *places*: `MapCopy.POWERED_BY` is "Powered by BTCMap.org" and the
alert explains that BTCMap "uses OpenStreetMap to tag places that accept bitcoin". Neither
sentence covers a basemap, because there is no basemap yet.

Required with the archive, in the same commit that sets `STYLE_URI`: **© OpenStreetMap
contributors**, visible on the map surface.

Deliberately not added ahead of that commit. It is user-facing copy and copy on this screen
is the Growth & Content Lead's to word — BIT-56 is the precedent. Adding an unreviewed
string now would also credit OSM for a basemap the app does not draw.

(This section originally said the string "goes in `shared/strings`". BIT-140 decided
otherwise, with the reasoning below; the assumption is corrected rather than deleted
because it is the one a reader would otherwise make again.)

**The wording is settled.** BIT-140 worded it **`Map data © OpenStreetMap contributors`**,
as `MapCopy.BASEMAP_ATTRIBUTION` — a plain constant, deliberately *not* in
`shared/strings/en.json`. That file is the cross-platform canonical source, and this string
must not be cross-platform: iOS renders through `MKMapView` on Apple's imagery, where this
credit would be false. Promote it the day iOS renders from bittr's tiles. "Map data" rather
than a bare credit because, one line under "Powered by BTCMap.org", a bare credit reads as
a second credit for the *places*; and because bittr produces the imagery while OSM supplied
the data, which is what the licence is about. BIT-140 also fixes the placement: its own
`Text`, second, outside the existing line's `clickable`, wrapping rather than truncating,
and in the same style. Do not reword `POWERED_BY_ALERT` to explain any of this — that
re-triggers the BIT-69 compliance read and re-opens the SE length budget.

**The "same commit" is enforced, not remembered.** `BasemapAttributionGuardTest` fails the
build if `STYLE_URI` is set to a URL while no constant in `MapCopy.kt` carries the phrase
`© OpenStreetMap contributors`, or while `MapScreen.kt` never reads that constant. It is
dormant today — `STYLE_URI` is `null`, so the app owes no basemap credit — and its
self-test runs the detectors against known offenders so a dormant check cannot quietly
become a broken one. Three things about the match are deliberate: the full phrase rather
than "OpenStreetMap", because the alert above already contains the shorter word while
covering no imagery; the `©` as U+00A9, so `(c)` and `&copy;` are rejected — the second
renders literally in a Compose `Text`; and *only* that phrase, so the framing around it
stays editable without touching the guard. What the guard still cannot see is whether the
credit is *legible* once rendered; that belongs in a rendered assertion beside the map
module's other Robolectric tests.

### Correction from the first build: OSM is not the only credit owed

Everything above reasons about OSM's licence, and everything above was written before any
tiles existed. Building them surfaces a **second** obligation that no part of this chain had
noticed — not BIT-73, not BIT-140, and not the guard.

The tiles are generated by planetiler's OpenMapTiles profile, so the *schema* is
OpenMapTiles' work even though the data is OSM's. From the pinned jar rather than from the
web page — this is planetiler's own end-of-run banner, and the same text is in the jar:

> Such tiles are reusable under CC-BY license granted by OpenMapTiles team […] Maps made
> with these vector tiles must display a visible credit: **© OpenMapTiles © OpenStreetMap
> contributors**

`MapCopy.BASEMAP_ATTRIBUTION` is `Map data © OpenStreetMap contributors`. That is the OSM
half and only the OSM half, and `BasemapAttributionGuardTest` matches on the OSM phrase
alone — so the guard passes in exactly the state the licence is not satisfied in. **This is
a wording change owned by BIT-140 and the Growth & Content Lead, not something to patch
here**; §3's whole point is that this copy is not the pipeline's to write.

Two things make it less alarming than it reads, and neither disposes of it:

- The built archive already carries the full combined credit in its own metadata —
  `attribution` is `© OpenMapTiles © OpenStreetMap contributors`, as two HTML links. That is
  planetiler's default; the build does not add it.
- `libmaplibre.so` 11.11.0 contains `PMTilesFileSource::Impl::request_tilejson`, i.e. the
  PMTiles source synthesises a TileJSON from that archive metadata, and `attribution` is a
  `Tileset` key the renderer parses and exposes through the bound `Source.getAttribution()`.

So the renderer's built-in attribution control plausibly already displays the complete
credit, straight out of the archive, with no style key involved. **That inverts the concern
the Head of App (Android) raised on BIT-139** — the worry was that adding `attribution` to
the style would produce a second credit next to BIT-140's; the actual risk is that a credit
appears that nobody in the repo put there, and that it is the only *complete* one. It is a
chain of static reads, not an observation: I cannot render MapLibre here. Settling it needs
one look at the map with `STYLE_URI` set, which is app-side.

## 4. Refresh cadence and owner

**Quarterly**, rebuilt from the upstream OSM extract, plus an out-of-band rebuild whenever
a user-visible basemap error is reported.

Quarterly rather than continuously because the two halves of this map age at completely
different rates and only one of them is in this pipeline. Which shops take bitcoin is the
volatile part, and that is the BTCMap sync, which already refreshes incrementally against
its own watermark. Street geometry is the slow part. A quarter-old basemap is not a
visibly wrong map; a quarter-old places list would be.

**Owner: the Backend & API Engineer**, who owns the storage and the edge.

That agent was paused when this section was written on 2026-09-13, so it named the **Head
of App (Android)** as interim owner until they were available. **They are available again
as of 2026-09-14, so the interim clause has lapsed** and the cadence sits with its real
owner; the first build and the hosting are [BIT-139](/BIT/issues/BIT-139). The standing
instruction survives the lapse: if the pipeline comes due while that agent is unavailable,
raise it with the CTO rather than letting the cadence lapse unowned — an unowned schedule
is the failure mode this section exists to prevent.

## 5. Tile-request logging

**Decided: tile-request access logs are not retained.**

Concretely, for the tiles hostname:

- Access logging **off** at the edge and on the bucket.
- If an operational incident (abuse, or an egress bill that needs explaining) requires
  turning it on, then for the duration: client IPs truncated at the edge before anything
  is written — IPv4 to /24, IPv6 to /48 — the request path reduced to the zoom level
  rather than the tile coordinate, retention capped at 24 hours, and the incident noted in
  this section.
- Tile requests are **never** joined to an account identifier, under any configuration.

This is the item the decision document flagged as a privacy property rather than an ops
preference, and the reason is worth restating: self-hosting does not stop the viewport
being disclosed. It relocates the disclosure from a vendor's logs into bittr's, and the
whole gain is that retention becomes bittr's decision. Deciding to retain nothing is what
converts "a different party learns it" into "nobody keeps it".

**This is a copy-relevant fact and the Growth & Content Lead asked to be told it.**
`shared/strings/README.md` records the upgrade to "we serve those map images ourselves, so
nobody outside bittr sees them" as available once this pipeline ships. With logging off
that sentence is supportable on Android — subject to the edge requirement in §2, which is
the part that can falsify it, and subject to the constraint the decision document is
emphatic about: it is **not** a two-platform claim while iOS renders through `MKMapView`
against Apple's tile servers. The claim and the pipeline ship together, never the claim
first.

## What the build enforces, and what it cannot

`TileHostGuardTest` holds the tile *host*, next to `MapSdkGuardTest` for the renderer and
`LocationEgressGuardTest` for coordinates in request bodies. Three checks over every
Kotlin, XML, JSON, properties, Gradle and catalog file under `android/`, plus a self-test
that runs each detector against a known offender so a regression in the detector fails the
build instead of quietly disarming the guard:

| Check | Catches |
|---|---|
| No banned tile host anywhere the app can read one | The vendors that were considered and rejected, and `demotiles.maplibre.org` — the quickstart URL, which is the likeliest accident |
| Every basemap-shaped URL is on a bittr host | The vendor nobody thought to list |
| `MapBasemap.STYLE_URI` is `null` or a bittr host | The case the other two miss — a style URL need not look like a tile URL, so `https://tiles.example.net/basemap` on an unfamiliar host escapes both. Reading the literal is the only check a chosen hostname cannot slip past |

Kotlin is read with comments stripped and string literals kept, so this document and the
guard's own KDoc can name the hosts the rules exclude.

`BasemapAttributionGuardTest` sits beside it and holds the *licence* rather than the host —
the §3 credit, and specifically its "same commit" sequencing. The two are independent on
purpose: every check in the table above passes on a basemap that is correctly hosted and
entirely uncredited, because the hostname is the only thing they read.

| Check | Catches |
|---|---|
| A set `STYLE_URI` implies the phrase `© OpenStreetMap contributors` in `MapCopy.kt`, read from `MapScreen.kt` | The commit that turns the basemap on and forgets the credit. That commit is a one-constant diff, which is exactly why it reads as too small to carry a licence obligation |

**What it cannot enforce** is everything in §2's edge requirement and all of §5, and
whether the §3 credit is legible rather than merely present. Those are deployment and
rendering properties; a hostname and a symbol reference are all a source scan can see. They
are written down here because writing them down is the only form of enforcement available
to them.

## Status

| Done-when | State |
|---|---|
| 1. Region scope and serving mechanism chosen and recorded | Done — §1, §2 |
| 2. Map renders from a bittr-controlled source | **Half done — [BIT-139](/BIT/issues/BIT-139)**, with the Backend & API Engineer. The archive is **built and verified** (2026-09-14, size in §1); it is **not hosted**, and hosting is not a tooling problem — it needs a bittr cloud account, object-storage credentials and DNS for `getbittr.com`, none of which exist inside an agent container, plus the §2 answer on who operates the edge. `STYLE_URI` stays `null` until it is served, which means no tile request leaves the device at all |
| 3. OSM attribution in the map UI | Specified in §3, ships with the commit that sets `STYLE_URI` — now **enforced** by `BasemapAttributionGuardTest` rather than relying on the reader. Wording commissioned on [BIT-140](/BIT/issues/BIT-140) |
| 4. Update cadence with a named owner | Done — §4. Interim ownership lapsed 2026-09-14 |
| 5. Tile-request logging decided and written down | Done — §5. Growth & Content Lead told on BIT-56, Compliance told on BIT-71 |
| 6. BIT-52 proxy capture passes against a build with a map | **Not done — [BIT-141](/BIT/issues/BIT-141)**, unassigned because the Application Security Engineer is still paused, and blocked on BIT-139 because there is no tile request to observe until one exists. Note the limit in §2: it cannot see who operates the edge |

Items 2 and 6 are the whole of the remainder, and neither is app-side work.

**BIT-73 is closed and those two moved to [BIT-119](/BIT/issues/BIT-119)** on 2026-09-13.
Everything BIT-73 could settle from this repo is settled and above; what is left is a build
and a deployment for two agents who are paused, so it was rehomed rather than left open
against an app-side owner who cannot do it. BIT-119 re-states the decisions in this table
as fixed inputs, so nothing above needs re-deciding to execute it.

Two facts that only hold while `STYLE_URI` is `null`, and that BIT-119 ends:

- **No tile request leaves the device**, so there is nothing for §5's logging policy to
  govern yet and nothing for Play to declare as collected. §5 is a commitment about the
  deployment BIT-119 will make, not a description of a system that exists.
- **The map has no streets.** That is the standing cost of waiting, and it is a product
  call rather than a technical blocker — the screen and its Maestro flow work without one.
