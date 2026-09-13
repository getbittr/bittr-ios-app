#!/usr/bin/env python3
"""Turn the regtest network's facts into the six BITTR_LDK_* build inputs.

BIT-132 scope item 1. `LdkEnvironmentConfig.fromBuildConfig()` returns null
unless all six fields are supplied at build time and their committed defaults are
the empty string, so the `wallet-instrumented` job builds a wallet with no node
in it. `LdkEnvironmentConfigTest` already asserts the all-or-nothing rule; this is
the thing that satisfies it, and it is a Python file with a test rather than four
strings in a YAML `env:` block for three reasons.

WHY THE TRANSLATION IS CODE

  1. **10.0.2.2 is a translation, not a value.** android/regtest/up.sh publishes
     every service on the runner's loopback. 10.0.2.2 is what the *emulator*
     calls that host — the QEMU NAT's alias for the host's gateway address. Every
     URL the APK is compiled with has to be written from the device's point of
     view, and nothing in docker-compose.yml can do that because nothing in
     docker-compose.yml knows there is a device.

  2. **Three of the four are constants and one is not.** LND's node id is
     generated when `--noseedbackup` creates its wallet, so it differs per
     bring-up. A mixed set of fixed and discovered values wants one place that
     assembles it.

  3. **The mainnet guard needs somewhere to live.** BIT-132: *never mainnet keys,
     never production node access, never real funds.* The committed defaults being
     empty is what makes that true of a clone. What makes it true of a CI run is
     [refuse_unless_regtest] and [check_emitted] below — a network that is not
     regtest and a host that is not the emulator's own gateway are both refused,
     and both are refused at the point the values are made rather than by
     reviewing the YAML that consumes them.

WHAT IT DOES NOT DO

It does not open a channel, and it cannot: the counterparty is LND, the channel
is opened by the app (see android/regtest/README.md), and the app's node id does
not exist until the APK this script's output builds has been installed and
unlocked. The channel is android/scripts/regtest-k7-host-phase.sh's job.

NO DEPENDENCIES, DELIBERATELY

stdlib only, matching check-wallet-instrumented-results.py, check_flow_ids.py and
every other check in android/scripts: these run on a runner, on a Mac and in a
container with no pip step in front of them. That is also why the compose
cross-check in the test file is a regex over the raw text and not a YAML parse.

Usage:
  python3 android/scripts/regtest-ldk-env.py                 # KEY=VALUE lines
  python3 android/scripts/regtest-ldk-env.py --format gradle # -P arguments
  python3 android/scripts/regtest-ldk-env.py >> "$GITHUB_ENV"
"""

import argparse
import json
import pathlib
import re
import sys

ANDROID_DIR = pathlib.Path(__file__).resolve().parents[1]
FACTS_PATH = ANDROID_DIR / "regtest" / "regtest-facts.json"

# The emulator's alias for the host that published the containers' ports.
#
# Hard-coded, and deliberately not derivable from the facts file or from the
# environment. Every other value here is data; this one is the whole safety
# argument. A regtest APK whose chain source or peer address pointed anywhere
# else is the one build in this repository that could touch a real node, and the
# thing that keeps it from doing so should not be a string somebody can pass in.
#
# 10.0.2.2 is fixed by the Android emulator's user-mode network stack (10.0.2.1
# is the router, 10.0.2.2 the host, 10.0.2.3 the first DNS server). It is not a
# choice and it is not configurable, which is exactly why it is safe to pin.
EMULATOR_HOST = "10.0.2.2"

# The four fields LdkEnvironmentConfig.missingFields() requires. Named here in
# the BuildConfig's own terms so a reader comparing this file to
# LdkEnvironmentConfig.kt is comparing like with like.
REQUIRED_FIELDS = (
    "BITTR_LDK_CHAIN_SOURCE_URL",
    "BITTR_LDK_ELECTRUM_URL",
    "BITTR_LDK_LIGHTNING_NODE_ID",
    "BITTR_LDK_LIGHTNING_NODE_ADDRESS",
)

