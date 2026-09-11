#!/usr/bin/env bash
#
# BIT-18 / K1 — does a non-auth-bound Keystore key survive a lock-screen change?
#
# BIT-8 rule 2 says the Android seed blob is wrapped by a Keystore key with no
# setUserAuthenticationRequired(true) and no setUnlockedDeviceRequired(true). The
# premise underneath that rule is that Keystore's documented lock-screen
# invalidation applies only to auth-bound keys. Today that premise rests on AOSP
# javadoc. Documentation is not a device and OEM builds diverge, so this script
# turns it into a per-device fact.
#
# Usage, with exactly one device attached (or -s <serial>):
#
#   bash android/scripts/k1-lockscreen-matrix.sh                 # all reachable cases
#   bash android/scripts/k1-lockscreen-matrix.sh M2 M5           # named cases only
#   bash android/scripts/k1-lockscreen-matrix.sh --with-device-owner   # adds M6
#   bash android/scripts/k1-lockscreen-matrix.sh -s emulator-5554 --out results/api33.md
#
# WHY THIS IS A SCRIPT AND NOT `connectedAndroidTest`
#
# The claim under test is that the key survives across a lock-screen mutation in
# a process that did not exist when the key was made. That needs three things
# Gradle cannot sequence on its own:
#
#   1. seal the blob                       (am instrument -c ...K1SealTest)
#   2. mutate the lock screen              (adb shell locksettings ...)  <-- host side
#   3. force-stop, then open the blob      (am instrument -c ...K1OpenTest)
#
# `connectedAndroidTest` runs 1 and 3 back to back with nothing in between. That
# does not silently pass: K1OpenTest asserts the *post*-mutation keyguard state
# first, so an unmutated run fails its start-state assertion instead of
# reporting a false green. But it also produces no K1 row, which is why the
# module's build file says so and why the matrix lives here.
#
# WHAT COUNTS AS A RESULT
#
# The expensive failure for this test is a false green: a run where the mutation
# silently did not happen, the key "survived" something that never occurred, and
# the row gets quoted in a security statement. Four independent things have to
# line up before a row is written PASS:
#
#   - the instrumentation exited 0 for both phases
#   - phase 2 emitted a `verdict=PASS` line (a green exit with no line is a
#     harness failure here, not a pass)
#   - the device-side witnesses in K1OpenTest passed: the KeyguardManager
#     transition, and for the credential-destroying cases the auth-bound control
#     key being gone
#   - the host-side witness observed the credential actually change, and change
#     into the thing the case says it changed into
#
# The last one is what carries M2/M3/M4, where the device is secure on both
# sides of the mutation and KeyguardManager cannot tell that anything happened.
# `locksettings verify` against the OLD credential must succeed before and fail
# after, and against the NEW one must fail before and succeed after. Without it
# those three rows would rest on the driver's say-so.
#
# The driver is exercised against a fake device — including each of those
# failure shapes — by android/scripts/test-k1-driver.sh, which needs no device
# and no Android SDK. Run it after touching anything in here.
#
# SAFETY — READ BEFORE POINTING THIS AT YOUR PHONE
#
# This sets, changes and removes the device lock screen. On a physical device
# that is your real lock screen, and a failure partway through can leave the
# device on the script's PIN (5678) rather than yours. Every case restores the
# device to "no lock screen" on exit, and the PIN in use is printed on failure.
# It refuses to touch a device holding user accounts unless --i-know overrides.
#
# M6 (device-owner forced credential reset) needs `dpm set-device-owner`, which
# cannot be undone without a factory reset. It is off by default, gated behind
# --with-device-owner, and refused outright on anything not recognised as an
# emulator.
#
# Never run this against a device holding a real wallet. The blob under test is
# a known constant, not a seed — but the lock-screen mutation is real.
set -euo pipefail

MODULE_PATH=":core:keystore-probe"
TEST_PKG="com.bittr.android.core.keystore.probe.test"
TEST_CLASS_ROOT="com.bittr.android.core.keystore.probe"
RUNNER="androidx.test.runner.AndroidJUnitRunner"
ADMIN_COMPONENT="${TEST_PKG}/${TEST_CLASS_ROOT}.K1DeviceAdminReceiver"

# The credentials the mutations move between. Nothing here is secret; they are
# printed on failure precisely so a physical device can be recovered by hand.
PIN_A="1234"
PIN_B="5678"
PASSWORD="k1pass99"
PATTERN="1236"

ALL_CASES="M1 M2 M3 M4 M5"
WITH_DEVICE_OWNER=0
FORCE=0
SERIAL=""
OUT=""

