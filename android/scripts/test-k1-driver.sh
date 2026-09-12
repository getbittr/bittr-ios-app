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
CI_WRAPPER="$PWD/android/scripts/k1-ci.sh"

if [ ! -f "$DRIVER" ]; then
  echo "test-k1-driver: $DRIVER not found" >&2
  exit 1
fi

if [ ! -f "$CI_WRAPPER" ]; then
  echo "test-k1-driver: $CI_WRAPPER not found" >&2
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
credtype() { cat "$D/credtype" 2>/dev/null || printf 'pin'; }
set_cred() { printf '%s' "$1" >"$D/cred"; printf '%s' "${2:-$(credtype)}" >"$D/credtype"; }
trace() { printf '%s\n' "$*" >>"$D/trace"; }
prop() { sed -n "s/^$1=//p" "$D/props" | head -n 1; }

# What DevicePolicyManager.getPasswordComplexity() would say about the credential
# this fake device is currently holding.
#
# The credential TYPE is tracked alongside the value, because the real API buckets
# by type as well as length and because "set-password landed as a pattern" is one
# of the faults this suite has to be able to stage. A driver that could not see
# that difference would report M3 for a device that did M4.
#
# Unreadable below API 29, which is the fact that makes M2/M3/M4 unreachable on
# the API 26 and 28 rows of the matrix — modelled here so that refusal is under
# test rather than taken on trust.
bucket() {
  [ "$(prop ro.build.version.sdk)" -lt 29 ] && { printf 'unreadable'; return; }
  [ "$(knob complexity_unreadable 0)" = "1" ] && { printf 'unreadable'; return; }
  local c t
  c="$(cred)"
  t="$(credtype)"
  [ -z "$c" ] && { printf 'NONE'; return; }
  case "$t" in
    pattern) printf 'LOW' ;;
    password) [ "${#c}" -ge 6 ] && printf 'HIGH' || printf 'MEDIUM' ;;
    *) [ "${#c}" -ge 8 ] && printf 'HIGH' || printf 'MEDIUM' ;;
  esac
}

# The driver only ever passes -s, and only first.
[ "${1:-}" = "-s" ] && shift 2

cmd="${1:-}"
shift || true

case "$cmd" in
  devices) cat "$D/devices"; exit 0 ;;
  wait-for-device) exit 0 ;;
  install)
    trace "install ${*}"
    # A real `adb install` prints Success or Failure, and across platform-tools
    # versions has exited 0 for both — which is why the driver reads the text.
    if [ "$(knob install_fails 0)" = "1" ]; then
      echo "Performing Streamed Install"
      echo "adb: failed to install $*: Failure [INSTALL_FAILED_INVALID_APK: Failed to extract native libraries]"
      exit "$(knob install_rc 0)"
    fi
    echo "Performing Streamed Install"
    echo "Success"
    exit 0
    ;;
  uninstall) trace "$cmd ${*}"; exit 0 ;;
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
INSTRUMENTATION_STATUS: stack=org.junit.AssumptionViolatedException: reason=${2:-$(knob skip_reason not-a-device-owner)}
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
  local cls="" kcase="" short verdict secure cx seal_cx
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
    K1ObserveTest) verdict="$(knob verdict_observe pass)" ;;
    *) verdict=fail ;;
  esac

  case "$verdict" in
    fail) emit_fail "$cls"; return ;;
    skip) emit_skip "$cls"; return ;;
    crash) emit_crash; return ;;
  esac

  [ -n "$(cred)" ] && secure=true || secure=false
  cx="$(bucket)"

  # K1SealTest's own refusal: a case that is secure on both sides and a device
  # that will not bucket its credential means nothing can witness the mutation.
  # The real test declines with assumeTrue; the driver must turn that into a
  # NOT REACHABLE row rather than into an error or, worse, a row.
  if [ "$short" = "K1SealTest" ] && [ "$cx" = "unreadable" ]; then
    case "$kcase" in
      M2 | M3 | M4)
        emit_skip "$cls" "no-credential-change-witness"
        return
        ;;
    esac
  fi

  emit_pass "$cls"
  case "$short" in
    K1SealTest)
      printf '%s' "$cx" >"$D/cx_seal"
      k1_log "phase=seal case=$kcase deviceSecure=$secure complexity=$cx securityLevel=TEE"
      ;;
    K1AdminResetTest)
      # The forced reset destroys the credential — K1Case.M6 is endsSecure=false.
      set_cred "" none
      k1_log "phase=admin-reset case=$kcase deviceSecure=false"
      ;;
    K1ObserveTest)
      k1_log "phase=observe case=- deviceSecure=$secure complexity=$cx"
      ;;
    K1OpenTest)
      seal_cx=$(cat "$D/cx_seal" 2>/dev/null || printf 'unreadable')
      if [ "$(knob open_no_verdict 0)" = "1" ]; then
        k1_log "phase=open case=$kcase deviceSecure=$secure complexityAtSeal=$seal_cx complexity=$cx securityLevel=TEE"
      else
        k1_log "phase=open case=$kcase deviceSecure=$secure complexityAtSeal=$seal_cx complexity=$cx securityLevel=TEE verdict=PASS"
      fi
      ;;
  esac
}

