#!/usr/bin/env bash
#
# Runs k1-lockscreen-matrix.sh end to end against a fake device.
#
# WHY THIS EXISTS
#
# android/scripts/test-k1-verdict.sh covers `run_verdict` — one function, the
# one that reads `am instrument` output. Everything else in the driver, the
# ~400 lines that decide whether a row is written PASS, ERROR, FAIL or NOT
# REACHABLE, had never been executed anywhere: it needs an attached Android
# device, and it will first meet one on the day someone runs the matrix for
# real and pastes the table into a security statement.
#
# That is the wrong day to find out that the fail-closed logic does not close.
#
# So this script gives the driver a device. `adb` is replaced on PATH by a stub
# that models one handset — a lock-screen credential, a property table, and an
# `am instrument` that emits real runner output shapes — with knobs to make it
# misbehave in the specific ways that would produce a false green:
#
#   * a mutation command that exits 0 and changes nothing
#   * a mutation that lands somewhere other than where it was aimed
#   * an open phase that exits clean but emits no verdict
#   * an open phase that reports "skipped" rather than "passed"
#
# The driver runs inside a throwaway git repo with a stub gradlew, so nothing
# here touches the real build, the real repo, or any real device. It needs
# bash and git and nothing else:
#
#   bash android/scripts/test-k1-driver.sh
#
# WHAT IT DOES NOT DO
#
# It does not test Android. Every fact about Keystore and `locksettings` on the
# other side of adb is *assumed* by the stub, and the whole point of BIT-18 is
# that those assumptions need a real device. This tests the driver's reasoning,
# not the platform's behaviour: that given what a device says, the driver draws
# the right conclusion and refuses to draw one when it cannot.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
DRIVER="$PWD/android/scripts/k1-lockscreen-matrix.sh"

if [ ! -f "$DRIVER" ]; then
  echo "test-k1-driver: $DRIVER not found" >&2
  exit 1
fi

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# ---------------------------------------------------------------------------
# The fake device
# ---------------------------------------------------------------------------

BIN="$ROOT/bin"
mkdir -p "$BIN"

cat >"$BIN/adb" <<'STUB'
#!/usr/bin/env bash
#
# A fake adb, for test-k1-driver.sh. Models exactly as much of one device as
# the K1 driver touches: a lock-screen credential, a property table, an
# instrumentation runner and a logcat ring.
#
# It always exits 0, however the emulated command went. That is not laziness —
# it is the behaviour that forced `sh_status` to exist in the driver, and
# reproducing it here is what keeps the driver's sentinel-echo plumbing under
# test rather than accidentally bypassed.
set -uo pipefail
D="${K1_FAKE_DIR:?K1_FAKE_DIR is not set}"

knob() { cat "$D/knobs/$1" 2>/dev/null || printf '%s' "${2:-}"; }
cred() { cat "$D/cred" 2>/dev/null || printf ''; }
set_cred() { printf '%s' "$1" >"$D/cred"; }
trace() { printf '%s\n' "$*" >>"$D/trace"; }
prop() { sed -n "s/^$1=//p" "$D/props" | head -n 1; }

# The driver only ever passes -s, and only first.
[ "${1:-}" = "-s" ] && shift 2

cmd="${1:-}"
shift || true

case "$cmd" in
  devices) cat "$D/devices"; exit 0 ;;
  wait-for-device) exit 0 ;;
  install|uninstall) trace "$cmd ${*}"; exit 0 ;;
  logcat)
    if [ "${1:-}" = "-c" ]; then : >"$D/logcat"; exit 0; fi
    cat "$D/logcat" 2>/dev/null
    exit 0
    ;;
  shell) ;;
  *) exit 0 ;;
esac

# --- adb shell -------------------------------------------------------------
#
# Two calling conventions reach here. `sh_ getprop ro.x` arrives as separate
# argv entries; `sh_status "locksettings verify --old '1234'"` arrives as one
# string with shell quoting inside it and a sentinel echo appended. Joining and
# re-splitting with `eval` is what a real `adb shell` does to its argument, so
# it is also the faithful thing to do here.
line="$*"
want_rc=0
suffix=' ; echo __k1_rc=$?'
case "$line" in
  *"$suffix") want_rc=1; line="${line%"$suffix"}" ;;
