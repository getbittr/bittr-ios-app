#!/usr/bin/env python3
"""Check that the ldk-node we actually ship still has the stale-state protections.

    android/scripts/check-ldk-data-loss-protect.py
    android/scripts/check-ldk-data-loss-protect.py --aar <path to ldk-node-android-*.aar>

Exit codes: 0 every required marker is in every shipped ABI · 1 one is missing.

WHY THIS EXISTS

`wallet-security-properties.md` §5 carried one claim with nothing behind it: that
a user who restores their mnemonic on a second device while the first still holds
live channels is protected by Lightning's own `option_data_loss_protect` rather
than by anything we wrote. iOS accepts it in as many words
(`LightningStorage.swift:21-23`), and BIT-123 said explicitly that it was **to be
verified against ldk-node 0.7.0 rather than asserted from memory**.

This is that verification, as a command anyone can re-run, because the alternative
is a paragraph in a document whose evidence is that an engineer once read a
changelog. The property is not ours and we cannot test it on the JVM: it lives in
rust-lightning, behind UniFFI, inside a `.so`. What CAN be checked without a peer
and a funded channel is that the code paths are compiled into the binary we
ship — which is the difference between "upstream has this feature" and "the
artifact in our APK has this feature".

WHAT IT DOES *NOT* PROVE, AND THIS MATTERS

A string in a binary proves a branch was compiled, not that it executes correctly
against a real peer. The behavioural half is BIT-123's K7, which needs a funded
regtest channel and a peer willing to send a `channel_reestablish` — see
android/docs/wallet-node-device-tests.md for why CI cannot supply that. So this
check is a REGRESSION guard on a property we are relying on and did not write:
it goes red the day an ldk-node bump drops the behaviour, which is the failure
this document's §5 would otherwise discover from a user.

WHY THE ASSERTIONS ARE ON BEHAVIOUR AND NOT ON A VERSION NUMBER

Pinning "verified against 0.7.0" and asserting the pin would make every bump red
and teach the next reader to bump the pin, which is the same as having no check.
These markers are version-agnostic: they are red only if the behaviour actually
goes away.

NO DEPENDENCIES, DELIBERATELY

stdlib only, matching check-wallet-instrumented-results.py and ci-runs.py: these
run on a runner, on a Mac and in a container, with no pip step in front of them.
"""

import argparse
import glob
import os
import pathlib
import re
import sys
import zipfile

ANDROID_DIR = pathlib.Path(__file__).resolve().parents[1]
VERSIONS_TOML = ANDROID_DIR / "gradle" / "libs.versions.toml"

# Every marker below was read out of ldk-node-android 0.7.0's arm64-v8a
# libldk_node.so on 2026-09-13. The comments say what each one is evidence OF,
# because a list of magic strings with no reasoning is unmaintainable: the next
# reader facing a red has to decide whether the behaviour moved or merely the
# wording, and that judgement needs to know what the string was standing in for.
REQUIRED_MARKERS = (
    (
        b"We have fallen behind - we have received proof that if we broadcast "
        b"our counterparty is going to claim all our funds.",
        "The stale-state branch itself. rust-lightning reaches this when a peer's "
        "channel_reestablish proves our commitment is older than theirs. The "
        "sentence continues '...you should restart with an empty ChannelManager "
        "and no ChannelMonitors, reconnect to peer(s), ensure they've force-closed "
        "all of your previous channels' — i.e. LDK does NOT broadcast the stale "
        "commitment. That refusal is the whole protection; publishing a revoked "
        "commitment is what hands the channel balance to the counterparty.",
    ),
    (
        b"Peer attempted to reestablish channel with a very old local commitment "
        b"transaction",
        "The error this channel is closed with. Present separately from the "
        "sentence above because the two are emitted on different arms and a "
        "refactor could keep one without the other.",
    ),
    (
        b"your_last_per_commitment_secret",
        "The option_data_loss_protect TLV field the counterparty sends us, and the "
        "only thing that lets a node discover it is behind rather than sign over "
        "stale state. Its presence is what makes the branch above reachable.",
    ),
    (
        b"my_current_per_commitment_point",
        "The other half of the same TLV: what WE send, and what lets a peer "
        "recognise that a restored device is behind instead of accepting its "
        "re-establish. The second-device case depends on this direction, not the "
        "first.",
    ),
    (
        b"set_data_loss_protect_required",
        "In lightning_types::features::sealed. LDK sets option_data_loss_protect "
        "as a COMPULSORY init feature bit, not an optional one — so a peer that "
        "does not implement it cannot complete feature negotiation with us at "
        "all. That is stronger than 'we support it': it removes the case where we "
        "talk to a peer that will not send us the secret we need.",
    ),
)

