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
bound is storage cost and the quarterly rebuild in §4 — not a re-upload, because as §4
records there is never a local copy to upload.

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
`MapBasemap.STYLE_URI` naming a specific version. A refresh writes a new object at a new
version prefix and the style URL moves in one commit, so a refresh cannot half-land, the
old archive stays cacheable, and a bad build is a one-line rollback.

The new object is *produced* by a rebuild on the serving side, not uploaded from here — see
§4. That is why the rollback is worth having: re-pointing `STYLE_URI` at the previous
version prefix is instant, whereas re-obtaining a superseded archive is another two hours.

### Bucket retention: keep the rollback target, and never on a timer

**Decided by the Backend & API Engineer, 2026-09-14.** The line above promises a one-line
rollback, and that promise is only true while the object it rolls back *to* still exists.
Once a deploy is a 2h15m rebuild rather than an upload, a superseded prefix is not
cheaply regenerable, so deleting one converts the rollback from a commit into an
afternoon. The policy follows from that and from nothing else:

- **No object-lifecycle expiration rule on `/basemap/`, ever.** Not a long one either. A
  lifecycle rule is the specific mechanism that deletes the rollback target silently, on a
  day nobody is looking, and its whole appeal is that it needs no operator — which is the
  property that makes it wrong here. Deletion is a manual step or it does not happen.
- **Retain the pinned version and the two before it** — about 1.7 GiB, roughly a year of
  history at §4's quarterly cadence. Nothing is deleted *by* a refresh; a refresh only
  adds. Version N−3 becomes eligible for deletion when version N lands, so the eligible
  prefix has been superseded for three quarters before anyone touches it.
- **The pinned version is not deletable by the thing that deploys.** The credential
  `build-basemap.sh` writes with gets create-only access to `/basemap/*` and no delete and
  no overwrite; deletion needs a separate human-held credential. This is the one rule worth
  spending a bucket policy on rather than a checklist: the rebuild is unattended and runs
  for over two hours, so "the script cannot destroy what is currently being served" should
  not depend on the script being correct.

Why three versions and not two, which is what "keep the previous one" would give. Rollback
exists for a bad build that the gates did not catch — `check-archive-coverage.py` and
`verify-deploy.sh` run before the URL is handed over, so anything that survives them is by
construction something only a user panning the map would see, and that arrives weeks late.
By then an out-of-band rebuild (§4) may itself have landed and been pinned. With two
versions retained, that fix occupies the rollback slot and the last *known-good* archive is
the one that just aged out. Three keeps a known-good prefix behind the fix, which is the
situation the rollback is for.

**Size is not the constraint and should not be argued as one.** Three versions is under
2 GiB of static objects against a rebuild that occupies a machine for 2h15m; no storage
rate makes that trade close. The reason to bound retention at all is that an unbounded set
of prefixes nobody reviews is its own small mess, not that the bytes matter.

**A same-month rebuild is the first thing that would delete a rollback target**, before any
retention rule gets a say. `build-basemap.sh` defaults `BASEMAP_VERSION` to
`$(date -u +%Y-%m)`, and an out-of-band rebuild fixing a bad build happens, almost by
definition, in the same calendar month as the build it is fixing — so the default sends it
straight at the prefix currently being served. **An out-of-band rebuild sets
`BASEMAP_VERSION=<yyyy-mm-dd>` explicitly**, and the script now refuses to start a build
whose version prefix is already live (`BASEMAP_SERVE_BASE`), because the create-only
credential above would otherwise turn that collision into a failure discovered 2h15m in.

**This does not contradict §5.** What is retained here is map geometry — the same OSM
extract everyone else can download — and nothing about who fetched it. §5's "retain
nothing" is about the access log, and the two sections stay consistent because the objects
hold no user-derived data at all. Keeping four copies of a map of Switzerland discloses
nothing about anybody.

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

Required with the archive, in the same commit that sets `STYLE_URI`, visible on the map
surface: **Map data © OpenStreetMap contributors, design © OpenMapTiles.org**. Two credits,
because two licences — "OSM is not the only credit owed" below is how the second was found,
and "The wording, settled" is where the sentence was fixed.

Deliberately not added ahead of that commit. It is user-facing copy and copy on this screen
is the Growth & Content Lead's to word — BIT-56 is the precedent. Adding an unreviewed
string now would also credit OSM for a basemap the app does not draw.

(This section originally said the string "goes in `shared/strings`". BIT-140 decided
otherwise, with the reasoning below; the assumption is corrected rather than deleted
because it is the one a reader would otherwise make again.)

