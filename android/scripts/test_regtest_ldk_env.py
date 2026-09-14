#!/usr/bin/env python3
"""Cases for regtest-ldk-env.py, the thing that decides what the K7/K8 APK reaches.

WHY THIS SUITE EXISTS

The script under test has exactly one green path and it will be taken every
night, so its only runs will be successful ones — which is the same argument
test_check_ldk_data_loss_protect.py makes about a checker whose markers are all
currently present. A green run of a broken translator is indistinguishable from a
green run of a working one, and the two ways this particular translator can be
broken are both silent:

  * a wrong port produces a wallet that starts, syncs nothing, and reports zero
    balance — which looks like a regtest chain with no coins in it;
  * a wrong HOST produces a build that reaches somewhere it should not, which is
    the one failure in this repository that can spend real money.

So the mainnet guard and the host post-condition get negative controls, and the
ports get compared against docker-compose.yml rather than against a copy of
themselves.

THE COMPOSE CROSS-CHECK, AND WHY IT IS A REGEX

android/regtest/regtest-facts.json's port numbers are written by up.sh and are
duplicated from docker-compose.yml. Two files disagreeing about a port is the
cheapest bug here to write: the network comes up healthy, the APK compiles, the
node starts, and nothing works — with no error naming a port anywhere.

The comparison is a regex over the compose file's raw text because these scripts
are stdlib-only by rule (see regtest-ldk-env.py's header). PyYAML is not
available on a bare runner, and adding a pip step to make one assertion prettier
would make every check in android/scripts pay for it.

Run: python3 android/scripts/test_regtest_ldk_env.py
"""

import contextlib
import importlib.util
import io
import json
import pathlib
import re
import sys
import tempfile

SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent
ANDROID_DIR = SCRIPTS_DIR.parent
COMPOSE_PATH = ANDROID_DIR / "regtest" / "docker-compose.yml"


