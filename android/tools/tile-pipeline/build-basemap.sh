#!/usr/bin/env bash
# Build the basemap PMTiles archive described by android/docs/tile-pipeline.md.
#
# Output: ch.pmtiles — z0-z5 planet, z6-z14 Switzerland plus a ~25 km buffer
# across the DE/FR/IT/AT/LI borders (section 1 of that document).
#
# The archive itself is not a repo artefact and is not checked in anywhere. This
# script is the artefact, because section 4 asks for a quarterly rebuild and a
# one-off blob cannot be rebuilt. Run it on any Linux host with ~12 GB of free
# disk, ~4 GB of free RAM and a JDK; it downloads everything else it needs.
#
#   ./build-basemap.sh [workdir]      # default workdir: ./basemap-build
#
# Two planetiler passes, because the two zoom bands have different footprints and
# a single pass cannot express that:
#
#   low  z0-z5   whole world, tiny, so panning out abroad shows a map not a void
#   high z6-z14  clipped to the buffer polygon, where the detail actually is
#
# They are merged into one MBTiles and converted once to PMTiles, which is what
# MapLibre reads directly over HTTP range requests — see section 2 on why there
# is no tile server process at the far end of this.

set -euo pipefail

WORKDIR="${1:-$PWD/basemap-build}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pinned rather than :latest so a rebuild three months from now is the same
# pipeline with newer data, instead of two variables moving at once.
PLANETILER_VERSION="v0.10.2"
PMTILES_VERSION="1.31.2"

# Geofabrik regions covering Switzerland and everything within 25 km of its
# border. The four neighbours plus Liechtenstein are not enough on their own:
# the German border runs into Bavaria near Lindau (schwaben) and the Italian
# border runs into South Tyrol in Val Mustair (nord-est).
REGIONS=(
  europe/switzerland
  europe/liechtenstein
  europe/austria
  europe/germany/baden-wuerttemberg
  europe/germany/bayern/schwaben
  europe/france/alsace
  europe/france/franche-comte
  europe/france/rhone-alpes
  europe/italy/nord-ovest
  europe/italy/nord-est
)

OSM_DIR="$WORKDIR/osm"
CLIP_DIR="$WORKDIR/clipped"
BIN_DIR="$WORKDIR/bin"
mkdir -p "$OSM_DIR" "$CLIP_DIR" "$BIN_DIR"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need java
need osmium        # Debian/Ubuntu: apt-get install osmium-tool
need python3       # with shapely and pyproj: apt-get install python3-shapely python3-pyproj
need curl
need unzip         # for the glyph set

step() { printf '\n=== %s\n' "$1"; }

step "tools"
if [ ! -f "$BIN_DIR/planetiler.jar" ]; then
  curl -fsSL -o "$BIN_DIR/planetiler.jar" \
    "https://github.com/onthegomap/planetiler/releases/download/$PLANETILER_VERSION/planetiler.jar"
fi
if [ ! -x "$BIN_DIR/pmtiles" ]; then
  curl -fsSL "https://github.com/protomaps/go-pmtiles/releases/download/v$PMTILES_VERSION/go-pmtiles_${PMTILES_VERSION}_Linux_x86_64.tar.gz" \
    | tar xz -C "$BIN_DIR" pmtiles
  chmod +x "$BIN_DIR/pmtiles"
fi

step "osm extracts"
for region in "${REGIONS[@]}"; do
  name="$(basename "$region")"
  if [ ! -s "$OSM_DIR/$name.osm.pbf" ]; then
    echo "downloading $region"
    curl -fsSL -o "$OSM_DIR/$name.osm.pbf" \
      "https://download.geofabrik.de/$region-latest.osm.pbf"
  fi
done
curl -fsSL -o "$OSM_DIR/switzerland.poly" \
  "https://download.geofabrik.de/europe/switzerland.poly"

step "buffer polygon"
python3 "$SCRIPT_DIR/make-buffer.py" "$OSM_DIR/switzerland.poly" "$WORKDIR/ch-buffer-25km.geojson"