case "${1:-}" in
  getprop) prop "${2:-}" ;;

  input | wm) : ;;

  pm)
    # `pm list instrumentation` is what the driver checks before any case runs:
    # `am instrument` resolves an instrumentation entry, not a package, and an
    # APK that installs without one is instrumentable by nothing. The
    # no_instrumentation knob models exactly that.
    if [ "${2:-}" = "list" ] && [ "${3:-}" = "instrumentation" ]; then
      if [ "$(knob no_instrumentation 0)" != "1" ]; then
        echo "instrumentation:com.bittr.android.core.keystore.probe.test/androidx.test.runner.AndroidJUnitRunner (target=com.bittr.android.core.keystore.probe.test)"
      fi
      echo "instrumentation:com.example.other/androidx.test.runner.AndroidJUnitRunner (target=com.example.other)"
    fi
    # `pm list features` is the driver's preflight question "does this image
    # admit to having a secure lock screen". The no_secure_lock_screen knob is a
    # stripped image (aosp_atd is the one K1 met) that answers no.
    if [ "${2:-}" = "list" ] && [ "${3:-}" = "features" ]; then
      echo "feature:android.hardware.touchscreen"
      if [ "$(knob no_secure_lock_screen 0)" != "1" ]; then
        echo "feature:android.software.secure_lock_screen"
      fi
      echo "feature:android.software.app_widgets"
    fi
    ;;

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
        trace "locksettings-verify ${*}"
        # Models the API 34 `default` image as run #6 found it: exit 0 for
        # EVERYTHING — the credential just set, a deliberately wrong one, and a
        # bare `verify` with no argument.
        #
        # Kept, and kept broken, on purpose. The driver no longer calls it, and
        # this is the regression test for that: if a future edit reintroduces a
        # host-side credential check, this stub will cheerfully agree with it and
        # the scenarios below will catch the false green it produces.
        rc=0
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
        # The credential's type, which is what getPasswordComplexity() buckets by
        # and therefore what makes M3 (password) distinguishable from M4 (pattern)
        # on the device side.
        case "$sub" in
          set-pin) newtype=pin ;;
          set-password) newtype=password ;;
          set-pattern) newtype=pattern ;;
        esac
        if [ "$is_mutation" = "0" ]; then
          # Count the bare `set-pin` calls. The driver now makes one in its
          # preflight and one per case, and the two failure modes are different
          # findings: an image that never stores a credential is refused before
          # the matrix starts, while one that stops storing partway through is a
          # per-case ERROR. A single knob cannot tell them apart, so
          # setup_noop_after N no-ops every bare set-pin after the first N.
          n=$(cat "$D/setpins" 2>/dev/null || echo 0)
          n=$((n + 1))
          printf '%s' "$n" >"$D/setpins"
        fi
        if [ "$old" != "$(cred)" ]; then
          rc=1
        elif [ "$is_mutation" = "0" ] && [ "$(knob setup_noop 0)" = "1" ]; then
          rc=0
        elif [ "$is_mutation" = "0" ] && [ -n "$(knob setup_noop_after "")" ] &&
          [ "$n" -gt "$(knob setup_noop_after 0)" ]; then
          rc=0
        elif [ "$is_mutation" = "0" ]; then
          set_cred "$new" "$newtype"
          rc=0
        elif [ "$(knob mutation_fails 0)" = "1" ]; then
          rc=1
        elif [ "$(knob mutation_noop 0)" = "1" ]; then
          # Exits 0, changes nothing. The false green this whole test exists for.
          rc=0
        elif [ "$(knob mutation_wipes 0)" = "1" ]; then
          # Reported success and left the device with NO credential at all. On the
          # old host-side witness this was indistinguishable from a device that
          # simply had a credential, because `verify --old` answers yes either
          # way. The keyguard reading sees it immediately.
          set_cred "" none
          rc=0
        elif [ -n "$(knob mutation_lands_on "")" ]; then
          # Landed, but not where it was aimed. mutation_lands_on_type aims it at
          # a different credential TYPE as well, which is the shape that bucket
          # comparison catches and a value-only check would not.
          set_cred "$(knob mutation_lands_on "")" "$(knob mutation_lands_on_type "$newtype")"
          rc=0
        else
          set_cred "$new" "$newtype"
          rc=0
        fi
        ;;
      clear)
        old=""
        [ "${1:-}" = "--old" ] && old="${2:-}"
        # Counted for the same reason bare set-pin is: the driver's preflight
        # clears the credential it just set, so a device-wide clear fault is a
        # refusal before the matrix starts, while one that begins after the
        # preflight is M5's mutation failing and belongs in M5's row. The
        # *_after knobs aim at the second without disturbing the first.
        c=$(cat "$D/clears" 2>/dev/null || echo 0)
        c=$((c + 1))
        printf '%s' "$c" >"$D/clears"
        if [ "$(knob clear_fails 0)" = "1" ]; then
          rc=1
        elif [ -n "$(knob clear_fails_after "")" ] && [ "$c" -gt "$(knob clear_fails_after 0)" ]; then
          rc=1
        elif [ "$old" != "$(cred)" ]; then
          rc=1
        elif [ "$(knob clear_noop 0)" = "1" ]; then
          rc=0
        elif [ -n "$(knob clear_noop_after "")" ] && [ "$c" -gt "$(knob clear_noop_after 0)" ]; then
          rc=0
        else
          set_cred "" none
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
  printf 'none' >"$FAKE/credtype"
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
start_cred() { printf '%s' "$1" >"$FAKE/cred"; printf '%s' "${2:-pin}" >"$FAKE/credtype"; }

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

