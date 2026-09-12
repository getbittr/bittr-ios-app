#!/usr/bin/env python3
"""Check that every text the Maestro suite matches on still exists in the app's copy.

Some of what the suite selects on is still text. Alerts are not — BIT-78 gave
each one its own accessibility id, so *which* alert is on screen no longer
depends on its wording. What is left is screen labels, the keyboard accessory's
Done and OS-owned UI: 78 text matchers across the flows, 14 of them on app copy.

The `*Language.swift` -> `shared/strings/` consolidation moves every one of those
words. A rewording in transit breaks the suite in the worst possible way:

  - silently, because a copy change is not a behaviour change, so nobody expects
    a test result from it; and
  - on both platforms at once, because after the move iOS and Android read the
    same source.

This check makes that loud instead. `copy-lock.json` pins each matcher to the
string keys it depends on and to the text those keys had when the matcher was
written. The check re-resolves the lock against every copy source present --
`ios/bittr/Language.swift` and `shared/strings/en.json`, overlaid in that order
-- so the same lock file proves the move was verbatim without booting a
simulator. Run it on both sides of the migration commit, and at every point in
between: the move is a key at a time, and a key that has moved resolves from its
new home while the rest still resolve from the old one. Green throughout means no
word changed.

Not all of the app's copy is in the copy source. Some of what the suite matches
on is a hardcoded Swift literal or storyboard text (the QR menu's "Copy" and
"Share", the " sats" unit on move.satsInstant, "Swap complete" in the live
activity), which a consolidation that moves only `allWords` will walk straight
past. Those are locked as `literals`: text that must still appear verbatim in a
named file. Enumerated in shared/strings/README.md.

Five failures, each naming the flow that would have gone red:

  missing key   a key a matcher depends on is not in the copy source at all
  drift         the key is there but its text changed, and no longer matches
  literal gone  hardcoded copy a matcher depends on is no longer in its file
  undeclared    a flow matches on text that the lock does not classify
  unclassified  a lock entry is still `review` — --update proposed it, nobody
                decided

Exit status: 0 if the suite's copy dependencies all hold, 1 otherwise.

    ./shared/strings/check_flow_copy.py             # check
    ./shared/strings/check_flow_copy.py --update    # rewrite the lock from the
                                                    # current flows + copy source
    ./shared/strings/check_flow_copy.py --source shared/strings/en.json

Deliberately stdlib-only and regex-based, like shared/test-ids/*.py: these run
in CI on any python3 with no pip step.
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
LOCK_PATH = ROOT / "shared/strings/copy-lock.json"
FLOW_DIR = ROOT / "shared/flows"
SWIFT_SOURCE = ROOT / "ios/bittr/Language.swift"
JSON_SOURCE = ROOT / "shared/strings/en.json"

# Classes a matcher can be declared as. Only `copy` is enforced against the copy
# source; the rest are the matchers that are deliberately not app copy, and each
# one carries a `why` so the exemption is a decision rather than an oversight.
CLASSES = {
    "copy": "app copy — must still exist, verbatim, in the copy source",
    "system": "OS-owned UI (permission alerts, share sheet, paste prompt)",
    "data": "regtest data or a runtime-captured value, not copy",
    "payload": "text the flow itself injects (e.g. an APNs payload it posts)",
    "review": "proposed by --update, needs a human decision",
}

# Maestro selector keys whose value is matched against on-screen text. `text:` is
# the selector; `header_text`/`body_text` appear in the notification helper's
# runScript payloads, which is where a flow supplies its own copy.
TEXT_LINE = re.compile(
    r'(?:^|[\s{,])(?:text|header_text|body_text):\s*"((?:[^"\\]|\\.)*)"'
)
# A `#` that starts a comment: at line start or after whitespace. Flow prose
# says things like `# asserts text: "Oops!"`, which is not a live matcher.
COMMENT = re.compile(r"(?:^|\s)#.*$")

# `"key": "value",` — one entry of Language.swift's allWords dictionary.
SWIFT_ENTRY = re.compile(r'^\s*"([A-Za-z0-9_]+)"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$', re.M)
SWIFT_TABLE = re.compile(r"let allWords:\s*\[String:\s*String\]\s*=\s*\[(.*?)^\s*\]", re.S | re.M)

# A runtime substitution in a copy string: "Send all <amount> BTC". The flow sees
# the substituted rendering ("Send all 0.0001 BTC"), so a matcher can only ever
# be compared against the template with these holes widened.
PLACEHOLDER = re.compile(r"<[a-zA-Z0-9_]+>")


def load_copy(source: Path) -> dict[str, str]:
    """{key: text} from either Language.swift or a shared/strings locale JSON."""
    if source.suffix == ".json":
        data = json.loads(source.read_text())
        return {k: v for k, v in _flatten(data) if isinstance(v, str)}

    table = SWIFT_TABLE.search(source.read_text())
    if not table:
        sys.exit(
            f"{source}: no `let allWords:[String:String] = [` table found. If the "
            "consolidation has landed, point --source at shared/strings/en.json."
        )
    return {
        key: raw.encode().decode("unicode_escape")
        for key, raw in SWIFT_ENTRY.findall(table.group(1))
    }


def _flatten(node, prefix=""):
    """Nested locale JSON -> dotted keys. Flat files come through unchanged."""
    for key, value in node.items():
        if key.startswith("_"):
            continue
        full = f"{prefix}{key}"
        if isinstance(value, dict):
            yield from _flatten(value, f"{full}.")
        else:
            yield full, value


def default_sources() -> list[Path]:
    """Every copy source present, in migration order: Language.swift, then en.json.

    The point of the default is that the same command is correct on both sides of
    the migration commit, so CI does not need editing halfway through the move.
    The move is not one commit, though — it is a key at a time, and while it runs
    a key lives in exactly one of the two files. Preferring en.json the moment it
    exists reads a half-migrated tree as a mass deletion: BIT-56 landed a two-key
    en.json on `ios-parity` and the guard reported 10 keys missing that had never
    moved. So read both and overlay, which is the only reading that is true at
    every point of the move: en.json wins where both define a key, because that is
    where the key is going.
    """
    return [p for p in (SWIFT_SOURCE, JSON_SOURCE) if p.exists()]


def load_all(sources: list[Path]) -> dict[str, str]:
    """Merge the sources left to right; the destination of the move wins."""
    copy: dict[str, str] = {}
    for source in sources:
        copy.update(load_copy(source))
    return copy


def label_for(sources: list[Path]) -> str:
    """Repo-relative names for the messages. A --source outside the repo keeps its own."""
    names = []
    for source in sources:
        try:
            names.append(str(source.resolve().relative_to(ROOT)))
        except ValueError:
            names.append(str(source))
    return " + ".join(names)


def collect_matchers() -> dict[str, list[str]]:
    """{matcher: [flow paths]} for every text the flows match on."""
    found: dict[str, set[str]] = {}
    for path in sorted(FLOW_DIR.rglob("*.yaml")):
        rel = str(path.relative_to(ROOT))
        for raw in path.read_text().splitlines():
            for match in TEXT_LINE.finditer(COMMENT.sub("", raw)):
                found.setdefault(match.group(1), set()).add(rel)
    return {k: sorted(v) for k, v in sorted(found.items())}


def matches(matcher: str, text: str) -> bool:
    """Would Maestro's `text: <matcher>` select an element reading `text`?

    Maestro matches the value as a case-insensitive regex against the element's
    *entire* text, which is why the suite wraps every partial matcher in `.*`:
    `.*between 4 and 8 digits.*` for a long alert body, but a bare `oops!` where
    the label reads exactly "Oops!".

    Full match, not a substring search, and the difference matters in the
    direction that counts. Rewording `cancel` from "Cancel" to "Cancel payment"
    leaves a substring search green while Maestro's `text: "Cancel"` stops
    selecting the button — a guard that was more permissive than the tool it
    guards would go quiet on exactly the failure it exists to catch.
    """
    try:
        return re.fullmatch(matcher, text, re.I | re.S) is not None
    except re.error:
        return False


def matches_rendered(matcher: str, template: str) -> bool:
    """Whether `matcher` is a *rendered* form of a copy string, or embeds one.

    Two cases the other direction catches, both of them real in this suite:

      - `youcansend` is "You can send <amount> satoshis." and send_onchain.yaml
        waits for the literal "You can send 0 satoshis.". Widening the
        placeholder makes the copy the pattern and the matcher the subject.
      - remove_wallet.yaml waits for "0 sats" on a label the app builds by
        concatenating a number and a unit. The matcher embeds the copy rather
        than the other way round.

    Short copy is excluded from the second case: a two-character string appears
    inside half the matchers by accident.
    """
    if PLACEHOLDER.search(template):
        widened = ".{0,60}".join(re.escape(part) for part in PLACEHOLDER.split(template))
        return re.fullmatch(widened, matcher, re.I | re.S) is not None
    return len(template.strip()) >= 3 and template.strip().lower() in matcher.lower()


def resolve(matcher: str, copy: dict[str, str]) -> list[str]:
    """Every copy key `matcher` could be selecting on, best-effort.

    Used by --update to propose declarations, never by the check itself: the
    check only ever verifies the keys a human declared, so a short matcher like
    "Allow" cannot be quietly re-pointed at whatever copy happens to contain it.
    """
    hits = [key for key, text in copy.items() if matches(matcher, text)]
    if hits:
        return sorted(hits)
    return sorted(key for key, text in copy.items() if matches_rendered(matcher, text))


def holds(entry: dict, key: str, copy: dict[str, str]) -> bool:
    """Whether the matcher still selects on `key`'s current text."""
    text = copy[key]
    return matches(entry["matcher"], text) or matches_rendered(entry["matcher"], text)


