#!/usr/bin/env bash
#
# Run the Android smoke flow N times in a row against an already-booted device,
# and report the per-run wall-clock number.
#
# This exists because BIT-5's definition of done has two halves that a single
# `maestro test` cannot answer:
#
#   "green across three consecutive runs"  — one pass does not distinguish a
#                                            working harness from a lucky one
#   "report the wall-clock number"         — nobody times a manual run, and
#                                            eyeballing it afterwards is a guess
#
# Deliberately NO retries. A flow that needs a retry to pass is a failing flow
# (shared/flows/README.md), and this script is the instrument that would hide
# that if it had them. A red run does not stop the loop either: stopping at the
# first failure tells you "it broke", where finishing tells you "it broke 1 time
# in 3", and for a flakiness question that difference is the whole answer.
#
# Usage, from the repo root with an emulator up and the APK installed:
#
#   android/scripts/smoke-consecutive.sh              # 3 runs, the DoD default
#   android/scripts/smoke-consecutive.sh -n 10        # hunting a suspected flake
#   android/scripts/smoke-consecutive.sh -f shared/flows/features/pin_warning.yaml
#
# The flow is a SHARED one — `shared/flows/onboarding/smoke.yaml`, the same file
# iOS runs — and it takes its app id from `--env APP_ID`. That id is read off the
# workflow below rather than written here, so there is one copy of it per repo
# rather than one per script; override it with APP_ID=... in the environment.
#
# Written for bash 3.2, which is what /bin/bash still is on macOS — so no
# associative arrays, no ${var^^}, no EPOCHREALTIME.

set -uo pipefail

RUNS=3
FLOW="shared/flows/onboarding/smoke.yaml"
WORKFLOW=".github/workflows/android-maestro.yml"
OUT_DIR="${TMPDIR:-/tmp}/bittr-smoke-consecutive"

usage() {
  sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":n:f:o:h" opt; do
  case "$opt" in
    n) RUNS="$OPTARG" ;;
    f) FLOW="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    h) usage 0 ;;
    :) echo "error: -$OPTARG needs a value" >&2; exit 2 ;;
    *) echo "error: unknown option -$OPTARG" >&2; usage 2 ;;
  esac
done

case "$RUNS" in
  ''|*[!0-9]*) echo "error: -n must be a positive integer, got '$RUNS'" >&2; exit 2 ;;