**The wording is settled.** BIT-140 worded the OSM half **`Map data © OpenStreetMap
contributors`**; BIT-149 extended it to **`Map data © OpenStreetMap contributors, design ©
OpenMapTiles.org`** once the second licence surfaced. **Settled is not shipped: no constant
holds it yet.** Today the sentence exists only here and as the two phrases the guard pins —
there is no `BASEMAP_ATTRIBUTION` in `MapCopy.kt` and no credit `Text` in `MapScreen.kt`, by
the same "deliberately not added ahead of that commit" above. The commit that sets
`STYLE_URI` is the one that declares it and renders it, and the guard is what makes that
commit fail if it does not. Declare it as a plain constant, deliberately *not* in
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
build if `STYLE_URI` is set to a URL while `MapCopy.kt` is missing either required phrase —
`© OpenStreetMap contributors` or `© OpenMapTiles.org` — or while `MapScreen.kt` never
reads the constant carrying one of them. It is dormant today — `STYLE_URI` is `null`, so
the app owes no basemap credit — and its self-test runs the detectors against known
offenders so a dormant check cannot quietly become a broken one. Four things about the
match are deliberate: the full OSM phrase rather than "OpenStreetMap", because the alert
above already contains the shorter word while covering no imagery; the `©` as U+00A9, so
`(c)` and `&copy;` are rejected — the second renders literally in a Compose `Text`; the
`.org` on the OpenMapTiles credit, for the licence reason in "The wording, settled" below;
and *only* those phrases, so the framing around them stays editable without touching the
guard. What the guard still cannot see is whether the credit is *legible* once rendered;
that belongs in a rendered assertion beside the map module's other Robolectric tests, and
"Measured: how the line actually wraps" below is that measurement taken ahead of the commit.

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

The wording settled at that point — the string `BASEMAP_ATTRIBUTION` was to carry, not a
constant that existed — was `Map data © OpenStreetMap contributors`. That is the OSM
half and only the OSM half, and `BasemapAttributionGuardTest` matched on the OSM phrase
alone — so the guard passed in exactly the state the licence is not satisfied in. **This is
a wording change owned by BIT-140 and the Growth & Content Lead, not something to patch
here**; §3's whole point is that this copy is not the pipeline's to write.

*(Both halves are now resolved: the guard in the commit that added `OMT_CREDIT`, the
sentence in "The wording, settled" at the end of this section. What follows is kept as the
record of how the gap was found and what was believed while finding it.)*

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

### Settled from the SDK: the control is on, and it is a button

Answered without rendering anything, by disassembling the pinned
`org.maplibre.gl:android-sdk:11.11.0` AAR. Two findings, and they point opposite ways.

**The control is enabled by default.** `MapLibreMapOptions`' no-arg constructor sets
`attributionEnabled` to `true` — `iconst_1` immediately before
`putfield attributionEnabled:Z`, alongside `logoEnabled` — and nothing under
`android/feature/map/` calls `attributionEnabled(false)` or touches `uiSettings` at all. So
the first half of the reasoning above is confirmed rather than plausible.

**It does not put a credit on the map surface.** `AttributionDialogManager` is a
`View.OnClickListener` holding an `AlertDialog`; the credits reach the user through
`getAttributionTitles()` → `showAttributionDialog(String[])`, i.e. **only after a tap on an
ⓘ button**. The classes that lay attribution text out over the map —
`AttributionMeasure`, `AttributionLayout` — belong to the snapshotter, not the live view.

That resolves the question and it does **not** invert §3:

- Done-when item 4 says the credit is *visible on the map surface*. A dialog behind an
  unlabelled icon is not that, so the app-side `Text` is still required. The built-in
  control is a supplement, not a substitute.
- The duplicate the Head of App (Android) originally worried about does not appear either,
  because the control renders no text until it is opened. Both concerns were about the
  same assumption — that the control behaves like its web counterpart — and on Android it
  does not.
- `make-style.py`'s reason for omitting `attribution` therefore rests on a premise that is
  wrong in its particulars. Leave the key out anyway: the PMTiles source already supplies
  the combined credit from archive metadata, so adding it to the style would duplicate an
  entry *inside the dialog* for no gain.

**One thing to carry into BIT-141.** Tapping a dialog entry calls `showWebPage`, which is
an `ACTION_VIEW` intent to the external browser — the app itself makes no request. But
`showMapAttributionWebPage` first inspects the entry's URL, and if it contains
`https://apps.mapbox.com/feedback` or `https://www.mapbox.com/map-feedback` it *rewrites*
it into a feedback URL whose fragment is `/{lon}/{lat}/{zoom}/{bearing}/{tilt}`, taken from
the live `CameraPosition`. That is a third-party URL carrying the user's on-screen centre,
which is precisely what BIT-52's capture exists to catch.

It does not arm for this basemap: the rewrite is gated on the *attribution text of the
loaded source*, and ours carries OpenMapTiles and OpenStreetMap links only. Worth writing
down regardless, because the gate is upstream metadata rather than anything in this repo —
a future style or a vendor source could open it without a line changing here, and no guard
in the tree reads dialog entries.