# Substring tests are bash's own, not `printf | grep -qF`.
#
# Under `set -o pipefail` that pipeline reports the pipe's status as well as
# grep's, and `grep -q` exits the moment it matches — so a large enough $OUT
# leaves printf writing into a closed pipe, and a SIGPIPE turns a match into a
# reported non-match. The dangerous direction is refute_out, where it turns into
# a silent PASS: "the output does not contain this" is exactly what a test
# harness must never say by accident. This suite exists to keep false greens out
# of K1's table and it should not have that shape in itself.
#
# `case` also removes two processes per assertion, which is most of this suite's
# runtime.
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

expect_out() {
  if contains "$OUT" "$1"; then
    pass_check "output contains: $1"
  else
    fail_check "output contains: $1" "output follows:
$(printf '%s\n' "$OUT" | sed 's/^/        | /')"
  fi
}

refute_out() {
  if contains "$OUT" "$1"; then
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
expect_out "the credential complexity is MEDIUM both before and after the mutation"
# The driver must not even ask the question: running the open phase against an
# unmutated device produces a green that means nothing, and a green is what gets
# quoted later.
refute_trace "instrument K1OpenTest M2"

scenario "an image that never stores a credential is refused before any case runs"
# `locksettings set-pin` exits 0 and stores nothing — the shape run #3 hit on
# aosp_atd API 34, where the device then reported isDeviceSecure=false and five
# rows blamed the seal phase for it. No case can reach a start state on such an
# image, so the matrix must refuse it up front rather than produce rows about a
# mutation that never happened.
knob setup_noop 1
run_driver M2
expect_rc 2
refute_out "| M2 | PASS |"
expect_out "still reports itself as having no lock screen"
# The install now happens BEFORE this refusal, and that is the point rather than
# a regression. The question "will this image hold a lock screen" is asked of the
# device through K1ObserveTest, so there is nothing to ask until the probe is on
# it. What must still be true is that no CASE is spent.
expect_trace "install"
refute_trace "instrument K1SealTest M2"
refute_trace "instrument K1OpenTest M2"

scenario "a credential refusal quotes the device, not the driver's conclusion"
# The refusal message is the entire content of such a run — no table, no
# artefact, and the step log behind a 403. "The PIN did not take" is the
# driver's reading; what makes the next step obvious is the device's own words,
# so the observation goes in verbatim.
knob setup_noop 1
run_driver M2
expect_rc 2
expect_out "What the device answered:"
expect_out "phase=observe"
expect_out "deviceSecure=false"

scenario "an image that stops storing credentials mid-run is a per-case ERROR"
# The preflight's set-pin works, so the matrix starts; the one for M2's start
# state exits 0 and stores nothing. This has to be caught before the seal phase
# is spent on it, or the row names the seal phase for a setup failure.
knob setup_noop_after 1
run_driver M2
expect_rc 1
refute_out "| M2 | PASS |"
expect_out "| M2 | ERROR |"
expect_out "the device still reports no lock screen; the start state was never reached"
refute_trace "instrument K1SealTest M2"
refute_trace "instrument K1OpenTest M2"

scenario "an image with no secure_lock_screen feature is refused"
# What the image claims, as opposed to what it does. Checked on API 29+ only —
# the feature constant does not exist below that, so its absence there means
# nothing and must not refuse a device that works.
knob no_secure_lock_screen 1
run_driver M2
expect_rc 2
expect_out "does not declare android.software.secure_lock_screen"
refute_trace "instrument K1SealTest M2"

scenario "a clear that exits 0 and removes nothing is not a PASS"
# M5's mutation IS a clear, so this is the false green the case is most exposed
# to: the credential is still there and the key 'survived' a removal that never
# happened. Aimed past the preflight's own clear so it lands on the mutation.
knob clear_noop_after 1
run_driver M5
expect_rc 1
refute_out "| M5 | PASS |"
expect_out "| M5 | ERROR |"
refute_trace "instrument K1OpenTest M5"

scenario "a device that cannot clear its lock screen at all is refused up front"
knob clear_noop 1
run_driver M5
expect_rc 2
refute_out "| M5 | PASS |"
expect_out "could not clear the lock screen"
refute_trace "instrument K1SealTest M5"

scenario "a PIN change that wipes the credential entirely is not a PASS"
# M2 aims PIN -> longer PIN and the device ends with no credential at all. The
# complexity bucket DID move (MEDIUM -> NONE), so the witness that carries M2 is
# satisfied and would sign off on this row — the keyguard check is what catches
# it, and the row must describe an M5 rather than the M2 it aimed for.
knob mutation_wipes 1
run_driver M2
expect_rc 1
refute_out "| M2 | PASS |"
expect_out "| M2 | ERROR |"
expect_out "must end deviceSecure=true"
refute_trace "instrument K1OpenTest M2"

scenario "a set-password that in fact set a pattern is a PASS with the divergence named"
# The honest limit of the device-side witness, made explicit rather than left
# for someone to discover while quoting a row.
#
# Nothing public on Android reports the credential's TYPE, so a set-password that
# landed as a pattern cannot be refuted — the credential did change, the device
# is still secure, and the key's survival is a real observation either way. What
# K1 can see is that the bucket is LOW where a password predicts HIGH.
#
# That is recorded as a note against a row that still passes, and deliberately
# not as an ERROR: the bucket table is AOSP documentation, and a device that
# buckets differently would turn the whole matrix red on the strength of the
# very thing this test exists to distrust.
knob mutation_lands_on 1236
knob mutation_lands_on_type pattern
run_driver M3
expect_rc 0
expect_out "| M3 | PASS |"
expect_out "complexity:MEDIUM->LOW"
expect_out "AOSP's table predicts"

scenario "the driver never asks locksettings verify anything"
# The regression guard for run #6. This fake's `verify` exits 0 for everything,
# faithfully, so any host-side credential check reintroduced into the driver
# would be answered yes and would produce exactly the false green that six runs
# of this test were spent discovering. The defence is that the call is not made.
run_driver
expect_rc 0
refute_trace "locksettings-verify"

scenario "the witness column carries the observed transition, not a label"
# A reader deciding whether to quote a row should see the evidence, not the
# driver's summary of its own evidence.
run_driver M1 M4 M5
expect_rc 0
expect_out "secure:false->true+complexity:NONE->MEDIUM"
expect_out "secure:true->true+complexity:MEDIUM->LOW"
expect_out "secure:true->false+complexity:MEDIUM->NONE"

# ---------------------------------------------------------------------------
# Where the device cannot witness the mutation at all
# ---------------------------------------------------------------------------

scenario "on API 26 the secure-on-both-sides cases are NOT REACHABLE, not PASS"
# getPasswordComplexity() arrived in API 29. Below it nothing on the device can
# see a PIN -> PIN change happen: secure before, secure after, and no bucket to
# compare. BIT-18 asks for that mutation, so the answer is a recorded NOT
# REACHABLE with the reason — "K1 cannot witness this on API 26" is a true and
# useful sentence, where a green row would be a survival claim about a change
# nothing observed.
prop ro.build.version.sdk 26
run_driver
expect_rc 0
for c in M2 M3 M4; do
  expect_out "| $c | NOT REACHABLE |"
  refute_out "| $c | PASS |"
done
expect_out "no-credential-change-witness"
# And the cases that DO have a keyguard witness still run: an API-26 row is
# three results short, not empty.
expect_out "| M1 | PASS |"
expect_out "| M5 | PASS |"
# The refusal is the device's, made in the seal phase. The driver must not
# pre-empt it from $API — that inference is the mistake the isUnlockedDeviceRequired
# guard already made once.
expect_trace "instrument K1SealTest M2"
refute_trace "instrument K1OpenTest M2"

scenario "a device that will not report complexity is treated the same way"
# Same refusal, different cause: a modern API where getPasswordComplexity()
# throws rather than answers — an OEM that hardened a `normal` permission. The
# driver must not infer readability from the API level any more than it infers
# the API level from readability.
knob complexity_unreadable 1
run_driver
expect_rc 0
for c in M2 M3 M4; do expect_out "| $c | NOT REACHABLE |"; done
expect_out "| M1 | PASS |"
expect_out "| M5 | PASS |"
# The run still succeeds: nothing failed, three questions were unanswerable.
expect_out "every case run produced a result"

scenario "an observation that does not come back is not read as 'no lock screen'"
# Fail-closed, in the direction that protects a device rather than the one that
# produces rows. An unanswered observe must leave the driver believing the lock
# screen is still there, so reset_to_none keeps trying to remove it instead of
# reporting a removal that never happened — and no case is spent on a device
# whose state is unknown.
knob verdict_observe fail
run_driver M2
expect_rc 2
refute_out "| M2 | PASS |"
expect_out "could not clear the lock screen"

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

scenario "a device whose lock screen cannot be cleared is refused"
# It starts with a credential the driver cannot remove, so it can never reach
# M1's start state and nothing downstream would describe the device it ran on.
# Refused before any case is spent — the install precedes it now, because the
# question is asked of the device through K1ObserveTest.
start_cred 0000
knob clear_fails 1
run_driver M2
expect_rc 2
expect_out "could not clear the lock screen"
refute_out "| M2 | PASS |"
refute_trace "instrument K1SealTest M2"

scenario "a lock screen that stops clearing after the matrix starts is an ERROR"
# Same fault, arriving later: the preflight passes, so there is a table, and M5
# — whose mutation *is* a clear — reports the failed command instead of the run
# vanishing with no rows at all.
knob clear_fails_after 1
run_driver M5
expect_rc 1
refute_out "| M5 | PASS |"
expect_out "| M5 | ERROR |"
expect_out "the locksettings mutation command failed"

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

# ---------------------------------------------------------------------------
# The install has to be verified, not assumed
# ---------------------------------------------------------------------------
#
# Run #2 of the CI workflow produced five rows of `ERROR | seal`, each saying
# "seal phase failed", for a reason three steps upstream of the row. Anything
# that makes every case fail its first instrumentation looks identical in the
# table, and the table is the only thing that gets out — so the driver has to
# stop at the cause. Both shapes below are ones `adb` reports without failing.

scenario "an install that prints Failure and exits 0 stops the run"
# The classic: across platform-tools versions `adb install` has printed
# `Failure [INSTALL_FAILED_...]` on stdout and still exited 0. Reading only the
# exit status turns that into six cases that cannot possibly pass.
knob install_fails 1
knob install_rc 0
run_driver M2
expect_rc 1
expect_out "installing"
expect_out "INSTALL_FAILED_INVALID_APK"
refute_trace "instrument"

scenario "an install that fails and exits non-zero also stops the run"
knob install_fails 1
knob install_rc 1
run_driver M2
expect_rc 1
refute_trace "instrument"

scenario "an APK with no registered instrumentation stops the run"
# Installs perfectly, and `am instrument` can resolve nothing. The driver must
# say that rather than report it once per case as a failed seal.
knob no_instrumentation 1
run_driver M2
expect_rc 1
expect_out "is not registered as an instrumentation"
expect_out "am instrument cannot resolve it"
refute_trace "instrument"

scenario "a good install reports what it verified"
run_driver M2
expect_rc 0
expect_out "instrumentation androidx.test.runner.AndroidJUnitRunner registered"

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
# The CI wrapper
# ---------------------------------------------------------------------------
#
# android/scripts/k1-ci.sh is what .github/workflows/k1-keystore-lockscreen.yml
# runs on the emulator, and it is the thing that decides whether the JOB goes
# green. A wrapper that swallowed the driver's exit status would turn every
# shape of failure the section above pins down into a green tick on the run
# page — the driver would be right and nobody would ever read it.
#
# The step summary matters for the same reason. It is where a row gets read
# from, so a run that produced no table must say so there rather than leaving
# the previous run's heading standing alone above nothing.

run_ci() {
  cp "$CI_WRAPPER" "$SANDBOX/android/scripts/k1-ci.sh"
  set +e
  OUT=$(cd "$SANDBOX" && PATH="$BIN:$PATH" K1_FAKE_DIR="$FAKE" \
    K1_OUT="k1-results/api-33.md" K1_API_LEVEL=33 \
    GITHUB_STEP_SUMMARY="$SANDBOX/summary.md" "$@" \
    bash android/scripts/k1-ci.sh 2>&1)
  RC=$?
  set -e
}

# The annotation is the only copy of the table a reader without repository admin
# can get (k1-ci.sh, "Publishing the table somewhere it can actually be read").
# test-k1-annotation.sh pins the escaping; these checks pin that the wrapper still
# EMITS one, and that the table is inside it rather than beside it. Deleting the
# annotate call would otherwise break nothing any test could see.
annotation_line() {
  printf '%s\n' "$OUT" | grep -E '^::(notice|error) title=K1 API' | tail -n 1
}

expect_annotation() {
  # expect_annotation <level> <substring that must be in the message>
  local line
  line=$(annotation_line)
  if [ -z "$line" ]; then
    fail_check "annotation emitted ($1)" "no ::$1 line in the wrapper output"
    return
  fi
  case "$line" in
    "::$1 "*) pass_check "annotation emitted at level $1" ;;
    *) fail_check "annotation emitted at level $1" "got: ${line%%::*}::" ;;
  esac
  if contains "$line" "$2"; then
    pass_check "annotation carries: $2"
  else
    fail_check "annotation carries: $2" "annotation follows:
        | $line"
  fi
  # One physical line, or GitHub keeps only the first row of the table.
  if [ "$(printf '%s\n' "$OUT" | grep -cE '^::(notice|error) title=K1 API')" = "1" ]; then
    pass_check "exactly one annotation (GitHub caps 10 per level)"
  else
    fail_check "exactly one annotation (GitHub caps 10 per level)" \
      "$(printf '%s\n' "$OUT" | grep -cE '^::(notice|error) title=K1 API') emitted"
  fi
}