esac
eval "set -- $line"

rc=0
emit_pass() {
  cat <<EOF
INSTRUMENTATION_STATUS: class=$1
INSTRUMENTATION_STATUS: current=1
INSTRUMENTATION_STATUS_CODE: 1
INSTRUMENTATION_STATUS_CODE: 0
INSTRUMENTATION_RESULT: stream=
Time: 1.204

OK (1 test)

INSTRUMENTATION_CODE: -1
EOF
}
emit_fail() {
  cat <<EOF
INSTRUMENTATION_STATUS: class=$1
INSTRUMENTATION_STATUS_CODE: 1
INSTRUMENTATION_STATUS: stack=junit.framework.AssertionFailedError: the non-auth-bound key did NOT survive
INSTRUMENTATION_STATUS_CODE: -2
INSTRUMENTATION_RESULT: stream=
FAILURES!!!
Tests run: 1,  Failures: 1

INSTRUMENTATION_CODE: -1
EOF
}
emit_skip() {
  cat <<EOF
INSTRUMENTATION_STATUS: class=$1
INSTRUMENTATION_STATUS_CODE: 1
INSTRUMENTATION_STATUS: stack=org.junit.AssumptionViolatedException: reason=$(knob skip_reason not-a-device-owner)
INSTRUMENTATION_STATUS_CODE: -4
INSTRUMENTATION_RESULT: stream=
Time: 0.41

OK (1 test)

INSTRUMENTATION_CODE: -1
EOF
}
emit_crash() {
  cat <<'EOF'
INSTRUMENTATION_RESULT: shortMsg=Process crashed.
INSTRUMENTATION_CODE: 0
EOF
}

k1_log() { printf '10-01 12:00:00.000  4242  4242 I K1      : %s\n' "$*" >>"$D/logcat"; }

do_instrument() {
  local cls="" kcase="" short verdict secure
  while [ $# -gt 0 ]; do
    if [ "$1" = "-e" ]; then
      case "${2:-}" in
        class) cls="${3:-}" ;;
        k1_case) kcase="${3:-}" ;;
      esac
      shift 3 || shift $#
    else
      shift
    fi
  done
  short="${cls##*.}"
  trace "instrument $short $kcase"

  case "$short" in
    K1SealTest) verdict="$(knob verdict_seal pass)" ;;
    K1OpenTest) verdict="$(knob verdict_open pass)" ;;
    K1AdminResetTest) verdict="$(knob verdict_admin pass)" ;;
    *) verdict=fail ;;
  esac

  case "$verdict" in
    fail) emit_fail "$cls"; return ;;
    skip) emit_skip "$cls"; return ;;
    crash) emit_crash; return ;;
  esac

  emit_pass "$cls"
  [ -n "$(cred)" ] && secure=true || secure=false
  case "$short" in
    K1SealTest)
      k1_log "phase=seal case=$kcase deviceSecure=$secure securityLevel=TEE"
      ;;
    K1AdminResetTest)
      # The forced reset destroys the credential — K1Case.M6 is endsSecure=false.
      set_cred ""
      k1_log "phase=admin-reset case=$kcase deviceSecure=false"
      ;;
    K1OpenTest)
      if [ "$(knob open_no_verdict 0)" = "1" ]; then
        k1_log "phase=open case=$kcase deviceSecure=$secure securityLevel=TEE"
      else
        k1_log "phase=open case=$kcase deviceSecure=$secure securityLevel=TEE verdict=PASS"
      fi
      ;;
  esac
}

