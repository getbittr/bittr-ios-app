#!/usr/bin/env bash
#
# K7 — kill the process mid-payment and see whether the wallet comes back knowing
# what happened to the money (BIT-132).
#
# Invoked by android/scripts/ci-wallet-regtest.sh, after the undirected regtest
# suite, with an emulator booted and android/regtest/ up. Runnable by hand:
#
#   bash android/regtest/up.sh
#   eval "$(python3 android/scripts/regtest-ldk-env.py | sed 's/^/export /')"
#   bash android/scripts/k7-interrupted-payment.sh
#
# WHY THE TEST CANNOT DO THIS ITSELF
#
# It cannot observe its own restart. `am kill` takes the instrumentation process
# with it — the lesson BackupExclusionTest learned from `bmgr restore`, where an
# assertion died exactly when there was finally something worth asserting. So K7
# is four instrumented runs against one emulator boot, and this file is what
# happens between them: funding, mining, holding an HTLC, and the kill.
#
# THE KILL WINDOW IS IN THE COUNTERPARTY, NOT IN OUR SEND PATH
#
# android/docs/wallet-node-device-tests.md §3 rejected a latch inside
# LdkNodeSurface.sendBolt11: a branch in the fund-handling path that exists only
# to be taken either ships — a way to wedge a real payment — or it does not, in
# which case the thing under test is not the thing that ships.
#
# LND's `addholdinvoice` withholds the preimage instead. The HTLC arrives at the
# peer, is accepted, and STAYS accepted until this script settles or cancels it.
# The window is as wide as we want, it is observable (`lookupinvoice` reports
# state ACCEPTED exactly while the HTLC is in flight), and it needs no test-only
# code anywhere near the money.
#
# WHAT THIS SCRIPT REFUSES TO DO
#
# Kill the process before LND reports ACCEPTED. That kill would land in the
# NARROW window — inside `send`, before anything is on the wire — where K7's
# claim is not under test and a pass means nothing. So the hand-off below is
# written only on ACCEPTED, phase 3 blocks on it, and a run that never gets there
# fails rather than proceeding to a cheaper version of the test.
#
# It also never mines while the HTLC is held. A block is what moves a CLTV
# expiry, and an HTLC that times out during the window resolves itself for a
# reason that has nothing to do with process death.
#
# EXIT CODES
#
#   0  every phase ran and passed
#   1  a phase failed — read the gate's verdict; this may be a real K7 finding
#   2  the harness could not set the experiment up (no device, no network, no
#      channel). NOT a claim about the wallet.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
REGTEST_DIR="$REPO_ROOT/android/regtest"

# The INSTALLED package, which is not the namespace: applicationId is
# com.bittr.android and the debug build type adds `.regtest`. Getting this wrong
# is silent and fails toward green — `am kill` on a package that does not exist
# exits 0 and kills nothing, and phase 4's pid assertion is then the only thing
# between that and a vacuous pass. test_k7_host_phase.sh pins the default against
# build.gradle.kts in the build job.
APP_PACKAGE="${APP_ID:-com.bittr.android.regtest}"

TEST_CLASS="com.bittr.android.K7InterruptedPaymentTest"

# Duplicated in K7InterruptedPaymentTest, and pinned against it by
# test_k7_host_phase.sh. /data/local/tmp rather than the app's own data
# directory: this hand-off goes host -> device, and writing into /data/data/
# would need `adb root`, which some images refuse. A hand-off that silently never
# arrives is the one failure that would let phase 3 return early and kill the
# process in the narrow window.
HANDOFF_PATH="/data/local/tmp/k7-htlc-state"

# 50,000 sats, matching K7InterruptedPaymentTest.PAYMENT_AMOUNT_MSAT. The channel
# is 1,000,000 sats and the test checks the two against each other before it
# sends, so a drift here is a legible red rather than a route-not-found.
PAYMENT_AMOUNT_SATS=50000

# What the host sends to the device's on-chain address, in BTC. The channel is
# 0.01 BTC and ldk-node reserves for anchor outputs out of the same wallet, so
# this is comfortably more than the channel rather than exactly it.
FUNDING_BTC=0.02