expect_summary() {
  if [ -f "$SANDBOX/summary.md" ] && grep -qF -- "$1" "$SANDBOX/summary.md"; then
    pass_check "job summary contains: $1"
  else
    fail_check "job summary contains: $1" \
      "summary follows:
$(sed 's/^/        | /' "$SANDBOX/summary.md" 2>&1)"
  fi
}

scenario "the CI wrapper runs the matrix and publishes the table"
run_ci
expect_rc 0
if grep -q '| M2 | PASS |' "$SANDBOX/k1-results/api-33.md" 2>/dev/null; then
  pass_check "the table lands in K1_OUT"
else
  fail_check "the table lands in K1_OUT" "$(cat "$SANDBOX/k1-results/api-33.md" 2>&1)"
fi
expect_summary "## K1 — API 33"
expect_summary "| M2 | PASS |"
expect_summary "Every row PASS"
# The fingerprint is the difference between evidence and an anecdote.
expect_out "google/sdk_gphone64_x86_64"
# A green run annotates at `notice`, with the table escaped onto one line.
expect_annotation notice "%0A| M2 | PASS |"

scenario "a failing row fails the CI job"
# The row the whole test exists to catch: the key did NOT survive. A wrapper
# that exits 0 here reports a rule-2 contradiction as a green tick.
knob verdict_open fail
run_ci
if [ "$RC" -ne 0 ]; then
  pass_check "nonzero exit"
