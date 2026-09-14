#!/usr/bin/env bash
#
# K8's freshness half — move the chain while the device is dozing, so the wake
# has something to catch up to (BIT-132).
#
# Invoked by android/scripts/ci-wallet-regtest.sh AFTER
# k7-interrupted-payment.sh, with an emulator booted and android/regtest/ up.
# Runnable by hand:
#
#   bash android/regtest/up.sh
#   eval "$(python3 android/scripts/regtest-ldk-env.py | sed 's/^/export /')"
#   bash android/scripts/k7-interrupted-payment.sh
#   bash android/scripts/k8-doze-soak.sh
#
# WHY THIS IS ONE INSTRUMENTED RUN AND K7 IS FOUR
#
# Opposite constraints, and it is worth stating because the two scripts sit next
# to each other and look like they should have the same shape.
#
# K7 has to observe its own restart, so its phases are separate `am instrument`
# runs with the process death between them. K8's freshness half needs the node
# ALIVE for the whole idle window — and the framework tears the instrumented
# process down when a method returns, which is exactly the mechanism K7 uses as
# its kill. Split into phases, there would be no node in the window at all and
# the test would measure a dead process dozing.
#
# So the device blocks inside one method for the length of the soak, and this
# script does its work WHILE that method is blocked.
#
# THE TWO HAND-OFF DIRECTIONS, AND WHY THEY ARE DIFFERENT MECHANISMS
#
#   device -> host   logcat.  `UiAutomation.executeShellCommand` hands its string
#                    to Runtime.exec, which splits on whitespace and execs the
#                    binary directly — there is no shell, so a device-side
#                    `echo … > file` would pass `>` to echo as a literal argument
#                    and the file would never appear. Log.i needs no file.
#
#   host -> device   a file under /data/local/tmp, written with `adb shell`,
#                    which DOES have a shell on this side. Read on the device
#                    with a plain `cat`. The same mechanism K7's hand-off uses.
#
# WHY IT DEPENDS ON K7 HAVING RUN
#
# The channel. android/docs/wallet-node-device-tests.md §4 settled this: a second
# funding and a second channel open for K8's own use would cost two more
# mined-and-waited phases for a channel identical to the one K7 already left, on
# a job with a 90-minute ceiling. The price is that a red K7 phase 2 makes this
# unrunnable rather than merely unreadable, and the gate then reports it as "did
# not run at all" — which is the accurate verdict.
#
# EXIT CODES
#
#   0  the soak ran and the test passed
#   1  the test failed — that may be a real K8 finding; read the gate's verdict
#   2  the harness could not set the experiment up (no device, no network, the
#      device never reached the idle window). NOT a claim about the wallet.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
REGTEST_DIR="$REPO_ROOT/android/regtest"

# The INSTALLED package, which is not the namespace: applicationId is
# com.bittr.android and the debug build type adds `.regtest`. Pinned against
# build.gradle.kts by test_k8_doze_soak.sh, for the reason
# test_k7_host_phase.sh gives — ci-wallet-instrumented.sh's own host phase
# shipped with exactly this bug.
APP_PACKAGE="${APP_ID:-com.bittr.android.regtest}"

TEST_CLASS="com.bittr.android.K8ChannelFreshnessTest"
TEST_METHOD="theChannelSurvivesAForcedIdleWindowAndTheNodeCatchesUp"

# Duplicated in K8ChannelFreshnessTest and pinned against it.
HANDOFF_PATH="/data/local/tmp/k8-chain-state"

# The logcat tag the device announces under — Doze.TAG.
LOG_TAG="K8_DOZE_SOAK"

# What the device logs once it is inside the idle window, and what this script
# writes back once it has mined. Both pinned against the test.
MARKER_IDLE="state=IDLE"
MARKER_MINED="state=MINED"

# What the host pays into the node's on-chain wallet during the window, in BTC.
# Small on purpose: the assertion is that the balance MOVED, not that it reached
# a figure, and a large send would compete with the channel reserve K7 left.
SOAK_FUNDING_BTC=0.001

# Blocks mined during the window, after the send. Six rather than one for the
# reason K7 mines six: electrs has to index them before the device's node can see
# them at all, and spare blocks cost milliseconds on regtest.
SOAK_BLOCKS=6

# How long to wait for the device to announce that it is inside the window.
#
# Derived from the test's own timeouts rather than picked: before it forces idle
# it has to install, start a node, wait up to CHANNEL_TIMEOUT_MS (240s) for K7's
# channel to come back ready and up to PEER_TIMEOUT_MS (180s) for the peer, and
# Gradle's own install-and-launch is a minute or two in front of all of it. That
# is ~500s of legitimate waiting, so a tighter number here would kill a slow
# run at the moment it was about to work — and report it as a harness failure.
#
# It is rarely the thing that fires anyway: the wait below also breaks the
# moment the Gradle run exits, so a test that fails one of its own timeouts is
# reported by the test rather than by this clock.
IDLE_WAIT_SECONDS=900

