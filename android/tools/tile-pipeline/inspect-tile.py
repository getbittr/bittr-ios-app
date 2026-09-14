#!/usr/bin/env python3
"""Report which MVT layers exist in given tiles, and how many features each holds.

Enough protobuf to read layer names and count features -- Tile.layers is field 3,
Layer.name is field 1 and Layer.features is field 2. No dependency needed for that.

    inspect_tile.py <mbtiles|pmtiles-dir-not-supported> z x y [z x y ...]

Coordinates are XYZ (slippy); the mbtiles row is flipped on the way in.
"""
import gzip
import sqlite3
import sys


def varint(buf, i):
    shift = 0
    val = 0
    while True:
        b = buf[i]
        i += 1
        val |= (b & 0x7F) << shift
        if not b & 0x80:
            return val, i
        shift += 7


def fields(buf):
    i = 0
    while i < len(buf):
        key, i = varint(buf, i)
        tag, wire = key >> 3, key & 7
        if wire == 2:
            ln, i = varint(buf, i)
            yield tag, buf[i : i + ln]
            i += ln
        elif wire == 0:
            _, i = varint(buf, i)
        elif wire == 5:
            i += 4
        elif wire == 1:
            i += 8
        else:
            raise ValueError(f"wire type {wire}")


def layers(tile):
    if tile[:2] == b"\x1f\x8b":
        tile = gzip.decompress(tile)
    out = {}
    for tag, payload in fields(tile):
        if tag != 3:
            continue
        name, count = None, 0
        for t2, p2 in fields(payload):
            if t2 == 1:
                name = p2.decode()
            elif t2 == 2:
                count += 1
        out[name] = count
    return out


def main(path, coords):
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    for z, x, y in coords:
        flipped = (1 << z) - 1 - y
        row = db.execute(
            "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?",
            (z, x, flipped),
        ).fetchone()
        if row is None:
            print(f"z{z}/{x}/{y}: ABSENT")
            continue
        got = layers(row[0])
        print(f"z{z}/{x}/{y}: {len(row[0]):,}B  " + ", ".join(f"{k}={v}" for k, v in sorted(got.items())))


if __name__ == "__main__":
    path = sys.argv[1]
    nums = [int(v) for v in sys.argv[2:]]
    main(path, [tuple(nums[i : i + 3]) for i in range(0, len(nums), 3)])