else
  fail_check "nonzero exit" "the wrapper swallowed a FAIL row"
fi
expect_summary "Not every row is PASS"
# A red run annotates at `error`, so it shows on the run page as the failure
# reason instead of "The process '/usr/bin/sh' failed with exit code 1".
expect_annotation error "| M2 | **FAIL** |"

scenario "a mutation that silently did not happen fails the CI job"
knob mutation_noop 1
run_ci
if [ "$RC" -ne 0 ]; then
  pass_check "nonzero exit"
else
  fail_check "nonzero exit" "the wrapper reported an unwitnessed run as green"
fi
expect_summary "Not every row is PASS"

scenario "a run that produced no table says so in the summary"
# The driver refuses before writing anything; the summary must not be left
# implying a table exists.
prop ro.build.version.sdk 25
run_ci
if [ "$RC" -ne 0 ]; then
  pass_check "nonzero exit"
else
  fail_check "nonzero exit" "a refused run reported success"
fi
expect_summary "The matrix produced no table"
# Especially here: with no table at all, the annotation is the ONLY thing a
# reader without admin gets, so it must say what happened rather than be absent.
expect_annotation error "The matrix produced no table"

scenario "M6 is off unless the workflow asks for it"
run_ci
refute_trace "dpm set-device-owner"

scenario "K1_WITH_DEVICE_OWNER=1 reaches the driver"
run_ci env K1_WITH_DEVICE_OWNER=1
expect_rc 0
expect_out "| M6 |"

# ---------------------------------------------------------------------------

echo
printf 'test-k1-driver: %d checks, %d failed\n' "$checks" "$failures"
if [ "$failures" -ne 0 ]; then exit 1; fi