case "${1:-}" in
  getprop) prop "${2:-}" ;;

  input | wm | pm) : ;;

  dumpsys)
    if [ "${2:-}" = "account" ]; then
      n=$(knob accounts 0)
      i=0
      while [ "$i" -lt "$n" ]; do
        echo "  Account {name=user$i@example.com, type=com.google}"
        i=$((i + 1))
      done
    fi
    ;;

  dpm)
    if [ "${2:-}" = "set-device-owner" ]; then
      trace "set-device-owner ${3:-}"
      rc=$(knob dpm_rc 0)
      [ "$rc" = "0" ] && echo "Success: Device owner set to package ${3:-}"
    fi
    ;;

  am)
    case "${2:-}" in
      force-stop) trace "force-stop ${3:-}" ;;
      instrument) shift 2; do_instrument "$@" ;;
    esac
    ;;

  locksettings)
    sub="${2:-}"
    shift 2 || true
    case "$sub" in
      verify)
        if [ "${1:-}" = "--old" ]; then
          [ "${2:-}" = "$(cred)" ] && rc=0 || rc=1
        else
          [ -z "$(cred)" ] && rc=0 || rc=1
        fi
        ;;
      set-pin | set-password | set-pattern)
        # `--old` is what separates the two kinds of call the driver makes: it
        # reaches a case's start state with a bare `set-pin`, and performs the
        # mutation under test with `--old`. The fault knobs are aimed at one or
        # the other, never both, or a "the mutation did nothing" scenario would
        # silently become "the start state was never reached".
        if [ "${1:-}" = "--old" ]; then
          old="${2:-}"; new="${3:-}"; is_mutation=1
        else
          old=""; new="${1:-}"; is_mutation=0
        fi
        if [ "$old" != "$(cred)" ]; then
          rc=1
        elif [ "$is_mutation" = "0" ] && [ "$(knob setup_noop 0)" = "1" ]; then
          rc=0
        elif [ "$is_mutation" = "0" ]; then
          set_cred "$new"
          rc=0
        elif [ "$(knob mutation_fails 0)" = "1" ]; then
          rc=1
        elif [ "$(knob mutation_noop 0)" = "1" ]; then
          # Exits 0, changes nothing. The false green this whole test exists for.
          rc=0
        elif [ -n "$(knob mutation_lands_on "")" ]; then
          # Landed, but not where it was aimed.
          set_cred "$(knob mutation_lands_on "")"
          rc=0
        else
          set_cred "$new"
          rc=0
        fi
        ;;
      clear)
        old=""
        [ "${1:-}" = "--old" ] && old="${2:-}"
        if [ "$(knob clear_fails 0)" = "1" ]; then
          rc=1
        elif [ "$old" != "$(cred)" ]; then
          rc=1
        elif [ "$(knob clear_noop 0)" = "1" ]; then
          rc=0
        else
          set_cred ""
          rc=0
        fi
        ;;
      *) rc=1 ;;
    esac
    ;;
esac

[ "$want_rc" -eq 1 ] && printf '__k1_rc=%s\n' "$rc"
exit 0
STUB
chmod +x "$BIN/adb"

# ---------------------------------------------------------------------------
# Scenario plumbing
# ---------------------------------------------------------------------------

failures=0
checks=0
current=""
SANDBOX=""
FAKE=""
RC=0
OUT=""

# A throwaway repo the driver can `cd $(git rev-parse --show-toplevel)` into,
# with a gradlew that builds nothing and an APK that is an empty file.
scenario() {
  current="$1"
  printf '\n%s\n' "$current"
  SANDBOX="$ROOT/$(printf '%s' "$current" | tr -c 'a-zA-Z0-9' '-')-$RANDOM"
  FAKE="$SANDBOX/.fake"
  mkdir -p "$SANDBOX/android/scripts" \
    "$SANDBOX/android/core/keystore-probe/build/outputs/apk/androidTest" \
    "$FAKE/knobs"
  git -c init.defaultBranch=main init -q "$SANDBOX"
  cp "$DRIVER" "$SANDBOX/android/scripts/k1-lockscreen-matrix.sh"
  printf '#!/bin/sh\nexit 0\n' >"$SANDBOX/android/gradlew"
  chmod +x "$SANDBOX/android/gradlew"
  : >"$SANDBOX/android/core/keystore-probe/build/outputs/apk/androidTest/probe-debug-androidTest.apk"

  printf '' >"$FAKE/cred"
  : >"$FAKE/trace"
  : >"$FAKE/logcat"
  printf 'List of devices attached\nemulator-5554\tdevice\n\n' >"$FAKE/devices"
  cat >"$FAKE/props" <<'EOF'
ro.build.version.sdk=33
ro.product.manufacturer=Google
ro.product.model=sdk_gphone64_x86_64
ro.build.fingerprint=google/sdk_gphone64_x86_64/emu64x:13/TE1A.220922.021/9302419:userdebug/dev-keys
ro.hardware=ranchu
ro.kernel.qemu=1
ro.boot.qemu=1
EOF
}

