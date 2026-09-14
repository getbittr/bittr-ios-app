#!/usr/bin/env python3
"""Generate the MapLibre style document that `MapBasemap.STYLE_URI` points at.

    make-style.py <yyyy-mm> <out.json>

`STYLE_URI` is a *style*, not an archive: MapLibre is handed a style document and
that document names the PMTiles archive as one of its sources. So the URL handed
back to the app is `.../style.json`, and the archive sits behind it.

Everything the style references is on `tiles.getbittr.com` — the archive and the
glyphs both. The glyphs matter more than they look: a style with text labels fetches
`{fontstack}/{range}.pbf` per label, and the public endpoint for this schema is a
third party that would then receive the client IP on every label render. That is the
same disclosure section 2 of the tile-pipeline document exists to prevent, and it is
invisible to `TileHostGuardTest`, whose URL markers (`{z}`, `{x}`, `{y}`,
`style.json`, `.pmtiles`, `.mbtiles`) do not appear in a glyphs URL.

## The palette

Pinned to the map screen that already exists rather than chosen fresh:

- The background is `MapBasemap.BACKGROUND_COLOR`, so the moment `STYLE_URI` stops
  being null the land does not change colour — the streets simply arrive on top of
  the wash that was already there.
- Everything else is deliberately desaturated. `BasemapController` draws places in
  `#F6C744` on a `#1A1A1A` stroke, and those markers are the answer to the question
  the screen asks. A basemap with saturated roads and green parks competes with them.
  Section 1 of the document makes the same point about z14 being the ceiling: this is
  a map for placing a cafe on a street, not for reading the street.
"""
import json
import sys

HOST = "https://tiles.getbittr.com"

BACKGROUND = "#E8E4DC"  # MapBasemap.BACKGROUND_COLOR — must stay in step with it
WATER = "#C3D2DB"
WATER_LINE = "#B3C5D0"
GREEN = "#DEE1D0"
BUILDING = "#DCD6CB"
ROAD_MAJOR = "#FBF9F4"
ROAD_MINOR = "#F2EEE6"
ROAD_CASING = "#D6D0C4"
BOUNDARY = "#B0A99C"
LABEL = "#5A554C"  # 5.8:1 on the background
LABEL_HALO = "#F2EFE9"

FONT_REGULAR = ["Noto Sans Regular"]
FONT_MEDIUM = ["Noto Sans Medium"]


def style(version):
    base = f"{HOST}/basemap/{version}"
    return {
        "version": 8,
        "name": f"bittr basemap {version}",
        "metadata": {
            "bittr:source": "android/tools/tile-pipeline",
            "bittr:archive": f"{base}/ch.pmtiles",
        },
        # Both on the bittr host. See the module docstring on why the glyphs
        # endpoint is not an incidental detail.
        "glyphs": base + "/glyphs/{fontstack}/{range}.pbf",
        "sources": {
            "basemap": {
                "type": "vector",
                "url": f"pmtiles://{base}/ch.pmtiles",
                # Stated so a client that reads the style before the archive header
                # knows the world exists at low zoom — section 1's reason for the
                # z0-z5 band is that panning out abroad shows a map, not a void.
                "minzoom": 0,
                "maxzoom": 14,
            }
        },
        "layers": layers(),
    }