step "clip the neighbours to the buffer"
# Switzerland is inside the buffer by construction, so it goes in whole. Every
# other extract is clipped, which is what keeps the corners of the bounding box
# — deep Bavaria, the Po valley — out of the archive. complete_ways keeps ways
# that cross the boundary intact instead of severing roads at the clip line.
for region in "${REGIONS[@]}"; do
  name="$(basename "$region")"
  if [ "$name" = "switzerland" ]; then
    cp "$OSM_DIR/$name.osm.pbf" "$CLIP_DIR/$name.pbf"
    continue
  fi
  echo "clipping $name"
  osmium extract -p "$WORKDIR/ch-buffer-25km.geojson" \
    --strategy=complete_ways --overwrite -o "$CLIP_DIR/$name.pbf" "$OSM_DIR/$name.osm.pbf"
done

step "merge"
# osmium merge drops objects duplicated across the overlapping Geofabrik cuts.
osmium merge --overwrite -o "$WORKDIR/ch-buffer-25km.osm.pbf" "$CLIP_DIR"/*.pbf

step "render z6-z14 (switzerland + buffer)"
java -Xmx3g -jar "$BIN_DIR/planetiler.jar" \
  --osm-path="$WORKDIR/ch-buffer-25km.osm.pbf" \
  --output="$WORKDIR/high.mbtiles" \
  --polygon="$WORKDIR/ch-buffer-25km.poly" \
  --minzoom=6 --maxzoom=14 \
  --download --force

step "render z0-z5 (planet)"
# Natural Earth and the global water-polygon shapefile carry the planet-wide part
# of this band: coastlines, water, landcover, and country boundaries through z4.
#
# The same merged extract is fed in here rather than a token one, and that is not
# arbitrary. The openmaptiles profile takes the `place` layer from OSM and uses
# Natural Earth's populated places only to *rank* what OSM already gave it, so
# "no OSM here" means "no city name here". Built against a token input, the world
# band came out with no city labels anywhere at all. Feeding it the real extract
# costs nothing and puts names on the part of the world these users pan around.
#
# What that still does not buy, measured rather than assumed: country boundaries
# outside the extract stop at z4, because the profile switches the boundary layer
# from Natural Earth to OSM at z5. See section 1 of the document.
java -Xmx3g -jar "$BIN_DIR/planetiler.jar" \
  --osm-path="$WORKDIR/ch-buffer-25km.osm.pbf" \
  --output="$WORKDIR/low.mbtiles" \
  --bounds=world \
  --minzoom=0 --maxzoom=5 \
  --download --force

step "combine and convert"
python3 "$SCRIPT_DIR/merge-mbtiles.py" \
  "$WORKDIR/combined.mbtiles" "$WORKDIR/low.mbtiles" "$WORKDIR/high.mbtiles"
"$BIN_DIR/pmtiles" convert "$WORKDIR/combined.mbtiles" "$WORKDIR/ch.pmtiles"

step "style and glyphs"
# The app is pointed at the style, not at the archive, so the deployable set is
# three things and the archive is only one of them.
VERSION="${BASEMAP_VERSION:-$(date -u +%Y-%m)}"
STAGE="$WORKDIR/stage/basemap/$VERSION"
mkdir -p "$STAGE"
python3 "$SCRIPT_DIR/make-style.py" "$VERSION" "$STAGE/style.json"
mv "$WORKDIR/ch.pmtiles" "$STAGE/ch.pmtiles"

# Glyphs are served from the bittr host for the reason make-style.py gives: the
# public endpoint for this schema is a third party that would receive the client
# IP on every label render, and no test in the repo can see that.
if [ ! -d "$STAGE/glyphs" ]; then
  curl -fsSL -o "$WORKDIR/noto-sans.zip" \
    "https://github.com/openmaptiles/fonts/releases/download/v2.0/noto-sans.zip"
  mkdir -p "$STAGE/glyphs"
  unzip -q -o "$WORKDIR/noto-sans.zip" -d "$STAGE/glyphs"
fi

step "result"
du -h "$STAGE/ch.pmtiles"
du -sh "$STAGE/glyphs"
"$BIN_DIR/pmtiles" show "$STAGE/ch.pmtiles" | head -20
echo
echo "Deployable tree, to be placed under the nginx root as /basemap/$VERSION/:"
find "$STAGE" -maxdepth 1 -mindepth 1 -printf '  %f\n'
echo "MapBasemap.STYLE_URI = https://tiles.getbittr.com/basemap/$VERSION/style.json"
echo "See README.md for the nginx config and the three checks to run after upload."
