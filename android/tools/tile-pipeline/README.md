# Basemap build and deploy

The pipeline behind `android/docs/tile-pipeline.md`. That document decides *what* and
*why*; this directory is *how*, and is the thing that gets rerun.

| File | What it does |
|---|---|
| `build-basemap.sh` | End to end: download, clip, render, merge, convert. Produces `ch.pmtiles` |
| `make-buffer.py` | Switzerland + 25 km, in metres, as GeoJSON (for osmium) and `.poly` (for planetiler) |
| `merge-mbtiles.py` | Joins the z0–z5 planet pass to the z6–z14 Switzerland pass |
| `inspect-tile.py` | Reads layer names and feature counts out of given tiles — how the claims in §1 were checked rather than assumed |
| `make-world-places.py` | The z0–z5 world city labels planetiler will not emit. `--selftest` decodes its own output and checks each label's position |
| `make-style.py` | Generates the style document `MapBasemap.STYLE_URI` points at |
| `check-style-hosts.py` | Fails if the built style would send the client to a non-bittr host. Run by both scripts below; `--selftest` proves it both ways |
| `check-archive-coverage.py` | Fails if the built archive does not cover §1's scope — labels on every continent, street detail in the Swiss cities, and nothing past the buffer. Run by `build-basemap.sh` |
| `verify-deploy.sh` | Client-side checks against a deployed version, before its URL is handed to the app |

**The archive is not checked in and never should be.** It is 572 MiB and it is
regenerable; §4 of the document asks for a quarterly rebuild, which a committed blob
cannot satisfy. The scripts are the artefact.

## Build

Any Linux host with a JDK, ~12 GB free disk and ~4 GB free RAM:

```sh
apt-get install -y osmium-tool python3-shapely python3-pyproj
./build-basemap.sh /var/tmp/basemap-build
```

It downloads planetiler, the `pmtiles` CLI, ten Geofabrik extracts (~3.4 GB) and
planetiler's Natural Earth and water-polygon sources.

**Budget about 2h15m from cold, unattended** — measured on the first real build,
2026-09-14: ~30 min to fetch and clip the ten extracts, ~1h40m for the two planetiler
passes (run in parallel; the z6–z14 Switzerland render is the long one), then the merge
and the PMTiles conversion. Run it under `nohup`/`tmux`; nothing here needs an operator
after it starts.

Run it **after** the bucket and the edge exist, not before. The archive is 572 MiB and
lives only on the machine that built it — it is deliberately never checked in and there
is nowhere else to park it, so a build done ahead of hosting is thrown away. See §4 of
`android/docs/tile-pipeline.md`: a deploy is this rebuild, not an upload.

The upstream extracts move, so two builds a quarter apart are not byte-identical and
are not meant to be. What is pinned is the *pipeline* — planetiler and `pmtiles`
versions, the region list, the buffer distance and the zoom split — so that a
difference between two archives is a difference in OSM, not in how it was rendered.

## Check the output before deploying it

A PMTiles archive of the right size is not the same as an archive of the right
*contents*, and the two failures look identical from the outside. `inspect-tile.py`
reads the layers back out:

```sh
# Switzerland at z14, then the world band well away from the extract
python3 inspect-tile.py combined.mbtiles 14 8590 5745
python3 inspect-tile.py combined.mbtiles 4 3 6 4 14 6 3 7 4
```

What the world band contains, and where it comes from, because two of these arrive
from different places than you would guess:

| At world zooms | Source | Coverage |
|---|---|---|
| Coastlines, water, landcover | Natural Earth, via planetiler | Everywhere |
| Country boundaries | Natural Earth through z4, OSM from z5 | Everywhere to z4; from z5 only where the extract reaches |
| City names, `place` layer | OSM, via planetiler | **Only where the extract reaches** — i.e. Switzerland |
| City names, `place_world` layer | Natural Earth, via `make-world-places.py` | Everywhere, z0–z5 |

The third row is the one that surprises. planetiler's `Place` layer handles
`ne_10m_populated_places` with a single `PointIndex.put` — Natural Earth is a lookup
table for *ranking* cities that came from OSM, and never becomes a tile feature. So a
`place` layer built from a Swiss extract names Switzerland and nothing else, however
much of the world the band covers. Measured, not inferred: before the fourth row
existed, a z2 tile over the Americas had zero place strings and a z2 tile over the
Atlantic had 118, every one of them Switzerland, Liechtenstein, Aosta or Vorarlberg in
a different language.

