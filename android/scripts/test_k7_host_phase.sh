#!/usr/bin/env bash
#
# Pins the four strings K7's host phase uses to reach the device, against the
# files that actually define them (BIT-132).
#
#   bash android/scripts/test_k7_host_phase.sh
#
# WHY THIS EXISTS
#
# K7 is four instrumented runs with a host between them, and every join between
# the two halves is a STRING. There is no compiler and no manifest anywhere on
# that path: the method names are `-Pandroid.testInstrumentationRunnerArguments.
# class=` values, the package is an `am kill` argument, the hand-off is a path
# passed to `adb shell`, and the arguments the test reads back are bundle keys.
#
# Every one of those drifts silently, and — this is the part that makes it worth
# a guard rather than a comment — most of them drift toward a result that LOOKS
# like a K7 finding:
#
#   * A renamed method: the phase runs nothing, Gradle exits 0 having matched no
#     test, and the run reaches the kill with no payment in flight.
#   * A wrong package in `am kill`: the kill exits 0 and kills nothing. Phase 4's
#     pid assertion is then the only thing between that and a vacuous pass, and
#     it would report "the process did not die" for a reason that is a typo.
#     ci-wallet-instrumented.sh's own host phase shipped with exactly this bug:
#     `namespace` is com.bittr.android and the INSTALLED id is
#     com.bittr.android.regtest.
#   * A drifted hand-off path: the host writes one file and the device polls
#     another. Phase 3 waits out its timeout and fails — the safe direction, and
#     still a wasted emulator hour at 03:20 UTC.
#   * A phase that is not `@HostDriven`: it runs inside the undirected suite too,
#     out of order, and ITS red is read as a fund-safety result. This is the only
#     one of the four that fails toward a wrong conclusion rather than toward a
#     stall, which is why it is checked in both directions below.
#
# Same class of guard, same reason, as test_ci_wallet_host_phase.sh — which pins
# BIT-108's device-transfer phase — and it runs in the same place: the build job,
# on a machine with no emulator, seconds after the rename that caused it.
#
# No device, no emulator, no Gradle: greps and comparisons.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

SCRIPT="$SCRIPT_DIR/k7-interrupted-payment.sh"
SUITE_SCRIPT="$SCRIPT_DIR/ci-wallet-regtest.sh"
GATE="$SCRIPT_DIR/check-wallet-regtest-results.py"
GRADLE="$REPO_ROOT/android/app/build.gradle.kts"
TEST="$REPO_ROOT/android/app/src/androidTestRegtest/kotlin/com/bittr/android/K7InterruptedPaymentTest.kt"
ANNOTATION="$REPO_ROOT/android/app/src/androidTestRegtest/kotlin/com/bittr/android/HostDriven.kt"

failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

pass() {
  echo "ok: $*"
}

for path in "$SCRIPT" "$SUITE_SCRIPT" "$GATE" "$GRADLE" "$TEST" "$ANNOTATION"; do
  if [ ! -f "$path" ]; then
    echo "FAIL: missing $path — this guard cannot check what it cannot read."
    exit 1
  fi
done

