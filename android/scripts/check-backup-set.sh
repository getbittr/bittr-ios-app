#!/usr/bin/env bash
#
# BIT-59: read the backup SET, not bmgr's report of it.
#
#   bash android/scripts/check-backup-set.sh
#
# Exit codes:
#   0  clean, OR the set could not be inspected (see below — these are printed
#      very differently and only one of them is evidence)
#   1  wallet material was found inside a real backup set — the BIT-20 §5.3 HALT
#
# WHY THIS IS SEPARATE FROM THE TEST
#
# BackupExclusionTest plants files, backs up, deletes them, restores, and
# asserts none of them came back. That is a strong test, and it is also one
# whose green depends on `bmgr restore` having done something: a restore that
# silently no-ops produces "nothing came back" for the wrong reason. The suite's
# canary catches that when the framework reported Success — and by construction
# cannot when the framework declined the package, which is the expected
# `allowBackup="false"` outcome on the cloud path.
#
# This check needs no restore at all. If wallet material reached the set, the
# bytes are on disk under the transport's own directory and a grep finds them.
#
# The set lives under the transport's data directory, mode 0700 to another uid,
# and UiAutomation's shell runs as `shell` — so the test process cannot read it
# no matter how it is written. From the host, after `adb root`, it can be.
#
# WHY IT IS ITS OWN FILE RATHER THAN A BLOCK IN ci-wallet-instrumented.sh
#
# It decides a HALT, and everything else in this repo that decides something
# gets tested for it — ci-runs.py, check-instrumented-results.py,
# check-wallet-instrumented-results.py, report-test-failures.py. Inline in a
# script that runs Gradle against a booted emulator, this logic is reachable
# only by booting an emulator; as a file with a seam at `adb`, it is reachable
# by test_check_backup_set.sh with a stub on PATH. The first draft of it WAS
# inline, and it shipped the exact vacuity bug described below — grepping three
# paths that may not exist on this image and reporting the empty result as
# "clean". That is the bug this whole job exists to refuse, and it took a
# re-read rather than a test to catch.
#
# THREE OUTCOMES, AND ONLY ONE OF THEM IS EVIDENCE
#
#   1. Marker found in the transport's tree  -> exit 1. Wallet material reached a
#      real backup set. Unambiguous, and the BIT-20 §5.3 halt on `match -> keep`.
#   2. Transport directories present, no marker -> exit 0, and this is the one
#      that is evidence: we looked at the set and it was clean.
#   3. `adb root` refused, or no candidate directory exists on this image
#      -> exit 0 with a ::warning::. NOT evidence. A green BackupExclusionTest
#      from such a run rests on bmgr's report alone, and saying so is the whole
#      point — a check that cannot distinguish "clean" from "did not look" is
#      worse than no check, because it reads as the first.
#
# A backup-set DIRECTORY existing for the package is deliberately NOT a failure.
# The platform creates and prunes those for its own reasons; only the marker
# means our bytes are in there. It is printed so a person can see it.
set -euo pipefail

# Must match BackupExclusionTest's MARKER_PREFIX. test_check_backup_set.sh reads
# both files and fails in the `build` job if these two drift, because a drift
# would make the grep below match nothing for ever — a permanent silent pass on
# the one check that reads a real backup set.
MARKER_PREFIX="BIT101-WALLET-MARKER-"

# Where the local transport keeps its sets. Image-dependent, and which of the
# two LocalTransport packagings is present varies too, so this is a candidate
# list rather than a path. Anything not present is skipped, and ALL of them
# being absent is outcome 3 above, not outcome 2.
SET_ROOTS="/data/data/com.android.localtransport/files /data/system/backup /data/backup"

echo "--- Backup set inspection (the half the test cannot reach)"

if ! adb root >/dev/null 2>&1 || ! adb wait-for-device; then
  echo "::warning::Could not gain root on this device, so the backup set itself"\
    " was NOT inspected — only bmgr's report of it was. A green"\
    " BackupExclusionTest from this run is therefore weaker evidence than one"\
    " from a run where this check executed. It is not a failure: 'adb root' is"\
    " refused on a production image, and reporting that as a wallet finding"\
    " would be reporting the wrong thing."
  exit 0
fi

# $SET_ROOTS expands inside the double quotes, so the HOST shell does no
# splitting — the device shell splits it into separate arguments, which is the
# intent. Quoting it further would hand `ls` one path with spaces in it.
present=$(adb shell "ls -d $SET_ROOTS 2>/dev/null" | tr -d '\r' || true)

if [ -z "$present" ]; then
  echo "::warning::None of the candidate backup-transport directories exist on"\
    " this image, so the backup set itself was NOT inspected — only bmgr's"\
    " report of it was. This is NOT evidence that the set was clean. Looked in:"\
    " $SET_ROOTS. If this image keeps its sets elsewhere, add that path to"\
    " SET_ROOTS in this script; until then this run's BackupExclusionTest green"\
    " rests on bmgr's report alone."
  adb shell bmgr list transports 2>/dev/null | tr -d '\r' || true
  exit 0
fi

echo "Transport directories present on this image:"
printf '%s\n' "$present"

sets=$(adb shell "find $present -maxdepth 3 -name '*bittr*' 2>/dev/null" | tr -d '\r' || true)
echo "Backup-set paths mentioning this package (recorded, not asserted):"
printf '%s\n' "${sets:-  (none)}"

leaks=$(adb shell "grep -rl '$MARKER_PREFIX' $present 2>/dev/null" | tr -d '\r' || true)

if [ -n "$leaks" ]; then
  echo "::error::WALLET MATERIAL IS IN A REAL BACKUP SET. The marker"\
    " BackupExclusionTest wrote into the LDK state files it planted was found"\
    " inside the backup transport's own tree, which means the exclusion did not"\
    " hold on this device. This is the BIT-20 §5.3 HALT on 'match -> keep' — not"\
    " a flake, and not a test to loosen. It goes back to BIT-20 with this result"\
    " attached. Files containing it:"
  printf '%s\n' "$leaks"
  exit 1
fi

echo "Looked inside the backup set: no wallet marker under any of the above."
exit 0