# Asserting the ABSENCE of the optional setter is what turns the marker above
# from "the feature exists" into "the feature is required". Both setters exist in
# rust-lightning's source; only the one that is CALLED gets monomorphised into
# the binary. If a future version starts calling the optional form, the bit
# becomes advisory and a peer without data_loss_protect could connect — which is
# a real weakening and should be read, not skipped past.
FORBIDDEN_MARKERS = (
    (
        b"set_data_loss_protect_optional",
        "option_data_loss_protect has been downgraded from a required init "
        "feature bit to an optional one. A peer that does not implement it can "
        "now complete feature negotiation, so the guarantee that we will be told "
        "we are behind no longer holds for every peer we can connect to. This is "
        "not necessarily wrong — it is how most of the ecosystem advertises it — "
        "but it changes what wallet-security-properties.md §5 is entitled to say, "
        "so it stops the build rather than quietly narrowing the claim.",
    ),
)

# Reported, never asserted. These are facts about the binary that a reader of a
# red — or of a routine green — wants in front of them, and that we have no
# opinion about. bLIP-55 peer storage in particular is the mechanism by which a
# restored node COULD get its state back from the peer; it being optional is why
# §5 does not offer it as a recovery path.
OBSERVED_MARKERS = (
    (b"set_provide_storage_optional", "peer storage (bLIP-55) offered, not required"),
    (b"set_provide_storage_required", "peer storage REQUIRED of peers"),
    (b"set_static_remote_key_required", "option_static_remotekey required"),
)

CRATE_VERSION = re.compile(rb"lightning(?:-[a-z-]+)?-\d+\.\d+\.\d+")


def pinned_version():
    """`ldkNode = "x.y.z"` out of gradle/libs.versions.toml, or None.

    Read rather than hard-coded so this script and the build cannot disagree
    about which artifact is being checked — the disagreement would be silent and
    would make the check a statement about a version nobody ships.
    """
    try:
        text = VERSIONS_TOML.read_text(encoding="utf-8")
    except OSError:
        return None
    found = re.search(r'^\s*ldkNode\s*=\s*"([^"]+)"', text, re.MULTILINE)
    return found.group(1) if found else None


def find_aar(version):
    """The resolved ldk-node-android AAR in the Gradle module cache.

    Globbed rather than constructed: the directory between the version and the
    file name is a content hash, and Gradle has moved the `caches/modules-2`
    layout before. A miss here is reported as "run a build first", which is the
    actual remedy — this script deliberately does not download anything, so that
    what it checks is the artifact the build resolved and not one it fetched
    itself.
    """
    home = os.environ.get("GRADLE_USER_HOME") or os.path.join(
        os.path.expanduser("~"), ".gradle"
    )
    pattern = os.path.join(
        home,
        "caches",
        "modules-2",
        "files-2.1",
        "org.lightningdevkit",
        "ldk-node-android",
        version,
        "*",
        f"ldk-node-android-{version}.aar",
    )
    return sorted(glob.glob(pattern))