# Where the run's JUnit XML is preserved. NOT .../androidTest-results/connected,
# which every Gradle run overwrites — and which the gate also reads by default,
# so a snapshot placed inside it would be counted twice.
RESULTS_DIR="$REPO_ROOT/android/app/build/outputs/androidTest-results/k8/freshness"

compose() { docker compose --project-directory "$REGTEST_DIR" "$@"; }
btc() {
  compose exec -T bitcoind \
    bitcoin-cli -regtest -rpcuser=bittr -rpcpassword=bittr "$@"
}

harness_fail() {
  echo "::error title=K8 harness::$*"
  echo "This is a SETUP failure, not a K8 result. Nothing below it says anything"\
    " about whether a Lightning node survives Doze."
  exit 2
}

# --- Preflight ----------------------------------------------------------------

adb devices > /dev/null 2>&1 || harness_fail "adb is not available."
[ -n "$(adb devices | sed -n '2p')" ] || harness_fail "No device is attached to adb."

for name in BITTR_LDK_CHAIN_SOURCE_URL BITTR_LDK_LIGHTNING_NODE_ID; do
  eval "value=\${$name:-}"
  [ -n "$value" ] || harness_fail \
    "$name is unset, so the APK under test has no network and no peer. Run android/scripts/regtest-ldk-env.py after android/regtest/up.sh."
done

command -v docker > /dev/null 2>&1 || harness_fail "docker is not on PATH; this script drives bitcoind directly."
compose ps --status running --services 2> /dev/null | grep -q '^bitcoind$' \
  || harness_fail "The regtest bitcoind container is not running. Without it nothing can mine while the device is idle, and a node that 'caught up' to a chain that never moved is a pass that measured nothing."

mkdir -p "$RESULTS_DIR"

# A stale hand-off from a previous dispatch would let the device see MINED
# before this run has mined anything, and its catch-up assertion would then be
# measuring K7's blocks rather than this window's.
adb shell rm -f "$HANDOFF_PATH" > /dev/null 2>&1 || true

# Cleared so the marker this script waits for cannot be a previous run's. The
# device's announcement carries no run id — logcat is a shared buffer and this
# is the cheap way to make it this run's.
adb logcat -c > /dev/null 2>&1 || true

echo "Target package: $APP_PACKAGE"
echo "Chain source:   ${BITTR_LDK_CHAIN_SOURCE_URL}"
echo "Peer:           ${BITTR_LDK_LIGHTNING_NODE_ID}"

# --- The device's run, in the background --------------------------------------
#
# Backgrounded because it BLOCKS for the length of the soak and this script's
# work happens during that block. Same shape as K7's watcher, inverted: there the
# host watched and the device blocked on a file; here the host watches logcat and
# then writes the file.
#
# `leaveApksInstalledAfterRun` for the reason K7 passes it on every phase: AGP
# uninstalls both APKs when connectedAndroidTest finishes and an uninstall takes
# the wallet's data directory — seed, PIN verifier, ldk-node's state and the
# channel K7 opened — with it. Nothing runs after this today; it is here so that
# the next thing added to this suite does not have to rediscover it.
connected="$REPO_ROOT/android/app/build/outputs/androidTest-results/connected"
rm -rf "$connected"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

gradle_log=$(mktemp)
(
  cd "$REPO_ROOT/android" && ./gradlew :app:connectedDebugAndroidTest --no-daemon \
    -Pandroid.injected.androidTest.leaveApksInstalledAfterRun=true \
    -Pandroid.testInstrumentationRunnerArguments.class="$TEST_CLASS#$TEST_METHOD" \
    > "$gradle_log" 2>&1
) &
gradle_pid=$!

cleanup() {
  # A Gradle run left behind by a harness_fail is not merely untidy: it holds
  # the emulator and the build directory while ci-wallet-regtest.sh moves on to
  # the gate, which would then read results a still-running invocation is
  # rewriting. Killed first, so the device cleanup below happens with nothing
  # driving the device.
  if [ -n "${gradle_pid:-}" ] && kill -0 "$gradle_pid" 2> /dev/null; then
    kill "$gradle_pid" 2> /dev/null || true
    wait "$gradle_pid" 2> /dev/null || true
  fi
  # The device must not be left dozing with its battery unplugged if this script
  # dies mid-window. The test's own @After does it too; this is the half that
  # covers the case where the test never got to run.
  adb shell dumpsys deviceidle unforce > /dev/null 2>&1 || true
  adb shell dumpsys battery reset > /dev/null 2>&1 || true
}
trap cleanup EXIT

# --- Wait for the device to say it is inside the window ------------------------

