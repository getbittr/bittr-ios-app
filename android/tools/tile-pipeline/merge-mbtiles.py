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

Metadata comes from the last input, with the zoom range and bounds rewritten to
describe the combined archive rather than either half of it.
"""
import os
import sqlite3
import sys

# The whole world, because the low-zoom band covers it. Stating the Swiss bbox
# here would tell MapLibre not to bother requesting the tiles that exist for
# exactly the reason section 1 gives for building them.
WORLD_BOUNDS = "-180.0,-85.05113,180.0,85.05113"
CH_CENTER = "8.2275,46.8182,8"


def main(out_path, in_paths):
    if os.path.exists(out_path):
        os.remove(out_path)

    out = sqlite3.connect(out_path)
    out.execute("PRAGMA journal_mode=OFF")
    out.execute("PRAGMA synchronous=OFF")
    out.execute("CREATE TABLE metadata (name TEXT, value TEXT)")
    out.execute(
        "CREATE TABLE tiles ("
        "zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB)"
    )

    metadata = {}
    minzoom, maxzoom = None, None
    total = 0

    for path in in_paths:
        src = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        for name, value in src.execute("SELECT name, value FROM metadata"):
            metadata[name] = value

        count = 0
        batch = []
        for row in src.execute(
            "SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles"
        ):
            z = row[0]
            minzoom = z if minzoom is None else min(minzoom, z)
            maxzoom = z if maxzoom is None else max(maxzoom, z)
            batch.append(row)
            count += 1
            if len(batch) >= 20_000:
                out.executemany("INSERT INTO tiles VALUES (?,?,?,?)", batch)
                batch.clear()
        if batch:
            out.executemany("INSERT INTO tiles VALUES (?,?,?,?)", batch)
        src.close()
        total += count
        print(f"{os.path.basename(path)}: {count:,} tiles")

    # Deduplicate last, so a collision is resolved by "later input wins" rather
    # than by whichever row the index happens to reach first.
    out.execute(
        "CREATE TABLE tiles_dedup AS "
        "SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles "
        "GROUP BY zoom_level, tile_column, tile_row HAVING MAX(rowid)"
    )
    out.execute("DROP TABLE tiles")
    out.execute("ALTER TABLE tiles_dedup RENAME TO tiles")
    out.execute(
        "CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row)"
    )

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
    print(f"combined: {kept:,} tiles (z{minzoom}-z{maxzoom}), {total - kept:,} duplicates dropped")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