# The two that are legitimately blank, and why. Emitted as nothing at all rather
# than as empty strings, because in a GitHub `$GITHUB_ENV` file and in a Gradle
# property list an empty value and an absent one are the same thing — so writing
# them would only suggest they had been considered and left empty by accident.
#
#   BITTR_LDK_RAPID_GOSSIP_SYNC_URL  NodeConfigPlan.forEnvironment drops the RGS
#                                    source on regtest and signet outright,
#                                    because iOS has no RGS server there. A value
#                                    would be ignored.
#   BITTR_LDK_LSPS2_TOKEN            Empty on iOS (BitcoinManager.swift:172) and
#                                    therefore not required. LND does not speak
#                                    LSPS2 at all — see README.md for why that is
#                                    fine for this network.
DELIBERATELY_BLANK = (
    "BITTR_LDK_RAPID_GOSSIP_SYNC_URL",
    "BITTR_LDK_LSPS2_TOKEN",
)

# A compressed secp256k1 public key, lowercase. LND prints it this way and
# ldk-node parses it this way; a node id that is 64 or 130 characters is a
# different kind of key entirely and would fail inside the FFI with a message
# about hex rather than about configuration.
NODE_ID_RE = re.compile(r"\A0[23][0-9a-f]{64}\Z")


class FactsError(Exception):
    """The facts file cannot produce a safe, complete environment."""


def load_facts(path=FACTS_PATH):
    """Read regtest-facts.json, or say what to run to get one."""
    try:
        text = path.read_text()
    except FileNotFoundError:
        raise FactsError(
            f"{path} does not exist. The regtest network has not been brought up: "
            "run `bash android/regtest/up.sh` first."
        )
    try:
        facts = json.loads(text)
    except json.JSONDecodeError as error:
        raise FactsError(f"{path} is not valid JSON ({error}).")
    if not isinstance(facts, dict):
        raise FactsError(f"{path} must hold a JSON object, got {type(facts).__name__}.")
    return facts


def refuse_unless_regtest(facts):
    """The mainnet guard, and the reason this function has its own name.

    BIT-132's note is not advice: *never mainnet keys, never production node
    access, never real funds*. `up.sh` writes "regtest" unconditionally today, so
    this check cannot fail today — which is the case where a guard is worth the
    most and looks worth the least.

    What it is actually defending against is the plausible future edit: the same
    harness pointed at signet, or at a shared testnet node, by someone who
    changed one string in up.sh. Signet is not mainnet and it is still a network
    where the peer is somebody else's node. A build that reaches a node we do not
    own is outside what this file is allowed to produce, whatever the coins on it
    are worth.
    """
    network = facts.get("network")
    if network != "regtest":
        raise FactsError(
            f"network is {network!r}, and this script only builds regtest "
            "environments. BIT-132: never mainnet keys, never production node "
            "access, never real funds — a build pointed at any network whose peer "
            "we do not own is refused here rather than reviewed later."
        )


def port(facts, key):
    """One published port, as an int, or a message naming the key."""
    value = facts.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise FactsError(
            f"{key} must be an integer port, got {value!r}. "
            "android/regtest/up.sh writes it; a hand-edited facts file is the "
            "usual way this goes wrong."
        )
    if not 1 <= value <= 65535:
        raise FactsError(f"{key} is {value}, which is not a port number.")
    return value


def node_id(facts):
    """LND's identity pubkey, checked for shape rather than trusted."""
    value = facts.get("lightningNodeId")
    if not isinstance(value, str) or not NODE_ID_RE.match(value):
        raise FactsError(
            f"lightningNodeId is {value!r}, which is not a compressed "
            "secp256k1 public key (66 lowercase hex characters starting 02 or "
            "03). up.sh reads it from `lncli getinfo`; an empty one means LND "
            "answered before its wallet existed."
        )
    return value


def build_env(facts):
    """The four required BuildConfig inputs, from the device's point of view."""
    refuse_unless_regtest(facts)
    env = {
        # ldk-node's chain source. Esplora over HTTP, because
        # NodeConfigPlan.forEnvironment uses Electrum only on mainnet.
        "BITTR_LDK_CHAIN_SOURCE_URL":
            f"http://{EMULATOR_HOST}:{port(facts, 'esploraPort')}",
        # BDK's. A different protocol on a different port, which is why
        # LdkEnvironment.electrumUrl is its own field and not a reuse of the one
        # above. `tcp://` is the scheme bdk's ElectrumClient expects.
        "BITTR_LDK_ELECTRUM_URL":
            f"tcp://{EMULATOR_HOST}:{port(facts, 'electrumPort')}",
        "BITTR_LDK_LIGHTNING_NODE_ID": node_id(facts),
        # No scheme. ldk-node takes a bare host:port for a peer address, and a
        # `tcp://` prefix here fails inside the FFI rather than at configuration
        # time.
        "BITTR_LDK_LIGHTNING_NODE_ADDRESS":
            f"{EMULATOR_HOST}:{port(facts, 'lightningPort')}",
    }
    check_emitted(env)
    return env


