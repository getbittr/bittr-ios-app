#!/usr/bin/env bash
# Check a deployed basemap before its URL goes into MapBasemap.STYLE_URI.
#
#   ./verify-deploy.sh https://tiles.getbittr.com/basemap/2026-09
#
# Everything here is client-side and can be run by anyone from anywhere; it needs
# no access to the host. What it cannot check is the two things §2 and §5 of
# android/docs/tile-pipeline.md are actually about — who operates the machine that
# answered, and whether that machine wrote a log line. Those are checked by the
# person who runs the edge, on the edge. See README.md.
#
# Exit status is the number of failed checks, so this is usable as a gate.

set -uo pipefail

BASE="${1:-}"
if [ -z "$BASE" ]; then
  echo "usage: $0 <base-url, e.g. https://tiles.getbittr.com/basemap/2026-09>" >&2
  exit 64
fi
BASE="${BASE%/}"

fails=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# --- the host itself -------------------------------------------------------
# TileHostGuardTest enforces this inside the app; it is repeated here because a
# deploy can be pointed anywhere and this script may be run before that test is.
# Port stripped before matching: an explicit :443, or a non-default port on a
# staging host, is not a different host and must not read as one.
host="$(printf '%s' "$BASE" | sed -E 's#^https?://([^/]+).*#\1#; s#:[0-9]+$##')"
echo "host: $host"
case "$host" in
  *.getbittr.com | getbittr.com | *.bittr.ch | bittr.ch)
    pass "serving host is under a bittr apex" ;;
  *)
    fail "serving host is NOT under getbittr.com or bittr.ch — TileHostGuardTest will reject it, and per BIT-139 that is a decision change, not a workaround" ;;
esac

case "$BASE" in
  https://*) pass "scheme is https" ;;
  *) fail "scheme is not https" ;;
esac

# --- the archive -----------------------------------------------------------
echo "archive: $BASE/ch.pmtiles"
headers="$(curl -sS -D- -o /dev/null -r 1024-2047 "$BASE/ch.pmtiles" 2>/dev/null)"
status="$(printf '%s' "$headers" | sed -n '1s#.* \([0-9][0-9][0-9]\).*#\1#p' | head -1)"

if [ "$status" = "206" ]; then
  pass "range request returns 206"
else
  fail "range request returned '$status', expected 206 — MapLibre addresses every tile this way, so without it the map is blank rather than slow"
fi

if printf '%s' "$headers" | grep -qi '^content-range: bytes 1024-2047/'; then
  pass "Content-Range is the range that was asked for"
else
  fail "Content-Range missing or wrong"
fi

# Accept-Ranges is advertised on the 200, not on the 206 — nginx does not repeat it
# on a partial response and RFC 9110 does not require it to. Checking the 206 for it
# reads as a broken deploy on a working one, which is how this ended up as its own
# request rather than a second grep over the headers above.
full="$(curl -sS -D- -o /dev/null -I "$BASE/ch.pmtiles" 2>/dev/null)"
ar="$(printf '%s' "$full" | grep -ci '^accept-ranges: *bytes')"
if [ "$ar" = "1" ]; then
  pass "exactly one Accept-Ranges: bytes on the full response"
elif [ "$ar" = "0" ]; then
  fail "no Accept-Ranges: bytes on the full response"
else
  # nginx emits this natively for static files; an add_header on top duplicates it.
  fail "Accept-Ranges appears $ar times — something is adding a header the server already sends"
fi

if printf '%s' "$headers" | grep -qi '^cache-control:.*immutable'; then
  pass "immutable Cache-Control on the 206"
else
  fail "no immutable Cache-Control on the 206 — every tile read is a range request, so caching that only covers 200 covers nothing the map fetches"
fi

# The first seven bytes of a PMTiles v3 archive are the ASCII "PMTiles", then the
# spec version. Checked because an HTML error page can arrive with a 200 and a
# perfectly good Content-Length.
magic="$(curl -sS -r 0-7 "$BASE/ch.pmtiles" 2>/dev/null | head -c 7)"
if [ "$magic" = "PMTiles" ]; then
  pass "archive starts with the PMTiles magic bytes"
else
  fail "archive does not start with 'PMTiles' — got '$magic'"
fi

# --- the style and the glyphs ---------------------------------------------
# STYLE_URI points at the style, not the archive, and a style that 404s is a blank
# map with a perfectly healthy archive behind it.
style="$(curl -sS "$BASE/style.json" 2>/dev/null)"
if printf '%s' "$style" | grep -q '"version"'; then
  pass "style.json is served and looks like a style"
else
  fail "style.json missing or not JSON"
fi

if printf '%s' "$style" | grep -q "pmtiles://$BASE/ch.pmtiles"; then
  pass "style points at this version's archive"
else
  fail "style does not name $BASE/ch.pmtiles — a style pinned to a different version is exactly what the versioned path exists to prevent"
fi

# Any style with labels fetches one of these per label. A foreign glyph host would
# send the client IP to a third party on every label render, and TileHostGuardTest
# cannot see it — its URL markers do not appear in a glyphs URL.
for u in $(printf '%s' "$style" | tr ',' '\n' | sed -n 's#.*"glyphs": *"\([^"]*\)".*#\1#p'); do
  case "$u" in
    "$BASE"/*) pass "glyphs are on this host" ;;
    *) fail "glyphs URL is off-host: $u" ;;
  esac
done

# Every fontstack the style names, checked against what was actually deployed.
# MapLibre asks for a stack as one comma-joined path, so a name that is not a
# directory in the glyphs tree is a 404 and not a fallback — the layer's labels
# simply never draw, on a map that otherwise looks completely healthy. The
# openmaptiles glyph set ships Regular, Bold and Italic and no Medium, which is
# exactly the way this goes wrong.
# Newlines collapsed but not spaces: the font names contain spaces ("Noto Sans
# Regular"), and stripping them produced a name that 404s for the wrong reason.
stacks="$(printf '%s' "$style" | tr -d '\n' | grep -o '"text-font": *\[[^]]*\]' | grep -o '"[^"]*"' | grep -v 'text-font' | tr -d '"' | sort -u)"
if [ -z "$stacks" ]; then
  echo "  note  style names no text-font; skipping the glyph checks"
else
  while IFS= read -r stack; do
    [ -z "$stack" ] && continue
    enc="$(printf '%s' "$stack" | sed 's/ /%20/g')"
    gcode="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/glyphs/$enc/0-255.pbf" 2>/dev/null)"
    if [ "$gcode" = "200" ]; then
      pass "glyphs resolve for '$stack'"
    else
      fail "glyphs for '$stack' returned $gcode — every label in the layers using it will silently not draw"
    fi
  done <<EOF
$stacks
EOF
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "All client-side checks passed."
  echo "Still to confirm on the edge itself, because nothing here can see it:"
  echo "  - the access log gained no lines from this run (tile-pipeline.md §5)"
  echo "  - the TLS for this hostname is terminated by bittr, or by a processor"
  echo "    under contract with logging configured as in §5 (§2)"
else
  echo "$fails check(s) failed."
fi
exit "$fails"