knob() { printf '%s' "$2" >"$FAKE/knobs/$1"; }
prop() { sed -i "s|^$1=.*|$1=$2|" "$FAKE/props"; }
start_cred() { printf '%s' "$1" >"$FAKE/cred"; }

physical() {
  prop ro.hardware qcom
  prop ro.kernel.qemu ""
  prop ro.boot.qemu ""
  prop ro.product.manufacturer samsung
  prop ro.product.model SM-S911B
}

run_driver() {
  set +e
  OUT=$(cd "$SANDBOX" && PATH="$BIN:$PATH" K1_FAKE_DIR="$FAKE" \
    bash android/scripts/k1-lockscreen-matrix.sh "$@" 2>&1)
  RC=$?
  set -e
}

pass_check() {
  checks=$((checks + 1))
  printf '  ok    %s\n' "$1"
}

fail_check() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf '  FAIL  %s\n' "$1"
  if [ -n "${2:-}" ]; then printf '        %s\n' "$2"; fi
}

expect_rc() {
  if [ "$RC" = "$1" ]; then
    pass_check "exit $1"
  else
    fail_check "exit $1" "got $RC; output follows:
$(printf '%s\n' "$OUT" | sed 's/^/        | /')"
  fi
}

expect_out() {
  if printf '%s' "$OUT" | grep -qF -- "$1"; then
    pass_check "output contains: $1"
  else
    fail_check "output contains: $1" "output follows:
$(printf '%s\n' "$OUT" | sed 's/^/        | /')"
  fi
}

refute_out() {
  if printf '%s' "$OUT" | grep -qF -- "$1"; then
    fail_check "output must NOT contain: $1" "output follows:
$(printf '%s\n' "$OUT" | sed 's/^/        | /')"
  else
    pass_check "output does not contain: $1"
  fi
}

expect_trace() {
  if grep -qF -- "$1" "$FAKE/trace"; then
    pass_check "device saw: $1"
  else
    fail_check "device saw: $1" "trace follows:
$(sed 's/^/        | /' "$FAKE/trace")"
  fi
}

refute_trace() {
  if grep -qF -- "$1" "$FAKE/trace"; then
    fail_check "device must NOT have seen: $1" "trace follows:
$(sed 's/^/        | /' "$FAKE/trace")"
  else
    pass_check "device never saw: $1"
  fi
}

expect_cred() {
  local got
  got=$(cat "$FAKE/cred")
  if [ "$got" = "$1" ]; then
    pass_check "device credential is '${1:-<none>}'"
  else
    fail_check "device credential is '${1:-<none>}'" "got '$got'"
  fi
}

echo "test-k1-driver: running k1-lockscreen-matrix.sh against a fake device"

# ---------------------------------------------------------------------------
# The green path — so that everything below is a difference from a known state
# ---------------------------------------------------------------------------

scenario "M2 (PIN -> PIN), everything behaves"
run_driver M2
expect_rc 0
expect_out "| M2 | PASS |"
expect_out "every case run produced a result"
# The claim under test is survival across a *process* boundary, so the force-stop
# between the two instrumentation runs is part of the result, not housekeeping.
expect_trace "instrument K1SealTest M2"
expect_trace "force-stop com.bittr.android.core.keystore.probe.test"
expect_trace "instrument K1OpenTest M2"
# A device left on the script's PIN is the physical-device hazard the header warns
# about; the exit trap has to actually undo it.
expect_cred ""

