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
#   - the device observed its own credential actually change
#
# EVERY WITNESS IS ON THE DEVICE SIDE OF adb, AND THAT IS RECENT
#
# It used to be `adb shell locksettings verify`, and run #6 killed that. On the
# API 34 `default` image all three forms of it exit 0 — the credential just set,
# a deliberately wrong one, and a bare `verify` with no argument at all. A
# witness that always says yes is exactly how a false green gets made, and every
# host-side check in this script rested on that one call.
#
# So the questions moved across adb. `K1ObserveTest` runs on the device and
# reports what the framework itself sees:
#
#   KeyguardManager.isDeviceSecure       is there a credential at all
#   DevicePolicyManager.getPasswordComplexity()   which bucket it is in (API 29+)
#
# The first is decisive for the mutations that cross the has-a-credential line
# (M1 sets one, M5 and M6 destroy one) and available on every API here. The
# second is what carries M2/M3/M4, which are secure on both sides: the
# credentials below are picked to sit in different complexity buckets, so a
# mutation that landed moves the bucket and one that exited 0 and did nothing
# does not. Below API 29 nothing answers for those three and K1SealTest refuses
# them, which lands as a `NOT REACHABLE` row with the reason attached.
#
# This also costs the run nothing in failed credential attempts. The old probe
# spent one every time it asked a question, and Android locks the credential out
# for 30s after five in a row — a hazard on exactly the Samsung and Xiaomi
# handsets K1 exists for. Only a wrong `clear --old` guess costs one now.
#
# The driver is exercised against a fake device — including each of those
# failure shapes — by android/scripts/test-k1-driver.sh, which needs no device
# and no Android SDK. Run it after touching anything in here.
#
# SAFETY — READ BEFORE POINTING THIS AT YOUR PHONE
#
# This sets, changes and removes the device lock screen. On a physical device
# that is your real lock screen, and a failure partway through can leave the
# device on one of the script's credentials rather than yours. Every case
# restores the device to "no lock screen" on exit, and every credential the
# script can have left behind is printed on failure.
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
#
# CHOSEN SO THAT EVERY MUTATION MOVES THE COMPLEXITY BUCKET
#
# `getPasswordComplexity()` is the only device-side signal that can see M2/M3/M4
# happen, and it reports a bucket, not a credential. Two PINs in the same bucket
# would make a real PIN change indistinguishable from no change at all, and the
# row would be a survival claim about a mutation nothing observed.
#
# Under AOSP's buckets: a 4-digit PIN with no repeating or arithmetic run is
# MEDIUM, the same at 8 digits is HIGH, any pattern is LOW, an 8-character
# alphanumeric password is HIGH. So M1 NONE->MEDIUM, M2 MEDIUM->HIGH, M3
# MEDIUM->HIGH, M4 MEDIUM->LOW, M5/M6 MEDIUM->NONE.
#
# Note what is being relied on and what is not. The driver requires the bucket to
# MOVE, which is a fact it observes. It does not require it to land where the
# table above predicts — that mapping is AOSP documentation, and an OEM that
# buckets differently would still move. A surprising landing is recorded as a
# note next to the row for a human, not as a verdict.
#
# 1379 rather than the old 1234: consecutive digits are an arithmetic run, which
# drops a PIN to LOW and made PIN_A and PATTERN indistinguishable.
PIN_A="1379"
PIN_B="13795284"
PASSWORD="k1pass99"
PATTERN="1236"

# Everything the script can leave on a device if it dies partway through, for the
# recovery message and for reset_to_none's candidate list.
ALL_CREDS=("$PIN_A" "$PIN_B" "$PASSWORD" "$PATTERN")

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

# --- asking the device ------------------------------------------------------
#
# One `am instrument` of K1ObserveTest, whose answers land in OBS_SECURE and
# OBS_COMPLEXITY. See the header: this replaced `locksettings verify` wholesale
# after run #6 showed that call exits 0 on the API 34 image whatever is stored.
#
# Fails closed in the direction that keeps a device safe rather than the one that
# produces rows: an observation that does not come back leaves OBS_SECURE=true,
# so reset_to_none keeps trying to clear rather than reporting a lock screen
# removed that is still there.
OBS_SECURE="true"
OBS_COMPLEXITY="unreadable"
OBS_LINE=""