# --- 1. The package the host kills == applicationId + debug suffix -------------
application_id=$(grep -E '^\s*applicationId\s*=' "$GRADLE" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
suffix=$(grep -E '^\s*applicationIdSuffix\s*=' "$GRADLE" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
expected_package="${application_id}${suffix}"
script_package=$(grep -E '^APP_PACKAGE=' "$SCRIPT" | sed -E 's/.*:-([^}]+)\}.*/\1/')

if [ "$script_package" = "$expected_package" ]; then
  pass "APP_PACKAGE default '$script_package' matches applicationId + debug suffix."
else
  fail "k7-interrupted-payment.sh addresses '$script_package'; build.gradle.kts installs"\
    "'$expected_package'. \`am kill\` on a package that does not exist exits 0 and kills"\
    " nothing, so phase 4 would report an uninterrupted process as a wallet problem."
fi

# --- 2. Every phase the script runs exists in the test, and vice versa ---------
script_methods=$(grep -oE 'run_phase [0-9]+ [A-Za-z0-9_]+' "$SCRIPT" | awk '{print $3}' | sort -u)
test_methods=$(grep -oE 'fun phase[0-9][A-Za-z0-9_]*' "$TEST" | awk '{print $2}' | sort -u)

if [ "$script_methods" = "$test_methods" ]; then
  pass "The four phases the host runs are exactly the four the test declares."
else
  fail "The host script and K7InterruptedPaymentTest disagree about the phases."\
    " A method the script names and the test does not have runs nothing, and Gradle"\
    " exits 0 having matched no test — so the run reaches the kill with no payment in"\
    " flight. Script: [$(echo "$script_methods" | tr '\n' ' ')] Test:"\
    " [$(echo "$test_methods" | tr '\n' ' ')]"
fi

# --- 3. Every phase is @HostDriven, so the undirected suite skips it -----------
#
# Counted rather than matched per method, because the failure is quantitative:
# ONE unannotated phase is enough to put the whole sequence into the undirected
# run. `grep -c` on the annotation, against the number of phase methods.
annotated=$(grep -c '^\s*@HostDriven' "$TEST")
declared=$(echo "$test_methods" | grep -c .)

if [ "$annotated" = "$declared" ]; then
  pass "All $declared phases carry @HostDriven."
else
  fail "$declared phase methods and $annotated @HostDriven annotations. An unannotated"\
    " phase also runs inside ci-wallet-regtest.sh's undirected suite — out of order,"\
    " in one process, with no host between the phases — and its failure would be read"\
    " as a K7 result rather than as a sequencing mistake."
fi

# --- 4. The suite run actually applies that filter -----------------------------
if grep -q 'notAnnotation=com.bittr.android.HostDriven' "$SUITE_SCRIPT"; then
  pass "ci-wallet-regtest.sh excludes @HostDriven from the undirected suite."
else
  fail "ci-wallet-regtest.sh does not pass"\
    " -Pandroid.testInstrumentationRunnerArguments.notAnnotation=com.bittr.android.HostDriven."\
    " Annotating the phases only keeps them out of that run if the run asks."
fi

# --- 5. The hand-off path is one path --------------------------------------------
script_handoff=$(grep -E '^HANDOFF_PATH=' "$SCRIPT" | sed -E 's/.*"([^"]+)".*/\1/')
test_handoff=$(grep -E 'const val HANDOFF_PATH' "$TEST" | sed -E 's/.*"([^"]+)".*/\1/')

if [ -n "$script_handoff" ] && [ "$script_handoff" = "$test_handoff" ]; then
  pass "The hand-off path agrees: $script_handoff"
else
  fail "The host writes '$script_handoff' and the test polls '$test_handoff'. Phase 3"\
    " blocks on that file until the HTLC is accepted; if it never arrives the phase"\
    " waits out its timeout and fails, having booted an emulator to do it."
fi

# --- 6. The instrumentation arguments are the ones the test reads ----------------
for argument in k7Invoice k7PaymentHash k7KilledPid; do
  if ! grep -q "testInstrumentationRunnerArguments.$argument=" "$SCRIPT"; then
    fail "The host script never passes '$argument'. The test calls requireArgument for"\
      " it and would fail on a missing bundle key."
    continue
  fi
  if ! grep -q "\"$argument\"" "$TEST"; then
    fail "The host script passes '$argument' and the test names no such argument. A"\
      " bundle key nothing reads is silent — the payment id in particular is what"\
      " phase 4 looks the payment up BY, so a drift there reports a missing payment as"\
      " a fund-safety violation."
    continue
  fi
  pass "Instrumentation argument '$argument' is passed and read."
done

# --- 7. Every phase is REQUIRED by name in the gate -------------------------------
#
# BIT-132's definition of done, checked rather than remembered: "every method
# added goes into the REQUIRED set by name, per method, in the commit that writes
# it". BdkAccountXpubParityTest is why — it spent two runs executing while absent
# from the other gate's list, so the run that went green proved every required
# test ran and said nothing whatever about that one.
for method in $test_methods; do
  if grep -q "K7InterruptedPaymentTest#$method" "$GATE"; then
    pass "REQUIRED names $method."
  else
    fail "check-wallet-regtest-results.py does not require"\
      " K7InterruptedPaymentTest#$method. A phase absent from that set can stop running"\
      " entirely and the nightly job stays green."
  fi
done

echo
if [ "$failures" -ne 0 ]; then
  echo "::error::test_k7_host_phase.sh: $failures check(s) failed. K7's host phase and its"\
    " device phases are joined by strings with no compiler between them; every failure"\
    " above is a join that has come apart."
  exit 1
fi

echo "test_k7_host_phase.sh: all checks passed."
