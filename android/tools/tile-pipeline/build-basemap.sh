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

# Resolved here rather than at the staging step below, because the check under it
# is worthless once the render has already run. §2 "Bucket retention": the version
# prefix is immutable and the previous ones are the rollback target, so a build
# that would land on a prefix already being served is a build that destroys the
# thing §2 promises — and the default below walks straight into it. An out-of-band
# rebuild fixing a bad build happens in the same calendar month as the build it is
# fixing, so `date +%Y-%m` hands it the live prefix. Such a rebuild sets
# BASEMAP_VERSION=<yyyy-mm-dd> explicitly.
VERSION="${BASEMAP_VERSION:-$(date -u +%Y-%m)}"
echo "version prefix: $VERSION"

# Only checkable if we are told where "served" is; unset is the normal case for a
# first build, when nothing is live to collide with. Deliberately not defaulted to
# the production host: a script that reaches for tiles.getbittr.com on its own is
# one that behaves differently on a machine that can resolve it.
if [ -n "${BASEMAP_SERVE_BASE:-}" ]; then
  probe="${BASEMAP_SERVE_BASE%/}/basemap/$VERSION/ch.pmtiles"
  # Status and transport failure kept apart. `|| echo 000` on the substitution
  # concatenates curl's own "000" with the fallback and yields "000\n000", which
  # matches no arm and falls through to the "not already being served" one — i.e.
  # a host that could not be reached at all reads as a cleared check. Tested.
  code="$(curl -sS -o /dev/null -w '%{http_code}' -I "$probe" 2>/dev/null)" || code=""
  case "$code" in
    200|206)
      cat >&2 <<EOF
refusing to build version '$VERSION': $probe already exists.

That prefix is immutable and may be the rollback target for whatever is pinned in
MapBasemap.STYLE_URI. Overwriting it is the one deletion tile-pipeline.md §2 does
not permit, and with the create-only deploy credential §2 asks for, the write would
fail after this build has already run for two hours.

Pick a new prefix and rerun:  BASEMAP_VERSION=$(date -u +%Y-%m-%d) $0 $*
EOF
      exit 1 ;;
    ""|000)
      cat >&2 <<EOF
refusing to build: $probe could not be reached, so the collision check did not run.

You set BASEMAP_SERVE_BASE, which says something is live there — either it is down,
which is worth knowing before spending 2h15m producing something to deploy to it, or
the URL is wrong, in which case this check was never going to fire. Neither is a
state to start an unattended build in.

Unset BASEMAP_SERVE_BASE to build without the check.
EOF
      exit 1 ;;
    404|403|410)
      echo "  ok    $VERSION is not already being served (HTTP $code)" ;;
    *)
      # A 5xx, a redirect to a login page, anything else: the prefix may or may not
      # be there and this cannot tell. Same reasoning as the unreachable arm.
      echo "refusing to build: $probe answered HTTP $code, which is neither 'served' nor 'absent'." >&2
      echo "Resolve that before building, or unset BASEMAP_SERVE_BASE to build without the check." >&2
      exit 1 ;;
  esac
else
  echo "  note  BASEMAP_SERVE_BASE unset; not checking whether '$VERSION' is already served"
fi

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
# The same merged extract is fed in here rather than a token one. The openmaptiles
# profile takes the `place` layer from OSM and uses Natural Earth's populated places
# only to *rank* what OSM already gave it, so "no OSM here" means "no city name here",
# and a token input produced a world band with no city labels anywhere at all.
#
# The real extract does NOT fix that, which is worth stating plainly because the
# feature count says otherwise. It raises the world band from nine place features to a
# few hundred, and every one of them is still inside the extract: Switzerland,
# Liechtenstein, Aosta and Vorarlberg, in forty languages. Measured by reading the
# string pool of the `place` layer -- z2 over the Americas has zero. The world city
# labels section 1 asks for come from make-world-places.py below, which is the only
# way to get them without a planet-sized OSM input.
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

step "world city labels (z0-z5)"
# Section 1 specifies the low band as "coastlines, borders, major cities". The pass
# above delivers the first two worldwide from Natural Earth; it cannot deliver the
# third, for the reason in make-world-places.py -- planetiler indexes NE populated
# places to rank OSM cities and never emits them as features.
#
# So they are built here, straight from the Natural Earth table planetiler has already
# downloaded as a build dependency. 7,342 cities, ~230 KB of tiles for the whole world.
NE_ZIP="$WORKDIR/data/sources/natural_earth_vector.sqlite.zip"
if [ ! -f "$NE_ZIP" ]; then
  echo "missing $NE_ZIP — planetiler downloads it; run the render steps first" >&2
  exit 1