That is why the fourth row exists. §1 specifies the low band as "coastlines, borders,
major cities", and the first three rows deliver two of those three.

Checking it after a build:

```sh
# The Americas at z2: place_world present, place absent. Both are correct.
python3 inspect-tile.py combined.mbtiles 2 0 1
```

## Deploy

§2 settles the shape: object storage plus an edge, **no tile server process**. PMTiles
is one immutable file and MapLibre does the addressing itself over HTTP range
requests, so the entire server-side requirement is `Accept-Ranges`/206 on a static
file. Any competent static server does that already.

§2 also constrains *who runs the edge*, and this is the part that is easy to
misread as plumbing:

> the edge for the tiles hostname is bittr-operated, or it is a processor under
> contract with access logging configured as in §5.

Whoever terminates TLS for `tiles.getbittr.com` receives the on-screen area and the
client IP on every pan. Putting a vendor CDN there reverses the BIT-53 decision while
the DNS still reads `bittr`, and **nothing in this repo can detect it** —
`TileHostGuardTest` reads hostnames, and the BIT-52 proxy capture also only sees a
hostname. Neither can see who owns the machine that answers.

### Layout

Versioned, immutable, one directory per build:

```
/basemap/<yyyy-mm>/ch.pmtiles
/basemap/<yyyy-mm>/style.json
```

A rebuild writes a new directory and `MapBasemap.STYLE_URI` moves in one commit. The
old archive stays cacheable, a refresh cannot half-land, and a bad build is a one-line
rollback — §2 again.

### Keeping the old directories

§2 "Bucket retention" decides this; the operational form is three rules:

- **No lifecycle expiration rule on `/basemap/`.** Deleting a superseded prefix costs a
  2h15m rebuild to undo, so deletion is manual or it does not happen.
- **Keep the pinned version and the two before it.** A refresh only adds; version N−3
  becomes eligible for deletion when N lands. Three versions is under 2 GiB.
- **The deploy identity cannot delete or overwrite.** Create-only on `/basemap/*`;
  deletion needs a separate human-held credential. The rebuild is unattended and runs
  for over two hours, and "it cannot destroy what is currently served" should not rest
  on the script being right.

On local disk behind the nginx config below, that is `chattr +i` or simply a `/srv/tiles`
the deploy user can create in but not unlink from. On object storage it is a bucket
policy denying `DeleteObject` and `PutObject` overwrite to the deploy key.

**Re-running a build in the same month is the thing this protects against.**
`BASEMAP_VERSION` defaults to `$(date -u +%Y-%m)`, and an out-of-band rebuild fixing a
bad build lands in the same calendar month as the build it is fixing — so the default
aims it at the prefix currently being served. Set the version explicitly:

```sh
BASEMAP_VERSION=2026-09-14 ./build-basemap.sh /var/tmp/basemap-build
```

`build-basemap.sh` refuses to start when the prefix is already live, which needs to be
told where "live" is:

```sh
BASEMAP_SERVE_BASE=https://tiles.getbittr.com ./build-basemap.sh /var/tmp/basemap-build
```

It checks before downloading anything, because a collision discovered after the render
has already cost the two hours. Unreachable, or any status that is neither the archive
nor a clean 404, also stops the build — you asked for the check, so a check that could
not run is not a cleared one. Leave `BASEMAP_SERVE_BASE` unset for the first build,
when there is nothing live to collide with.

### nginx

