#!/usr/bin/env python3
"""Assert the built archive covers what tile-pipeline.md section 1 says it covers.

    check-archive-coverage.py <ch.pmtiles> [--pmtiles <path-to-pmtiles-binary>]

This exists because the first build shipped a defect that every other check was
blind to. The z0-z5 world band was built from a Swiss extract, so it had
coastlines and borders worldwide and **city names only inside Switzerland** --
pan to Chicago and the map is silent. Nothing caught it: the archive was the
right size, the tile count was right, `pmtiles show` was right, and the low pass
exited 0. A feature count even went *up* when the input was widened, which is
what made a half-fix read as a fix.

So this checks coverage rather than volume, and it checks it by naming places
and asserting what must be true at them:

  - the world band carries city labels on every continent, not just ours
  - the Swiss band has street-level detail in the cities the app is for
  - the ~25 km border buffer reaches across all four borders and Liechtenstein
  - and it stops -- a tile well outside the buffer is absent, so a build that
    quietly widened to a whole-country or whole-planet extract fails here
    instead of at the storage bill

Absence is asserted as loudly as presence. A build that emits every tile on
earth satisfies every positive case in this file and is still wrong.

Exit 0 and a table on success; exit 1 naming each failed expectation otherwise.
"""
import argparse
import gzip
import math
import os
import subprocess
import sys

# (lon, lat, label, expectation). `True` means the tile must exist and carry the
# layers named in LAYER_EXPECTATIONS; `False` means it must not exist at all.
#
# Distances are to the nearest point of the Swiss border. The cases either side
# of ~25 km are the ones that make this a test of the buffer rather than a test
# of Switzerland: Loerrach and Konstanz sit on it, Freiburg and Milan sit well
# past it. Annecy is the closest negative at ~30 km, so the pair
# (Annecy absent, Como present) brackets the boundary from both sides.
Z14_CASES = [
    (8.5417, 47.3769, "Zurich, CH", True),
    (6.1432, 46.2044, "Geneva, CH", True),
    (8.9569, 46.0037, "Lugano, CH (Ticino)", True),
    (7.5886, 47.5596, "Basel, CH", True),
    (9.5215, 47.1410, "Vaduz, LI -- on the border", True),
    (9.1859, 47.6603, "Konstanz, DE -- ~0 km", True),
    (7.6614, 47.6150, "Loerrach, DE -- ~2 km", True),
    (9.0852, 45.8081, "Como, IT -- ~5 km", True),
    (6.4953, 46.5197, "Thonon, FR -- ~5 km", True),
    (9.7500, 47.4000, "Bregenz, AT -- ~10 km", True),
    (6.1294, 45.8992, "Annecy, FR -- ~30 km", False),
    (7.8522, 47.9990, "Freiburg i.B., DE -- ~45 km", False),
    (11.3931, 47.2692, "Innsbruck, AT -- ~40 km", False),
    (9.1900, 45.4642, "Milan, IT -- ~45 km", False),
    (5.0415, 47.3220, "Dijon, FR -- ~180 km", False),
]

# The world band, by tile rather than by place: these are the continents a
# Swiss-extract build leaves empty. `place_world` is the layer
# make-world-places.py writes; `place` is planetiler's own, which is populated
# only where the OSM extract reaches, so asserting on `place` here would pass
# for exactly the broken build this file exists to catch.
WORLD_CASES = [
    (2, 0, 1, "the Americas"),
    (3, 1, 3, "South America / S Atlantic"),
    (2, 3, 1, "east Asia / Pacific"),
    (3, 4, 4, "Africa"),
    (2, 1, 1, "western Europe / N Atlantic"),
]

# A z14 tile in a Swiss city with none of these is not a street map, whatever
# its byte count says.
STREET_LAYERS = {"transportation", "building", "poi"}


def varint(buf, i):
    shift = value = 0
    while True:
        byte = buf[i]
        i += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, i
        shift += 7


def layer_names(tile):
    """Every layer name in a decompressed MVT tile.

    Tile.layers is field 3, Layer.name is field 1 -- the same walk
    merge-mbtiles.py does, kept here so this file runs standalone against an
    archive someone hands it.
    """
    names, i = [], 0
    while i < len(tile):
        key, i = varint(tile, i)
        field, wire = key >> 3, key & 7
        if wire == 2:
            length, i = varint(tile, i)
            payload, i = tile[i:i + length], i + length
            if field == 3:
                j = 0
                while j < len(payload):
                    k, j = varint(payload, j)
                    f, w = k >> 3, k & 7
                    if w == 2:
                        n, j = varint(payload, j)
                        if f == 1:
                            names.append(payload[j:j + n].decode("utf8", "replace"))
                        j += n
                    elif w == 0:
                        _, j = varint(payload, j)
                    elif w == 5:
                        j += 4
                    elif w == 1:
                        j += 8
        elif wire == 0:
            _, i = varint(tile, i)
        elif wire == 5:
            i += 4
        elif wire == 1:
            i += 8
        else:
            break
    return names


