#!/usr/bin/env python3
"""Fail if the built style would make the client fetch from a non-bittr host.

    check-style-hosts.py <style.json>
    check-style-hosts.py --selftest

## Why this is a separate check and not a test in the app repo

`TileHostGuardTest` and its siblings scan the `android/` tree. The style the client
actually fetches is generated here, uploaded, and never exists in that tree — so the
app-side scan cannot see it, and pointing the scan at `make-style.py` instead would be
worse than nothing: this pipeline legitimately fetches from Geofabrik and from GitHub
releases at build time, and a regex over the generator cannot tell a build-time fetch
from one the client will make. The built artefact has no such ambiguity. Every URL in
it is, by definition, a URL the renderer resolves on the device.

Written from the check the Head of App (Android) handed over on BIT-139, widened in
four places that a `re.findall` over the raw text cannot reach. Each of them is a way
the map ends up talking to a third party while the file still reads as clean:

- **Scheme-relative URLs.** `"//fonts.example.com/{fontstack}/{range}.pbf"` is a valid
  glyphs value and MapLibre resolves it against the style's scheme. It contains no
  `http://`, so a `https?://` scan does not see it at all.
- **Cleartext to our own host.** `http://tiles.getbittr.com/...` is on a bittr apex and
  passes a host-only test, but it is the tile path in the clear — the same disclosure
  section 2 of the document exists to prevent, minus the TLS.
- **`attribution` is not a fetch.** A source's `attribution` is rendered as text; a
  `<a href="https://www.openstreetmap.org/copyright">` inside it is the licence link,
  not a resource request. A text scan flags it, and the way that gets "fixed" is by
  deleting a licence credit. Flagged here as a note instead. (Today the style carries
  no `attribution` at all — see the comment in make-style.py and BIT-140 — so this arm
  is inert by design, and exists so it stays inert for the right reason.)
- **Structure.** Reporting `sources.basemap.url` rather than a bare URL means the
  reader knows what will break and where to fix it.

Kept out on purpose: any attempt to check *what is at* the URL. This runs offline in
the build, before anything is uploaded. verify-deploy.sh is what fetches.
"""
import json
import re
import sys

ALLOWED_APEXES = ("getbittr.com", "bittr.ch")

# Schemes MapLibre layers on top of a real URL. `pmtiles://https://host/x.pmtiles` is
# one URL wearing two schemes, and the host that matters is the inner one.
WRAPPER_SCHEMES = ("pmtiles://", "mbtiles://")

# Keys whose string value the renderer resolves and fetches. Everything else in a
# style is paint, layout, filters and metadata. This list is not used to *limit* the
# scan — every string is scanned — but to say so in the failure message.
FETCH_KEYS = {"url", "tiles", "data", "glyphs", "sprite"}


def unwrap(value):
    for scheme in WRAPPER_SCHEMES:
        if value.startswith(scheme):
            return value[len(scheme):]
    return value


def host_of(url):
    """Authority of an absolute or scheme-relative URL, lowercased, port stripped."""
    rest = url.split("//", 1)[1]
    authority = re.split(r"[/?#]", rest, maxsplit=1)[0]
    if "@" in authority:  # userinfo@host — the host is what is contacted
        authority = authority.rsplit("@", 1)[1]
    return re.sub(r":[0-9]+$", "", authority).lower()


def on_bittr(host):
    return any(host == a or host.endswith("." + a) for a in ALLOWED_APEXES)


def walk(node, path=""):
    """Yield (json-path, key-name, string) for every string in the document."""
    if isinstance(node, dict):
        for key, value in node.items():
            yield from walk(value, f"{path}.{key}" if path else key)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from walk(value, f"{path}[{index}]")
    elif isinstance(node, str):
        yield path, path.split(".")[-1].split("[")[0], node