esac
[ "$RUNS" -ge 1 ] || { echo "error: -n must be at least 1" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Milliseconds, portably.
#
# `date +%s%3N` is GNU-only — macOS date prints a literal "3N" and you get a
# number that looks plausible and is wrong by a factor of 1000. python3 is
# already a hard dependency of this repo's checks (shared/test-ids/*.py), but if
# it is missing we degrade to whole seconds rather than lying about precision.
# ---------------------------------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
  PRECISION="ms"
else
  now_ms() { echo $(($(date +%s) * 1000)); }
  PRECISION="s"
fi

# 12345 -> "12.3s". Integer arithmetic only; bash has no floats.
fmt_ms() {
  local ms=$1
  printf '%d.%ds' $((ms / 1000)) $(((ms % 1000) / 100))
}

fail() { echo "error: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preconditions. Each one of these, unchecked, produces a failure that reads as
# a broken app rather than a broken setup.
# ---------------------------------------------------------------------------
[ -f "$FLOW" ] || fail "no flow at '$FLOW'. Run this from the repo root."

command -v maestro >/dev/null 2>&1 \
  || fail "maestro is not on PATH. See android/docs/local-setup-macos.md."

# Homebrew's android-commandlinetools cask puts sdkmanager on PATH, not adb.
# The Mac setup doc exports ANDROID_HOME and stops there, so resolve through
# that before complaining. Prepend so Maestro's own adb lookup sees it too.
if ! command -v adb >/dev/null 2>&1; then
  if [ -n "${ANDROID_HOME:-}" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ]; then
    PATH="$ANDROID_HOME/platform-tools:$PATH"
    export PATH
  elif [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ]; then
    PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
    export PATH
  else
    fail "adb is not on PATH. Export ANDROID_HOME and add \$ANDROID_HOME/platform-tools (see android/docs/local-setup-macos.md)."
  fi
fi

# Exactly one device. With two attached, adb refuses every command with
# "more than one device/emulator" — but Maestro picks one on its own, so the
# run succeeds against whichever device it chose and the number you measured
# belongs to a device you did not mean to test.
devices=$(adb devices | sed -n 's/[[:space:]]*device$//p' | grep -v '^List of devices' | sed '/^$/d')
device_count=$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l | tr -d ' ')
[ "$device_count" -ge 1 ] || fail "no booted device. See android/docs/local-setup-macos.md section 2."
if [ "$device_count" -gt 1 ]; then
  fail "$device_count devices attached; Maestro would pick one silently. Detach all but the one under test:
$devices"
fi

# The pinned Maestro version is what CI runs. A local number measured on a
# different version is not comparable to a CI number, and "it's slower on CI"
# then sends someone after the runner instead of after the tool.
maestro_version=$(maestro --version 2>/dev/null | tr -d '[:space:]')
if [ -f "$WORKFLOW" ]; then
  pinned=$(sed -n "s/^[[:space:]]*MAESTRO_VERSION:[[:space:]]*['\"]\{0,1\}\([^'\"[:space:]]*\)['\"]\{0,1\}.*/\1/p" "$WORKFLOW" | head -1)
  if [ -n "$pinned" ] && [ -n "$maestro_version" ] && [ "$pinned" != "$maestro_version" ]; then
    echo "warning: local Maestro is $maestro_version, CI pins $pinned. Timings are not comparable to CI." >&2
  fi
fi

# The app id the shared flow launches. Read from the workflow for the same reason
# the Maestro version is: a local copy of the literal is a copy that can disagree
# with what CI actually runs, and the symptom would be a green local run against
# the wrong package. An explicit APP_ID in the environment still wins, which is
# what you want when testing a renamed or flavoured build.
if [ -z "${APP_ID:-}" ] && [ -f "$WORKFLOW" ]; then
  APP_ID=$(sed -n "s/^[[:space:]]*APP_ID:[[:space:]]*['\"]\{0,1\}\([^'\"[:space:]]*\)['\"]\{0,1\}.*/\1/p" "$WORKFLOW" | head -1)
fi
if [ -z "${APP_ID:-}" ]; then
  echo "error: APP_ID is unset and could not be read from $WORKFLOW (env.APP_ID)." >&2
  echo "       Re-run as: APP_ID=com.bittr.android.regtest $0" >&2
  exit 2
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "Flow:     $FLOW"
echo "App id:   $APP_ID"
echo "Runs:     $RUNS consecutive, no retries"
echo "Maestro:  ${maestro_version:-unknown}"
echo "Device:   $devices"
echo "Debug:    $OUT_DIR"
echo

# ---------------------------------------------------------------------------
# The loop.
# ---------------------------------------------------------------------------
green=0
statuses=""   # space-separated exit codes, index = run number
durations=""  # space-separated ms,  index = run number
suite_start=$(now_ms)

run=1
while [ "$run" -le "$RUNS" ]; do
  printf 'run %d/%d ... ' "$run" "$RUNS"

  run_dir="$OUT_DIR/run-$run"
  mkdir -p "$run_dir"

  start=$(now_ms)
  maestro test \
    --env APP_ID="$APP_ID" \
    --debug-output "$run_dir/debug" \
    --format junit \
    --output "$run_dir/report.xml" \
    "$FLOW" >"$run_dir/maestro.log" 2>&1
  status=$?
  end=$(now_ms)

  elapsed=$((end - start))
  statuses="$statuses $status"
  durations="$durations $elapsed"

  if [ "$status" -eq 0 ]; then
    green=$((green + 1))
    printf 'green  %s\n' "$(fmt_ms "$elapsed")"
  else
    printf 'RED    %s  (exit %d)\n' "$(fmt_ms "$elapsed")" "$status"
    # Surface the failure inline. Waiting until the summary to mention it means
    # a long -n run scrolls the only useful output off the screen.
    sed -n '/[Ff]ailed\|[Ee]rror\|not found/p' "$run_dir/maestro.log" | head -5 | sed 's/^/         | /'
    echo "         | full log: $run_dir/maestro.log"
  fi

  run=$((run + 1))
done

suite_end=$(now_ms)

# ---------------------------------------------------------------------------
# The report. This is the thing BIT-5 asks to be told.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2086
set -- $durations
sorted=$(printf '%s\n' "$@" | sort -n)
min=$(printf '%s\n' "$sorted" | head -1)
max=$(printf '%s\n' "$sorted" | tail -1)
median=$(printf '%s\n' "$sorted" | sed -n "$(((RUNS + 1) / 2))p")

echo
echo "| run | result | wall clock |"
echo "|-----|--------|------------|"
i=1
for d in $durations; do
  s=$(echo "$statuses" | cut -d' ' -f$((i + 1)))
  if [ "$s" -eq 0 ]; then r="green"; else r="RED"; fi
  printf '| %d | %s | %s |\n' "$i" "$r" "$(fmt_ms "$d")"
  i=$((i + 1))
done
echo
echo "$green/$RUNS green   median $(fmt_ms "$median")   min $(fmt_ms "$min")   max $(fmt_ms "$max")"
echo "total $(fmt_ms $((suite_end - suite_start)))"
[ "$PRECISION" = "s" ] && echo "(no python3 — timings rounded to whole seconds)"

# A spread this wide is not a timing curiosity. The flow is a launch and three
# assertions; if the slowest run is more than double the fastest, something
# non-deterministic is in the loop (a settling animation, a background service,
# a device throttling) and the median is not a number to quote as "the" figure.
if [ "$min" -gt 0 ] && [ "$max" -gt $((min * 2)) ]; then
  echo
  echo "note: slowest run is more than 2x the fastest. The wall-clock number is not"
  echo "      stable yet — investigate before quoting one, even if all runs were green."
fi

echo
if [ "$green" -eq "$RUNS" ]; then
  echo "PASS — $RUNS consecutive green runs."
  exit 0
fi
echo "FAIL — $((RUNS - green)) of $RUNS runs were red. A flaky pass is a failure; do not re-run for a better result."
exit 1