# Pull `key=value` out of a K1 report line.
field() {
  printf '%s' "$1" | grep -oE "(^| )$2=[^ ]*" | tail -n 1 | cut -d= -f2
}

observe() {
  local out="$workdir/observe.out" verdict
  verdict=$(instrument "${TEST_CLASS_ROOT}.K1ObserveTest" "$out" "-")
  OBS_LINE=$(k1_line)
  if [ "$verdict" != "pass" ] || [ -z "$OBS_LINE" ]; then
    OBS_SECURE="true"
    OBS_COMPLEXITY="unreadable"
    OBS_LINE="(K1ObserveTest did not report: $(failure_excerpt "$out"))"
    return 1
  fi
  OBS_SECURE=$(field "$OBS_LINE" deviceSecure)
  OBS_COMPLEXITY=$(field "$OBS_LINE" complexity)
  [ -n "$OBS_SECURE" ] || OBS_SECURE="true"
  [ -n "$OBS_COMPLEXITY" ] || OBS_COMPLEXITY="unreadable"
  return 0
}

# True when the device reports itself as having a lock-screen credential.
device_has_credential() {
  observe || return 0
  [ "$OBS_SECURE" = "true" ]
}

has_no_credential() {
  ! device_has_credential
}

# Put the device in the state a case says it must start from, from whatever
# state the last case left behind. The device's own start state is unknown on
# the first call, hence the check before the loop.
reset_to_none() {
  wake
  has_no_credential && return 0
  for old in "${ALL_CREDS[@]}"; do
    # Re-probe only after a clear that claimed success.
    #
    # The probe itself is free now — asking K1ObserveTest costs no credential
    # attempt — but a wrong `locksettings clear --old` still does, and Android
    # locks the credential out for 30s after five in a row. Four candidates is
    # inside that, and skipping the probe after a failed clear keeps the loop
    # short on the handsets where a lockout would surface as "could not clear
    # the lock screen" on a device that was merely being asked too fast.
    if sh_status "locksettings clear --old '$old'" >/dev/null 2>&1; then
      has_no_credential && return 0
    fi
  done
  # One last look before giving up, in case a clear removed the credential while
  # reporting failure.
  has_no_credential && return 0
  echo "k1: could not clear the lock screen on $DEVICE_LABEL." >&2
  echo "    Credentials tried: ${ALL_CREDS[*]} (pattern as digits)." >&2
  echo "    The device reports: ${OBS_LINE:-nothing}" >&2
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
#
# Deliberately a functional probe and not only a feature query. Both are checked
# and they answer different questions: `android.software.secure_lock_screen`
# (API 29+) is what the image *claims*, and set-then-observe-then-clear is what
# it *does*. The second has to exist because the first is absent on API 26-28 by
# definition and because a feature flag is another piece of documentation.
#
# It runs AFTER the install, which is new: the probe it uses is on the device
# now, so there is nothing to ask until the APK is there. The install checks
# above it are cheap and catch their own failures, so nothing is lost by the
# reorder — and a lock-screen refusal arriving after "installed" reads correctly,
# because that is the order the two facts were established in.
#
# What it also establishes, once, for the whole run: whether this device answers
# getPasswordComplexity() at all. That answer is what decides between a real row
# and a `NOT REACHABLE` one for M2/M3/M4 — but the decision is made on the device
# by K1SealTest, not here. This only prints it, so the reason a matrix came back
# three rows short is visible at the top of the log rather than inferred from
# three identical notes at the bottom.
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
  # `set-pin` exiting 0 is not evidence a credential exists. The device is what
  # says so, and it says so through the same KeyguardManager the OS locks with.
  if ! device_has_credential; then
    echo "k1: on $DEVICE_LABEL, 'locksettings set-pin $PIN_A' exited 0 and the device" >&2
    echo "    still reports itself as having no lock screen. K1 cannot mutate a lock" >&2
    echo "    screen this image will not hold, so it will not report rows about one." >&2
    echo >&2
    echo "    What the device answered:" >&2
    echo "      $OBS_LINE" >&2
    sh_ locksettings clear --old "$PIN_A" >/dev/null 2>&1 || true
    return 1
  fi

  # One reading, kept for the run: does this device bucket its credential at all?
  #
  # Not a refusal either way. Without it M1/M5/M6 still have a decisive keyguard
  # witness and are worth running; it is M2/M3/M4 that go NOT REACHABLE, and
  # K1SealTest makes that call per case on the device rather than here.
  COMPLEXITY_READABLE=0
  if [ "$OBS_COMPLEXITY" != "unreadable" ] && [ -n "$OBS_COMPLEXITY" ]; then
    COMPLEXITY_READABLE=1
    echo "k1: credential complexity is readable here ('$PIN_A' buckets as $OBS_COMPLEXITY)"
  else
    echo "k1: this device does not report credential complexity (API $API)." >&2
    echo "    M2/M3/M4 are secure on both sides of their mutation, so nothing on this" >&2
    echo "    device can witness them; they will be recorded NOT REACHABLE rather than" >&2
    echo "    run without a witness. M1/M5/M6 are unaffected." >&2
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
# Lock-screen preflight
# ---------------------------------------------------------------------------
#
# Needs the workdir, because every question it asks the device goes through an
# `am instrument` whose output has to land somewhere. The trap gains the
# lock-screen restore once there is an installed probe able to check it.
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

if ! lockscreen_preflight; then
  echo "k1: refusing to run the matrix — see above." >&2
  exit 2
fi

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
    # table blamed the seal phase. Checked here, the row names the setup.
    if ! device_has_credential; then
      record "$case_id" "ERROR" "-" "-" \
        "locksettings set-pin reported success but the device still reports no lock screen; the start state was never reached. Device said: $OBS_LINE"
      overall=1
      continue
    fi
  fi

  # What the device bucketed the start credential as. This is half of the only
  # witness M2/M3/M4 have; the other half is read after the mutation.
  cx_before="$OBS_COMPLEXITY"

  # --- phase 1: seal -----------------------------------------------------
  #
  # A skip here is the device refusing the case for want of a witness: M2/M3/M4
  # are secure on both sides, so below API 29 — where getPasswordComplexity()
  # does not exist — nothing on the device can see their mutation happen.
  #
  # That decision is made on the device, in K1SealTest, and not from $API here.
  # K1 has already been wrong once about which API level a method arrived in
  # (the isUnlockedDeviceRequired readback was gated at 28 for something that
  # landed in 36.1, and compileSdk hid it on every device in the matrix). The
  # device is the only thing that knows, so it is the thing that is asked.
  seal_verdict=$(instrument "${TEST_CLASS_ROOT}.K1SealTest" "$seal_out" "$case_id")
  if [ "$seal_verdict" = "skip" ]; then
    reason=$(grep -oE 'reason=[^ ]+' "$seal_out" | tail -n 1)
    record "$case_id" "NOT REACHABLE" "none available" "-" \
      "${reason:-the device declined this case}: nothing on this device can witness a mutation that leaves it secure on both sides. A row here would be a survival claim about a change nothing observed."
    continue
  fi
  if [ "$seal_verdict" != "pass" ]; then
    echo "k1: seal phase failed for $case_id"
    sed -n '1,40p' "$seal_out"
    note=""
    # The one seal failure that is a finding about the device rather than a bug
    # in the harness: the driver just asked the device, through K1ObserveTest,
    # and the seal phase asks the same KeyguardManager moments later and gets the
    # other answer. It matters in BOTH directions — run #4 hit the M1 one (the
    # credential was cleared and the device still reported itself secure) having
    # been built expecting only the M2-M5 one.
    #
    # Recorded with the earlier observation quoted, because "the driver did not
    # reach the start state" is the seal phase's reading and the row needs the
    # other side of the disagreement to be worth anything.
    if grep -q 'did not reach the start state' "$seal_out"; then
      note=" — NOTE: the driver's own observation immediately before this was"
      note="$note '$OBS_LINE', which disagrees with what the seal phase then read."
      note="$note Two readings of KeyguardManager on the same device, moments apart,"
      note="$note disagreeing: suspect the image (see the image step in"
      note="$note .github/workflows/k1-keystore-lockscreen.yml) before the driver."
    fi
    record "$case_id" "ERROR" "seal" "-" "seal phase failed; no verdict on rule 2 — $(failure_excerpt "$seal_out")$note"
    overall=1
    continue
  fi
  seal_line=$(k1_line)
  echo "k1:   seal  $seal_line"

  # The seal phase's own reading, taken in the process that made the key. Used
  # for the witness column so the table shows the transition the *probe* saw
  # rather than the one the driver arranged.
  sealed_secure=$(field "$seal_line" deviceSecure)

  # --- phase 2: mutate ---------------------------------------------------
  #
  # What the device must look like afterwards. `end_secure` is required and
  # decides the row; `expect_cx` is the bucket AOSP's table predicts and only
  # ever produces a note — see the credential block at the top of this file for
  # why the predicted value is not allowed to decide anything.
  case "$case_id" in
    M1)     end_secure="true";  expect_cx="MEDIUM" ;;
    M2)     end_secure="true";  expect_cx="HIGH" ;;
    M3)     end_secure="true";  expect_cx="HIGH" ;;
    M4)     end_secure="true";  expect_cx="LOW" ;;
    M5|M6)  end_secure="false"; expect_cx="NONE" ;;
  esac

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

  # --- the witness -------------------------------------------------------
  #
  # Did the mutation actually happen? Asked of the device, once, here — before
  # the open phase runs, deliberately.
  #
  # K1OpenTest asserts the same two things itself, and that redundancy is the
  # point rather than an oversight: this check makes a failed witness an ERROR
  # ("this run has no verdict on rule 2"), while the same failure reaching
  # K1OpenTest would come back as a failed test and be recorded **FAIL** ("this
  # device contradicts BIT-8 rule 2"). Those two rows mean opposite things and
  # only one of them is about Android. A harness bug must not be able to
  # masquerade as a platform finding.
  #
  # Two required checks:
  #
  #   keyguard  — the device must end up on the right side of the
  #               has-a-credential line. Decisive for M1/M5/M6; for M2/M3/M4 it
  #               catches a mutation that landed as a wipe, which would
  #               otherwise pass the complexity check and mislabel an M5 as an
  #               M3.
  #   bucket    — where it is readable, the complexity bucket must have MOVED.
  #               This is the check that carries M2/M3/M4, and it is the direct
  #               replacement for `locksettings verify`: a mutation command that
  #               exits 0 and does nothing leaves the bucket where it was.
  #
  # And one check that only ever annotates: whether it moved to the bucket AOSP
  # predicts. Getting that wrong means either the mutation landed somewhere else
  # or this device buckets credentials differently — and K1 cannot tell which,
  # so it records both values and lets a human decide. Failing the row on it
  # would make the matrix red on the first OEM that disagrees with the
  # documentation this test exists to distrust.
  observe || true
  if [ "$OBS_SECURE" != "$end_secure" ]; then
    record "$case_id" "ERROR" "mutate" "-" \
      "after the mutation the device reports deviceSecure=$OBS_SECURE, but $case_id must end deviceSecure=$end_secure — the mutation did not do what the row would say it did. Device said: $OBS_LINE"
    overall=1
    continue
  fi
  # The witness column carries the observations themselves, not a word standing
  # in for them. A reader checking whether a row means what it says should not
  # have to trust the driver's summary of its own evidence.
  witness="secure:${sealed_secure:-?}->${OBS_SECURE}"

  cx_after="$OBS_COMPLEXITY"
  if [ "$cx_before" != "unreadable" ] && [ "$cx_after" != "unreadable" ]; then
    if [ "$cx_before" = "$cx_after" ]; then
      record "$case_id" "ERROR" "mutate" "-" \
        "the credential complexity is $cx_before both before and after the mutation — nothing observable changed, so a survival result would be evidence of nothing"
      overall=1
      continue
    fi
    witness="${witness}+complexity:${cx_before}->${cx_after}"
    if [ "$cx_after" != "$expect_cx" ]; then
      notes+=("**$case_id** — the mutation landed, but in bucket \`$cx_after\` where AOSP's table predicts \`$expect_cx\`. Either it landed on a different credential than the one $case_id names, or this device buckets credentials differently. The row's verdict does not rest on this; check the device by hand before quoting this row as being specifically about ${case_id}'s credential type.")
    fi
  elif [ "$case_id" = "M2" ] || [ "$case_id" = "M3" ] || [ "$case_id" = "M4" ]; then
    # Belt and braces: K1SealTest should already have skipped these. Reaching
    # here means the seal phase and this disagree about what is readable, and a
    # row written now would rest on nothing.
    record "$case_id" "ERROR" "mutate" "-" \
      "no credential-change witness (complexity before=$cx_before after=$cx_after) and $case_id is secure on both sides; the seal phase should have declined this case"
    overall=1
    continue
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