def load_module():
    """Import the hyphenated script under test.

    `regtest-ldk-env` is not a legal module name, so there is no `import` that
    reaches it. Same loader shape as test_check_wallet_instrumented_results.py.
    """
    path = SCRIPTS_DIR / "regtest-ldk-env.py"
    spec = importlib.util.spec_from_file_location("regtest_ldk_env", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


env_script = load_module()

GOOD_FACTS = {
    "network": "regtest",
    "lightningNodeId": "02" + "ab" * 32,
    "lightningPort": 9735,
    "esploraPort": 3002,
    "electrumPort": 60401,
    "bitcoindRpcPort": 18443,
    "lndRpcPort": 10009,
}

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print(f"  ok    {name}")
    else:
        print(f"  FAIL  {name}{(': ' + detail) if detail else ''}")
        FAILURES.append(name)


def expect_refusal(name, facts, needle):
    """build_env must refuse `facts`, and must say why in terms a reader can act on.

    The needle is checked as well as the refusal. A guard that raises the wrong
    message is a guard somebody will spend a night misdiagnosing, and in this
    file's case the message is the entire user interface: the script runs inside
    a nightly job whose log nobody reads until it is red.
    """
    try:
        env_script.build_env(facts)
    except env_script.FactsError as error:
        check(name, needle in str(error), f"message was {str(error)!r}")
    else:
        check(name, False, "build_env accepted it")


# --- The happy path, asserted value by value ----------------------------------
#
# Spelled out rather than compared to a dict built by the same expressions the
# script uses. A test that recomputes the answer agrees with any change,
# including a wrong one.

print("the four required fields, from the device's point of view")
env = env_script.build_env(dict(GOOD_FACTS))
check(
    "the chain source is Esplora over HTTP on the emulator's host",
    env["BITTR_LDK_CHAIN_SOURCE_URL"] == "http://10.0.2.2:3002",
    env["BITTR_LDK_CHAIN_SOURCE_URL"],
)
check(
    "the Electrum URL is a tcp:// scheme on its own port",
    env["BITTR_LDK_ELECTRUM_URL"] == "tcp://10.0.2.2:60401",
    env["BITTR_LDK_ELECTRUM_URL"],
)
check(
    "the peer address carries no scheme",
    env["BITTR_LDK_LIGHTNING_NODE_ADDRESS"] == "10.0.2.2:9735",
    env["BITTR_LDK_LIGHTNING_NODE_ADDRESS"],
)
check(
    "the node id is passed through unchanged",
    env["BITTR_LDK_LIGHTNING_NODE_ID"] == GOOD_FACTS["lightningNodeId"],
    env["BITTR_LDK_LIGHTNING_NODE_ID"],
)
check(
    "the chain source and the Electrum URL are different endpoints",
    # The collapse LdkEnvironment's own comment warns about: pointing BDK at the
    # Esplora URL. It compiles, it configures, and ElectrumClient then talks the
    # wrong protocol to the right machine.
    env["BITTR_LDK_CHAIN_SOURCE_URL"] != env["BITTR_LDK_ELECTRUM_URL"],
)
check(
    "exactly the four required fields are emitted",
    set(env) == set(env_script.REQUIRED_FIELDS),
    sorted(env),
)

# --- The mainnet guard, with the negative control it exists for ---------------

print("refuse_unless_regtest")
for network in ("bitcoin", "mainnet", "signet", "testnet", None, ""):
    facts = dict(GOOD_FACTS)
    if network is None:
        del facts["network"]
    else:
        facts["network"] = network
    expect_refusal(f"refuses network={network!r}", facts, "regtest")

# --- The host post-condition ---------------------------------------------------

print("check_emitted")
# Driven by handing check_emitted a hand-built environment rather than by mutating
# EMULATOR_HOST: the point is that the post-condition fires on the VALUES, so a
# future edit that sources the host from a flag or from the facts file is caught
# even though it never touches the constant.
try:
    env_script.check_emitted(
        {
            "BITTR_LDK_CHAIN_SOURCE_URL": "http://esplora.example.com:3002",
            "BITTR_LDK_ELECTRUM_URL": "tcp://10.0.2.2:60401",
            "BITTR_LDK_LIGHTNING_NODE_ID": GOOD_FACTS["lightningNodeId"],
            "BITTR_LDK_LIGHTNING_NODE_ADDRESS": "10.0.2.2:9735",
        }
    )
except env_script.FactsError as error:
    check(
        "a non-emulator host in any emitted URL is refused",
        "10.0.2.2" in str(error) and "esplora.example.com" in str(error),
        str(error),
    )
else:
    check("a non-emulator host in any emitted URL is refused", False, "accepted")

for field in env_script.REQUIRED_FIELDS:
    partial = dict(env)
    partial[field] = ""
    try:
        env_script.check_emitted(partial)
    except env_script.FactsError as error:
        check(
            f"a blank {field} is refused as partially configured",
            field in str(error) and "SeedWalletService" in str(error),
            str(error),
        )
    else:
        check(f"a blank {field} is refused as partially configured", False, "accepted")

check(
    "the node id is exempt from the host check rather than accidentally passing it",
    # It contains no host, so splitting it on "://" and ":" yields the whole key,
    # which is not 10.0.2.2 — i.e. without the explicit `continue` in
    # check_emitted the happy path above would fail. This asserts the exemption
    # is real and not a coincidence of the fixture's shape.
    env_script.NODE_ID_RE.match(GOOD_FACTS["lightningNodeId"]) is not None
    and ":" not in GOOD_FACTS["lightningNodeId"],
)

# --- Node id shape -------------------------------------------------------------

print("node_id")
for bad in (
    "",
    None,
    "04" + "ab" * 32,          # uncompressed prefix
    "02" + "AB" * 32,          # uppercase; LND prints lowercase
    "02" + "ab" * 31,          # one byte short
    "02" + "zz" * 32,          # not hex
    "0x02" + "ab" * 32,
):
    facts = dict(GOOD_FACTS)
    facts["lightningNodeId"] = bad
    expect_refusal(f"refuses lightningNodeId={bad!r}", facts, "secp256k1")

# --- Port shape ----------------------------------------------------------------

print("port")
for key in ("esploraPort", "electrumPort", "lightningPort"):
    for bad in (None, "3002", 0, 70000, True, 3.5):
        facts = dict(GOOD_FACTS)
        if bad is None:
            del facts[key]
        else:
            facts[key] = bad
        expect_refusal(f"refuses {key}={bad!r}", facts, key)

# --- The facts file itself -----------------------------------------------------

print("load_facts")
with tempfile.TemporaryDirectory() as tmp:
    missing = pathlib.Path(tmp) / "nope.json"
    try:
        env_script.load_facts(missing)
    except env_script.FactsError as error:
        check(
            "a missing facts file names the command that makes one",
            "up.sh" in str(error),
            str(error),
        )
    else:
        check("a missing facts file names the command that makes one", False, "read it")

    broken = pathlib.Path(tmp) / "broken.json"
    broken.write_text("{not json")
    try:
        env_script.load_facts(broken)
    except env_script.FactsError as error:
        check("invalid JSON is reported as invalid JSON", "JSON" in str(error))
    else:
        check("invalid JSON is reported as invalid JSON", False, "read it")

    listy = pathlib.Path(tmp) / "list.json"
    listy.write_text("[]")
    try:
        env_script.load_facts(listy)
    except env_script.FactsError as error:
        check("a JSON array is refused", "object" in str(error))
    else:
        check("a JSON array is refused", False, "read it")

# --- Rendering -----------------------------------------------------------------
#
# Both formats, because both are consumed: `env` by the nightly workflow writing
# $GITHUB_ENV, `gradle` by a human reproducing the build locally. The Gradle
# property names are NOT the environment names lowercased, so the mapping is a
# thing that can be wrong.

print("render")
rendered_env = env_script.render(env, "env")
check(
    "the env format is one KEY=VALUE per line with no quoting",
    sorted(rendered_env.splitlines())
    == sorted(f"{key}={value}" for key, value in env.items()),
    rendered_env,
)
rendered_gradle = env_script.render(env, "gradle")
check(
    "the gradle format uses app/build.gradle.kts's property names",
    all(
        name in rendered_gradle
        for name in (
            "-Pbittr.ldk.chainSourceUrl=http://10.0.2.2:3002",
            "-Pbittr.ldk.electrumUrl=tcp://10.0.2.2:60401",
            "-Pbittr.ldk.lightningNodeAddress=10.0.2.2:9735",
            f"-Pbittr.ldk.lightningNodeId={GOOD_FACTS['lightningNodeId']}",
        )
    ),
    rendered_gradle,
)
check(
    "the gradle format names no property the build file does not define",
    # The build file's four names, read out of it rather than restated. An
    # -P argument whose property nothing reads is silently ignored by Gradle:
    # the build succeeds and the APK has no node in it, which is the exact
    # failure mode BIT-132 is about.
    all(
        prop in (ANDROID_DIR / "app" / "build.gradle.kts").read_text()
        for prop in re.findall(r"-P([\w.]+)=", rendered_gradle)
    ),
    rendered_gradle,
)

# --- main(), including the exit code and where the output goes ------------------

print("main")
with tempfile.TemporaryDirectory() as tmp:
    good = pathlib.Path(tmp) / "facts.json"
    good.write_text(json.dumps(GOOD_FACTS))
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = env_script.main(["--facts", str(good)])
    check("a good facts file exits 0", code == 0, f"exit {code}")
    check(
        "stdout carries only the KEY=VALUE lines",
        # Load-bearing: the workflow redirects stdout into $GITHUB_ENV, and one
        # stray note on that stream becomes a malformed environment file — which
        # GitHub reports as a failure in the step AFTER the one that caused it.
        sorted(out.getvalue().strip().splitlines())
        == sorted(f"{key}={value}" for key, value in env.items()),
        repr(out.getvalue()),
    )
    check(
        "the deliberately-blank fields are explained on stderr",
        all(field in err.getvalue() for field in env_script.DELIBERATELY_BLANK),
        repr(err.getvalue()),
    )

    bad = pathlib.Path(tmp) / "mainnet.json"
    bad.write_text(json.dumps({**GOOD_FACTS, "network": "bitcoin"}))
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = env_script.main(["--facts", str(bad)])
    check("a mainnet facts file exits 1", code == 1, f"exit {code}")
    check(
        "the refusal is an ::error:: annotation and nothing lands on stdout",
        err.getvalue().startswith("::error::") and out.getvalue() == "",
        repr(err.getvalue()) + repr(out.getvalue()),
    )

# --- The compose cross-check ----------------------------------------------------

print("docker-compose.yml publishes the ports up.sh writes down")
compose_text = COMPOSE_PATH.read_text()
# Published ports in a compose `ports:` list, in either shape this file uses:
#   "127.0.0.1:3002:3002"   -> host port 3002
#   "9735:9735"             -> host port 9735
published = set()
for match in re.finditer(
    r'^\s*-\s*"(?:(?P<ip>[\d.]+):)?(?P<host>\d+):(?P<container>\d+)"\s*$',
    compose_text,
    re.MULTILINE,
):
    published.add(int(match.group("host")))
check(
    "the regex found the compose file's published ports at all",
    # Without this the two assertions below pass vacuously on a compose file
    # whose formatting changed — the same shape of mistake as a grep that found
    # nothing and reported clean.
    len(published) >= 4,
    sorted(published),
)
for key in ("esploraPort", "electrumPort", "lightningPort"):
    check(
        f"{key} ({GOOD_FACTS[key]}) is published by docker-compose.yml",
        GOOD_FACTS[key] in published,
        f"published: {sorted(published)}",
    )
check(
    "no service is published on an interface other than loopback",
    # The emulator forwards 10.0.2.2 to the host's LOOPBACK, so loopback-only
    # publishing is sufficient for the device and is what keeps an auto-unlocked
    # seedless LND off the runner's network. The tempting "just to be sure" edit
    # is to widen the Lightning port; this is what asks it not to.
    all(
        match.group("ip") == "127.0.0.1"
        for match in re.finditer(
            r'^\s*-\s*"(?:(?P<ip>[\d.]+):)?(?P<host>\d+):(?P<container>\d+)"\s*$',
            compose_text,
            re.MULTILINE,
        )
    ),
    compose_text,
)

print()
if FAILURES:
    print(f"{len(FAILURES)} failed:")
    for name in FAILURES:
        print(f"  - {name}")
    sys.exit(1)
print("all regtest-ldk-env.py cases passed")