fi
# Unpacked to 850 MB, used, and removed in the same step: this runs on a box where
# the extracts and the two planetiler temp directories are already the constraint.
unzip -o -q -j "$NE_ZIP" 'packages/natural_earth_vector.sqlite' -d "$WORKDIR/ne"
python3 "$SCRIPT_DIR/make-world-places.py" \
  "$WORKDIR/ne/natural_earth_vector.sqlite" "$WORKDIR/world-places.mbtiles"
rm -rf "$WORKDIR/ne"

step "combine and convert"
# --union, not the default replace. make-world-places.py writes `place_world` into the
# same z0-z5 tiles the low pass filled with coastlines and landcover, so replacing
# would hand back a world with city names and nothing under them. The two passes below
# it are still disjoint by zoom, so --union changes nothing for them.
python3 "$SCRIPT_DIR/merge-mbtiles.py" --union \
  "$WORKDIR/combined.mbtiles" \
  "$WORKDIR/low.mbtiles" "$WORKDIR/world-places.mbtiles" "$WORKDIR/high.mbtiles"
"$BIN_DIR/pmtiles" convert "$WORKDIR/combined.mbtiles" "$WORKDIR/ch.pmtiles"

step "style and glyphs"
# The app is pointed at the style, not at the archive, so the deployable set is
# three things and the archive is only one of them.
STAGE="$WORKDIR/stage/basemap/$VERSION"   # VERSION resolved and collision-checked at the top
mkdir -p "$STAGE"
python3 "$SCRIPT_DIR/make-style.py" "$VERSION" "$STAGE/style.json"

# Gate the generated style before anything is staged next to it. The app-side guards
# scan the `android/` tree and this file is never in it, so this is the only place the
# artefact the client actually fetches gets checked — see check-style-hosts.py for why
# scanning the generator instead would be worse. Run against the built style, not the
# uploaded one, so a bad edit to make-style.py fails here rather than after a deploy;
# verify-deploy.sh runs the same check against what the server returns.
python3 "$SCRIPT_DIR/check-style-hosts.py" "$STAGE/style.json"

mv "$WORKDIR/ch.pmtiles" "$STAGE/ch.pmtiles"

# Coverage, not volume. The first build produced a correctly sized archive whose
# world band carried city names only inside Switzerland, and nothing here noticed:
# the tile count, the byte count and `pmtiles show` were all exactly right. This
# names places and asserts what must be true at them, the absences included — so a
# build that silently widened past §1's scope fails as loudly as one that fell
# short. §4 calls for a quarterly rebuild; this is what stops the next one
# regressing in a way only a human panning the map would ever see.
PMTILES_BIN="$BIN_DIR/pmtiles" python3 "$SCRIPT_DIR/check-archive-coverage.py" \
  "$STAGE/ch.pmtiles"

# Glyphs are served from the bittr host for the reason make-style.py gives: the
# public endpoint for this schema is a third party that would receive the client
# IP on every label render, and no test in the repo can see that.
#
# Only the fontstacks the style actually names are staged, read back out of the
# style rather than listed here so the two cannot drift. The set the upstream zip
# ships is Regular, Bold and Italic — a style naming anything else (a "Medium",
# say) produces a 404 per label and no visible error, which is why
# verify-deploy.sh checks each name against what was deployed.
if [ ! -d "$STAGE/glyphs" ]; then
  curl -fsSL -o "$WORKDIR/noto-sans.zip" \
    "https://github.com/openmaptiles/fonts/releases/download/v2.0/noto-sans.zip"
  mkdir -p "$STAGE/glyphs"
  python3 - "$STAGE/style.json" <<'PY' | while IFS= read -r stack; do
import json, sys
style = json.load(open(sys.argv[1]))
names = set()
for layer in style["layers"]:
    for font in layer.get("layout", {}).get("text-font", []):
        names.add(font)
print("\n".join(sorted(names)))
PY
    echo "staging glyphs: $stack"
    unzip -q -o "$WORKDIR/noto-sans.zip" "$stack/*" -d "$STAGE/glyphs"
  done
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
