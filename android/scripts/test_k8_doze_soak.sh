#!/usr/bin/env bash
#
# Pins the joins between K8's two halves, the host that drives one of them, and
# the gate that requires both (BIT-132).
#
#   bash android/scripts/test_k8_doze_soak.sh
#
# WHY THIS EXISTS, AND WHY IT IS NOT JUST test_k7_host_phase.sh AGAIN
#
# The same class of guard — strings joining a host script to a device test with
# no compiler anywhere on the path — and two joins K7 does not have:
#
#   * A LOGCAT TAG. K8's freshness half signals device -> host over logcat,
#     because `UiAutomation.executeShellCommand` has no shell and a device-side
#     redirect would not write a file. So the tag and the marker the host greps
#     for are a contract, and a drift makes the host wait out IDLE_WAIT_SECONDS
#     and exit 2 — a harness verdict after ten minutes of a 90-minute job.
#
#   * AN ANNOTATION THAT MUST BE PRESENT ON ONE CLASS AND ABSENT ON THE OTHER.
#     This is the one that fails toward a wrong conclusion rather than a stall,
#     and it fails in BOTH directions:
#
#       - K8ChannelFreshnessTest#… without @HostDriven also runs inside the
#         undirected suite, where K7 has not run yet, there is no channel, and
#         its red reads as "the node did not survive Doze" when it means "this
#         ran in the wrong order".
#       - K8DozeMachineryTest WITH @HostDriven silently stops running anywhere:
#         the undirected suite filters it out and no host script names it. The
#         gate catches that as "did not run at all" — which is the right verdict
#         and an expensive way to learn it.
#
# Same place as its sibling: the build job, on a machine with no emulator,
# seconds after the edit that caused it.
#
# No device, no emulator, no Gradle: greps and comparisons.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

SCRIPT="$SCRIPT_DIR/k8-doze-soak.sh"
SUITE_SCRIPT="$SCRIPT_DIR/ci-wallet-regtest.sh"
GATE="$SCRIPT_DIR/check-wallet-regtest-results.py"
GRADLE="$REPO_ROOT/android/app/build.gradle.kts"
REGTEST_SRC="$REPO_ROOT/android/app/src/androidTestRegtest/kotlin/com/bittr/android"
FRESHNESS="$REGTEST_SRC/K8ChannelFreshnessTest.kt"
MACHINERY="$REGTEST_SRC/K8DozeMachineryTest.kt"
DOZE="$REGTEST_SRC/DozeControl.kt"

failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

pass() {
  echo "ok: $*"
}

for path in "$SCRIPT" "$SUITE_SCRIPT" "$GATE" "$GRADLE" "$FRESHNESS" "$MACHINERY" "$DOZE"; do
  if [ ! -f "$path" ]; then
    echo "FAIL: missing $path — this guard cannot check what it cannot read."
    exit 1
  fi
done

# Every method carrying @Test in a file, in declaration order.
#
# The annotation line is anchored rather than merely matched, so a `@Test` inside
# a KDoc paragraph does not make this guard invent a method and then fail for
# want of it in the gate.
test_methods() {
  awk '
    /^[[:space:]]*@Test[[:space:]]*$/ { pending = 1; next }
    pending && match($0, /fun [A-Za-z0-9_]+/) {
      print substr($0, RSTART + 4, RLENGTH - 4)
      pending = 0
    }
  ' "$1"
}

