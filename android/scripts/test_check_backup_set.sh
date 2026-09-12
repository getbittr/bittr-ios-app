#!/usr/bin/env bash
#
# Tests for check-backup-set.sh.
#
#   bash android/scripts/test_check_backup_set.sh
#
# The seam is `adb`, so each case puts a stub `adb` on PATH and asserts on the
# exit code and the output. No emulator, no device, no Gradle.
#
# WHY THESE EXIST
#
# The same argument every other gate in this directory makes, with the sharpest
# version of the stakes. check-backup-set.sh decides a HALT on BIT-20's
# `match -> keep`, and its failure mode is not a crash — it is reporting "no
# wallet marker" when it never looked. That reads exactly like evidence. The
# first draft of this logic, inline in ci-wallet-instrumented.sh, shipped that
# bug: it grepped three hard-coded paths and treated "none of them exist on this
# image" as clean. `outcome_3_no_directories` is that bug, pinned.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/check-backup-set.sh"

failures=0
stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

# Writes a stub `adb` whose behaviour is set by three files in $stub_dir:
#   root_ok  — "yes" or "no", what `adb root` does
#   present  — what `ls -d <roots>` prints
#   leaks    — what `grep -rl <marker> ...` prints
write_stub() {
  cat > "$stub_dir/adb" <<'STUB'
#!/usr/bin/env bash
dir=$(dirname "$0")
case "$1" in
  root)
    [ "$(cat "$dir/root_ok")" = "yes" ] && exit 0
    exit 1
    ;;
  wait-for-device) exit 0 ;;
  shell)
    shift
    joined="$*"
    case "$joined" in
      *"ls -d"*)   cat "$dir/present" ;;
      *"grep -rl"*) cat "$dir/leaks" ;;
      *find*)      echo "/data/data/com.android.localtransport/files/1/com.bittr.android.regtest" ;;
      *"bmgr list transports"*) echo "  com.android.localtransport/.LocalTransport" ;;
    esac
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "$stub_dir/adb"
}

# configure <root_ok> <present> <leaks>
configure() {
  printf '%s' "$1" > "$stub_dir/root_ok"
  printf '%s' "$2" > "$stub_dir/present"
  printf '%s' "$3" > "$stub_dir/leaks"
}

# expect <name> <expected exit> <substring that must appear> <substring that must NOT appear>
expect() {
  local name=$1 want=$2 must=$3 must_not=${4:-}
  local out got
  out=$(PATH="$stub_dir:$PATH" bash "$SCRIPT" 2>&1)
  got=$?

  if [ "$got" -ne "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    printf '%s\n' "$out" | sed 's/^/    /'
    failures=$((failures + 1))
    return
  fi
  # `case` rather than `grep -qF`: the script's messages contain UTF-8 (§, —)
  # and the whole point of this harness is that its verdict is never in doubt.
  # Bash pattern matching has no locale handling, no binary-input heuristic and
  # no pipeline to mis-wire — one less thing that can make a green mean nothing.
  case "$out" in
    *"$must"*) ;;
    *)
      echo "FAIL $name: output does not contain '$must'"
      printf '%s\n' "$out" | sed 's/^/    /'
      failures=$((failures + 1))
      return
      ;;
  esac
  if [ -n "$must_not" ] && case "$out" in *"$must_not"*) true ;; *) false ;; esac; then
    echo "FAIL $name: output must not contain '$must_not'"
    printf '%s\n' "$out" | sed 's/^/    /'
    failures=$((failures + 1))
    return
  fi
  echo "ok   $name"
}

write_stub

# --- Outcome 1: the halt ------------------------------------------------------
configure yes "/data/data/com.android.localtransport/files" \
  "/data/data/com.android.localtransport/files/1/com.bittr.android.regtest/f1"
expect "outcome_1_marker_in_the_set_is_a_halt" 1 "HALT"

# --- Outcome 2: looked, and it was clean. The only evidential pass ------------
configure yes "/data/data/com.android.localtransport/files" ""
expect "outcome_2_present_and_clean" 0 "Looked inside the backup set"

# --- Outcome 3a: no root ------------------------------------------------------
#
# Must NOT claim the set was clean. `adb root` is refused on a production image
# and that is a fact about the emulator, not about the wallet.
configure no "" ""
expect "outcome_3_no_root" 0 "was NOT inspected" "Looked inside the backup set"

# --- Outcome 3b: root, but none of the candidate directories exist ------------
#
# THE PINNED BUG. The inline first draft returned an empty grep here and printed
# "no wallet marker anywhere", which reads as evidence and is not.
configure yes "" ""
expect "outcome_3_no_directories" 0 "NOT evidence that the set was clean" \
  "Looked inside the backup set"

# --- The marker the grep is keyed on must be the one the test writes ----------
#
# The two halves of the strongest backup assertion are joined by a literal, in
# two languages, in two files: BackupExclusionTest writes it into the LDK state
# files it plants, and check-backup-set.sh greps the transport's tree for it.
#
# If they drift, nothing goes red on its own. The grep simply matches nothing,
# for ever, and every run reports "no wallet marker under any of the above" —
# which reads as evidence and is not. That is BIT-20 §5.3's halt condition
# failing open, so it gets a check of its own rather than trusting a rename to
# touch both files.
marker_here=$(grep -oE 'MARKER_PREFIX="[^"]+"' "$SCRIPT" | head -1 | cut -d'"' -f2)
marker_test=$(grep -oE 'MARKER_PREFIX = "[^"]+"' \
  "$SCRIPT_DIR/../app/src/androidTest/kotlin/com/bittr/android/BackupExclusionTest.kt" \
  | head -1 | cut -d'"' -f2)
if [ "$marker_here" = "$marker_test" ] && [ -n "$marker_here" ]; then
  echo "ok   marker_prefix_agrees_with_BackupExclusionTest ($marker_here)"
else
  echo "FAIL marker_prefix_agrees_with_BackupExclusionTest: script='$marker_here' test='$marker_test'"
  failures=$((failures + 1))
fi

# --- ...and it must be distinctive enough that a hit means something -----------
#
# The grep runs over a directory of opaque backup blobs. A short or common prefix
# could match bytes the platform put there itself, and that failure is the
# expensive direction: a spurious HALT on `match -> keep`, escalated to BIT-20 as
# an empirical result. Naming the issue in it also makes a hit in a backup set
# self-explaining to whoever finds it.
#
# It names BIT101 rather than BIT59 because BIT-101 wrote the class that plants
# the material; BIT-59 only runs it. The issue named here should be the one
# whose test writes the bytes, so that a hit found in a backup set leads to the
# file that put it there.
if [ "${#marker_here}" -ge 12 ] && [ "${marker_here#*BIT101}" != "$marker_here" ]; then
  echo "ok   marker_prefix_is_distinctive ($marker_here)"
else
  echo "FAIL marker_prefix_is_distinctive: '$marker_here' must be >= 12 chars and name BIT101"
  failures=$((failures + 1))
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed."
  exit 1
fi
echo "All check-backup-set.sh tests passed."