scenario "M1 (no lock screen -> PIN)"
run_driver M1
expect_rc 0
expect_out "| M1 | PASS |"
expect_cred ""

scenario "M5 (remove the lock screen)"
run_driver M5
expect_rc 0
expect_out "| M5 | PASS |"
expect_cred ""

scenario "the default case list is M1-M5 and excludes M6"
run_driver
expect_rc 0
for c in M1 M2 M3 M4 M5; do expect_out "| $c | PASS |"; done
refute_out "| M6 |"
refute_trace "set-device-owner"

# ---------------------------------------------------------------------------
# False greens — a mutation that did not happen must never produce a PASS row
# ---------------------------------------------------------------------------

scenario "a mutation that exits 0 and changes nothing is not a PASS"
knob mutation_noop 1
run_driver M2
expect_rc 1
refute_out "| M2 | PASS |"
expect_out "| M2 | ERROR |"
expect_out "the OLD credential still verifies after the mutation"
# The driver must not even ask the question: running the open phase against an
# unmutated device produces a green that means nothing, and a green is what gets
# quoted later.
refute_trace "instrument K1OpenTest M2"

scenario "a start state that was never reached is an ERROR"
# `locksettings set-pin` exits 0 without setting anything, so the case would run
# its mutation from a state it does not know it is in. The driver has to notice
# before it mutates, not after.
knob setup_noop 1
run_driver M2
expect_rc 1
refute_out "| M2 | PASS |"
expect_out "the start credential did not verify before mutating"
refute_trace "instrument K1OpenTest M2"

scenario "a clear that exits 0 and removes nothing is not a PASS"
knob clear_noop 1
run_driver M5
expect_rc 1
refute_out "| M5 | PASS |"
expect_out "| M5 | ERROR |"
refute_trace "instrument K1OpenTest M5"

scenario "a mutation that lands on the wrong credential is not a PASS"
# set-password reports success, the old PIN stops verifying — so the existing
# old-credential witness is satisfied — but what is on the device is not what M3
# says is on the device. Only a positive check on the new credential catches it.
knob mutation_lands_on 9999
run_driver M3
expect_rc 1
refute_out "| M3 | PASS |"
expect_out "| M3 | ERROR |"

scenario "an open phase with no verdict line is not a PASS"
knob open_no_verdict 1
run_driver M2
expect_rc 1
refute_out "| M2 | PASS |"
expect_out "emitted no verdict line"

scenario "an open phase that skips is not a PASS"
knob verdict_open skip
run_driver M2
expect_rc 1
refute_out "| M2 | PASS |"

scenario "an open phase that crashes is not a PASS"
knob verdict_open crash
run_driver M2
expect_rc 1
refute_out "| M2 | PASS |"

# ---------------------------------------------------------------------------
# Real reds and real harness errors, told apart from each other
# ---------------------------------------------------------------------------

scenario "a failed open phase is FAIL, and says do not switch designs"
knob verdict_open fail
run_driver M2
expect_rc 1
expect_out "| M2 | **FAIL** |"
expect_out "Do NOT switch designs"
expect_out "at least one row is FAIL or ERROR"

scenario "a failed seal phase is an ERROR, not a FAIL"
# A seal that never happened is a broken harness. Calling it FAIL would report a
# rule-2 contradiction that was never tested.
knob verdict_seal fail
run_driver M2
expect_rc 1
expect_out "| M2 | ERROR | seal |"
refute_out "**FAIL**"
refute_trace "instrument K1OpenTest M2"

scenario "a mutation command that fails outright is an ERROR"
knob mutation_fails 1
run_driver M2
expect_rc 1
expect_out "| M2 | ERROR |"
refute_out "| M2 | PASS |"

scenario "a device whose lock screen cannot be cleared is an ERROR"
start_cred 0000
knob clear_fails 1
run_driver M2
expect_rc 1
expect_out "could not clear the lock screen"
refute_out "| M2 | PASS |"

scenario "one bad case does not suppress the others, and the run still fails"
knob verdict_open fail
run_driver M1 M2
expect_rc 1
expect_out "| M1 | **FAIL** |"
expect_out "| M2 | **FAIL** |"

