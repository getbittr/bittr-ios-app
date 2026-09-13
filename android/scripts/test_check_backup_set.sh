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

# Writes a stub `adb` whose behaviour is set by five files in $stub_dir:
#   root_ok  — "yes" or "no", what `adb root` does
#   present  — what `ls -d <roots>` prints
#   leaks    — what `grep -rl <wallet marker> ...` prints
#   canaries — what `grep -rl <canary marker> ...` prints
#   decoys   — what `grep -rl <decoy marker> ...` prints
#
# The three greps are told apart by the prefix in the command line, which means
# this stub depends on the script passing each prefix to a SEPARATE grep. That is
# the point: a rewrite that folded them into one `grep -E` would make the cases
# below indistinguishable, and the harness would start lying rather than go red.
# If you fold them, fold this too, and keep one case per outcome.
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
    # Record verbatim what the device shell was handed. A newline in here is not
    # cosmetic: it ends one command and starts another, so a root that lands on
    # the second line is never searched. Only a recording stub can see that --
    # the return values look identical either way.
    printf '%s\n<<<END>>>\n' "$joined" >> "$dir/cmdlog"
    case "$joined" in
      *"ls -d"*)   cat "$dir/present" ;;
      *"grep -rl"*)
        case "$joined" in
          *WALLET-MARKER*) cat "$dir/leaks" ;;
          *CANARY-MARKER*) cat "$dir/canaries" ;;
          *DECOY-MARKER*)  cat "$dir/decoys" ;;
          *)
            echo "STUB SAW AN UNRECOGNISED GREP: $joined" >&2
            exit 3
            ;;
        esac
        ;;
      *"-type f"*) cat "$dir/setfiles" ;;
      *find*)      cat "$dir/sets" ;;
      *"bmgr list transports"*) echo "  com.android.localtransport/.LocalTransport" ;;
    esac
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "$stub_dir/adb"
}

# The canary path a populated set has in it. Spelled once so the cases below read
# as "a normal populated set, plus/minus the thing under test".
CANARY_IN_SET="/data/data/com.android.localtransport/files/1/com.bittr.android.regtest/c1"

# The set directory `find` reports when the transport did write one.
SET_PATH="/data/data/com.android.localtransport/files/1/com.bittr.android.regtest"