# Where each phase's JUnit XML is preserved. NOT under .../androidTest-results/
# connected, which every Gradle run overwrites — and which is also what the gate
# reads by default, so a snapshot placed inside it would be counted twice.
RESULTS_ROOT="$REPO_ROOT/android/app/build/outputs/androidTest-results/k7"

compose() { docker compose --project-directory "$REGTEST_DIR" "$@"; }
btc() {
  compose exec -T bitcoind \
    bitcoin-cli -regtest -rpcuser=bittr -rpcpassword=bittr "$@"
}
lnc() {
  compose exec -T lnd \
    lncli --network=regtest --rpcserver=localhost:10009 "$@"
}

harness_fail() {
  echo "::error title=K7 harness::$*"
  echo "This is a SETUP failure, not a K7 result. Nothing below it says anything"\
    " about whether an interrupted payment resolves to one outcome."
  exit 2
}

json_field() {
  # $1 = field, stdin = JSON. python3 rather than jq: every other check in
  # android/scripts is stdlib-only, and jq is not a runner requirement.
  FIELD="$1" python3 -c '
import json, os, sys
try:
    print(json.load(sys.stdin).get(os.environ["FIELD"], ""))
except Exception:
    print("")
'
}

# Pull one `key=value` out of the K7 evidence lines a phase printed into its
# JUnit XML. The evidence line is the only channel out of the device that
# survives into an artefact, and on this public repository the annotation built
# from it is the only one readable without a token.
evidence_value() {
  RESULTS="$1" KEY="$2" python3 -c '
import os, pathlib, sys, xml.etree.ElementTree as ET

key = os.environ["KEY"] + "="
found = ""
for path in sorted(pathlib.Path(os.environ["RESULTS"]).rglob("TEST-*.xml")):
    for out in ET.parse(path).getroot().iter("system-out"):
        for line in (out.text or "").splitlines():
            line = line.strip()
            if not line.startswith("K7_INTERRUPTED_PAYMENT"):
                continue
            for token in line.split():
                if token.startswith(key):
                    found = token[len(key):]
print(found)
'
}

# One phase: one `connectedDebugAndroidTest` filtered to one method, then its
# results moved somewhere the next phase will not overwrite.
#
# `leaveApksInstalledAfterRun` on every phase, not just the last. AGP uninstalls
# both APKs when connectedAndroidTest finishes, and an uninstall takes the
# wallet's data directory — seed, PIN verifier, ldk-node's state — with it. Phase
# 2 would then find no wallet, and the test asserts that rather than quietly
# creating a second one.
run_phase() {
  number="$1"
  method="$2"
  shift 2

  results_dir="$RESULTS_ROOT/phase$number"
  connected="$REPO_ROOT/android/app/build/outputs/androidTest-results/connected"
  rm -rf "$results_dir"
  mkdir -p "$results_dir"

  # Cleared BEFORE the run, not just copied after it. A phase that dies before
  # writing results would otherwise be snapshotted with the PREVIOUS phase's XML,
  # and the gate would see phase 2's pass filed under phase 3 — a green verdict
  # assembled out of a run that did not happen. Stale results outliving a run is
  # the failure this repository has already paid for once.
  rm -rf "$connected"

  echo "--- K7 phase $number: $method"
  outcome=0
  (
    cd "$REPO_ROOT/android" && ./gradlew :app:connectedDebugAndroidTest --no-daemon \
      -Pandroid.injected.androidTest.leaveApksInstalledAfterRun=true \
      -Pandroid.testInstrumentationRunnerArguments.class="$TEST_CLASS#$method" \
      "$@"
  ) || outcome=$?

  # Preserved whether the phase passed or failed. A failed phase's XML is the
  # only place its assertion message exists, and the gate is what turns it into
  # an annotation.
  if [ -d "$connected" ]; then
    cp -R "$connected/." "$results_dir/" 2> /dev/null || true
  fi

  if [ ! -d "$results_dir" ] || [ -z "$(find "$results_dir" -name 'TEST-*.xml' -print -quit)" ]; then
    echo "::warning title=K7 phase $number::No TEST-*.xml was produced. Gradle"\
      " failed before any test ran, or the filter matched nothing — a renamed"\
      " method is the usual cause, and check-wallet-regtest-results.py will report"\
      " it as 'did not run at all' rather than as a pass."
  fi

  return "$outcome"
}