def check(lock: dict, copy: dict[str, str], used: dict[str, list[str]], source: str) -> int:
    declared = {entry["matcher"]: entry for entry in lock["matchers"]}
    failures = 0

    for matcher, flows in used.items():
        entry = declared.get(matcher)
        if entry is None:
            failures += 1
            print(
                f"undeclared: {matcher!r}\n"
                f"  matched in: {', '.join(flows)}\n"
                f"  A flow matches on text that copy-lock.json does not classify. Run "
                f"--update, then set its class to one of: {', '.join(CLASSES)}."
            )
            continue
        if entry["class"] == "review":
            failures += 1
            print(
                f"unclassified: {matcher!r}\n"
                f"  matched in: {', '.join(flows)}\n"
                f"  --update proposed keys {entry['keys'] or '[]'} and nobody confirmed "
                f"them. Decide the class; `review` is not a resting state."
            )
            continue
        if entry["class"] != "copy":
            if not entry.get("why"):
                failures += 1
                print(
                    f"unexplained exemption: {matcher!r} is class={entry['class']} with no "
                    f"`why`. An exemption without a reason is indistinguishable from an "
                    f"oversight."
                )
            continue

        for key in entry["keys"]:
            if key not in copy:
                failures += 1
                print(
                    f"missing key: {key}\n"
                    f"  matcher: {matcher!r}\n"
                    f"  expected text: {entry['texts'].get(key)!r}\n"
                    f"  was in: {source}, now absent\n"
                    f"  would fail: {', '.join(flows)}"
                )
            elif not holds(entry, key, copy):
                failures += 1
                print(
                    f"drift: {key}\n"
                    f"  matcher: {matcher!r}\n"
                    f"  was: {entry['texts'].get(key)!r}\n"
                    f"  now: {copy[key]!r}\n"
                    f"  would fail: {', '.join(flows)}\n"
                    f"  Either the consolidation reworded copy it said it was only "
                    f"moving, or the change is deliberate — in which case update the "
                    f"assertion and re-lock in the same commit."
                )

        for literal in entry.get("literals", []):
            path = ROOT / literal["file"]
            if not path.exists():
                failures += 1
                print(
                    f"literal gone: {literal['text']!r}\n"
                    f"  matcher: {matcher!r}\n"
                    f"  {literal['file']} no longer exists\n"
                    f"  would fail: {', '.join(flows)}"
                )
            # Quoted, not a bare substring: renaming UIAction(title: "Copy") to
            # "Copy address" leaves "Copy" present as a substring, and that rename
            # is precisely the drift this is here to catch. Swift literals and
            # storyboard attributes are both double-quoted, so one form covers both.
            elif f'"{literal["text"]}"' not in path.read_text(errors="replace"):
                failures += 1
                print(
                    f"literal gone: {literal['text']!r}\n"
                    f"  matcher: {matcher!r}\n"
                    f"  not in {literal['file']} any more\n"
                    f"  would fail: {', '.join(flows)}\n"
                    f"  This copy is hardcoded outside {source}. If the "
                    f"consolidation has replaced it with a key lookup, move the entry from "
                    f"`literals` to `keys` in the same commit."
                )

    for matcher in sorted(set(declared) - set(used)):
        # Harmless, and sometimes deliberate: an entry can be pre-locked ahead of a
        # flow that is still in review, so the merge does not land as a red build.
        note = declared[matcher].get("why", "")
        print(
            f"stale: {matcher!r} is locked but no flow matches on it "
            f"(harmless; --update prunes it)" + (f"\n  {note}" if note else "")
        )

    enforced = [e for e in declared.values() if e["class"] == "copy"]
    keys = sum(len(e["keys"]) for e in enforced)
    literals = sum(len(e.get("literals", [])) for e in enforced)
    print(
        f"{len(used)} matchers across {len(set().union(*used.values())) if used else 0} flow files; "
        f"{len(enforced)} declared as copy, covering {keys} keys in "
        f"{source} and {literals} hardcoded literals; "
        f"{len(copy)} keys available; {failures} failures"
    )
    return 1 if failures else 0


