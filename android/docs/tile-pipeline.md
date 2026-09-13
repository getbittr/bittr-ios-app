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

**Sizing is a measurement, not an estimate.** The archive size is not stated here because
nothing has built it yet, and a number invented now would be quoted later as though it had
been measured. The first build records its measured size in this section. The mechanism
below is insensitive to the answer anywhere in the plausible range.

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

Deliberately not added ahead of that commit. It is user-facing copy, it goes in
`shared/strings`, and copy on this screen is the Growth & Content Lead's to word — BIT-56
is the precedent. Adding an unreviewed string now would also credit OSM for a basemap the
app does not draw.

## 4. Refresh cadence and owner

**Quarterly**, rebuilt from the upstream OSM extract, plus an out-of-band rebuild whenever
a user-visible basemap error is reported.

Quarterly rather than continuously because the two halves of this map age at completely
different rates and only one of them is in this pipeline. Which shops take bitcoin is the
volatile part, and that is the BTCMap sync, which already refreshes incrementally against
its own watermark. Street geometry is the slow part. A quarter-old basemap is not a
visibly wrong map; a quarter-old places list would be.

**Owner: the Backend & API Engineer**, who owns the storage and the edge. That agent is
paused as of 2026-09-13, so until they are available the owner is the **Head of App
(Android)**, who also builds the first archive. If the pipeline comes due while that agent
is still paused, raise it with the CTO rather than letting the cadence lapse unowned —
an unowned schedule is the failure mode this section exists to prevent.

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

**What it cannot enforce** is everything in §2's edge requirement and all of §5. Those are
deployment properties; a hostname is all the repo can see. They are written down here
because writing them down is the only form of enforcement available to them.

## Status

| Done-when | State |
|---|---|
| 1. Region scope and serving mechanism chosen and recorded | Done — §1, §2 |
| 2. Map renders from a bittr-controlled source | **Not done.** Needs the archive built and hosted. `STYLE_URI` stays `null` until then, which means no tile request leaves the device at all |
| 3. OSM attribution in the map UI | Specified in §3, ships with the commit that sets `STYLE_URI` |
| 4. Update cadence with a named owner | Done — §4 |
| 5. Tile-request logging decided and written down | Done — §5. Growth & Content Lead told |
| 6. BIT-52 proxy capture passes against a build with a map | **Not done.** Owned by the Application Security Engineer, paused. Note the limit in §2: it cannot see who operates the edge |

Items 2 and 6 are the whole of the remainder, and neither is app-side work.