This is the whole configuration. `access_log off` is not a tidiness preference, it is
§5:

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name tiles.getbittr.com;

    ssl_certificate     /etc/letsencrypt/live/tiles.getbittr.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tiles.getbittr.com/privkey.pem;

    # The worker user has to be able to read this. Getting it wrong gives 403 on
    # every tile and looks nothing like a permissions problem from the client.
    root /srv/tiles;

    # Without this a .pmtiles is served as text/plain, because nginx's mime.types
    # has never heard of it. MapLibre reads bytes and does not care, but a proxy
    # or a scanner in the path might, and the correct type costs one line.
    types { application/octet-stream pmtiles; application/json json; }

    # Section 5: tile-request access logs are not retained. If an incident forces
    # this on, it goes on with the truncation and the 24 h cap that section
    # specifies, and the incident is written into that section.
    access_log off;

    # Nothing here is dynamic and nothing is user-specific; the only reason a
    # client comes back to the origin is a new <yyyy-mm> prefix. add_header
    # applies to 206 as well as 200, which is the case that matters — every tile
    # read is a range request, so a directive that only reached 200 would cache
    # nothing that the map actually fetches.
    location /basemap/ {
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location / { return 404; }
}
```

No `add_header Accept-Ranges bytes` here, deliberately. nginx emits it natively for
static files, and adding it produces the header **twice** on a 200 — verified against
this exact config, which is also how that line came to be deleted rather than
reasoned about. Check it rather than assert it; the check is below.

Serve the file from local disk, or from object storage behind this — either is fine
as long as the TLS termination above is bittr's. If a bucket is in the path, its own
access logging is off too, per §5.

### Verify before handing the URL over

```sh
./verify-deploy.sh https://tiles.getbittr.com/basemap/<yyyy-mm>
```

Ten client-side checks plus one per fontstack the style names — the serving host is
under a bittr apex, ranges return 206 with the right `Content-Range`, exactly one
`Accept-Ranges: bytes`, immutable `Cache-Control` on the 206, the archive really
begins with the PMTiles magic bytes rather than being an error page with a healthy
status, the style is served and names *this* version's archive, every URL in that
style is https on a bittr apex, and each fontstack resolves. It exits with the number
of failures, so it works as a gate. It needs no access to the host and anyone can run
it from anywhere.

The style-host check runs twice on purpose: `build-basemap.sh` runs it on the file it
just generated, so a bad edit to `make-style.py` fails the build rather than a deploy,
and `verify-deploy.sh` runs it again on what the server actually returned. Those are
the same bytes right up until someone uploads by hand, which is the case the second
run exists for.

Then the one that matters, by hand, on the edge:

```sh
sudo wc -l /var/log/nginx/access.log      # expect zero new lines from the run above
```

That check is last on purpose. It is the only one that fails silently, the only one
no test in this repo and no client-side script can make for you, and the one that
decides whether §5 is true. The same goes for the §2 requirement above it: nothing
you can run from outside tells you who terminated the TLS.

## Still needed before `STYLE_URI` can be set

The archive is the data. MapLibre is pointed at a **style document**, not at the
archive, so `MapBasemap.STYLE_URI` will be `.../style.json` and that style needs two
more things on the same bittr host:

- **`style.json`** — an OpenMapTiles-schema style whose one source is
  `pmtiles://https://tiles.getbittr.com/basemap/<yyyy-mm>/ch.pmtiles`.
- **A glyph range endpoint** — any style with text labels fetches
  `{fontstack}/{range}.pbf` per label. The public default for this schema is a
  third-party host, and pointing at it would send the client IP off to that third
  party on every label render. Glyphs are served from `tiles.getbittr.com` alongside
  the archive.

### Which check covers which half

A foreign glyph host used to pass `TileHostGuardTest` outright — its URL markers were
`{z}`, `{x}`, `{y}`, `style.json`, `.pmtiles` and `.mbtiles`, and a glyphs URL contains
none of them. The Head of App (Android) has widened `TILE_URL_MARKERS` with
`{fontstack}`, `{range}` and `/sprite` (BIT-119); the first two are required by the
MapLibre style spec in any `glyphs` value, so there is no spelling that evades them.

That closes the half of the problem that lives in the `android/` tree. It cannot close
this half, and the split is worth stating because each side looks complete on its own:

| Where the URL is | What sees it |
|---|---|
| Hard-coded in a Kotlin or XML file | `TileHostGuardTest` — scans the `android/` tree |
| In the generated `style.json` | `check-style-hosts.py` — the file is built here, uploaded, and never enters that tree |

`check-style-hosts.py` also runs in CI on every push (`android-maestro.yml`, the
`build` job), against a style generated on the spot. That matters more than it looks:
`TileHostGuardTest` walks `kt/xml/json/properties/kts/toml`, so `make-style.py` is
invisible to it *by extension*, and until that step existed, editing the one `HOST`
constant in it moved every client's tile and glyph fetches to a third party with
nothing in the repo going red.

Pointing the app-side scan at `make-style.py` would be worse than leaving the gap:
this pipeline fetches from Geofabrik and from GitHub releases at build time, both
legitimately, and no regex over the generator tells a build-time fetch from one the
client will make. The built artefact carries no such ambiguity — every URL in it is a
URL the renderer resolves on the device.
