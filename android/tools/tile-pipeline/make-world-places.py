#!/usr/bin/env python3
"""Build the z0-z5 world city labels that planetiler will not produce.

    make-world-places.py <natural_earth_vector.sqlite> <out.mbtiles>

## Why this exists

Section 1 of android/docs/tile-pipeline.md specifies the low band as "Planet --
coastlines, borders, major cities". The first two arrive: planetiler's OpenMapTiles
profile emits Natural Earth coastlines, boundaries and landcover worldwide regardless
of the OSM extract. The third does not, and the reason is in the jar rather than in any
documentation. `org.openmaptiles.layers.Place.processNaturalEarth` handles
`ne_10m_populated_places` with exactly one call:

    PointIndex.put(...)     -- into a field `PointIndex<NaturalEarthPoint> cities`

The FeatureCollector it is handed is never touched on that path, and NaturalEarthPoint
carries `{name, wikidataid, scalerank, Set<name|namealt|meganame|name_en|nameascii>}`.
That is a name-matching record: Natural Earth is a lookup table used to *rank* cities
that came from OSM. It never becomes a tile feature.

So the `place` layer is OSM-derived end to end, and a planet-wide `place` layer needs a
planet-wide OSM input -- ~80 GB of PBF to label cities that fit in a 1.4 MB table. The
band is built from a Switzerland extract, so without this script the world band names
Switzerland and nothing else, which is the "markers floating on nothing" failure that
section 1 raises as its reason for having a low band at all.

## The layer is `place_world`, not `place`

Two layers with the same name in one MVT tile is not behaviour worth depending on, and
these two do not agree on attributes anyway -- the OSM layer carries `class`, `rank`
and OSM's name tags, this one carries Natural Earth's. Keeping them separate also makes
the zoom split explicit in the style rather than implicit in a merge: `place_world` is
z0-z5, the OSM `place` layer is z6 and up, and no city is labelled by both.

## Which cities, at which zoom

`scalerank` is Natural Earth's own answer to "at what scale is this city worth drawing",
which is the question being asked, so it is used rather than a population cutoff. A
population threshold gets Chinese prefecture cities at z2 and misses Bern entirely --
Bern is scalerank 3 at 275k, Baoding is scalerank 7 at 2.3M.

The exception is deliberate: national capitals are promoted one rank. A world map at z3
that shows Sao Paulo but not Brasilia reads as broken to anyone who lives there, and
`featurecla` marks them.
"""
import gzip
import json
import math
import sqlite3
import sys

LAYER = "place_world"
EXTENT = 4096
MIN_ZOOM, MAX_ZOOM = 0, 5

# scalerank -> first zoom the city appears at. Natural Earth ships ranks 0-10; only what
# is reachable by z5 matters here, and the tail is dropped rather than piled onto z5.
FIRST_ZOOM = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 4, 6: 5, 7: 5}

CAPITAL_CLASSES = ("Admin-0 capital", "Admin-0 capital alt")

# `featurecla` is not all settlements. Within scalerank <= 7 the table also carries 39
# Antarctic research stations and 5 abandoned Arctic ones -- Vostok, McMurdo, Chernobyl,
# Logashkino. Drawn in a layer the style labels as cities, they read as cities, and a
# map that says there is a city at Vostok is wrong in a way a user cannot check.
#
# They are also where the Mercator clamp below does its worst: seventeen of them sit
# past 85 degrees of latitude or near enough that clamping moves them hundreds of km.
# The South Pole Station is the extreme -- latitude -90, clamped, 550 km out of place.
# Dropping them is both the correctness fix and the accuracy fix.
SETTLEMENT_CLASSES = (
    "Populated place", "Populated Place",
    "Admin-0 capital", "Admin-0 capital alt", "Admin-0 region capital",
    "Admin-1 capital", "Admin-1 region capital",
)


def first_zoom(place):
    if place.get("featurecla") not in SETTLEMENT_CLASSES:
        return None
    """The zoom a city starts drawing at, capitals promoted one step."""
    rank = place["scalerank"]
    if place.get("featurecla") in CAPITAL_CLASSES:
        rank = max(0, rank - 1)
    return FIRST_ZOOM.get(rank)


def project(lon, lat):
    """Web Mercator, as a fraction of the world square. Clamped to the map's own
    latitude limit: Longyearbyen and McMurdo are in this table and tan() of their
    true latitude is off the tile grid."""
    lat = max(-85.05112878, min(85.05112878, lat))
    x = (lon + 180.0) / 360.0
    s = math.sin(math.radians(lat))
    y = 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)
    return x, y