device_pid() {
  adb shell pidof "$APP_PACKAGE" 2> /dev/null | tr -d '\r' | awk '{print $1}'
}

# --- Preflight ----------------------------------------------------------------

adb devices > /dev/null 2>&1 || harness_fail "adb is not available."
[ -n "$(adb devices | sed -n '2p')" ] || harness_fail "No device is attached to adb."

for name in BITTR_LDK_LIGHTNING_NODE_ID BITTR_LDK_LIGHTNING_NODE_ADDRESS; do
  eval "value=\${$name:-}"
  [ -n "$value" ] || harness_fail \
    "$name is unset, so the APK under test has no peer to open a channel to. Run android/scripts/regtest-ldk-env.py after android/regtest/up.sh."
done

command -v docker > /dev/null 2>&1 || harness_fail "docker is not on PATH; this phase drives bitcoind and LND directly."
compose ps --status running --services 2> /dev/null | grep -q '^lnd$' \
  || harness_fail "The regtest LND container is not running. K7's kill window IS the counterparty; without it there is no window."

mkdir -p "$RESULTS_ROOT"

echo "Target package: $APP_PACKAGE"
echo "Peer: ${BITTR_LDK_LIGHTNING_NODE_ID} at ${BITTR_LDK_LIGHTNING_NODE_ADDRESS}"

# A stale hand-off from a previous run would let phase 3 return the instant it
# started, killing the process in the narrow window with nothing on the wire.
# Removed before phase 1 rather than before phase 3, so that a crash between them
# cannot leave one behind.
adb shell rm -f "$HANDOFF_PATH" > /dev/null 2>&1 || true

# --- Phase 1: ask the device where to send the coins ---------------------------
#
# The host cannot derive this address. It would need ldk-node 0.7.0's exact
# derivation, which is not recoverable from the shipped .so, and a guess funds an
# address nothing is watching — failing one phase later at openChannel with an
# insufficient-funds error that says nothing about derivation.
run_phase 1 phase1RevealTheAddressTheHostMustFund || {
  echo "::error::K7 phase 1 failed: the node did not come up or would not reveal an on-chain address."
  exit 1
}

funding_address=$(evidence_value "$RESULTS_ROOT/phase1" fundingAddress)
[ -n "$funding_address" ] || harness_fail \
  "Phase 1 passed and printed no fundingAddress evidence line. The test and this script disagree about the evidence format; test_k7_host_phase.sh pins them."

echo "--- Funding the device's node wallet: $FUNDING_BTC BTC to $funding_address"
btc createwallet bittr > /dev/null 2>&1 || btc loadwallet bittr > /dev/null 2>&1 || true
mining_address=$(btc -rpcwallet=bittr getnewaddress) \
  || harness_fail "bitcoind has no usable wallet to mine to."
btc -rpcwallet=bittr sendtoaddress "$funding_address" "$FUNDING_BTC" > /dev/null \
  || harness_fail "bitcoind would not send to '$funding_address'. If it calls the address invalid, the device is on a different network than this chain — which RegtestEnvironmentTest asserts against and would have caught."
# Three, not one. ldk-node treats an on-chain output as spendable at one
# confirmation, and electrs has to index the block before the node can see it at
# all; a couple of spare blocks costs milliseconds on regtest and removes a race
# that would present as "the node never saw its coins".
btc generatetoaddress 3 "$mining_address" > /dev/null

# --- Phase 2: open the channel -------------------------------------------------
run_phase 2 phase2OpenAChannelToTheRegtestPeer || {
  echo "::error::K7 phase 2 failed: the node never saw its coins, or the channel open was refused."
  exit 1
}

echo "--- Mining the channel funding transaction"
# LND is configured with `--bitcoin.defaultchanconfs=1`, so six is generous and
# is about electrs and the device's own sync rather than about LND's policy.
btc generatetoaddress 6 "$mining_address" > /dev/null