def tile_of(lon, lat, z):
    n = 2 ** z
    x = int((lon + 180.0) / 360.0 * n)
    y = int((1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n)
    return x, y


def read_tile(pmtiles_bin, archive, z, x, y):
    """The decompressed tile, or None if the archive does not hold it.

    `pmtiles tile` exits non-zero for a missing tile, which is the same signal
    as a broken archive -- so a genuinely unreadable archive is caught by the
    header probe in main() before any of these run, and a non-zero exit here can
    be read as absence.
    """
    proc = subprocess.run([pmtiles_bin, "tile", archive, str(z), str(x), str(y)],
                          capture_output=True)
    if proc.returncode != 0 or not proc.stdout:
        return None
    body = proc.stdout
    return gzip.decompress(body) if body[:2] == b"\x1f\x8b" else body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("archive")
    ap.add_argument("--pmtiles", default=os.environ.get("PMTILES_BIN", "pmtiles"),
                    help="path to the pmtiles binary (default: $PMTILES_BIN or 'pmtiles')")
    args = ap.parse_args()

    # Prove the archive is readable before reading absence as a result. Without
    # this, a missing file or a wrong --pmtiles path makes every positive case
    # fail and every negative case pass, which reads like a coverage bug.
    probe = subprocess.run([args.pmtiles, "show", args.archive], capture_output=True)
    if probe.returncode != 0:
        sys.exit(f"cannot read {args.archive} with '{args.pmtiles}': "
                 f"{probe.stderr.decode('utf8', 'replace').strip()}")

    failures = []
    print(f"world band (z0-z5) -- city labels off our own extract")
    for z, x, y, label in WORLD_CASES:
        tile = read_tile(args.pmtiles, args.archive, z, x, y)
        if tile is None:
            failures.append(f"z{z}/{x}/{y} ({label}): tile absent from the world band")
            print(f"  z{z}/{x}/{y}  {label:32s} ABSENT")
            continue
        names = layer_names(tile)
        ok = "place_world" in names
        if not ok:
            failures.append(
                f"z{z}/{x}/{y} ({label}): no `place_world` layer, so this part of the "
                f"world has no city names. Layers present: {', '.join(sorted(set(names))) or 'none'}")
        print(f"  z{z}/{x}/{y}  {label:32s} {'ok' if ok else 'NO LABELS':9s} "
              f"{len(tile):7,d}B  {','.join(sorted(set(names)))}")

    print(f"\nSwiss band (z6-z14) -- detail inside, nothing outside")
    for lon, lat, label, expected in Z14_CASES:
        x, y = tile_of(lon, lat, 14)
        tile = read_tile(args.pmtiles, args.archive, 14, x, y)
        present = tile is not None
        if present != expected:
            failures.append(
                f"z14/{x}/{y} ({label}): expected {'a tile' if expected else 'no tile'}, "
                f"got {'a tile' if present else 'none'}. "
                + ("The buffer does not reach here." if expected else
                   "The build covers more than section 1's scope."))
        if not present:
            print(f"  z14/{x}/{y}  {label:32s} {'absent':9s}"
                  f"{'' if not expected else '   <-- expected a tile'}")
            continue
        names = set(layer_names(tile))
        missing = STREET_LAYERS - names
        if expected and missing:
            failures.append(
                f"z14/{x}/{y} ({label}): tile exists but is not a street map -- "
                f"missing {', '.join(sorted(missing))}")
        print(f"  z14/{x}/{y}  {label:32s} {'present':9s} {len(tile):7,d}B"
              f"{'' if expected else '   <-- expected no tile'}"
              f"{'' if not missing else '   missing ' + ','.join(sorted(missing))}")

    if failures:
        print(f"\n{len(failures)} coverage expectation(s) failed:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print("\nSection 1 of android/docs/tile-pipeline.md is the specification "
              "these assert; if the scope genuinely changed, change it there first.",
              file=sys.stderr)
        sys.exit(1)
    print("\ncoverage ok: world band labelled on every continent, Swiss band detailed, "
          "buffer bounded")


if __name__ == "__main__":
    main()