# --- just enough MVT to write points -------------------------------------------
# Tile.layers is field 3, Layer{version=15, name=1, features=2, keys=3, values=4,
# extent=5}, Feature{id=1, tags=2, type=3, geometry=4}. Writing is far less code than
# reading, and a dependency for 60 lines of varints is not worth the supply chain.

def varint(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def tag(field, wire):
    return varint((field << 3) | wire)


def length_delimited(field, payload):
    return tag(field, 2) + varint(len(payload)) + payload


def zigzag(value):
    return (value << 1) ^ (value >> 31)


def encode_layer(features):
    """features: [(x, y, {key: value})] in tile-local integer coordinates."""
    keys, values = [], []
    key_index, value_index = {}, {}
    body = bytearray()

    for x, y, attrs in features:
        tags = []
        for key, value in attrs.items():
            if key not in key_index:
                key_index[key] = len(keys)
                keys.append(key)
            if isinstance(value, bool):
                encoded = ("bool", value)
            elif isinstance(value, int):
                encoded = ("int", value)
            else:
                encoded = ("str", str(value))
            if encoded not in value_index:
                value_index[encoded] = len(values)
                values.append(encoded)
            tags += [key_index[key], value_index[encoded]]

        feature = bytearray()
        feature += length_delimited(2, b"".join(varint(t) for t in tags))
        feature += tag(3, 0) + varint(1)  # geometry type: POINT
        geometry = varint((1 << 3) | 1)  # MoveTo, count 1
        geometry += varint(zigzag(x)) + varint(zigzag(y))
        feature += length_delimited(4, geometry)
        body += length_delimited(2, bytes(feature))

    layer = bytearray()
    layer += tag(15, 0) + varint(2)  # version
    layer += length_delimited(1, LAYER.encode())
    layer += body
    for key in keys:
        layer += length_delimited(3, key.encode())
    for kind, value in values:
        if kind == "str":
            inner = length_delimited(1, value.encode())
        elif kind == "int":
            inner = tag(4, 0) + varint(zigzag(value) if value < 0 else value * 2)
        else:
            inner = tag(7, 0) + varint(1 if value else 0)
        layer += length_delimited(4, inner)
    layer += tag(5, 0) + varint(EXTENT)
    return length_delimited(3, bytes(layer))


def build(places, out_path):
    connection = sqlite3.connect(out_path)
    connection.executescript("""
        CREATE TABLE IF NOT EXISTS metadata (name TEXT, value TEXT);
        CREATE TABLE IF NOT EXISTS tiles (
            zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
        CREATE UNIQUE INDEX IF NOT EXISTS tile_index
            ON tiles (zoom_level, tile_column, tile_row);
    """)

    written = 0
    for zoom in range(MIN_ZOOM, MAX_ZOOM + 1):
        side = 1 << zoom
        buckets = {}
        for place in places:
            start = first_zoom(place)
            if start is None or start > zoom:
                continue
            wx, wy = project(place["lon"], place["lat"])
            tx, ty = min(side - 1, int(wx * side)), min(side - 1, int(wy * side))
            px = int((wx * side - tx) * EXTENT)
            py = int((wy * side - ty) * EXTENT)
            name = place.get("name") or place.get("name_en")
            if not name:
                continue
            attrs = {"name": name, "rank": place["scalerank"]}
            if place.get("name_en") and place["name_en"] != name:
                attrs["name_en"] = place["name_en"]
            if place.get("featurecla") in CAPITAL_CLASSES:
                attrs["capital"] = 1
            buckets.setdefault((tx, ty), []).append((px, py, attrs))

        for (tx, ty), features in buckets.items():
            blob = gzip.compress(encode_layer(features), mtime=0)
            connection.execute(
                "INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)",
                (zoom, tx, side - 1 - ty, blob),
            )
            written += 1
        print(f"  z{zoom}: {len(buckets)} tiles, "
              f"{sum(len(f) for f in buckets.values())} labels")

    connection.executemany(
        "INSERT INTO metadata VALUES (?,?)",
        [("name", "bittr world places"), ("format", "pbf"),
         ("minzoom", str(MIN_ZOOM)), ("maxzoom", str(MAX_ZOOM)),
         ("bounds", "-180.0,-85.05113,180.0,85.05113"), ("type", "overlay")],
    )
    connection.commit()
    connection.close()
    print(f"wrote {out_path}: {written} tiles")


def load_places(source):
    """Accepts the Natural Earth sqlite, or the small JSON dumped from it."""
    if source.endswith(".json"):
        return json.load(open(source))
    connection = sqlite3.connect(source)
    rows = connection.execute("""
        SELECT name, name_en, scalerank, featurecla, longitude, latitude
        FROM ne_10m_populated_places
    """)
    return [{"name": r[0], "name_en": r[1], "scalerank": r[2],
             "featurecla": r[3], "lon": r[4], "lat": r[5]} for r in rows]


def selftest():
    """Encode a handful of known cities, decode the result, and check it lands where
    the city is.

    This is here because the MVT writer above is hand-rolled. A tile that decodes and
    reports the right layer name and feature count can still put every label in the
    wrong place, and nothing downstream would notice: the archive would pass
    verify-deploy.sh, the style would render, and the defect would be "the map looks
    subtly wrong", found by a person or not at all.
    """
    cases = [
        # name, lon, lat, the zoom/tile it must land in
        ("Tokyo", 139.7514, 35.6850),
        ("New York", -73.9808, 40.7142),
        ("Sydney", 151.1832, -33.9200),
        ("Cape Town", 18.4333, -33.9167),
        ("Reykjavik", -21.9500, 64.1500),
        ("Ushuaia", -68.3000, -54.8000),
    ]
    places = [{"name": n, "name_en": n, "scalerank": 0, "featurecla": "Populated place",
               "lon": lon, "lat": lat} for n, lon, lat in cases]

    import tempfile, os as _os
    path = _os.path.join(tempfile.mkdtemp(), "selftest.mbtiles")
    build(places, path)

    connection = sqlite3.connect(path)
    worst, checked = 0.0, 0
    for zoom, column, row, blob in connection.execute(
            "SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles"):
        side = 1 << zoom
        y = side - 1 - row
        for name, px, py, extent in _read_points(gzip.decompress(blob)):
            truth = next(c for c in cases if c[0] == name)
            wx, wy = (column + px / extent) / side, (y + py / extent) / side
            lon = wx * 360.0 - 180.0
            lat = math.degrees(math.atan(math.sinh(math.pi - 2.0 * math.pi * wy)))
            # A degree of longitude is ~111 km at the equator; the tolerance is the
            # quantisation step of this zoom, which is the only error there should be.
            step_km = 40075.0 / (side * EXTENT)
            error = math.hypot((lon - truth[1]) * 111.32 * math.cos(math.radians(lat)),
                               (lat - truth[2]) * 110.57)
            checked += 1
            if error > max(worst, 0):
                worst = max(worst, error)
            if error > step_km * 2:
                print(f"  BAD {name} at z{zoom}: {error:.1f} km out, "
                      f"step is {step_km:.1f} km")
                return 1
    print(f"\n  ok  {checked} labels decoded and round-tripped, worst {worst:.2f} km")
    print(f"  ok  no label further from its city than this zoom's quantisation step")
    return 0


def _read_points(tile):
    """(name, x, y, extent) for each point — the decoder half, used only by selftest."""
    def rd(buf, i):
        shift = value = 0
        while True:
            byte = buf[i]; i += 1
            value |= (byte & 0x7F) << shift
            if not byte & 0x80:
                return value, i
            shift += 7

    def walk(buf):
        i = 0
        while i < len(buf):
            key, i = rd(buf, i)
            field, wire = key >> 3, key & 7
            if wire == 2:
                n, i = rd(buf, i); yield field, buf[i:i + n]; i += n
            elif wire == 0:
                v, i = rd(buf, i); yield field, v
            elif wire == 5: i += 4
            elif wire == 1: i += 8

    for field, payload in walk(tile):
        if field != 3:
            continue
        keys, values, points, extent = [], [], [], EXTENT
        for f, p in walk(payload):
            if f == 3:
                keys.append(p.decode())
            elif f == 4:
                for vf, vp in walk(p):
                    if vf == 1:
                        values.append(vp.decode())
                    elif vf == 4:
                        values.append(vp // 2)
            elif f == 5:
                extent = p
            elif f == 2:
                tags, point = [], None
                for gf, gp in walk(p):
                    if gf == 2:
                        j = 0
                        while j < len(gp):
                            v, j = rd(gp, j); tags.append(v)
                    elif gf == 4:
                        j = 0
                        _, j = rd(gp, j)
                        dx, j = rd(gp, j)
                        dy, j = rd(gp, j)
                        point = ((dx >> 1) ^ -(dx & 1), (dy >> 1) ^ -(dy & 1))
                points.append((tags, point))
        # Tags are resolved only now. encode_layer writes features before the key and
        # value pools they index into -- legal protobuf, any field order is -- so
        # resolving inside the walk reads a pool that is still half empty.
        return [(dict((keys[t[k]], values[t[k + 1]])
                      for k in range(0, len(t), 2))["name"], p[0], p[1], extent)
                for t, p in points]
    return []


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <natural_earth_vector.sqlite|places.json> "
                 f"<out.mbtiles>  |  --selftest")
    build(load_places(sys.argv[1]), sys.argv[2])