echo "--- Waiting for LND to report the channel active"
deadline=$(( $(date +%s) + 240 ))
while :; do
  # Counted, not just "listchannels is non-empty", and counted for OUR node id.
  # LND is a throwaway container but it is not necessarily channel-free: a failed
  # earlier attempt can leave one behind (`--maxpendingchannels=5` exists for
  # exactly that), and waiting on somebody else's channel would let phase 3 start
  # against a route that does not reach this device.
  active=$(lnc listchannels 2> /dev/null | python3 -c '
import json, sys
try:
    channels = json.load(sys.stdin).get("channels", [])
except Exception:
    channels = []
# The peer id in BITTR_LDK_* is LNDs own — the device dials it — so the channel
# this run cares about is the one LND does NOT report as itself: every entry here
# is already a channel to LND, and remote_pubkey is the devices node id, which
# nothing on the host knows until the channel exists. So the count is of active
# channels, and the guard against a stale one is that up.sh brought this LND up
# fresh for this run.
print(sum(1 for c in channels if c.get("active")))
')
  [ "${active:-0}" -gt 0 ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    compose logs --tail=80 lnd || true
    lnc pendingchannels || true
    harness_fail "LND never reported an active channel within 240s. Phase 3 has nothing to pay over."
  fi
  # Mine while waiting, but only here: a block during the HELD HTLC later would
  # move a CLTV expiry and resolve the payment for a reason that is not process
  # death.
  btc generatetoaddress 1 "$mining_address" > /dev/null 2>&1 || true
  sleep 4
done
echo "LND reports the channel active."

# --- The hold invoice ----------------------------------------------------------
#
# The host chooses the preimage, so the host is the only party that can settle.
# That is what makes the window ours: LND cannot release the payment early even
# if it wanted to, and nothing on the device can either.
read -r preimage payment_hash <<< "$(python3 -c '
import hashlib, os
p = os.urandom(32)
print(p.hex(), hashlib.sha256(p).hexdigest())
')"

invoice=$(lnc addholdinvoice --memo="bittr K7 interrupted payment" \
  --amt="$PAYMENT_AMOUNT_SATS" "$payment_hash" 2> /dev/null | json_field payment_request)
[ -n "$invoice" ] || harness_fail \
  "LND would not create a hold invoice for hash $payment_hash. invoicesrpc is compiled into every released LND, so an error here is about this container rather than about the build."

echo "--- Hold invoice created. hash=$payment_hash amount=${PAYMENT_AMOUNT_SATS}sat"

# --- Phase 3: pay it, and watch for the HTLC to stick --------------------------
#
# The watcher runs alongside the phase because the phase BLOCKS until the
# hand-off appears, and the hand-off is what this loop writes. It also captures
# the pid while the process is provably holding the in-flight payment — the one
# moment at which that number means anything, and the one phase 4 asserts it is
# not running as.
watch_state="$(mktemp -d)"
trap 'rm -rf "$watch_state"' EXIT

(
  watch_deadline=$(( $(date +%s) + 200 ))
  while [ "$(date +%s)" -lt "$watch_deadline" ]; do
    state=$(lnc lookupinvoice "$payment_hash" 2> /dev/null | json_field state)
    if [ "$state" = "ACCEPTED" ]; then
      device_pid > "$watch_state/pid"
      # The state, in LND's own word for it, so the device can assert on the
      # thing that was actually true rather than on the file's existence.
      adb shell "echo 'invoice=$payment_hash state=ACCEPTED' > $HANDOFF_PATH" \
        > /dev/null 2>&1 || true
      echo "$state" > "$watch_state/state"
      exit 0
    fi
    sleep 2
  done
  echo "TIMEOUT" > "$watch_state/state"
) &
watcher=$!

phase3_outcome=0
run_phase 3 phase3PayTheHoldInvoiceAndLeaveItInFlight \
  -Pandroid.testInstrumentationRunnerArguments.k7Invoice="$invoice" \
  -Pandroid.testInstrumentationRunnerArguments.k7PaymentHash="$payment_hash" \
  || phase3_outcome=$?

wait "$watcher" 2> /dev/null || true
htlc_state=$(cat "$watch_state/state" 2> /dev/null || echo "NONE")
killed_pid=$(cat "$watch_state/pid" 2> /dev/null || echo "")

echo "--- LND's view of the invoice at the end of phase 3: $htlc_state"
echo "--- Process holding the in-flight payment: pid ${killed_pid:-<none observed>}"

if [ "$phase3_outcome" != 0 ]; then
  # Cancel rather than leave it held. A stuck HTLC keeps the channel wedged for
  # the rest of the emulator's life, and the next dispatch of this script would
  # then fail at a place that has nothing to do with its own run.
  lnc cancelinvoice "$payment_hash" > /dev/null 2>&1 || true
  echo "::error::K7 phase 3 failed. LND reported the invoice as '$htlc_state'. If that"\
    " is not ACCEPTED then the payment never reached the counterparty and no kill"\
    " window ever opened — which is a routing or channel problem, NOT a fund-safety"\
    " finding."
  exit 1
fi

[ "$htlc_state" = "ACCEPTED" ] || harness_fail \
  "Phase 3 passed but LND reports the invoice as '$htlc_state'. Those cannot both be true — the phase only returns on a hand-off this script writes on ACCEPTED. Refusing to draw a conclusion."

if [ -z "$killed_pid" ]; then
  harness_fail "No process of $APP_PACKAGE was alive while the HTLC was held. Phase 4 cannot show that the process died, so a pass would prove nothing about an interruption."
fi

# --- The kill ------------------------------------------------------------------
#
# `am kill`, never `am force-stop`. Force-stop puts the package in Android's
# stopped state, which is a different event from process death and one the
# platform treats differently — wallet-node-device-tests.md §2 is the same
# correction for K2.
#
# Belt and braces: the framework already tears the instrumented process down when
# phase 3 returns. This is what makes "the process is gone" a checked fact rather
# than an assumption about instrumentation teardown, and it is why phase 4 is
# handed the pid observed above.
echo "--- Killing $APP_PACKAGE (pid $killed_pid) with the HTLC still held"
adb shell am kill "$APP_PACKAGE" > /dev/null 2>&1 || true

kill_deadline=$(( $(date +%s) + 60 ))
while [ -n "$(device_pid)" ]; do
  if [ "$(date +%s)" -ge "$kill_deadline" ]; then
    harness_fail "$APP_PACKAGE is still running 60s after am kill (pid $(device_pid)). Phase 4 would run against a node that was never interrupted."
  fi
  adb shell am kill "$APP_PACKAGE" > /dev/null 2>&1 || true
  sleep 2
done
echo "Process gone."

# --- Settle, while the app is dead ---------------------------------------------
#
# The asymmetric direction, and the reason this suite settles rather than
# cancels. The money has left and the counterparty holds the preimage; the wallet
# must come back knowing the payment SUCCEEDED. A wallet that reports Failed here
# has lost the claim — it shows the user a failed payment they were charged for,
# and a retry pays twice.
#
# LND settles against a peer that is not connected by persisting it and
# completing on re-establish, which is exactly the path K7 is about: the settle
# happened while we could not hear it.
echo "--- Settling the hold invoice while nothing is listening"
lnc settleinvoice "$preimage" > /dev/null 2>&1 \
  || harness_fail "LND would not settle the hold invoice. Without the settle, phase 4 measures an HTLC that is still in flight rather than an outcome."

settled_state=$(lnc lookupinvoice "$payment_hash" 2> /dev/null | json_field state)
echo "LND's view after the settle: $settled_state"

# --- Phase 4: the verdict ------------------------------------------------------
phase4_outcome=0
run_phase 4 phase4TheInterruptedPaymentResolvedToExactlyOneOutcome \
  -Pandroid.testInstrumentationRunnerArguments.k7PaymentHash="$payment_hash" \
  -Pandroid.testInstrumentationRunnerArguments.k7KilledPid="$killed_pid" \
  || phase4_outcome=$?

echo "--- K7 summary"
echo "  peer           ${BITTR_LDK_LIGHTNING_NODE_ID}"
echo "  payment hash   $payment_hash"
echo "  window         wide (LND held the HTLC: $htlc_state)"
echo "  killed pid     $killed_pid"
echo "  invoice after  $settled_state"
echo "  results        $RESULTS_ROOT/phase{1,2,3,4}"

if [ "$phase4_outcome" != 0 ]; then
  echo "::error::K7 FAILED at phase 4. The process was killed with the HTLC accepted at"\
    " the counterparty, the invoice was then settled, and the restarted wallet did not"\
    " report exactly one terminal outcome for it. Read the assertion text in the gate's"\
    " annotation before rerunning: this is the fund-safety claim BIT-6 calls 'no path"\
    " where a user can lose funds', and a rerun that goes green does not withdraw it."
  exit 1
fi

echo "K7: an interrupted payment resolved to exactly one terminal outcome."