# --- 1. The package the host addresses == applicationId + debug suffix ---------
application_id=$(grep -E '^\s*applicationId\s*=' "$GRADLE" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
suffix=$(grep -E '^\s*applicationIdSuffix\s*=' "$GRADLE" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
expected_package="${application_id}${suffix}"
script_package=$(grep -E '^APP_PACKAGE=' "$SCRIPT" | sed -E 's/.*:-([^}]+)\}.*/\1/')

if [ "$script_package" = "$expected_package" ]; then
  pass "APP_PACKAGE default '$script_package' matches applicationId + debug suffix."
else
  fail "k8-doze-soak.sh addresses '$script_package'; build.gradle.kts installs"\
    " '$expected_package'. \`adb shell\` commands against a package that does not"\
    " exist exit 0 and do nothing, so the hand-off would be written nowhere and the"\
    " device would doze for its whole window for want of it."
fi

# --- 2. The method the host runs is the method the test declares ---------------
script_class=$(grep -E '^TEST_CLASS=' "$SCRIPT" | sed -E 's/.*"([^"]+)".*/\1/')
script_method=$(grep -E '^TEST_METHOD=' "$SCRIPT" | sed -E 's/.*"([^"]+)".*/\1/')
freshness_methods=$(test_methods "$FRESHNESS")

if [ "$script_class" = "com.bittr.android.K8ChannelFreshnessTest" ]; then
  pass "The host runs $script_class."
else
  fail "k8-doze-soak.sh names class '$script_class', which is not"\
    " com.bittr.android.K8ChannelFreshnessTest."
fi

if [ "$script_method" = "$freshness_methods" ]; then
  pass "The host runs the one method the freshness half declares: $script_method."
else
  fail "k8-doze-soak.sh runs '$script_method'; K8ChannelFreshnessTest declares"\
    " [$(echo "$freshness_methods" | tr '\n' ' ')]. A filter that matches no test makes"\
    " Gradle exit 0 having run nothing, and this script would then wait out"\
    " IDLE_WAIT_SECONDS for an announcement nothing was ever going to make."
fi

# --- 3. Exactly the freshness half is @HostDriven, and the machinery half is not
#
# Both directions, because they fail differently and only one of them stalls.
freshness_annotated=$(grep -c '^\s*@HostDriven' "$FRESHNESS")
freshness_declared=$(echo "$freshness_methods" | grep -c .)
machinery_annotated=$(grep -c '^\s*@HostDriven' "$MACHINERY")
machinery_methods=$(test_methods "$MACHINERY")

if [ "$freshness_annotated" = "$freshness_declared" ]; then
  pass "All $freshness_declared freshness method(s) carry @HostDriven."
else
  fail "K8ChannelFreshnessTest declares $freshness_declared test method(s) and carries"\
    " $freshness_annotated @HostDriven annotation(s). An unannotated one also runs"\
    " inside ci-wallet-regtest.sh's undirected suite — before K7, with no channel open"\
    " — and its red would be read as 'the node did not survive Doze'."
fi

if [ "$machinery_annotated" = "0" ]; then
  pass "K8DozeMachineryTest carries no @HostDriven, so the undirected suite runs it."
else
  fail "K8DozeMachineryTest carries $machinery_annotated @HostDriven annotation(s)."\
    " The undirected suite filters those out and no host script names this class, so"\
    " an annotated method would run NOWHERE. The gate reports that as 'did not run at"\
    " all', which is correct and costs a nightly run to learn."
fi

# --- 4. The undirected suite applies the filter, and invokes this script -------
if grep -q 'notAnnotation=com.bittr.android.HostDriven' "$SUITE_SCRIPT"; then
  pass "ci-wallet-regtest.sh excludes @HostDriven from the undirected suite."
else
  fail "ci-wallet-regtest.sh does not pass"\
    " -Pandroid.testInstrumentationRunnerArguments.notAnnotation=com.bittr.android.HostDriven."\
    " Annotating the freshness half only keeps it out of that run if the run asks."
fi

if grep -q 'k8-doze-soak.sh' "$SUITE_SCRIPT"; then
  pass "ci-wallet-regtest.sh invokes k8-doze-soak.sh."
else
  fail "ci-wallet-regtest.sh never runs android/scripts/k8-doze-soak.sh. The"\
    " freshness half is @HostDriven, so nothing else would run it: it would be absent"\
    " from every result and reported by the gate as never having run."
fi

if grep -q 'androidTest-results/k8' "$SUITE_SCRIPT"; then
  pass "ci-wallet-regtest.sh hands the gate K8's results directory."
else
  fail "ci-wallet-regtest.sh does not pass --results-dir for"\
    " androidTest-results/k8. Every Gradle run overwrites .../connected, so the"\
    " freshness half's XML would be read as some other run's or not at all."
fi

# --- 5. The hand-off path is one path -----------------------------------------
script_handoff=$(grep -E '^HANDOFF_PATH=' "$SCRIPT" | sed -E 's/.*"([^"]+)".*/\1/')
test_handoff=$(grep -E 'const val HANDOFF_PATH' "$FRESHNESS" | sed -E 's/.*"([^"]+)".*/\1/')

if [ -n "$script_handoff" ] && [ "$script_handoff" = "$test_handoff" ]; then
  pass "The hand-off path agrees: $script_handoff"
else
  fail "The host writes '$script_handoff' and the test polls '$test_handoff'. The"\
    " device would hold its whole idle window, see no hand-off, and fail saying the"\
    " chain never moved — after dozing for it."
fi

# --- 6. The logcat tag and the two markers agree -------------------------------
#
# The device -> host direction has no file and no compiler. A drift here is the
# one that costs IDLE_WAIT_SECONDS of a 90-minute job to discover.
doze_tag=$(grep -E 'const val TAG' "$DOZE" | sed -E 's/.*"([^"]+)".*/\1/')
script_tag=$(grep -E '^LOG_TAG=' "$SCRIPT" | sed -E 's/.*"([^"]+)".*/\1/')

if [ -n "$doze_tag" ] && [ "$doze_tag" = "$script_tag" ]; then
  pass "The logcat tag agrees: $doze_tag"
else
  fail "Doze.TAG is '$doze_tag' and k8-doze-soak.sh greps for '$script_tag'. The host"\
    " would never see the device enter its window, never mine, and exit 2 — a harness"\
    " verdict rather than a K8 result, ten minutes in."
fi

# `grep -F` on a fixed marker, because both sides contain an `=`.
for marker in MARKER_IDLE MARKER_MINED; do
  script_value=$(grep -E "^$marker=" "$SCRIPT" | sed -E 's/.*"([^"]+)".*/\1/')
  test_value=$(grep -E "const val $marker" "$FRESHNESS" | sed -E 's/.*"([^"]+)".*/\1/')
  if [ -n "$script_value" ] && [ "$script_value" = "$test_value" ]; then
    pass "$marker agrees: '$script_value'"
  else
    fail "$marker is '$script_value' in k8-doze-soak.sh and '$test_value' in"\
      " K8ChannelFreshnessTest. The device asserts on the hand-off's CONTENTS and the"\
      " host greps logcat for its marker; a drift in either direction stalls the run"\
      " rather than failing it legibly."
  fi
done

# The address token the host parses out of the device's announcement. Its
# absence is the failure that funds nothing and reports a catch-up that never
# happened, so it is pinned in both directions.
if grep -qF 's/^address=//p' "$SCRIPT" && grep -qF 'address=$address' "$FRESHNESS"; then
  pass "The host parses 'address=' and the device announces it."
else
  fail "The host's address parser and the device's announcement have come apart. The"\
    " host would have nothing to send to and would exit 2 — or, worse, a future edit"\
    " that guessed the address instead would fund a wallet nothing is watching, so the"\
    " balance never moves and the test reports a Doze failure that is really a"\
    " derivation mistake."
fi

# --- 7. Every method of both halves is REQUIRED by name in the gate ------------
#
# BIT-132's definition of done, checked rather than remembered: "every method
# added goes into the REQUIRED set by name, per method, in the commit that writes
# it".
for method in $freshness_methods; do
  if grep -q "K8ChannelFreshnessTest#$method" "$GATE"; then
    pass "REQUIRED names K8ChannelFreshnessTest#$method."
  else
    fail "check-wallet-regtest-results.py does not require"\
      " K8ChannelFreshnessTest#$method. A method absent from that set can stop running"\
      " entirely and the nightly job stays green."
  fi
done

for method in $machinery_methods; do
  if grep -q "K8DozeMachineryTest#$method" "$GATE"; then
    pass "REQUIRED names K8DozeMachineryTest#$method."
  else
    fail "check-wallet-regtest-results.py does not require"\
      " K8DozeMachineryTest#$method. A method absent from that set can stop running"\
      " entirely and the nightly job stays green."
  fi
done

echo
if [ "$failures" -ne 0 ]; then
  echo "::error::test_k8_doze_soak.sh: $failures check(s) failed. K8's device halves and"\
    " the host between them are joined by strings with no compiler on the path; every"\
    " failure above is a join that has come apart."
  exit 1
fi

echo "test_k8_doze_soak.sh: all checks passed."