usage() {
  sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

cases=()
while [ $# -gt 0 ]; do
  case "$1" in
    -s) SERIAL="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --with-device-owner) WITH_DEVICE_OWNER=1; shift ;;
    --i-know) FORCE=1; shift ;;
    -h|--help) usage 0 ;;
    M[1-6]|m[1-6]) cases+=("$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"); shift ;;
    *) echo "k1: unknown argument '$1'" >&2; usage 2 ;;
  esac
done

if [ ${#cases[@]} -eq 0 ]; then
  read -r -a cases <<<"$ALL_CASES"
  [ "$WITH_DEVICE_OWNER" -eq 1 ] && cases+=("M6")
fi

for c in "${cases[@]}"; do
  if [ "$c" = "M6" ] && [ "$WITH_DEVICE_OWNER" -eq 0 ]; then
    echo "k1: M6 needs --with-device-owner (it sets a device owner, which needs a" >&2
    echo "    factory reset to undo). Refusing to infer that from a bare 'M6'." >&2
    exit 2
  fi
done

cd "$(git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# adb plumbing
# ---------------------------------------------------------------------------

if ! command -v adb >/dev/null 2>&1; then
  echo "k1: adb not found. Add \$ANDROID_HOME/platform-tools to PATH." >&2
  exit 127
fi

adb_args=()
[ -n "$SERIAL" ] && adb_args=(-s "$SERIAL")

a() { adb "${adb_args[@]}" "$@"; }
sh_() { a shell "$@"; }

# `adb shell` reports the *shell's* exit status only when asked, and on some
# images swallows it entirely. Everything that needs a real status goes through
# here: echo a sentinel and read it back, which works on every API in the matrix.
# Substring tests here are bash's own rather than `printf | grep -q`. Under the
# `set -o pipefail` at the top of this file, that pipeline reports the pipe's
# status too, and `grep -q` exits on first match — so a long enough $out leaves
# printf writing into a closed pipe and a SIGPIPE turns a match into a reported
# non-match. In sh_status that would mean an adb command that succeeded being
# reported as failed, which is the sentinel's whole job. `case` cannot do that,
# and costs no processes.
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

sh_status() {
  local out
  out=$(a shell "$* ; echo __k1_rc=\$?" 2>&1 | tr -d '\r')
  printf '%s\n' "$out" | sed '/__k1_rc=/d'
  contains "$out" '__k1_rc=0'
}

device_count=$(adb devices | grep -cE '[[:space:]]device$' || true)
if [ -z "$SERIAL" ] && [ "$device_count" -ne 1 ]; then
  echo "k1: expected exactly one attached device, found $device_count. Use -s <serial>." >&2
  adb devices >&2
  exit 2
fi

a wait-for-device >/dev/null

API=$(sh_ getprop ro.build.version.sdk | tr -d '\r')
MANUFACTURER=$(sh_ getprop ro.product.manufacturer | tr -d '\r')
MODEL=$(sh_ getprop ro.product.model | tr -d '\r')
FINGERPRINT=$(sh_ getprop ro.build.fingerprint | tr -d '\r')
DEVICE_LABEL="${MANUFACTURER}/${MODEL} (API ${API})"

# ro.kernel.qemu is the classic marker; ro.boot.qemu and the goldfish/ranchu
# hardware names cover the images where it was dropped.
is_emulator() {
  case "$(sh_ getprop ro.hardware | tr -d '\r')" in goldfish*|ranchu*) return 0 ;; esac
  [ "$(sh_ getprop ro.kernel.qemu | tr -d '\r')" = "1" ] && return 0
  [ "$(sh_ getprop ro.boot.qemu | tr -d '\r')" = "1" ] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Refusals — before anything is installed or any credential is touched
# ---------------------------------------------------------------------------

if ! is_emulator && [ "$FORCE" -eq 0 ]; then
  accounts=$(sh_ dumpsys account 2>/dev/null | grep -c 'Account {' || true)
  if [ "${accounts:-0}" -gt 0 ]; then
    echo "k1: $DEVICE_LABEL is a physical device holding $accounts account(s)." >&2
    echo "    This script sets, changes and REMOVES the lock screen. Re-run with" >&2
    echo "    --i-know once you are sure this is a test handset." >&2
    exit 2
  fi
fi

if [ "$WITH_DEVICE_OWNER" -eq 1 ] && ! is_emulator; then
  echo "k1: refusing --with-device-owner on $DEVICE_LABEL — it is not an emulator." >&2
  echo "    A device owner cannot be removed without a factory reset. Run M6 on an" >&2
  echo "    emulator; record it as 'not reachable' on physical devices, which is a" >&2
  echo "    finding, not a gap." >&2
  exit 2
fi

if [ "$API" -lt 26 ]; then
  echo "k1: API $API is below the project's minSdk 26." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Lock-screen mutation, host side
# ---------------------------------------------------------------------------

# `locksettings` needs the screen on and unlocked on several images; a device
# sitting at a dark keyguard silently no-ops some of these.
wake() {
  sh_ input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  sh_ wm dismiss-keyguard >/dev/null 2>&1 || true
}

# A credential no case ever sets, used to ask one unambiguous question.
#
# `locksettings verify --old X` succeeds for EVERY X when no credential is set —
# there is nothing to check against, so the shell command has nothing to reject.
# That makes a bare `verify --old "$PIN_A"` two claims at once, "the credential
# is $PIN_A" and "there is no credential", and K1 spent run #4 unable to tell
# them apart: M2-M5 reported "the OLD credential still verifies after the
# mutation" (which is also what a device with NO credential looks like) while M1
# reported the device secure when the driver believed it had cleared it. Two
# opposite device states, one observation.
#
# A deliberately wrong credential separates them, because it can only verify on a
# device that has none.
JUNK_CRED="90197"

# True when the device has SOME lock-screen credential. The one primitive the
# other two are built on.
#
# Fails closed: an unreadable or unrecognised answer leaves this true ("still
# secure"), so reset_to_none keeps trying rather than reporting a clear that
# never happened.
#
# Costs one failed credential attempt when a credential IS set, and Android
# throttles after five in a row (30s lockout), so this is called at decision
# points rather than in loops. A successful verify resets that counter, which is
# why credential_is asks this one first and the positive check second.
device_has_credential() {
  ! sh_status "locksettings verify --old '$JUNK_CRED'" >/dev/null 2>&1
}

# True when $1 is the device's current credential. This is the witness that
# carries M2/M3/M4 — see WHAT COUNTS AS A RESULT above.
#
# Both halves are required. Without the first, this returns true on a device
# with no lock screen at all, which is the false green K1 is least able to
# afford: "the key survived a PIN change" reported from a device that never had
# a PIN.
credential_is() {
  device_has_credential || return 1
  sh_status "locksettings verify --old '$1'" >/dev/null 2>&1
}

# True when the device has no lock-screen credential at all.
#
# Deliberately the same tool the mutations use, rather than grepping `dumpsys
# trust` for a field name that is not stable across API 26-35.
has_no_credential() {
  ! device_has_credential
}

# Put the device in the state a case says it must start from, from whatever
# state the last case left behind. The device's own start state is unknown on
# the first call, hence the check before the loop.
reset_to_none() {
  wake
  has_no_credential && return 0
  for old in "$PIN_A" "$PIN_B" "$PASSWORD" "$PATTERN"; do
    # Re-probe only after a clear that claimed success.
    #
    # Both a wrong `clear --old` and a `device_has_credential` probe against a
    # device that still has one are failed credential attempts, and Android locks
    # the credential out for 30s after five in a row. Probing on every iteration
    # made this loop cost up to nine, which is past that line — and a lockout
    # here would surface as "could not clear the lock screen" on a device that
    # was merely being asked too fast. Cheap on an emulator that gets deleted
    # afterwards; not cheap on the Samsung and Xiaomi handsets, which are the
    # rows K1 actually exists for.
    if sh_status "locksettings clear --old '$old'" >/dev/null 2>&1; then
      has_no_credential && return 0
    fi
  done
  # One last look before giving up, in case a clear removed the credential while
  # reporting failure. Costs a probe only on the path that is already failing.
  has_no_credential && return 0
  echo "k1: could not clear the lock screen on $DEVICE_LABEL." >&2
  echo "    Credentials tried: $PIN_A $PIN_B $PASSWORD $PATTERN (pattern as digits)." >&2
  return 1
}

# ---------------------------------------------------------------------------
# Refusal — can this image hold a lock screen at all?
# ---------------------------------------------------------------------------
#
# K1 mutates the lock screen. An image that cannot hold one does not produce a
# red row, it produces six rows describing a mutation that never happened, and
# the cause lands three steps downstream of where it started. Run #3 spent a
# whole emulator boot to report five `ERROR | seal` rows whose real content was
# "the PIN never took".
#
# So the capability is established once, up front, against the device — not
# inferred from the API level, and not assumed because `locksettings` exited 0.
# It costs four adb round-trips and it runs before the APK is installed, because
# a device that fails this cannot produce a K1 result by any route.
#
# Deliberately a functional probe and not only a feature query. Both are checked
# and they answer different questions: `android.software.secure_lock_screen`
# (API 29+) is what the image *claims*, and set/verify/clear is what it *does*.
# The second has to exist because the first is absent on API 26-28 by definition
# and because a feature flag is another piece of documentation.
# The raw observations behind a credential refusal, not a conclusion drawn from
# them.
#
# Two different device behaviours produce an identical "the PIN did not take",
# and K1 has now been wrong about which one it was looking at:
#
#   (a) `set-pin` stores nothing. Then no `verify` has anything to check and they
#       all succeed, including the deliberately wrong one.
#   (b) `locksettings verify` always exits 0 on this image whatever is stored.
#       Then the credential may be perfectly well set and the WITNESS is what is
#       broken — and every host-side witness in this script is built on it,
#       including the one that carries M2/M3/M4.
#
# (b) is the more serious finding, because a witness that always says yes is how
# a false green gets made. Run #4 is consistent with it end to end: every
# `credential_is` answering yes explains M1 finding the device secure after a
# clear AND M2-M5 reporting the old credential surviving a change.
#
# So this prints what each form actually returned and lets the reader conclude.
# Three verifies, run once, on a device the run is abandoning anyway.
credential_probe_report() {
  echo "    What the device answered, raw — the same question three ways:"
  echo "      locksettings verify --old '$PIN_A'   (the credential just set)"
  if sh_status "locksettings verify --old '$PIN_A'" >/dev/null 2>&1; then
    echo "        -> exit 0 (accepted)"
  else
    echo "        -> non-zero (rejected)"
  fi
  echo "      locksettings verify --old '$JUNK_CRED'   (deliberately wrong)"
  if sh_status "locksettings verify --old '$JUNK_CRED'" >/dev/null 2>&1; then
    echo "        -> exit 0 (ACCEPTED — a wrong credential cannot verify on a device"
    echo "           that has one, so either nothing is stored or verify is not"
    echo "           checking. Every host-side witness in this script rests on this"
    echo "           call, so K1 has no usable witness on this image either way.)"
  else
    echo "        -> non-zero (rejected, which is correct: something IS stored, and"
    echo "           the failure above is then about '$PIN_A' specifically)"
  fi
  echo "      locksettings verify   (no --old)"
  if sh_status "locksettings verify" >/dev/null 2>&1; then
    echo "        -> exit 0"
  else
    echo "        -> non-zero"
  fi
}

lockscreen_preflight() {
  wake

  # What the image claims. API 29+ only: the feature constant does not exist
  # below it, so its absence there is meaningless rather than damning.
  if [ "$API" -ge 29 ]; then
    if ! sh_ pm list features 2>/dev/null | tr -d '\r' | grep -qx 'feature:android.software.secure_lock_screen'; then
      echo "k1: $DEVICE_LABEL does not declare android.software.secure_lock_screen." >&2
      echo "    This image has no secure lock screen, so there is nothing for K1 to" >&2
      echo "    mutate and every row it could produce would describe a mutation that" >&2
      echo "    did not happen. Stripped images (aosp_atd) are the usual cause; pick" >&2
      echo "    'default' or 'google_apis' in the image step of" >&2
      echo "    .github/workflows/k1-keystore-lockscreen.yml." >&2
      return 1
    fi
  fi

  # What the image does.
  reset_to_none || return 1

  if ! sh_status "locksettings set-pin '$PIN_A'" >/dev/null; then
    echo "k1: locksettings set-pin failed on $DEVICE_LABEL before any case ran." >&2
    return 1
  fi
  if ! credential_is "$PIN_A"; then
    echo "k1: on $DEVICE_LABEL, 'locksettings set-pin $PIN_A' exited 0 and the" >&2
    echo "    credential does not verify afterwards. K1 cannot witness a lock-screen" >&2
    echo "    mutation on this image, so it will not report rows about one." >&2
    echo >&2
    credential_probe_report >&2
    sh_ locksettings clear --old "$PIN_A" >/dev/null 2>&1 || true
    return 1
  fi

  # Leave nothing behind: M1 requires a device with no credential, and it is the
  # first case to run.
  if ! reset_to_none; then
    echo "k1: the preflight PIN could not be cleared again on $DEVICE_LABEL." >&2
    return 1
  fi

  echo "k1: lock screen is settable and clearable on $DEVICE_LABEL"
  return 0
}

if ! lockscreen_preflight; then
  echo "k1: refusing to run the matrix — see above." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Instrumentation
# ---------------------------------------------------------------------------

# Classify one `am instrument -w -r` output file. Echoes exactly one of
# `pass`, `skip` or `fail`.
#
# No adb in here on purpose: this is the function that decides whether a K1 row
# is green, so android/scripts/test-k1-verdict.sh exercises it directly against
# captured runner output. It is the only part of the driver that can be tested
# without a device, and it is the part whose bugs are false greens.
#
# `am instrument` exits 0 whatever happened, so the output text is the status.
# Two different things in that text are called a "code", and they mean opposite
# things:
#
#   INSTRUMENTATION_CODE: -1        is Activity.RESULT_OK. It says the *run*
#                                   completed, and it is printed identically for
#                                   a run whose every test failed. It is NOT a
#                                   pass and must never be read as one.
#   INSTRUMENTATION_STATUS_CODE:    is per test. 1 = started, 0 = passed,
#                                   -1 = error, -2 = assertion failure,
#                                   -3 = ignored, -4 = assumption failure.
#
# Order matters. `skip` is tested first because an assumption failure — how
# K1AdminResetTest reports "not reachable on this device" — still prints an
# `OK (1 test)` summary, so a pass-first reading would score it green.
#
# Anything unrecognised (a runner that never started, a process that died
# mid-run) falls through to `fail` rather than to silence.
run_verdict() {
  local f="$1"
  if grep -qE '^INSTRUMENTATION_STATUS_CODE: -4$' "$f" ||
    grep -q 'AssumptionViolatedException' "$f"; then
    echo skip
    return 0
  fi
  if grep -qE '^INSTRUMENTATION_STATUS_CODE: -[12]$' "$f" ||
    grep -q 'FAILURES!!!' "$f"; then
    echo fail
    return 0
  fi
  if grep -q 'OK (' "$f"; then
    echo pass
    return 0
  fi
  echo fail
}

# One `am instrument` invocation. Echoes the verdict; the raw output is left in
# $2 for the caller to read witnesses out of.
instrument() {
  local class="$1" outfile="$2" case_id="$3"
  a logcat -c >/dev/null 2>&1 || true
  # -w blocks; -r gives the raw status stream that carries K1Harness.sendStatus.
  sh_ "am instrument -w -r -e k1_case '$case_id' -e class '$class' '$TEST_PKG/$RUNNER'" \
    >"$outfile" 2>&1 || true
  run_verdict "$outfile"
}

k1_line() { a logcat -d -s K1:I 2>/dev/null | grep -oE 'phase=.*' | tail -n 1; }

# The decisive lines of a failed `am instrument` run, on ONE line, for the table.
#
# WHY THIS IS NOT JUST "SEE THE RUN LOG"
#
# It was, and that was a dead end. On this repository the step log needs
# repository admin to read (403), the artefact needs a token (401), and the job
# summary is not in the REST API at all — so "see the run log" pointed at the one
# place the reader could not go. Run #2 of the CI workflow came back with five
# rows of `ERROR | seal | - | seal phase failed — see the run log`, which says
# that the probe did not seal and nothing whatsoever about why.
#
# The table is the artefact that survives, and k1-ci.sh sends it out as an
# annotation, which is readable without credentials. So the cause has to travel
# in the table or it does not travel.
#
# Bounded deliberately: the first exception line plus the first few frames is
# what identifies a failure, and the annotation carrying it has a size limit that
# a full stack trace per row would blow. The untruncated output stays in the step
# log for anyone who does have admin.
failure_excerpt() {
  local f="$1" text
  # `stack=` is what AndroidJUnitRunner reports a throwable as; the bare
  # `Exception`/`Error` grep catches a runner that died before it could report one
  # (no instrumentation target, missing runner class, APK not installed), which is
  # precisely the shape that produces an identical ERROR row for every case.
  text=$(
    grep -hE 'stack=|^(java|android|kotlin|com\.bittr)[^ ]*(Exception|Error)|Exception:|Error:|INSTRUMENTATION_RESULT: shortMsg|Unable to find instrumentation|does not exist|Process crashed' "$f" 2>/dev/null |
      head -n 6 |
      sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
      tr '\n' '\a' |
      sed 's/\a/ · /g; s/ · $//'
  )
  if [ -z "$text" ]; then
    # No recognisable failure text is itself the finding — it means the runner
    # produced output this does not know how to read, and guessing would be worse
    # than saying so.
    text="no recognisable failure text in the instrumentation output (first line: $(head -n 1 "$f" | cut -c1-120))"
  fi
  # A `|` would split the markdown table cell this lands next to.
  printf '%s' "$text" | tr '|' '/' | cut -c1-600
}

# ---------------------------------------------------------------------------
# Build and install
# ---------------------------------------------------------------------------

echo "k1: $DEVICE_LABEL"
echo "k1: $FINGERPRINT"
echo "k1: cases ${cases[*]}"
echo

echo "k1: building $MODULE_PATH androidTest APK"
(cd android && ./gradlew --quiet "${MODULE_PATH}:assembleDebugAndroidTest")

apk=$(find "android/core/keystore-probe/build/outputs/apk/androidTest" -name '*.apk' | head -n 1)
if [ -z "$apk" ]; then
  echo "k1: no androidTest APK produced." >&2
  exit 1
fi

# Uninstall rather than -r: a leftover install from a previous run carries the
# previous run's no_backup state, and K1State.read would then find a sealed
# envelope belonging to a key that no longer exists.
a uninstall "$TEST_PKG" >/dev/null 2>&1 || true

# `adb install` is one of the commands this harness must not take at its word.
# Across platform-tools versions it has printed `Failure [INSTALL_FAILED_...]` on
# stdout and still exited 0, so `a install ... >/dev/null` can swallow a failed
# install whole. What follows is then six cases that each fail their first
# instrumentation and six identical ERROR rows saying "seal phase failed", which
# describes the symptom three steps downstream of the cause.
install_out=$(a install -t "$apk" 2>&1) || true
if ! contains "$install_out" 'Success'; then
  echo "k1: installing $apk failed." >&2
  printf '%s\n' "$install_out" | sed 's/^/    /' >&2
  exit 1
fi

# And then the thing `am instrument` actually resolves, which is not the package:
# it is the instrumentation entry the APK registers. A self-instrumenting
# androidTest APK whose <instrumentation> tag did not survive manifest merging
# installs perfectly and cannot be instrumented, and the failure text for that
# ("Unable to find instrumentation info") arrives per case rather than once.
#
# Checked here, once, so the run stops at the cause with the device's own answer
# quoted, instead of reporting a platform verdict it never measured.
if ! sh_ pm list instrumentation 2>/dev/null | tr -d '\r' | grep -qF "$TEST_PKG/$RUNNER"; then
  echo "k1: $TEST_PKG installed, but $RUNNER is not registered as an instrumentation." >&2
  echo "    am instrument cannot resolve it, so no case could produce a result." >&2
  echo "    The device reports:" >&2
  sh_ pm list instrumentation 2>/dev/null | tr -d '\r' | sed 's/^/      /' >&2
  exit 1
fi

echo "k1: installed $TEST_PKG, instrumentation $RUNNER registered"
echo

# ---------------------------------------------------------------------------
# Per-case run
# ---------------------------------------------------------------------------

rows=()
notes=()
overall=0

# The explicit `return 0` is load-bearing under `set -e`: without it the final
# `[ -n ... ]` becomes the function's exit status, so recording a row with no
# note — which is exactly what a PASS does — would abort the whole run after the
# first case that succeeded.
record() {
  rows+=("| $1 | $2 | $3 | $4 |")
  if [ -n "${5:-}" ]; then
    notes+=("**$1** — $5")
  fi
  return 0
}

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"; reset_to_none >/dev/null 2>&1 || true' EXIT

for case_id in "${cases[@]}"; do
  echo "k1: === $case_id ==="
  seal_out="$workdir/$case_id.seal"
  open_out="$workdir/$case_id.open"
  mutate_out="$workdir/$case_id.mutate"
  witness="not-applicable"

  # --- start state -------------------------------------------------------
  reset_to_none || { record "$case_id" "ERROR" "-" "-" "could not clear the lock screen"; overall=1; continue; }

  if [ "$case_id" != "M1" ]; then
    wake
    if ! sh_status "locksettings set-pin '$PIN_A'" >/dev/null; then
      record "$case_id" "ERROR" "-" "-" "locksettings set-pin failed; cannot reach the start state"
      overall=1
      continue
    fi
    # `set-pin` exiting 0 is not evidence that a credential exists — the same
    # lesson `adb install` taught above. Until run #3 this went unchecked until
    # the pre-mutation witness, which is two `am instrument` invocations later,
    # so the run spent the seal phase on a device it was wrong about and the
    # table blamed the seal phase. Verified here, the row names the setup.
    if ! credential_is "$PIN_A"; then
      record "$case_id" "ERROR" "-" "-" \
        "locksettings set-pin reported success but '$PIN_A' does not verify afterwards; the start state was never reached"
      overall=1
      continue
    fi
  fi

  # --- phase 1: seal -----------------------------------------------------
  # A skip is not a valid outcome for the seal phase — only K1AdminResetTest has
  # an assumption in it — so anything other than a pass is an error here.
  if [ "$(instrument "${TEST_CLASS_ROOT}.K1SealTest" "$seal_out" "$case_id")" != "pass" ]; then
    echo "k1: seal phase failed for $case_id"
    sed -n '1,40p' "$seal_out"
    note=""
    # The one seal failure that is a finding about the device rather than a bug
    # in the harness: the driver established the start state and verified it
    # through LockSettingsService, and KeyguardManager in the app process
    # disagrees. Those two read the same credential, so a divergence is the
    # platform contradicting itself — and it matters in BOTH directions. Run #4
    # hit the M1 one (host cleared the credential, device still reported secure)
    # having been built expecting only the M2-M5 one.
    #
    # Recorded with what the host actually observed, because "the driver did not
    # reach the start state" is the probe's reading and the row needs the other
    # side of the disagreement to be worth anything.
    if grep -q 'did not reach the start state' "$seal_out"; then
      if [ "$case_id" = "M1" ]; then
        note=" — NOTE: the host observed NO credential here (a deliberately wrong one verified,"
        note="$note which only happens on a device with none), yet the device reports itself secure."
      else
        note=" — NOTE: the host verified '$PIN_A' here and confirmed a wrong credential is"
        note="$note rejected, yet the device reports itself insecure."
      fi
      note="$note LockSettingsService and KeyguardManager disagree on this image; suspect it"
      note="$note (see the image step in .github/workflows/k1-keystore-lockscreen.yml)"
      note="$note before the driver."
    fi
    record "$case_id" "ERROR" "seal" "-" "seal phase failed; no verdict on rule 2 — $(failure_excerpt "$seal_out")$note"
    overall=1
    continue
  fi
  seal_line=$(k1_line)
  echo "k1:   seal  $seal_line"

  # --- phase 2: mutate ---------------------------------------------------
  # The old credential must verify *before* the mutation, so that its failure
  # afterwards means the mutation landed rather than that it never worked.
  # What must verify before the mutation, and what must verify after it. Both
  # halves are needed: see the witness section below.
  case "$case_id" in
    M1)     pre_cred="";        post_cred="$PIN_A" ;;
    M2)     pre_cred="$PIN_A";  post_cred="$PIN_B" ;;
    M3)     pre_cred="$PIN_A";  post_cred="$PASSWORD" ;;
    M4)     pre_cred="$PIN_A";  post_cred="$PATTERN" ;;
    M5|M6)  pre_cred="$PIN_A";  post_cred="" ;;
  esac
  if [ -n "$pre_cred" ] && ! credential_is "$pre_cred"; then
    record "$case_id" "ERROR" "-" "-" "the start credential did not verify before mutating; witness unusable"
    overall=1
    continue
  fi

  wake
  mutated=1
  case "$case_id" in
    M1) sh_status "locksettings set-pin '$PIN_A'" >/dev/null || mutated=0 ;;
    M2) sh_status "locksettings set-pin --old '$PIN_A' '$PIN_B'" >/dev/null || mutated=0 ;;
    M3) sh_status "locksettings set-password --old '$PIN_A' '$PASSWORD'" >/dev/null || mutated=0 ;;
    M4) sh_status "locksettings set-pattern --old '$PIN_A' '$PATTERN'" >/dev/null || mutated=0 ;;
    M5) sh_status "locksettings clear --old '$PIN_A'" >/dev/null || mutated=0 ;;
    M6)
      if ! sh_status "dpm set-device-owner '$ADMIN_COMPONENT'" >/dev/null; then
        record "$case_id" "NOT REACHABLE" "-" "-" \
          "dpm set-device-owner refused (an account or an existing owner is present)"
        continue
      fi
      # The reset token activates only after the existing credential is
      # confirmed once. This is the provocation; the test reports honestly if
      # it did not take on this image.
      wake
      sh_ input keyevent KEYCODE_SLEEP >/dev/null 2>&1 || true
      wake
      sh_ input text "$PIN_A" >/dev/null 2>&1 || true
      sh_ input keyevent KEYCODE_ENTER >/dev/null 2>&1 || true

      # This is the one place a `skip` is a real answer rather than a problem:
      # BIT-18 says "where reachable" of this mutation, and an unreachable M6 is
      # a finding to record, not a row to drop.
      case "$(instrument "${TEST_CLASS_ROOT}.K1AdminResetTest" "$mutate_out" "$case_id")" in
        pass) ;;
        skip)
          reason=$(grep -oE 'reason=[^ ]+' "$mutate_out" | tail -n 1)
          record "$case_id" "NOT REACHABLE" "-" "-" \
            "${reason:-the reset-password token could not be set or activated}"
          continue
          ;;
        *)
          record "$case_id" "ERROR" "mutate" "-" "K1AdminResetTest failed outright — $(failure_excerpt "$mutate_out")"
          overall=1
          continue
          ;;
      esac
      ;;
  esac

  if [ "$mutated" -eq 0 ]; then
    record "$case_id" "ERROR" "mutate" "-" "the locksettings mutation command failed; no verdict on rule 2"
    overall=1
    continue
  fi

  # --- the host-side witness --------------------------------------------
  # For M2/M3/M4 this is the only evidence the credential changed at all:
  # KeyguardManager reports secure on both sides, so K1OpenTest's device-side
  # witness cannot see these mutations happen.
  #
  # Two halves, and both are load-bearing:
  #
  #   negative — the OLD credential must stop verifying. Catches a mutation
  #              command that exits 0 and changes nothing.
  #   positive — the intended NEW credential must verify (or, for the cases
  #              that destroy it, no credential must). Catches a mutation that
  #              reported success and landed somewhere else: `set-password`
  #              that in fact cleared the lock screen satisfies the negative
  #              half perfectly, and the row would then say M3 while the device
  #              did M5. The key survives both, so the verdict would even be
  #              right — about the wrong mutation.
  #
  # The positive half fails closed. Where `locksettings verify` cannot check a
  # credential type on some image — a pattern passed as digits is the one to
  # watch — the row comes out ERROR ("no verdict") rather than PASS. That is the
  # correct direction for this test, but it does mean an ERROR here is a reason
  # to check the device by hand, not automatically a broken device.
  if [ -n "$pre_cred" ]; then
    if credential_is "$pre_cred"; then
      record "$case_id" "ERROR" "mutate" "-" \
        "the OLD credential still verifies after the mutation — nothing changed, so a survival result would be evidence of nothing"
      overall=1
      continue
    fi
    witness="old-credential-rejected"
  else
    witness="keyguard-transition"
  fi

  if [ -n "$post_cred" ]; then
    if ! credential_is "$post_cred"; then
      record "$case_id" "ERROR" "mutate" "-" \
        "the mutation reported success and the old credential is gone, but the credential $case_id aimed for does not verify either — the device is in an unknown state and this row would not describe the mutation it names"
      overall=1
      continue
    fi
    witness="${witness}+new-credential-set"
  else
    if ! has_no_credential; then
      record "$case_id" "ERROR" "mutate" "-" \
        "$case_id was supposed to destroy the credential, but the device still has one — the row would not describe the mutation it names"
      overall=1
      continue
    fi
    witness="${witness}+credential-gone"
  fi

  # --- phase 3: open, in a process that did not exist at seal time -------
  sh_ am force-stop "$TEST_PKG" >/dev/null 2>&1 || true

  # As with the seal phase, a skip is not a valid outcome here: K1OpenTest has no
  # assumption in it, so anything that is not a pass means no verdict on rule 2.
  if [ "$(instrument "${TEST_CLASS_ROOT}.K1OpenTest" "$open_out" "$case_id")" != "pass" ]; then
    echo "k1: open phase FAILED for $case_id"
    sed -n '1,60p' "$open_out"
    record "$case_id" "**FAIL**" "$witness" "-" \
      "the non-auth-bound key did not survive, or a witness assertion failed. Do NOT switch designs — report on BIT-18 and BIT-8 (see the issue). $(failure_excerpt "$open_out")"
    overall=1
    continue
  fi

  open_line=$(k1_line)
  echo "k1:   open  $open_line"

  # A green exit with no verdict line is a harness failure, not a pass.
  if ! contains "$open_line" 'verdict=PASS'; then
    record "$case_id" "ERROR" "$witness" "-" \
      "the open phase exited clean but emitted no verdict line; the run has no result"
    overall=1
    continue
  fi

  level=$(printf '%s' "$open_line" | grep -oE 'securityLevel=[^ ]+' | cut -d= -f2)
  record "$case_id" "PASS" "$witness" "${level:-unrecorded}"
done

reset_to_none >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# The table
# ---------------------------------------------------------------------------

{
  echo
  echo "### ${DEVICE_LABEL}"
  echo
  echo "\`${FINGERPRINT}\`"
  echo
  echo "| case | result | mutation witness | key security level |"
  echo "|---|---|---|---|"
  if [ ${#rows[@]} -gt 0 ]; then
    printf '%s\n' "${rows[@]}"
  fi
  if [ ${#notes[@]} -gt 0 ]; then
    echo
    printf '%s\n\n' "${notes[@]}"
  fi
} | tee "${OUT:-/dev/null}"

echo
if [ "$overall" -eq 0 ]; then
  echo "k1: every case run produced a result. Paste the table into"
  echo "    android/docs/k1-keystore-lockscreen.md."
else
  echo "k1: at least one row is FAIL or ERROR. A FAIL row is a BIT-8 rule-2"
  echo "    contradiction on this device: comment on BIT-18 and BIT-8, and do not"
  echo "    switch designs here. An ERROR row means the run has no verdict."
fi
exit "$overall"