def check(style):
    """Return (failures, notes). A failure is a client fetch off a bittr apex."""
    failures, notes = [], []
    for path, key, value in walk(style):
        inner = unwrap(value.strip())
        in_attribution = key == "attribution"

        # An attribution value is display HTML, so the URLs inside it are hrefs. Any
        # other string holding a URL is either a fetch key or something that should
        # not contain a URL at all; both are worth failing on.
        urls = (
            re.findall(r'https?://[^"\'\s<>)]+', inner)
            if in_attribution
            else [inner] if re.match(r"(https?:)?//", inner) else []
        )

        for url in urls:
            host = host_of(url)
            if in_attribution:
                if not on_bittr(host):
                    notes.append(
                        f"{path}: links to {host} — a licence href, not a fetch; "
                        f"left alone deliberately"
                    )
                continue
            if not on_bittr(host):
                what = "fetched by the renderer" if key in FETCH_KEYS else "a URL"
                failures.append(f"{path}: {what} on {host} — not under "
                                f"{' or '.join(ALLOWED_APEXES)}\n      {url}")
            elif url.startswith("//"):
                failures.append(f"{path}: scheme-relative URL — resolves against the "
                                f"style's scheme rather than pinning https\n      {url}")
            elif url.startswith("http://"):
                failures.append(f"{path}: cleartext http:// to our own host — the tile "
                                f"path in the clear\n      {url}")
    return failures, notes


SELFTESTS = [
    # (name, mutation applied to a known-good style, must it fail?)
    ("unmodified style", lambda s: s, False),
    ("foreign glyph host",
     lambda s: {**s, "glyphs": "https://fonts.openmaptiles.org/{fontstack}/{range}.pbf"},
     True),
    ("scheme-relative glyph host",
     lambda s: {**s, "glyphs": "//fonts.example.com/{fontstack}/{range}.pbf"}, True),
    ("cleartext to our own host",
     lambda s: {**s, "glyphs": "http://tiles.getbittr.com/g/{fontstack}/{range}.pbf"},
     True),
    ("apex-suffix lookalike",
     lambda s: {**s, "glyphs": "https://getbittr.com.tiles.example.net/{fontstack}/{range}.pbf"},
     True),
    ("foreign sprite",
     lambda s: {**s, "sprite": "https://cdn.example.com/sprite"}, True),
    ("foreign tile source",
     lambda s: {**s, "sources": {**s["sources"],
                                 "extra": {"type": "raster",
                                           "tiles": ["https://tile.example.com/{z}/{x}/{y}.png"]}}},
     True),
    ("pmtiles:// wrapping a foreign host",
     lambda s: {**s, "sources": {**s["sources"],
                                 "basemap": {**s["sources"]["basemap"],
                                             "url": "pmtiles://https://r2.example.com/ch.pmtiles"}}},
     True),
    ("explicit port on our own host",
     lambda s: {**s, "glyphs": "https://tiles.getbittr.com:443/g/{fontstack}/{range}.pbf"},
     False),
    ("OSM licence href in an attribution",
     lambda s: {**s, "sources": {**s["sources"],
                                 "basemap": {**s["sources"]["basemap"],
                                             "attribution": '<a href="https://www.openstreetmap.org/copyright">OSM</a>'}}},
     False),
]


def selftest():
    """Prove the check both ways against the style this repo generates today.

    The first case is the one that matters most: it asserts the correct style does not
    trip its own gate, so this cannot become a check that is routinely overridden.
    """
    # Loaded by path: the hyphen in make-style.py makes it not importable by name,
    # and generating the baseline rather than checking in a copy is the point — a
    # pinned fixture would go stale the first time the style changes.
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "make_style", __file__.rsplit("/", 1)[0] + "/make-style.py")
    make_style = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(make_style)
    base = make_style.style("2026-09")

    bad = 0
    for name, mutate, must_fail in SELFTESTS:
        failures, _ = check(mutate(json.loads(json.dumps(base))))
        did_fail = bool(failures)
        ok = did_fail == must_fail
        print(f"  {'ok  ' if ok else 'BAD '} {name}: "
              f"{'rejected' if did_fail else 'accepted'}"
              f"{'' if ok else '  <-- expected the opposite'}")
        if not ok:
            bad += 1
    print()
    if bad:
        print(f"{bad} self-test(s) failed.")
        return 1
    print(f"All {len(SELFTESTS)} self-tests passed.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <style.json> | --selftest")

    with open(sys.argv[1]) as fh:
        document = json.load(fh)
    failures, notes = check(document)
    for note in notes:
        print(f"  note  {note}")
    if failures:
        print(f"\n{sys.argv[1]} references hosts the client must not talk to:")
        for failure in failures:
            print(f"  FAIL  {failure}")
        sys.exit(1)
    print(f"  ok    every URL in {sys.argv[1]} is https on a bittr apex")
