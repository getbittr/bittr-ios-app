#!/usr/bin/env python3
"""Build the CH + 25 km border-buffer polygon used to scope the z6-z14 basemap data.

Input : switzerland.poly (Geofabrik polygon-filter format, EPSG:4326)
Output: ch-buffer-25km.geojson (EPSG:4326) + the bbox planetiler is given

The buffer is measured in metres in EPSG:3035 (ETRS89 / LAEA Europe), which is
equal-area and low-distortion over the Alps, then projected back to WGS84.
Rationale for the buffer is tile-pipeline.md section 1: Basel, Geneva and Ticino
users see across the DE/FR/IT/AT/LI borders at street zoom.
"""
import json
import sys

from pyproj import Transformer
from shapely.geometry import MultiPolygon, Polygon, mapping
from shapely.ops import transform, unary_union

BUFFER_M = 25_000


def read_poly(path):
    """Parse the Geofabrik .poly format into a list of rings."""
    rings = []
    current = None
    negative = False
    with open(path) as fh:
        lines = [ln.rstrip("\n") for ln in fh]
    i = 1  # line 0 is the polygon file name
    while i < len(lines):
        line = lines[i].strip()
        if line == "END":
            break
        if not line:
            i += 1
            continue
        negative = line.startswith("!")
        current = []
        i += 1
        while i < len(lines) and lines[i].strip() != "END":
            parts = lines[i].split()
            if len(parts) >= 2:
                current.append((float(parts[0]), float(parts[1])))
            i += 1
        i += 1  # consume the ring's END
        if len(current) >= 4:
            rings.append((Polygon(current), negative))
    return rings


def main(poly_path, out_path):
    rings = read_poly(poly_path)
    outer = [p for p, neg in rings if not neg]
    inner = [p for p, neg in rings if neg]
    land = unary_union([p.buffer(0) for p in outer])
    if inner:
        land = land.difference(unary_union([p.buffer(0) for p in inner]))

    to_m = Transformer.from_crs("EPSG:4326", "EPSG:3035", always_xy=True).transform
    to_deg = Transformer.from_crs("EPSG:3035", "EPSG:4326", always_xy=True).transform

    metric = transform(to_m, land)
    buffered = metric.buffer(BUFFER_M, quad_segs=8)
    # 250 m tolerance: far below the 25 km buffer, keeps the osmium filter cheap.
    buffered = buffered.simplify(250)
    wgs = transform(to_deg, buffered)
    if isinstance(wgs, Polygon):
        wgs = MultiPolygon([wgs])

    with open(out_path, "w") as fh:
        json.dump(
            {
                "type": "Feature",
                "properties": {"name": "ch-plus-25km"},
                "geometry": mapping(wgs),
            },
            fh,
        )

    # Planetiler's --polygon takes the same .poly format, and clipping the tile
    # set to the shape rather than to its bounding box keeps the corners (deep
    # Bavaria, the Po valley) out of the archive.
    poly_out = out_path.rsplit(".", 1)[0] + ".poly"
    with open(poly_out, "w") as fh:
        fh.write("ch-plus-25km\n")
        for n, geom in enumerate(wgs.geoms, start=1):
            fh.write(f"{n}\n")
            for x, y in geom.exterior.coords:
                fh.write(f"   {x:.7E}   {y:.7E}\n")
            fh.write("END\n")
        fh.write("END\n")

    minx, miny, maxx, maxy = wgs.bounds
    ch_area = transform(to_m, land).area / 1e6
    print(f"CH area          : {ch_area:,.0f} km2")
    print(f"buffered area    : {buffered.area / 1e6:,.0f} km2")
    print(f"vertices         : {sum(len(g.exterior.coords) for g in wgs.geoms)}")
    print(f"bbox (w,s,e,n)   : {minx:.4f},{miny:.4f},{maxx:.4f},{maxy:.4f}")
    print(f"PLANETILER_BOUNDS={minx:.4f},{miny:.4f},{maxx:.4f},{maxy:.4f}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
