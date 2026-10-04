#!/usr/bin/env python3
"""Refuse a release bundle that is not on mainnet.

`:app:bundleRelease` already guards its *inputs* — it will not run with a
non-mainnet node configuration in the environment. This checks the *output*,
which is a different claim: that the values actually reached the artefact that
is about to be uploaded. A guard on inputs cannot see a stale intermediate, a
half-rebuilt dex or an artefact picked up from the wrong path.

**Check the node identity, not the URLs.** `BoltzApi.kt` hardcodes
`https://esplora-regtest.bittr.io` as a DEVELOPMENT enum constant, so that string
is in the dex of every build and finding it proves nothing. The node id and
address only ever arrive from the environment, so their presence or absence is
the decisive test.

Usage:

    python3 scripts/check-bundle-network.py path/to/app-release.aab
"""

import sys
import zipfile

# From ios/bittr/Helpers/EnvironmentConfig.swift, which both platforms read as
# the source of truth. Mirrored here rather than parsed out of production.env,
# because a check that reads its expectations from the same file the build read
# cannot catch the file being wrong.
MUST_BE_ABSENT = {
    "regtest node id": b"02bbc42b52f2bf041f37e6e556c7138cdc9cc2a77175ef6c1c3d5a3fbc6fa88148",
    "regtest node address": b"66.163.116.210:39735",
}

MUST_BE_PRESENT = {
    "mainnet node id": b"03e8d988a67ee7de983cd39d9d3d4d19771019305da4d2332be76c8b9fb1687776",
    "mainnet node address": b"86.104.228.24:9735",
}


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <bundle.aab>", file=sys.stderr)
        return 2

    bundle = argv[1]
    try:
        with zipfile.ZipFile(bundle) as archive:
            dex = b"".join(
                archive.read(name)
                for name in archive.namelist()
                if name.endswith(".dex")
            )
    except (OSError, zipfile.BadZipFile) as error:
        print(f"could not read {bundle}: {error}", file=sys.stderr)
        return 2

    if not dex:
        print(f"{bundle} contains no dex files — not a bundle?", file=sys.stderr)
        return 2

    failures = []
    for label, needle in MUST_BE_ABSENT.items():
        found = needle in dex
        print(f"  {label:22} absent:  {'no  <-- WRONG' if found else 'yes'}")
        if found:
            failures.append(f"{label} is compiled into the bundle")
    for label, needle in MUST_BE_PRESENT.items():
        found = needle in dex
        print(f"  {label:22} present: {'yes' if found else 'no  <-- WRONG'}")
        if not found:
            failures.append(f"{label} is missing from the bundle")

    if failures:
        print(file=sys.stderr)
        print(f"{bundle} is not a mainnet build:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        print(file=sys.stderr)
        print(
            "Build it with android/production.env sourced. See "
            "android/docs/play-release.md.",
            file=sys.stderr,
        )
        return 1

    print(f"\n{bundle} is on mainnet.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