echo "--- Waiting for the device to enter its forced idle window (up to ${IDLE_WAIT_SECONDS}s)"
idle_line=""
deadline=$(( $(date +%s) + IDLE_WAIT_SECONDS ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  # -d drains and exits rather than following, so this is a poll rather than a
  # second background process to reap.
  idle_line=$(adb logcat -d -s "$LOG_TAG:I" 2> /dev/null | grep -F "$MARKER_IDLE" | tail -1 || true)
  [ -n "$idle_line" ] && break
  # A Gradle run that has already exited will never announce anything.
  if ! kill -0 "$gradle_pid" 2> /dev/null; then
    break
  fi
  sleep 5
done

if [ -z "$idle_line" ]; then
  wait "$gradle_pid" 2> /dev/null || true
  tail -40 "$gradle_log" || true
  harness_fail "The device never announced '$MARKER_IDLE' under the $LOG_TAG tag within ${IDLE_WAIT_SECONDS}s. It did not reach its idle window, so nothing was mined during one. The usual cause is the test failing before it got there — K7's channel not coming back ready is the first thing to check in the report above."
fi

echo "--- Device is idle: $idle_line"

# The address is the device's, and it has to be: deriving it on the host needs
# ldk-node 0.7.0's exact derivation path, which is not recoverable from the
# shipped .so. A guess funds an address nothing is watching, the balance never
# moves, and the run reports a catch-up failure that is really a derivation
# mistake. K7 phase 1 pays for that finding already.
funding_address=$(echo "$idle_line" | tr ' ' '\n' | sed -n 's/^address=//p' | tail -1)
[ -n "$funding_address" ] || harness_fail \
  "The device announced its idle window and printed no address= token: '$idle_line'. The test and this script disagree about the evidence format; test_k8_doze_soak.sh pins them."

# --- Move the chain, while it cannot see us ------------------------------------

echo "--- Sending $SOAK_FUNDING_BTC BTC to $funding_address and mining $SOAK_BLOCKS blocks"
btc createwallet bittr > /dev/null 2>&1 || btc loadwallet bittr > /dev/null 2>&1 || true
mining_address=$(btc -rpcwallet=bittr getnewaddress) \
  || harness_fail "bitcoind has no usable wallet to mine to."
btc -rpcwallet=bittr sendtoaddress "$funding_address" "$SOAK_FUNDING_BTC" > /dev/null \
  || harness_fail "bitcoind would not send to '$funding_address'. If it calls the address invalid, the device is on a different network than this chain — which RegtestEnvironmentTest asserts against and would have caught."
btc generatetoaddress "$SOAK_BLOCKS" "$mining_address" > /dev/null \
  || harness_fail "bitcoind would not mine. The device is idle with nothing to catch up to."

height=$(btc getblockcount 2> /dev/null || echo "")
echo "--- Chain is now at height ${height:-<unknown>} and the device has not seen any of it"

# The device polls this file from inside the window and asserts on its contents.
# The state word is what it matches on; the rest is for a reader of a red run.
adb shell "echo '$MARKER_MINED height=$height blocks=$SOAK_BLOCKS sent=$SOAK_FUNDING_BTC address=$funding_address' > $HANDOFF_PATH" \
  > /dev/null 2>&1 \
  || harness_fail "Could not write $HANDOFF_PATH. The device will wait out its window and fail for want of a hand-off, having dozed for nothing."

# --- Wait the soak out ---------------------------------------------------------
#
# No mining from here on. The device holds the window to its end after the
# hand-off arrives, and the whole point of that remainder is that ldk-node's
# 30-second sync intervals fall due inside it and are missed. Mining more would
# not add to that and would extend what the node has to reconcile on waking,
# which makes a slow resume look like a failed one.
echo "--- Waiting for the device's soak and its assertions to finish"
gradle_outcome=0
wait "$gradle_pid" || gradle_outcome=$?
cat "$gradle_log"

# Preserved whether it passed or failed. A failed run's XML is the only place its
# assertion message exists, and the gate is what turns it into an annotation.
if [ -d "$connected" ]; then
  cp -R "$connected/." "$RESULTS_DIR/" 2> /dev/null || true
fi

if [ ! -d "$RESULTS_DIR" ] || [ -z "$(find "$RESULTS_DIR" -name 'TEST-*.xml' -print -quit)" ]; then
  echo "::warning title=K8::No TEST-*.xml was produced. Gradle failed before any test"\
    " ran, or the filter matched nothing — a renamed method is the usual cause, and"\
    " check-wallet-regtest-results.py will report it as 'did not run at all' rather"\
    " than as a pass."
fi

echo "--- K8 freshness summary"
echo "  package        $APP_PACKAGE"
echo "  funded         $funding_address with $SOAK_FUNDING_BTC BTC"
echo "  mined          $SOAK_BLOCKS blocks, to height ${height:-<unknown>}"
echo "  hand-off       $HANDOFF_PATH"
echo "  results        $RESULTS_DIR"

if [ "$gradle_outcome" != 0 ]; then
  echo "::error::K8's freshness half FAILED. The device was held in a forced deep-idle"\
    " window while the host mined ${SOAK_BLOCKS} blocks it could not see. Read the"\
    " assertion text in the gate's annotation: 'the node did not catch up' is a"\
    " finding about Doze and the foreground service, and 'K7's channel was not"\
    " usable before the window' is not a K8 result at all."
  exit 1
fi

echo "K8 freshness: the channel survived a forced idle window and the node caught the chain up."