def check_emitted(env):
    """Assert the values this script is about to print are the ones it promised.

    A post-condition rather than an input check, and it exists because of how
    this file is most likely to be broken. Nobody is going to delete
    EMULATOR_HOST; somebody is quite likely to make it a parameter — an
    `--host` flag for a runner where the emulator is on another machine, or a
    facts-file key for a Docker-in-Docker layout. Either change is reasonable and
    either one silently widens what a regtest APK may be compiled to reach.

    So the rule is restated where it can be measured: every value emitted names
    the emulator's own gateway, and nothing else. If a future edit needs a
    different host, it has to come here and say so, and the test file will ask it
    to explain itself.
    """
    missing = [field for field in REQUIRED_FIELDS if not env.get(field)]
    if missing:
        raise FactsError(
            "refusing to emit a partially configured environment; missing "
            + ", ".join(missing)
            + ". LdkEnvironmentConfig.missingFields() would return non-empty and "
            "fromBuildConfig() would return null, which composes SeedWalletService "
            "— a build with no node in it, which is the state BIT-132 exists to end."
        )
    for field, value in sorted(env.items()):
        if field == "BITTR_LDK_LIGHTNING_NODE_ID":
            continue
        host = value.split("://", 1)[-1].split(":", 1)[0]
        if host != EMULATOR_HOST:
            raise FactsError(
                f"{field} is {value!r}, whose host is {host!r} rather than "
                f"{EMULATOR_HOST}. A regtest APK may only be compiled to reach "
                "the emulator's own host. See check_emitted()."
            )


def render(env, fmt):
    """The same four values in whichever shape the caller consumes."""
    if fmt == "env":
        # The $GITHUB_ENV shape, and also `export $(... | xargs)`-able. One
        # KEY=VALUE per line, no quoting: none of these four values can contain a
        # space, and app/build.gradle.kts refuses any that contains a quote or a
        # backslash at configuration time.
        return "\n".join(f"{key}={value}" for key, value in sorted(env.items()))
    if fmt == "gradle":
        # One line of -P arguments, for pasting after `./gradlew`. The property
        # names are app/build.gradle.kts's, which are NOT the environment
        # variable names lowercased — the mapping is explicit there and copied
        # here rather than derived, so a rename on either side is a visible diff.
        properties = {
            "BITTR_LDK_CHAIN_SOURCE_URL": "bittr.ldk.chainSourceUrl",
            "BITTR_LDK_ELECTRUM_URL": "bittr.ldk.electrumUrl",
            "BITTR_LDK_LIGHTNING_NODE_ID": "bittr.ldk.lightningNodeId",
            "BITTR_LDK_LIGHTNING_NODE_ADDRESS": "bittr.ldk.lightningNodeAddress",
        }
        return " ".join(
            f"-P{properties[key]}={env[key]}" for key in sorted(env)
        )
    raise FactsError(f"unknown format {fmt!r}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--facts",
        type=pathlib.Path,
        default=FACTS_PATH,
        help="the file android/regtest/up.sh wrote (default: %(default)s)",
    )
    parser.add_argument(
        "--format",
        choices=("env", "gradle"),
        default="env",
        help="KEY=VALUE lines for $GITHUB_ENV, or -P arguments for ./gradlew",
    )
    args = parser.parse_args(argv)

    try:
        env = build_env(load_facts(args.facts))
    except FactsError as error:
        # ::error:: so it lands in the check-run annotation list, which on this
        # public repo is the only part of a run readable without a token — see
        # the header of check-wallet-instrumented-results.py.
        print(f"::error::{error}", file=sys.stderr)
        return 1

    print(render(env, args.format))
    # To stderr, so `>> "$GITHUB_ENV"` stays clean. The two blank fields are the
    # most likely thing for a reader of a green run to think was forgotten.
    print(
        "Not emitted, deliberately: " + ", ".join(DELIBERATELY_BLANK)
        + " (see DELIBERATELY_BLANK in this file).",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