def update(lock_path: Path, copy: dict[str, str], used: dict[str, list[str]], source: str) -> int:
    """Rewrite the lock: keep every human declaration, propose the new matchers.

    Classifications are never downgraded by a regeneration — an entry a human
    marked `system` stays `system` even though "Allow" also appears inside app
    copy. Only `texts` is refreshed, and only for keys that still match, so a
    drift cannot be laundered into the lock by running --update.
    """
    existing = {}
    if lock_path.exists():
        existing = {e["matcher"]: e for e in json.loads(lock_path.read_text())["matchers"]}

    entries, proposed = [], 0
    for matcher, flows in used.items():
        old = existing.get(matcher)
        if old:
            entry = {
                "matcher": matcher,
                "class": old["class"],
                "keys": old.get("keys", []),
                "texts": {
                    # A key whose text no longer matches keeps its locked text, so
                    # --update cannot launder a drift into the lock: the next check
                    # still reports it against the wording the matcher was written for.
                    key: copy[key] if key in copy and holds(old, key, copy)
                    else old.get("texts", {}).get(key, copy.get(key, ""))
                    for key in old.get("keys", [])
                },
                "literals": old.get("literals", []),
                "why": old.get("why", ""),
                "flows": flows,
            }
        else:
            proposed += 1
            candidates = resolve(matcher, copy)
            entry = {
                "matcher": matcher,
                "class": "copy" if len(candidates) == 1 else "review",
                "keys": candidates,
                "texts": {key: copy[key] for key in candidates},
                "literals": [],
                "why": "" if len(candidates) == 1 else "proposed by --update; confirm the class and keys",
                "flows": flows,
            }
            print(f"proposed: {matcher!r} -> class={entry['class']} keys={candidates or '[]'}")
        if not entry["why"]:
            entry.pop("why")
        if not entry["literals"]:
            entry.pop("literals")
        entries.append(entry)

    pruned = sorted(set(existing) - set(used))
    for matcher in pruned:
        print(f"pruned: {matcher!r} (no flow matches on it any more)")

    lock_path.write_text(
        json.dumps(
            {
                "_comment": (
                    "Generated by shared/strings/check_flow_copy.py --update, then "
                    "hand-classified. Pins every text the Maestro suite matches on to "
                    "the copy keys it depends on, so the *Language.swift -> "
                    "shared/strings/ move cannot reword a string without a build "
                    "failure. See shared/strings/README.md."
                ),
                "_classes": CLASSES,
                "source": source,
                "matchers": entries,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )
    print(
        f"wrote {lock_path.relative_to(ROOT)}: {len(entries)} matchers "
        f"({proposed} newly proposed, {len(pruned)} pruned)"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--update", action="store_true", help="rewrite copy-lock.json from the current flows")
    parser.add_argument(
        "--source",
        type=Path,
        action="append",
        default=None,
        help="copy source, repeatable, later ones win (default: every source present)",
    )
    args = parser.parse_args()

    sources = args.source or default_sources()
    for source in sources:
        if not source.exists():
            sys.exit(f"{source}: no such copy source")
    if not sources:
        sys.exit(f"no copy source found: neither {SWIFT_SOURCE} nor {JSON_SOURCE} exists")

    copy = load_all(sources)
    source = label_for(sources)
    used = collect_matchers()

    if args.update:
        return update(LOCK_PATH, copy, used, source)
    if not LOCK_PATH.exists():
        sys.exit(f"{LOCK_PATH}: missing. Create it with --update, then classify the proposals.")
    return check(json.loads(LOCK_PATH.read_text()), copy, used, source)


if __name__ == "__main__":
    sys.exit(main())
