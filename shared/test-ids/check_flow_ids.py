#!/usr/bin/env python3
"""Check that every ID a Maestro flow selects on is in the shared registry.

A flow that selects `id: buy.contineuButton` fails at run time with "element not
found", on both platforms, and the failure looks exactly like a missing testTag
in the app. This check turns that into a build-time error instead.

Registered means one of:
  - a plain leaf in test-ids.json                       → `buy.continueButton`
  - a runtime-indexed leaf (`_index`) plus a number     → `history.transactionButton0`

Exit status: 0 if every selected ID resolves, 1 otherwise.

    ./shared/test-ids/check_flow_ids.py            # check
    ./shared/test-ids/check_flow_ids.py --unused   # also list registered-but-unselected IDs
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
JSON_PATH = ROOT / "shared/test-ids/test-ids.json"
FLOW_DIR = ROOT / "shared/flows"

# `id: foo`, `id: "foo"`, `- id: foo` — Maestro's selector key, wherever it sits.
ID_LINE = re.compile(r'(?:^|[\s{,])id:\s*"?([A-Za-z0-9_.${}*-]+)"?')
# A `#` that starts a comment: at line start, or after whitespace. Prose in a
# comment can contain "bundle id: the ...", which is not a selector.
COMMENT = re.compile(r"(?:^|\s)#.*$")


def load_registry(data: dict) -> tuple[set[str], dict[str, dict]]:
    """(plain IDs, {base: index spec}) — the two ways an ID can be registered."""
    plain: set[str] = set()
    indexed: dict[str, dict] = {}

    def walk(node: dict, path: list[str]) -> None:
        for key, value in node.items():
            if key.startswith("_"):
                continue
            full = ".".join(path + [key])
            if isinstance(value, dict) and "_index" in value:
                spec = value["_index"] or {}
                indexed[full] = {
                    "offset": spec.get("offset", 0),
                    "separator": spec.get("separator", ""),
                }
            elif isinstance(value, dict):
                walk(value, path + [key])
            else:
                plain.add(full)

    walk(data, [])
    return plain, indexed


def collect_used(flow_dir: Path) -> dict[str, list[str]]:
    """{id: ["path:line", ...]} for every ID selected anywhere in the flows."""
    used: dict[str, list[str]] = {}
    for path in sorted(flow_dir.rglob("*.yaml")):
        for lineno, raw in enumerate(path.read_text().splitlines(), 1):
            line = COMMENT.sub("", raw)
            for match in ID_LINE.finditer(line):
                where = f"{path.relative_to(ROOT)}:{lineno}"
                used.setdefault(match.group(1), []).append(where)
    return used


def resolve(candidate: str, plain: set[str], indexed: dict[str, dict]) -> str | None:
    """The registry entry `candidate` selects on, or None if it selects on nothing.

    `history.transactionButton0` resolves to the indexed entry
    `history.transactionButton` — so a numbered selector also counts that entry
    as covered, which is what --unused reports on.
    """
    if candidate in plain or candidate in indexed:
        return candidate
    for base, spec in indexed.items():
        suffix = candidate[len(base) :]
        if candidate.startswith(base) and re.fullmatch(
            re.escape(spec["separator"]) + r"\d+", suffix
        ):
            return base
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--unused",
        action="store_true",
        help="also report registered IDs that no flow selects on",
    )
    args = parser.parse_args()

    plain, indexed = load_registry(json.loads(JSON_PATH.read_text()))
    used = collect_used(FLOW_DIR)

    covered: set[str] = set()
    unresolved: dict[str, list[str]] = {}
    for identifier, where in sorted(used.items()):
        entry = resolve(identifier, plain, indexed)
        if entry is None:
            unresolved[identifier] = where
            print(f"unregistered: {identifier}  ({len(where)} uses, first at {where[0]})")
        else:
            covered.add(entry)

    if args.unused:
        for identifier in sorted((plain | set(indexed)) - covered):
            print(f"unused: {identifier}")

    print(
        f"{len(used)} IDs selected across {len(list(FLOW_DIR.rglob('*.yaml')))} flow files; "
        f"{len(plain)} plain + {len(indexed)} indexed registered; "
        f"{len(unresolved)} unregistered"
    )
    return 1 if unresolved else 0


if __name__ == "__main__":
    sys.exit(main())