# ---------------------------------------------------------------------------
# M6 — reachability is an answer, not a gap
# ---------------------------------------------------------------------------

scenario "M6 needs --with-device-owner and will not be inferred"
run_driver M6
expect_rc 2
expect_out "needs --with-device-owner"
refute_trace "set-device-owner"

scenario "M6 on an emulator, device owner granted"
knob verdict_admin pass
run_driver --with-device-owner M6
expect_rc 0
expect_out "| M6 | PASS |"
expect_trace "set-device-owner"

scenario "M6 where dpm refuses is NOT REACHABLE, not an error"
knob dpm_rc 1
run_driver --with-device-owner M6
expect_rc 0
expect_out "| M6 | NOT REACHABLE |"
expect_out "dpm set-device-owner refused"

scenario "M6 where the reset token will not activate is NOT REACHABLE, with the reason"
knob verdict_admin skip
knob skip_reason no-secure-hardware-to-escrow-the-token
run_driver --with-device-owner M6
expect_rc 0
expect_out "| M6 | NOT REACHABLE |"
expect_out "reason=no-secure-hardware-to-escrow-the-token"

scenario "M6 is refused on a physical device"
physical
run_driver --with-device-owner M6
expect_rc 2
expect_out "refusing --with-device-owner"
refute_trace "set-device-owner"

# ---------------------------------------------------------------------------
# Refusals — before anything is installed or any credential is touched
# ---------------------------------------------------------------------------

scenario "a physical device holding accounts is refused"
physical
knob accounts 3
run_driver M2
expect_rc 2
expect_out "holding 3 account(s)"
expect_out "--i-know"
refute_trace "install"

scenario "--i-know overrides the account refusal"
physical
knob accounts 3
run_driver --i-know M2
expect_rc 0
expect_out "| M2 | PASS |"
expect_out "samsung/SM-S911B (API 33)"

scenario "an emulator is not account-checked"
knob accounts 3
run_driver M2
expect_rc 0
expect_out "| M2 | PASS |"

scenario "an API below minSdk is refused"
prop ro.build.version.sdk 25
run_driver M2
expect_rc 2
expect_out "below the project's minSdk 26"
refute_trace "install"

scenario "two attached devices and no -s is refused"
printf 'List of devices attached\nemulator-5554\tdevice\nemulator-5556\tdevice\n\n' >"$FAKE/devices"
run_driver M2
expect_rc 2
expect_out "expected exactly one attached device, found 2"
refute_trace "install"

scenario "-s picks one of two attached devices"
printf 'List of devices attached\nemulator-5554\tdevice\nemulator-5556\tdevice\n\n' >"$FAKE/devices"
run_driver -s emulator-5556 M2
expect_rc 0
expect_out "| M2 | PASS |"

scenario "an unauthorised device does not count as attached"
printf 'List of devices attached\nemulator-5554\tunauthorized\n\n' >"$FAKE/devices"
run_driver M2
expect_rc 2
expect_out "found 0"

scenario "an unknown argument is refused"
run_driver --wipe-everything
expect_rc 2
expect_out "unknown argument"

# ---------------------------------------------------------------------------
# The artefact
# ---------------------------------------------------------------------------

scenario "--out writes the table to a file"
run_driver --out "$SANDBOX/api33.md" M2
expect_rc 0
if [ -s "$SANDBOX/api33.md" ] && grep -q '| M2 | PASS |' "$SANDBOX/api33.md"; then
  pass_check "the table lands in the --out file"
else
  fail_check "the table lands in the --out file" "$(cat "$SANDBOX/api33.md" 2>&1)"
fi
# The row is worthless without the build it came from.
expect_out "google/sdk_gphone64_x86_64"

scenario "case ids are accepted in lower case"
run_driver m2
expect_rc 0
expect_out "| M2 | PASS |"

# ---------------------------------------------------------------------------

echo
printf 'test-k1-driver: %d checks, %d failed\n' "$checks" "$failures"
if [ "$failures" -ne 0 ]; then exit 1; fi
