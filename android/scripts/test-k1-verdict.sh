#!/usr/bin/env bash
#
# Tests `run_verdict` from k1-lockscreen-matrix.sh against captured
# `am instrument -w -r` output.
#
# WHY THIS EXISTS
#
# `run_verdict` is the function that decides whether a K1 row is green. K1's
# whole purpose is to replace an assumption about Keystore with a measurement,
# and the way that goes wrong is not a red row — it is a **green row from a run
# that measured nothing**, quoted later in a security statement.
#
# It had exactly that bug. The first version read
#
#   grep -qE '^INSTRUMENTATION_(CODE|STATUS_CODE): -1$'  ->  pass
#
# which conflates two different fields. `INSTRUMENTATION_CODE: -1` is
# `Activity.RESULT_OK` — it means the run completed, and it is printed
# identically for a run whose every test failed. `INSTRUMENTATION_STATUS_CODE:
# -1` is a per-test *error*. So the check scored both a passing run and a
# failing one as a pass, and a real rule-2 contradiction on a device would have
# been recorded PASS.
#
# The fixtures below are the shapes that bug could not tell apart. This runs on
# any machine, needs no device, and takes about a second:
#
#   bash android/scripts/test-k1-verdict.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Source the driver for its functions without running it. Everything above the
# marker is pure definition; `set -- ` clears the args so the arg parser sees
# nothing to complain about.
DRIVER="android/scripts/k1-lockscreen-matrix.sh"

# shellcheck disable=SC2016
run_verdict() {
  # Extracted by line range rather than sourced: the driver `exit`s on a missing
  # adb long before it defines anything, so sourcing it is not an option.
  :
}
eval "$(sed -n '/^run_verdict() {$/,/^}$/p' "$DRIVER")"

if ! declare -f run_verdict >/dev/null; then
  echo "test-k1-verdict: could not extract run_verdict from $DRIVER" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
check() {
  local name="$1" expected="$2" body="$3"
  printf '%s\n' "$body" >"$tmp/out"
  local got
  got=$(run_verdict "$tmp/out")
  if [ "$got" = "$expected" ]; then
    printf '  ok    %-46s -> %s\n' "$name" "$got"
  else
    printf '  FAIL  %-46s -> %s (expected %s)\n' "$name" "$got" "$expected"
    failures=$((failures + 1))
  fi
}

echo "test-k1-verdict: classifying am instrument output"

# The happy path. Note INSTRUMENTATION_CODE: -1 is present here *and* in the
# failing fixture below — that is the whole point.
check "a passing run" pass "INSTRUMENTATION_STATUS: class=com.bittr.android.core.keystore.probe.K1OpenTest
INSTRUMENTATION_STATUS: current=1
INSTRUMENTATION_STATUS_CODE: 1
INSTRUMENTATION_STATUS: k1_verdict=PASS
INSTRUMENTATION_STATUS_CODE: 0
INSTRUMENTATION_RESULT: stream=
Time: 1.23

OK (1 test)

INSTRUMENTATION_CODE: -1"

# The regression. Same INSTRUMENTATION_CODE: -1 trailer as the pass above, and
# the original implementation called this green.
check "an assertion failure is not a pass" fail "INSTRUMENTATION_STATUS: class=com.bittr.android.core.keystore.probe.K1OpenTest
INSTRUMENTATION_STATUS_CODE: 1
INSTRUMENTATION_STATUS: stack=junit.framework.AssertionFailedError: the non-auth-bound key did NOT survive
INSTRUMENTATION_STATUS_CODE: -2
INSTRUMENTATION_RESULT: stream=
FAILURES!!!
Tests run: 1,  Failures: 1

INSTRUMENTATION_CODE: -1"

check "a test error is not a pass" fail "INSTRUMENTATION_STATUS_CODE: 1
INSTRUMENTATION_STATUS: stack=android.security.keystore.KeyPermanentlyInvalidatedException
INSTRUMENTATION_STATUS_CODE: -1
INSTRUMENTATION_CODE: -1"

# An assumption failure still prints an OK summary, so a pass-first reading
# would score M6's "not reachable" as a green row.
check "an assumption failure is a skip, not a pass" skip "INSTRUMENTATION_STATUS: class=com.bittr.android.core.keystore.probe.K1AdminResetTest
INSTRUMENTATION_STATUS_CODE: 1
INSTRUMENTATION_STATUS: stack=org.junit.AssumptionViolatedException: not a device owner
INSTRUMENTATION_STATUS_CODE: -4
INSTRUMENTATION_RESULT: stream=
Time: 0.4

OK (1 test)

INSTRUMENTATION_CODE: -1"

check "a skip is detected from the exception alone" skip "INSTRUMENTATION_STATUS: stack=org.junit.AssumptionViolatedException: no secure hardware
INSTRUMENTATION_RESULT: stream=
OK (1 test)
INSTRUMENTATION_CODE: -1"

# Everything unrecognised must fall to fail, never to a pass and never to
# silence — a row with no evidence behind it is the thing being prevented.
check "a process crash is a failure" fail "INSTRUMENTATION_RESULT: shortMsg=Process crashed.
INSTRUMENTATION_CODE: 0"

check "a runner that never started is a failure" fail \
  "android.util.AndroidException: INSTRUMENTATION_FAILED: com.bittr.android.core.keystore.probe.test/androidx.test.runner.AndroidJUnitRunner"

check "empty output is a failure" fail ""

check "INSTRUMENTATION_CODE alone is not a pass" fail "INSTRUMENTATION_CODE: -1"

echo
if [ "$failures" -eq 0 ]; then
  echo "test-k1-verdict: all checks passed"
else
  echo "test-k1-verdict: $failures check(s) failed" >&2
fi
exit "$failures"