def check_library(name, blob, problems):
    """Assert every required marker, and no forbidden one, in one .so."""
    for marker, why in REQUIRED_MARKERS:
        if blob.find(marker) < 0:
            problems.append(
                f"{name}: missing {marker.decode()!r}.\n"
                f"  What it stands for: {why}\n"
                "  A bump that removes this has changed what happens when a "
                "restored device re-establishes a channel it is behind on. Do not "
                "update this list to match the new binary until "
                "wallet-security-properties.md §5 has been re-derived against it."
            )
    for marker, why in FORBIDDEN_MARKERS:
        if blob.find(marker) >= 0:
            problems.append(f"{name}: found {marker.decode()!r}.\n  {why}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--aar",
        type=pathlib.Path,
        help="The ldk-node-android AAR to read. Defaults to the one the Gradle "
             "module cache holds for the version pinned in libs.versions.toml.",
    )
    args = parser.parse_args(argv)

    version = pinned_version()
    if version is None and args.aar is None:
        print("::error::No `ldkNode` version in "
              f"{VERSIONS_TOML} and no --aar given, so there is nothing to check. "
              "This script asserts a property of the artifact we SHIP; guessing "
              "which artifact that is would make the result a statement about "
              "some other binary.")
        return 1

    if args.aar is not None:
        aar_path = args.aar
        if not aar_path.is_file():
            print(f"::error::No such AAR: {aar_path}")
            return 1
    else:
        candidates = find_aar(version)
        if not candidates:
            print(f"::error::ldk-node-android {version} is not in the Gradle module "
                  "cache, so there is no shipped binary to read. Run a build that "
                  "resolves :core:wallet-ldk first — this check deliberately does "
                  "not download the artifact itself, because then it would be "
                  "checking a binary the build never saw.")
            return 1
        aar_path = pathlib.Path(candidates[0])

    print(f"Reading {aar_path}")
    print(f"ldkNode pinned at {version or '(unknown — --aar given)'}\n")

    problems = []
    observed = {}
    crates = set()
    libraries = 0

    with zipfile.ZipFile(aar_path) as aar:
        names = [n for n in aar.namelist() if n.endswith("libldk_node.so")]
        if not names:
            print(f"::error::{aar_path} contains no libldk_node.so. Either the "
                  "packaging changed or this is not the ldk-node AAR.")
            return 1
        for name in sorted(names):
            blob = aar.read(name)
            libraries += 1
            print(f"  {name}  ({len(blob) // (1024 * 1024)} MiB)")
            check_library(name, blob, problems)
            for marker, label in OBSERVED_MARKERS:
                if blob.find(marker) >= 0:
                    observed[label] = True
            crates.update(m.group(0).decode() for m in CRATE_VERSION.finditer(blob))

    # Printed on green runs too, and as an annotation rather than only to the log:
    # on this PUBLIC repo the job log answers 403 and artifacts 401, so anything
    # not in an annotation is readable by a signed-in maintainer and by nobody
    # else. Same argument, and the same escaping, as
    # check-wallet-instrumented-results.py.
    lines = [
        f"ldk-node-android {version} — {libraries} ABI(s) checked, "
        f"{len(REQUIRED_MARKERS)} required marker(s) each.",
        "rust-lightning crates linked: " + ", ".join(sorted(crates)) or "(none found)",
    ]
    lines += [f"observed: {label}" for label in sorted(observed)]
    lines.append(
        "This proves the stale-state branch is COMPILED IN, not that it runs "
        "correctly against a real peer. The behavioural half is BIT-123 K7 and "
        "needs a funded regtest channel — android/docs/wallet-node-device-tests.md."
    )
    report = "\n".join(lines)
    print("\n" + report)
    encoded = report.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::notice title=ldk-node data_loss_protect::{encoded}")

    if problems:
        print()
        for problem in problems:
            encoded = problem.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
            print(f"::error::{encoded}")
            print(problem)
        print("check-ldk-data-loss-protect: FAILED.")
        return 1

    print("\ncheck-ldk-data-loss-protect: every required marker is in every "
          "shipped ABI.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