def layers():
    out = [
        {
            "id": "background",
            "type": "background",
            "paint": {"background-color": BACKGROUND},
        },
        {
            "id": "landcover",
            "type": "fill",
            "source": "basemap",
            "source-layer": "landcover",
            "filter": ["in", "class", "wood", "grass", "farmland"],
            "paint": {"fill-color": GREEN, "fill-opacity": 0.7},
        },
        {
            "id": "park",
            "type": "fill",
            "source": "basemap",
            "source-layer": "park",
            "paint": {"fill-color": GREEN, "fill-opacity": 0.5},
        },
        {
            "id": "water",
            "type": "fill",
            "source": "basemap",
            "source-layer": "water",
            "filter": ["!=", "brunnel", "tunnel"],
            "paint": {"fill-color": WATER},
        },
        {
            "id": "waterway",
            "type": "line",
            "source": "basemap",
            "source-layer": "waterway",
            "minzoom": 8,
            "paint": {
                "line-color": WATER_LINE,
                "line-width": ["interpolate", ["linear"], ["zoom"], 8, 0.5, 14, 2],
            },
        },
        {
            "id": "building",
            "type": "fill",
            "source": "basemap",
            "source-layer": "building",
            # z14 only: the ceiling of the archive, and the only zoom where a
            # building footprint helps rather than clutters.
            "minzoom": 14,
            "paint": {"fill-color": BUILDING, "fill-opacity": 0.6},
        },
        # Roads in two passes, casing under fill, so junctions read as junctions
        # rather than as overlapping strokes.
        {
            "id": "road-casing",
            "type": "line",
            "source": "basemap",
            "source-layer": "transportation",
            "minzoom": 9,
            "filter": ["!in", "class", "ferry", "path", "track"],
            "layout": {"line-cap": "round", "line-join": "round"},
            "paint": {
                "line-color": ROAD_CASING,
                "line-width": ["interpolate", ["linear"], ["zoom"], 9, 1.4, 14, 7],
            },
        },
        {
            "id": "road-minor",
            "type": "line",
            "source": "basemap",
            "source-layer": "transportation",
            "minzoom": 12,
            "filter": ["in", "class", "minor", "service", "residential"],
            "layout": {"line-cap": "round", "line-join": "round"},
            "paint": {
                "line-color": ROAD_MINOR,
                "line-width": ["interpolate", ["linear"], ["zoom"], 12, 0.8, 14, 4.5],
            },
        },
        {
            "id": "road-major",
            "type": "line",
            "source": "basemap",
            "source-layer": "transportation",
            "minzoom": 6,
            "filter": ["in", "class", "motorway", "trunk", "primary", "secondary"],
            "layout": {"line-cap": "round", "line-join": "round"},
            "paint": {
                "line-color": ROAD_MAJOR,
                "line-width": ["interpolate", ["linear"], ["zoom"], 6, 0.6, 14, 5.5],
            },
        },
        {
            "id": "boundary-country",
            "type": "line",
            "source": "basemap",
            "source-layer": "boundary",
            "filter": ["<=", "admin_level", 2],
            "paint": {
                "line-color": BOUNDARY,
                "line-dasharray": [3, 2],
                "line-width": ["interpolate", ["linear"], ["zoom"], 2, 0.6, 10, 1.6],
            },
        },
    ]

    # Labels last so nothing draws over them. Halos rather than a heavier weight:
    # the text has to survive crossing a road casing and a park fill without
    # getting dark enough to compete with the place markers.
    out += [
        {
            "id": "label-water",
            "type": "symbol",
            "source": "basemap",
            "source-layer": "water_name",
            "minzoom": 9,
            "layout": {
                "text-field": ["get", "name"],
                "text-font": FONT_REGULAR,
                "text-size": 11,
            },
            "paint": {
                "text-color": WATER_LINE,
                "text-halo-color": LABEL_HALO,
                "text-halo-width": 1,
            },
        },
        {
            "id": "label-street",
            "type": "symbol",
            "source": "basemap",
            "source-layer": "transportation_name",
            "minzoom": 13,
            "layout": {
                "text-field": ["get", "name"],
                "text-font": FONT_REGULAR,
                "text-size": 10,
                "symbol-placement": "line",
            },
            "paint": {
                "text-color": LABEL,
                "text-halo-color": LABEL_HALO,
                "text-halo-width": 1.2,
            },
        },
        {
            "id": "label-place",
            "type": "symbol",
            "source": "basemap",
            "source-layer": "place",
            "filter": ["in", "class", "country", "state", "city", "town", "village"],
            "layout": {
                "text-field": ["get", "name"],
                "text-font": FONT_MEDIUM,
                "text-size": [
                    "interpolate",
                    ["linear"],
                    ["zoom"],
                    3,
                    10,
                    10,
                    13,
                    14,
                    15,
                ],
            },
            "paint": {
                "text-color": LABEL,
                "text-halo-color": LABEL_HALO,
                "text-halo-width": 1.4,
            },
        },
    ]
    return out


if __name__ == "__main__":
    version, out_path = sys.argv[1], sys.argv[2]
    with open(out_path, "w") as fh:
        json.dump(style(version), fh, indent=2)
        fh.write("\n")
    print(f"wrote {out_path} for /basemap/{version}/")
