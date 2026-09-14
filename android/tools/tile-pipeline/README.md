# Basemap build and deploy

The pipeline behind `android/docs/tile-pipeline.md`. That document decides *what* and
*why*; this directory is *how*, and is the thing that gets rerun.

| File | What it does |
|---|---|
| `build-basemap.sh` | End to end: download, clip, render, merge, convert. Produces `ch.pmtiles` |
| `make-buffer.py` | Switzerland + 25 km, in metres, as GeoJSON (for osmium) and `.poly` (for planetiler) |
| `merge-mbtiles.py` | Joins the z0–z5 planet pass to the z6–z14 Switzerland pass |
| `inspect-tile.py` | Reads layer names and feature counts out of given tiles — how the claims in §1 were checked rather than assumed |

**The archive is not checked in and never should be.** It is gigabytes and it is
regenerable; §4 of the document asks for a quarterly rebuild, which a committed blob
cannot satisfy. The scripts are the artefact.

## Build

Any Linux host with a JDK, ~12 GB free disk and ~4 GB free RAM:

```sh
apt-get install -y osmium-tool python3-shapely python3-pyproj
./build-basemap.sh /var/tmp/basemap-build
```

It downloads planetiler, the `pmtiles` CLI, ten Geofabrik extracts (~3.4 GB) and
planetiler's Natural Earth and water-polygon sources. Expect an hour or so; the
z6–z14 render is the long part.

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

What the world band contains is worth knowing before someone reports it as a bug:
coastlines, water and landcover everywhere; country boundaries everywhere through
z4, and from z5 only where the OSM extract reaches; city names only where the OSM
extract reaches. That last one is a property of the schema, not of this pipeline —
the profile derives `place` from OSM and uses Natural Earth only to rank it. §1 of
the document records the same thing.

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

    root /srv/tiles;

    # Section 5: tile-request access logs are not retained. If an incident forces
    # this on, it goes on with the truncation and the 24 h cap that section
    # specifies, and the incident is written into that section.
    access_log off;

    # Nothing here is dynamic and nothing is user-specific; the only reason a
    # client comes back to the origin is a new <yyyy-mm> prefix.
    location /basemap/ {
        add_header Cache-Control "public, max-age=31536000, immutable";
        # nginx serves byte ranges for static files by default. Stated explicitly
        # because every tile read is a range request and a proxy or a module that
        # silently disabled them would look like a blank map, not like an error.
        add_header Accept-Ranges bytes;
    }

    location / { return 404; }
}
```

Serve the file from local disk, or from object storage behind this — either is fine
as long as the TLS termination above is bittr's. If a bucket is in the path, its own
access logging is off too, per §5.

### Verify before handing the URL over

```sh
# 1. Range requests work. Expect: HTTP/1.1 206 and Content-Range.
curl -sI -r 0-16383 https://tiles.getbittr.com/basemap/<yyyy-mm>/ch.pmtiles | head -5

# 2. The PMTiles header is really there (magic bytes "PMTiles", spec version 3).
curl -s -r 0-7 https://tiles.getbittr.com/basemap/<yyyy-mm>/ch.pmtiles | xxd

# 3. Nothing is being logged. Expect no new lines for the requests above.
sudo wc -l /var/log/nginx/access.log
```

Check 3 is the one that is worth doing by hand every time, because it is the only one
of the three that fails silently and that no test in the repo can make for you.

## Still needed before `STYLE_URI` can be set

The archive is the data. MapLibre is pointed at a **style document**, not at the
archive, so `MapBasemap.STYLE_URI` will be `.../style.json` and that style needs two
more things on the same bittr host:

- **`style.json`** — an OpenMapTiles-schema style whose one source is
  `pmtiles://https://tiles.getbittr.com/basemap/<yyyy-mm>/ch.pmtiles`.
- **A glyph range endpoint** — any style with text labels fetches
  `{fontstack}/{range}.pbf` per label. The public default for this schema is a
  third-party host, and pointing at it would send the client IP off to that third
  party on every label render. It is also a gap in the guard:
  `TileHostGuardTest.TILE_URL_MARKERS` looks for `{z}`, `{x}`, `{y}`, `style.json`,
  `.pmtiles`, `.mbtiles` — a glyphs URL contains none of them, so a foreign font host
  would pass the scan. Glyphs are served from `tiles.getbittr.com` alongside the
  archive, and that rule lives here because the build cannot hold it.
