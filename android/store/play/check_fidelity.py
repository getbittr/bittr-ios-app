#!/usr/bin/env python3
"""Bind every claim the Play listing makes to the Android build that has to back it.

`check_listing.py` reads the copy for words the perimeter forbids. It is a word
list, so it catches copy that *names* the regulated service. It cannot catch copy
that describes a capability the shipped APK does not have — and that was the
**first** of the two reasons Compliance blocked the original listing (BIT-37,
Tier 1 review, 2026-09-10):

    A first-release listing whose headline feature is absent from the APK is a
    misrepresentation in the store, independently of anything regulatory.

That reason was applied to `Buy bitcoin` because `Buy bitcoin` was the sentence
someone noticed. It is the same rule, and it applies to every other claim in the
copy too. This script applies it mechanically, so the next edit cannot
reintroduce an unbacked claim quietly.

How it works: `claims.json` lists each claim in the approved copy and the
`shared/docs/parity.md` feature rows that must read `done` in the **Android**
column before the claim may be published. This script joins the two and fails on
any claim whose rows are not all done.

Usage:
    check_fidelity.py [--parity PATH] [--claims PATH]

Exit code 0 = every claim is backed by the Android build, 1 = at least one claim
is not yet publishable.

### What a failure here means

It does **not** mean the copy is wrong. It means the copy is ahead of the build.
The listing is submitted once and is cached and indexed from that moment, so the
copy has to describe the APK at submission — not the APK at the end of the port.
Either the claim waits for the feature, or the sentence comes out of the listing
and goes back in when the feature lands.

### What this script cannot see

It trusts `claims.json` to enumerate the claims. Nothing mechanically proves that
every sentence of the copy has a corresponding entry — that mapping is a reading
of the text and stays a human job. Adding a sentence to the listing without
adding its claim here defeats the check silently, which is why `claims.json`
carries the copy's exact wording in `quote` rather than a paraphrase: it can be
diffed against the listing by eye.
"""

import argparse
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]

DEFAULT_PARITY = REPO / "shared" / "docs" / "parity.md"
DEFAULT_CLAIMS = HERE / "claims.json"

# The parity tables are `| Feature | iOS | Android | Maestro flow | Notes |`.
# Only the first three columns matter here.
ROW = re.compile(r"^\|(?P<cells>.+)\|\s*$")
SEPARATOR = re.compile(r"^[\s|:-]+$")


def parse_parity(path: pathlib.Path) -> dict[str, str]:
    """Map each parity feature name to its Android-column status, verbatim."""
    statuses: dict[str, str] = {}

    for raw in path.read_text(encoding="utf-8").splitlines():
        match = ROW.match(raw.strip())
        if not match or SEPARATOR.match(raw.strip()):
            continue

        cells = [c.strip() for c in match.group("cells").split("|")]
        if len(cells) < 3:
            continue

        feature, ios, android = cells[0], cells[1], cells[2]

        # Skip the header row of each table.
        if feature == "Feature" and ios == "iOS":
            continue

        # `claims.json` matches column 1 exactly, so strip the emphasis markup
        # the Notes column uses but the Feature column occasionally inherits.
        feature = feature.strip("*_` ")
        if feature:
            statuses[feature] = android

    return statuses


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parity", type=pathlib.Path, default=DEFAULT_PARITY)
    parser.add_argument("--claims", type=pathlib.Path, default=DEFAULT_CLAIMS)
    args = parser.parse_args()

    if not args.parity.exists():
        print(f"parity tracker not found: {args.parity}", file=sys.stderr)
        return 1
    if not args.claims.exists():
        print(f"claims file not found: {args.claims}", file=sys.stderr)
        return 1

    statuses = parse_parity(args.parity)
    claims = json.loads(args.claims.read_text(encoding="utf-8"))["claims"]

    print(f"parity: {len(statuses)} feature rows from {args.parity}")
    print(f"claims: {len(claims)} from {args.claims}")
    print()

    blocked = []
    ungated = []

    for claim in claims:
        required = claim.get("requires") or []

        if not required:
            # A claim that is true by construction or a fact about the company.
            # Printed rather than skipped so the set is visibly complete: a claim
            # with no requirements should be a deliberate choice, not an
            # omission.
            ungated.append(claim)
            print(f"  --  {claim['id']}: no feature dependency")
            continue

        problems = []
        for feature in required:
            if feature not in statuses:
                problems.append(f"{feature!r} — NO SUCH PARITY ROW")
            elif statuses[feature] != "done":
                problems.append(f"{feature!r} — Android reads {statuses[feature]!r}")

        if problems:
            blocked.append((claim, problems))
            print(f"  FAIL {claim['id']}")
            for problem in problems:
                print(f"         {problem}")
        else:
            print(f"  ok   {claim['id']}")

    print()
    print(
        f"{len(claims)} claims · {len(claims) - len(blocked) - len(ungated)} backed · "
        f"{len(ungated)} ungated · {len(blocked)} NOT publishable"
    )

    if not blocked:
        print("every gated claim is backed by the Android build.")
        return 0

    print()
    print("The listing claims capabilities the Android build does not have.")
    print("Each of these is the same defect Compliance blocked `Buy bitcoin` for:")
    print()
    for claim, _ in blocked:
        print(f"  {claim['id']}:")
        print(f"    “{claim['quote']}”")
    print()
    print("Remove the sentence from the listing, or hold submission until the")
    print("parity rows read done. Do not submit and fix the copy afterwards — a")
    print("listing that has been live has been seen, cached and indexed.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