### The guard now requires both credits

`BasemapAttributionGuardTest` pins both `© OpenMapTiles.org` and `© OpenStreetMap
contributors`, each checked separately and each required to be rendered by `MapScreen.kt`.
Whether they live in one constant or two is not pinned, and neither is the framing — the
sentence is settled just below.

The phrases are taken from the built archive's own PMTiles `attribution` metadata rather
than from licence prose, so the guard asks for the credit the artefact says it carries.
Proven in both directions before landing, by patching the tree rather than by reading it:
with `STYLE_URI` set and `BASEMAP_ATTRIBUTION` holding the OSM half alone — the BIT-140
wording, and the exact state the licence is unmet in — the guard fails naming
`© OpenMapTiles`; adding the OpenMapTiles half turns it green, with `TileHostGuardTest`
green throughout. The first run matters more than the second: it is the state this guard
used to pass.

### The wording, settled

`MapCopy.BASEMAP_ATTRIBUTION` is:

> **Map data © OpenStreetMap contributors, design © OpenMapTiles.org**

One string, one `Text`, in the placement BIT-140 already fixed. Four decisions in it.

**It extends BIT-140's phrase rather than replacing it.** `Map data © OpenStreetMap
contributors` survives verbatim and contiguous, so the half that went through BIT-140 is
not reopened and the OSM pin keeps matching. Only the clause after the comma is new.

**"design", not a second "data".** `NOTICE.md` in the pinned planetiler jar is specific
about what is CC-BY here: "the cartography and visual design features of the map tile
schema". OSM supplied the data; OpenMapTiles supplied the schema the tiles are cut to. A
combined `Map data © OpenMapTiles © OpenStreetMap contributors` — the form the banner
shows — would credit OpenMapTiles for the data, which is not what either licence says.
Splitting the roles costs one word and makes the line true.

**`.org`, and it is load-bearing.** The same notice states the obligation as two
alternatives: visibly credit "OpenMapTiles.org", **or** reference "OpenMapTiles" with a
link to openmaptiles.org. Planetiler's banner and the archive metadata both take the second
— they render `© OpenMapTiles` as an `<a href>`. This credit is a plain, unclickable
`Text`, so the second alternative is not available to it and the first is what has to be
met; the first names the domain. A bare unlinked `© OpenMapTiles` would satisfy neither,
and the guard rejects it with its own fixture. If this credit ever becomes a real link,
relax the pin in that commit.

**OSM first.** Neither licence constrains order. The existing copy on this screen is
OSM-centric — "Powered by BTCMap.org" and an alert about OSM tagging — so leading with OSM
reads continuously with the line above it, and it is what keeps BIT-140's phrase contiguous.

Not promoted to `shared/strings/en.json`, for BIT-140's reason unchanged and now doubled:
iOS renders through `MKMapView` on Apple's imagery, where *both* credits would be false.

`POWERED_BY_ALERT` is not reworded to explain any of this — that re-triggers the BIT-69
compliance read.

### Measured: how the line actually wraps, and the one thing wrong with it

The 64-character estimate above was a prediction. It has now been measured on the JVM, by
patching the three files of the `STYLE_URI` commit into the tree, rendering `MapScreen`
under Robolectric in `NATIVE` graphics mode — which rasterises the real Gilroy face rather
than the stub metrics `LEGACY` returns — and reading the `TextLayoutResult` back. The patch
was reverted; nothing below is in the tree.

| | available width | lines | overflow |
|---|---|---|---|
| 320 dp, fontScale 1.0 | 290 dp | 2 | none |
| 411 dp, fontScale 1.0 | 381 dp | 2 | none |
| 320 dp, fontScale 1.3 | 290 dp | 3 | none |

So the credit is legible and nothing is truncated, including at the largest font scale,
where the block grows from 32 dp to 63 dp. That answers the question BIT-149 raised.

**It wraps in the wrong place, and not only on a narrow screen.** At both 320 dp and
411 dp the break falls here:

> Map data © OpenStreetMap contributors, design ©
> OpenMapTiles.org

The `©` is orphaned onto the end of the first line, separated from the thing it credits.
This is not a narrow-screen artefact — 411 dp is the ordinary phone width every other
screenshot in this repo is taken at, and it breaks identically there, because the line is
long enough to wrap at both. Whatever is done about it is a copy decision and belongs to
the Growth & Content Lead; it is recorded here because it will otherwise be discovered in
the `STYLE_URI` commit, which is the one commit that cannot absorb a copy round-trip.

**A non-breaking space is the obvious fix and it fails the build.** `© OpenMapTiles.org`
would hold the sign against its subject, but `BasemapAttributionGuardTest` pins
`OMT_CREDIT` with an ASCII space and matches it with `indexOf`, so the substring stops
matching and the guard goes red naming the credit as absent. Proven, not inferred: patched
in, the guard failed with *"no constant in MapCopy.kt carries the credit © OpenMapTiles.org"*.
That is the guard working — it cannot tell a typographic refinement from a deleted credit,
and for a licence artefact that is the safer direction to be wrong in. If the non-breaking
space is chosen, `OMT_CREDIT` and `OSM_CREDIT` have to move in the *same* commit, and the
fixtures with them.

### Measured: the SDK's own overlays sit clear of ours

The other half of the same question. `BasemapController` never touches `uiSettings`, so
both of MapLibre's default-on overlays appear, and both default to `BOTTOM|LEFT` inside the
280 dp map card. From the pinned `android-sdk-11.11.0.aar`:

- the logo is `maplibre_logo_icon`, **88 × 23 dp** at mdpi, with 4 dp default margins;
- the ⓘ button's default left margin is **92 dp** — `NINETY_TWO_DP` in
  `MapLibreMapOptions`, which is the logo's 88 dp plus that 4 dp gap. The two are designed
  to sit side by side, not stacked and not overlapping.

Their combined footprint is therefore roughly 92 dp wide by 31 dp tall in the bottom-left
corner of a card that is full-width by 280 dp. The app's own control on that card is the
my-location button, which is `BottomEnd` — the opposite corner — so there is no collision
to design around and no `uiSettings` call is needed.

What this does **not** cover: that either overlay draws at all. MapLibre renders through
GL, there is no GL under Robolectric, and the map card is stubbed to an empty `Box` in
every test in this repo. The geometry above is read from the AAR's resources and bytecode,
not from a picture. Confirming they are actually drawn needs the emulator or a device, and
it is the only part of BIT-119's done-when item 4 that does.

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

### A deploy is a rebuild, not an upload

**There is no archive anywhere to upload, and there never will be.** The 572 MiB measured
in §1 exists only inside the container that built it; this section forbids checking the
archive in, and no durable store outside the serving bucket is in scope. So every deploy —
the first one and each quarterly refresh — is a **full unattended rebuild via
`build-basemap.sh`, roughly 2h15m from cold** as measured by the BIT-139 owner on
2026-09-14: about 30 minutes to fetch and clip the ten Geofabrik extracts covering the
buffer ring, about 1h40m for the two planetiler passes run in parallel, then the merge and
the PMTiles conversion.

Two consequences, and the first is a sequencing rule:

- **Do not treat "build" and "host" as separable steps weeks apart.** The bucket and the
  edge come first; the rebuild is then run in one sitting, by whoever runs it, writing
  straight to the version prefix it will be served from. Building first only produces an
  artefact that expires with the container.
- The rebuild is not a second chance to get the contents wrong. `check-style-hosts.py` and
  `check-archive-coverage.py` both run *inside* `build-basemap.sh`, so a build that
  reproduces the world-band-without-city-names failure fails there rather than shipping.

This corrects an earlier reading of §2 on which a deploy was "an upload and a
`verify-deploy.sh` run". `verify-deploy.sh` still runs, and still runs against the served
URL — but it verifies the output of that rebuild, it is not the deploy.

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

"Basemap-shaped" in the second row means the tiles **and the assets the style pulls in
behind them** — the glyph ranges and the sprite sheet. The glyphs were missing from that
list until the BIT-139 owner pointed it out, and the omission mattered more than its size
suggests: a style with text labels fetches `{fontstack}/{range}.pbf` once per label, so a
foreign font host is a stream of requests carrying the client IP for as long as the map is
on screen — the same disclosure §2 exists to prevent — and it contained no `{z}`, no
`style.json` and no archive extension, so every check in the table passed it. `{fontstack}`
and `{range}` are safe markers rather than lucky ones: the MapLibre style spec requires
both tokens in a `glyphs` value, so no spelling of a glyphs URL avoids them. `sprite` has
no required token and is matched on the path segment, which is convention rather than a
closed set.

These checks read the `android/` tree, and the style document the app fetches is
**generated** by `android/tools/tile-pipeline/` and uploaded — it never exists in this
repo, so no source scan here can see its `glyphs` value. That gap is closed in the
pipeline instead, by `check-style-hosts.py`, which runs against the built artefact: every
URL the renderer would resolve on the device must be on a bittr host over TLS. Running on
the artefact rather than on the generator is what makes it sound — this pipeline
legitimately fetches from Geofabrik and from GitHub at *build* time, and no pattern over a
build script can tell those from a fetch the *client* will make.

It also covers four cases a `https?://` scan cannot: scheme-relative URLs, cleartext to a
bittr host, a lookalike host with `getbittr.com` as a prefix, and `attribution` values —
which are rendered as text rather than fetched, so flagging the licence link inside one
would invite "fixing" it by deleting a credit.

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
