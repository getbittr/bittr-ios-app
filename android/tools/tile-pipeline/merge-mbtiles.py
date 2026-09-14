#!/usr/bin/env python3
"""Combine the low-zoom planet pass and the high-zoom Switzerland pass.

    merge-mbtiles.py <out.mbtiles> <in.mbtiles> [<in.mbtiles> ...]

Inputs are read through their `tiles` relation, which is a view over
`tiles_shallow`/`tiles_data` in planetiler's deduplicated schema and a plain
table elsewhere — either way the columns are the same, so this does not care
which one it was handed. The output is a plain `tiles` table, which is the
shape `pmtiles convert` expects.

Later inputs win on a collision. The two passes cover disjoint zoom bands
(z0-z5 and z6-z14) so there should be none; the rule exists so that a rerun
with overlapping bands is defined rather than arbitrary.

With `--union`, a collision instead merges the two tiles' layer lists. That is
what the world city labels need: make-world-places.py writes `place_world` into
the same z0-z5 tiles the low pass already filled with coastlines, boundaries and
landcover, so "later input wins" would hand back a world with city names and no
coastline under them. An MVT tile is a protobuf whose `layers` is a repeated
field, so the union is a concatenation of the two decompressed bodies -- no
re-encoding, and nothing to get wrong about geometry.

Layer names are checked before that concatenation. Two layers with the same name
in one tile is not a defined thing for a renderer to resolve, so it is refused
rather than written; the two inputs this is used for name theirs `place` and
`place_world` precisely so it cannot happen.

Metadata comes from the last input, with the zoom range and bounds rewritten to
describe the combined archive rather than either half of it.
"""
import gzip
import os
import sqlite3
import sys

GZIP_MAGIC = b"\x1f\x8b"


def _varint(buf, i):
    shift = value = 0
    while True:
        byte = buf[i]
        i += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, i
        shift += 7


def layer_names(tile):
    """The name of every layer in a decompressed MVT tile.

    Tile.layers is field 3 and Layer.name is field 1 -- enough protobuf to answer
    the one question the union has to ask, and no dependency for it.
    """
    names, i = [], 0
    while i < len(tile):
        key, i = _varint(tile, i)
        field, wire = key >> 3, key & 7
        if wire == 2:
            length, i = _varint(tile, i)
            payload, i = tile[i:i + length], i + length
            if field == 3:
                j = 0
                while j < len(payload):
                    k, j = _varint(payload, j)
                    f, w = k >> 3, k & 7
                    if w == 2:
                        n, j = _varint(payload, j)
                        if f == 1:
                            names.append(payload[j:j + n].decode("utf8", "replace"))
                        j += n
                    elif w == 0:
                        _, j = _varint(payload, j)
                    elif w == 5:
                        j += 4
                    elif w == 1:
                        j += 8
        elif wire == 0:
            _, i = _varint(tile, i)
        elif wire == 5:
            i += 4
        elif wire == 1:
            i += 8
        else:
            break
    return names


def _plain(blob):
    return gzip.decompress(blob) if blob[:2] == GZIP_MAGIC else blob


def union_tiles(existing, incoming, where):
    """Concatenate two MVT tiles' layer lists, refusing a duplicate layer name."""
    a, b = _plain(existing), _plain(incoming)
    clash = set(layer_names(a)) & set(layer_names(b))
    if clash:
        raise SystemExit(
            f"{where}: both inputs carry layer(s) {sorted(clash)}. Two layers with "
            f"one name in a tile is not something a renderer is obliged to resolve, "
            f"so this is refused rather than written. Rename one, or drop --union."
        )
    return gzip.compress(a + b, mtime=0)

# The whole world, because the low-zoom band covers it. Stating the Swiss bbox
# here would tell MapLibre not to bother requesting the tiles that exist for
# exactly the reason section 1 gives for building them.
WORLD_BOUNDS = "-180.0,-85.05113,180.0,85.05113"
CH_CENTER = "8.2275,46.8182,8"


def main(out_path, in_paths, union=False):
    if os.path.exists(out_path):
        os.remove(out_path)

    out = sqlite3.connect(out_path)
    out.execute("PRAGMA journal_mode=OFF")
    out.execute("PRAGMA synchronous=OFF")
    out.execute("CREATE TABLE metadata (name TEXT, value TEXT)")
    # The unique index exists before any insert so that INSERT OR REPLACE resolves
    # collisions as they arrive. Deduplicating afterwards with a CREATE TABLE ... AS
    # would copy every tile blob, which on a multi-gigabyte archive means peaking at
    # twice the final size on disk for a merge whose inputs are disjoint anyway.
    out.execute(
        "CREATE TABLE tiles ("
        "zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB, "
        "PRIMARY KEY (zoom_level, tile_column, tile_row))"
    )

    metadata = {}
    minzoom, maxzoom = None, None
    total = 0

    for path in in_paths:
        src = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        for name, value in src.execute("SELECT name, value FROM metadata"):
            metadata[name] = value

        count = 0
        merged = 0
        batch = []
        for row in src.execute(
            "SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles"
        ):
            z = row[0]
            minzoom = z if minzoom is None else min(minzoom, z)
            maxzoom = z if maxzoom is None else max(maxzoom, z)
            if union:
                # Flush first: the tile this one collides with may still be sitting
                # in `batch` rather than in the table, and reading only the table
                # would silently drop one of the two layer sets.
                if batch:
                    out.executemany(
                        "INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)", batch)
                    batch.clear()
                prior = out.execute(
                    "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? "
                    "AND tile_row=?", row[:3]).fetchone()
                if prior:
                    row = row[:3] + (
                        union_tiles(prior[0], row[3], f"z{z}/{row[1]}/{row[2]}"),)
                    merged += 1
            batch.append(row)
            count += 1
            # Small batches on purpose: a z14 tile can be tens of kilobytes, so a
            # batch counted in tens of thousands is counted in hundreds of megabytes.
            if len(batch) >= 2_000:
                out.executemany("INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)", batch)
                batch.clear()
        if batch:
            out.executemany("INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)", batch)
        out.commit()
        src.close()
        total += count
        note = f", {merged:,} unioned into an existing tile" if merged else ""
        print(f"{os.path.basename(path)}: {count:,} tiles{note}")

    metadata.update(
        {
            "name": "bittr basemap",
            "format": "pbf",
            "type": "baselayer",
            "minzoom": str(minzoom),
            "maxzoom": str(maxzoom),
            "bounds": WORLD_BOUNDS,
            "center": CH_CENTER,
        }
    )
    out.executemany(
        "INSERT INTO metadata VALUES (?,?)", sorted(metadata.items())
    )
    out.commit()

    kept = out.execute("SELECT COUNT(*) FROM tiles").fetchone()[0]
    out.close()
    verb = "unioned" if union else "duplicates dropped"
    print(f"combined: {kept:,} tiles (z{minzoom}-z{maxzoom}), {total - kept:,} {verb}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--union"]
    if len(args) < 2:
        sys.exit(f"usage: {sys.argv[0]} [--union] <out.mbtiles> <in.mbtiles> ...")
    main(args[0], args[1:], union="--union" in sys.argv[1:])