# configure <root_ok> <present> <leaks> [canaries] [decoys]
#
# canaries defaults to CANARY_IN_SET — i.e. to a set the framework actually
# populated — so each case below states only what it is actually varying. The
# empty-set case passes "" explicitly, because that is its whole subject.
configure() {
  printf '%s' "$1" > "$stub_dir/root_ok"
  printf '%s' "$2" > "$stub_dir/present"
  printf '%s' "$3" > "$stub_dir/leaks"
  printf '%s' "${4-$CANARY_IN_SET}" > "$stub_dir/canaries"
  printf '%s' "${5-}" > "$stub_dir/decoys"
  # $6 is what `find` returns: the set paths on disk. Defaults to a populated
  # set, so every case that is not about set DISCOVERY reads unchanged. An empty
  # value is the distinct, real state "the transport wrote nothing to these
  # roots", which is not the same as "a set exists and holds none of our markers"
  # and must not be stubbed as if it were.
  printf '%s' "${6-$SET_PATH}" > "$stub_dir/sets"
  # $7 is what `ls -l` reports for the regular files under those set paths. It
  # decides set_bytes, and therefore whether a no-canary run is reported as an
  # empty set or as a set this check could not read. Defaults to empty -- i.e.
  # zero bytes -- so every case written before sizes existed reads unchanged.
  printf '%s' "${7-}" > "$stub_dir/setfiles"
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

# ...and a halt is still a halt when the set also contains a decoy. The decoy is
# a finding about dataExtractionRules; it must not soften or replace §5.3.
configure yes "/data/data/com.android.localtransport/files" \
  "/data/data/com.android.localtransport/files/1/com.bittr.android.regtest/f1" \
  "$CANARY_IN_SET" \
  "/data/data/com.android.localtransport/files/1/com.bittr.android.regtest/d1"
expect "outcome_1_halt_survives_a_decoy" 1 "HALT"

# --- Outcome 2: looked, non-empty, and clean. The only evidential pass --------
configure yes "/data/data/com.android.localtransport/files" ""
expect "outcome_2_present_nonempty_and_clean" 0 "Looked inside the backup set"

# ...and it has to be READABLE, which is a separate property from being correct.
#
# The asymmetry this pins: outcomes 1 and 3 always emitted annotations, while
# outcome 2 — the only one that is evidence — was a bare echo. On this public
# repo the job log answers 403 and artifacts answer 401, so the run that proved
# something was the one run nobody could read without credentials. It matters
# most on a RED run, because this check needs no surviving instrumentation
# process and so still answers when the in-process assertions cannot.
expect "outcome_2_is_readable_without_a_token" 0 \
  "::notice title=Backup set inspection::"

# --- Outcome 3: THE SECOND PINNED BUG (BIT-109) -------------------------------
#
# No wallet marker AND no canary. Before BIT-109 this was reported as outcome 2:
# a ::notice:: saying the set was searched and clean. It is the same failure this
# file's header refuses — "clean" indistinguishable from "did not look" — reached
# from a different direction, and it is the LIKELY direction rather than an
# exotic one.
#
# It must exit 0: neither cause is one this script should fail the build for. It
# must NOT be readable as evidence.
configure yes "/data/data/com.android.localtransport/files" "" ""
expect "outcome_3_empty_set_is_not_evidence" 0 "NOT evidence" \
  "::notice title=Backup set inspection::"

# The halves stated separately, so a rewrite cannot satisfy this by dropping the
# annotation and leaving the misleading prose, or the reverse.
configure yes "/data/data/com.android.localtransport/files" "" ""
expect "outcome_3_empty_set_says_why_it_is_empty" 0 "the package ineligible"

# THE THIRD PINNED BUG. The first version of the warning above named the cloud
# path's cause — `allowBackup="false"` making the package ineligible — as the
# cause of ANY empty set, and run 136 was read through it. On the device-transfer
# path `allowBackup` does not apply at all; that is why the path exists. The set
# there was empty because the target process died mid-backup (BIT-108). Naming
# one cause for a two-cause condition reads as "expected, nothing to see" on
# exactly the run where something is wrong, so the warning must name both and
# must say it cannot tell them apart from the tree alone.
configure yes "/data/data/com.android.localtransport/files" "" ""
expect "outcome_3_empty_set_says_allowBackup_does_not_cover_device_transfer" 0 \
  "allowBackup does NOT apply"

configure yes "/data/data/com.android.localtransport/files" "" ""
expect "outcome_3_empty_set_names_the_incomplete_backup_cause" 0 \
  "backup did not complete"

configure yes "/data/data/com.android.localtransport/files" "" ""
expect "outcome_3_empty_set_does_not_attribute_a_path" 0 "CANNOT say which"

configure yes "/data/data/com.android.localtransport/files" "" ""
expect "outcome_3_empty_set_is_not_a_failure" 0 "NOT a failure"

# THE FOURTH PINNED BUG, and the first run carrying both halves is what exposed
# it. The warning named process death (BIT-108) as the device-transfer cause of
# an empty set. That run reported the device-transfer backup as Success with the
# process surviving — and the set was still empty, so the only device-transfer
# cause the warning named was excluded by another annotation on the same run,
# leaving a reader with no cause that fits. The condition has a third state and
# the warning has to admit it: completed, survived, and still nothing here.
configure yes "/data/data/com.android.localtransport/files" "" ""
expect "outcome_3_empty_set_names_the_completed_but_empty_cause" 0 \
  "DID report Success"

# And the facts that tell the two apart must reach the ANNOTATION. They were
# echoed to stdout only, which on this public repo means the job log, which
# answers 403 without a token — the same inaccessibility every other verdict in
# this script routes around. "Which directories exist" and "did anything land in
# them" is the first question an empty set raises, and it was the one thing a
# reader could not get at.
configure yes "/data/data/com.android.localtransport/files" "" ""
expect "outcome_3_empty_set_puts_the_searched_roots_in_the_annotation" 0 \
  "transport directories present = [/data/data/com.android.localtransport/files]"

# The no-set-at-all case must be legible as such rather than as a blank. The
# stub's `find` returns nothing here, which is the shape that says the transport
# never wrote a set to these roots -- a WHERE question, not an exclusion result.
configure yes "/data/data/com.android.localtransport/files" "" "" "" ""
expect "outcome_3_empty_set_marks_an_absent_set_as_none" 0 \
  "mentioning this package = [(none)]"

# Once the roots are really searched, the set directory turns up (run d823265
# found it at .../files/1/_full/<pkg>), so "was a set written here" is answered
# and the next question is whether anything is IN it. A directory the framework
# created and wrote nothing into is indistinguishable, from the canary grep
# alone, from one whose contents were all excluded -- the first produced no data,
# the second would be evidence. That fact has to be in the annotation for the
# same reason as the roots: the job log answers 403.
configure yes "/data/data/com.android.localtransport/files" "" "" "" ""
expect "outcome_3_with_no_set_says_there_was_nothing_to_size" 0 \
  "(no set paths to size)"

configure yes "/data/data/com.android.localtransport/files" "" ""
expect "outcome_3_with_a_set_reports_the_files_under_it" 0 \
  "Regular files under those paths = ["

# --- THE SIXTH PINNED BUG: "no canary" is not "empty set" ---------------------
#
# Once the roots were searched properly the set could be measured for the first
# time, and the run for 9dc0b64 measured it: 4608 bytes under
# .../files/1/_full/<pkg>, with NONE of the three prefixes greppable. So the
# framework wrote real data and the script was calling that an EMPTY SET --
# an inference that was sound only while the set could not be measured.
#
# It points at the FORMAT: a full backup reaches the transport as a tar stream
# and the bytes on disk need not hold contents as plaintext. The serious part is
# that this applies to the $MARKER_PREFIX grep too -- the one that decides the
# §5.3 halt -- so wallet material could be in the set and this check would report
# exactly what it reported. A non-halt here must not read as "no leak".
NONEMPTY_SET_FILES="-rw------- 1 system system 4608 2026-09-13 04:11 $SET_PATH"

configure yes "/data/data/com.android.localtransport/files" "" "" "" "$SET_PATH" \
  "$NONEMPTY_SET_FILES"
expect "nonempty_set_without_a_canary_is_not_called_empty" 0 \
  "The set is NOT empty and this check  could not read it" "produced was EMPTY"

configure yes "/data/data/com.android.localtransport/files" "" "" "" "$SET_PATH" \
  "$NONEMPTY_SET_FILES"
expect "nonempty_unreadable_set_says_the_halt_grep_is_blind_too" 0 \
  "Do not read a non-halt here as 'no leak'"

configure yes "/data/data/com.android.localtransport/files" "" "" "" "$SET_PATH" \
  "$NONEMPTY_SET_FILES"
expect "nonempty_unreadable_set_reports_the_byte_count" 0 "total 4608 bytes"

# ...and it is still not the halt, which requires the marker to be FOUND.
configure yes "/data/data/com.android.localtransport/files" "" "" "" "$SET_PATH" \
  "$NONEMPTY_SET_FILES"
expect "nonempty_unreadable_set_is_still_not_a_failure" 0 "NOT a clean bill of health"

# A genuinely empty set must still get the empty-set wording, not the new one.
configure yes "/data/data/com.android.localtransport/files" "" "" "" "$SET_PATH" ""
expect "a_zero_byte_set_still_reads_as_empty" 0 \
  "So the set this run produced was EMPTY" "NOT empty and this check"

# --- Every present root is actually searched ----------------------------------
#
# THE FIFTH PINNED BUG, and the most serious one in this file's history: the
# §5.3 halt grep could not have found wallet material sitting in the real backup
# set, so the gate failed as a pass.
#
# `present` is built from `ls -d`, which emits ONE PATH PER LINE, and it was
# interpolated raw into the command strings handed to `adb shell`. A newline
# there does not separate arguments, it separates COMMANDS, so
#     grep -rl 'MARKER' /data/backup /data/data/com.android.localtransport/files
# was really sent as
#     grep -rl 'MARKER' /data/backup
#     /data/data/com.android.localtransport/files
# — the first root only, plus a line the shell tried to run as a program, whose
# failure `2>/dev/null` swallowed. On the emulator image both roots are present
# and the sets live under the SECOND one, so the tree that mattered was never
# read. Observed on the run for ecd2e5e, where `find` returned an unfiltered
# recursive listing of /data/backup and not one path matching its own -name.
#
# Every case above configures a single root, which is why the suite could not
# see this: with one root there is no newline and the bug is invisible. So this
# case configures TWO, and asserts against what the stub was actually handed
# rather than against the verdict -- the verdict is identical either way, which
# is precisely what made this silent.
two_roots="/data/backup
/data/data/com.android.localtransport/files"
configure yes "$two_roots" "" "" "" ""
rm -f "$stub_dir/cmdlog"
PATH="$stub_dir:$PATH" bash "$SCRIPT" >/dev/null 2>&1 || true

halt_grep=$(awk '/<<<END>>>/{f=0} f{print} /grep -rl .BIT101-WALLET-MARKER-/{f=1; print}' \
  "$stub_dir/cmdlog" 2>/dev/null | head -20)
if printf '%s' "$halt_grep" | grep -q '^/data/data/com.android.localtransport/files'; then
  echo "FAIL halt_grep_searches_every_present_root: the second root landed on its own"
  echo "     line, so it was a separate command and was never searched:"
  printf '%s\n' "$halt_grep" | sed 's/^/    /'
  failures=$((failures + 1))
else
  echo "ok   halt_grep_searches_every_present_root"
fi

for probe in "BIT101-WALLET-MARKER-" "BIT101-CANARY-MARKER-" "find"; do
  if grep -c "$probe" "$stub_dir/cmdlog" >/dev/null 2>&1 &&
     awk -v p="$probe" '
       /<<<END>>>/ {if (hit && n > 1) bad=1; hit=0; n=0; next}
       $0 ~ p {hit=1}
       hit {n++}
       END {exit bad ? 1 : 0}' "$stub_dir/cmdlog"; then
    echo "ok   ${probe}_is_sent_as_a_single_command"
  else
    echo "FAIL ${probe}_is_sent_as_a_single_command: spans more than one line, so"
    echo "     everything after the first newline is a separate command"
    failures=$((failures + 1))
  fi
done

# --- A decoy is reported, and is never by itself a halt -----------------------
#
# Clean of wallet material, non-empty, but the <exclude domain="file"> entries
# did not exclude the paths they name. That is a real finding and it is NOT
# §5.3: exit 0, and it must not print the halt.
configure yes "/data/data/com.android.localtransport/files" "" "$CANARY_IN_SET" \
  "/data/data/com.android.localtransport/files/1/com.bittr.android.regtest/d1"
expect "decoy_without_wallet_marker_is_not_a_halt" 0 "A DECOY" "HALT"

# --- Outcome 4a: no root ------------------------------------------------------
#
# Must NOT claim the set was clean. `adb root` is refused on a production image
# and that is a fact about the emulator, not about the wallet.
configure no "" ""
expect "outcome_4_no_root" 0 "was NOT inspected" "Looked inside the backup set"

# --- Outcome 4b: root, but none of the candidate directories exist ------------
#
# THE FIRST PINNED BUG. The inline first draft returned an empty grep here and
# printed "no wallet marker anywhere", which reads as evidence and is not.
configure yes "" ""
expect "outcome_4_no_directories" 0 "NOT evidence that the set was clean" \
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

# --- The canary and decoy prefixes are joined across the same two files --------
#
# Same argument as MARKER_PREFIX, failing in the opposite direction. If the
# canary prefix drifts, the canary grep matches nothing for ever and NO run ever
# reaches the evidence outcome — every run warns "the set was empty" instead.
# That is the safe direction (loud, not silent) but it is still permanently
# wrong, and it would look exactly like a genuine ineligible-package result,
# which is the one thing this check exists to tell apart. The decoy prefix
# drifting silently retires the dataExtractionRules finding.
check_prefix_agrees() {
  local name=$1 here test
  here=$(grep -oE "$name=\"[^\"]+\"" "$SCRIPT" | head -1 | cut -d'"' -f2)
  test=$(grep -oE "$name = \"[^\"]+\"" \
    "$SCRIPT_DIR/../app/src/androidTest/kotlin/com/bittr/android/BackupExclusionTest.kt" \
    | head -1 | cut -d'"' -f2)
  if [ "$here" = "$test" ] && [ -n "$here" ]; then
    echo "ok   ${name}_agrees_with_BackupExclusionTest ($here)"
  else
    echo "FAIL ${name}_agrees_with_BackupExclusionTest: script='$here' test='$test'"
    failures=$((failures + 1))
  fi
}
check_prefix_agrees CANARY_PREFIX
check_prefix_agrees DECOY_PREFIX

# --- ...and all three must be DISTINCT ----------------------------------------
#
# The reason they are three strings rather than one is that the canary and the
# decoys have to be findable WITHOUT that counting as the §5.3 halt. Collapse any
# two of them and the halt fires on the test's own canary — a spurious halt
# escalated to BIT-20 as an empirical result — or, worse, the wallet grep starts
# matching the decoy and the halt stops meaning what it says.
canary_here=$(grep -oE 'CANARY_PREFIX="[^"]+"' "$SCRIPT" | head -1 | cut -d'"' -f2)
decoy_here=$(grep -oE 'DECOY_PREFIX="[^"]+"' "$SCRIPT" | head -1 | cut -d'"' -f2)
distinct=yes
for pair in "$marker_here:$canary_here" "$marker_here:$decoy_here" "$canary_here:$decoy_here"; do
  a=${pair%%:*} b=${pair##*:}
  # Substring either way, not just equality: the greps are plain substring
  # matches, so a prefix that CONTAINS another matches wherever that one does.
  if [ "${a#*"$b"}" != "$a" ] || [ "${b#*"$a"}" != "$b" ]; then
    echo "FAIL prefixes_are_distinct: '$a' and '$b' overlap"
    distinct=no
    failures=$((failures + 1))
  fi
done
[ "$distinct" = yes ] && echo "ok   prefixes_are_distinct"

echo
if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed."
  exit 1
fi
echo "All check-backup-set.sh tests passed."
