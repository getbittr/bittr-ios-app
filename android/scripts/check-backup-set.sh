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
# Since BIT-108 it is not merely separate from the test — it is the ONLY thing
# that returns a verdict on BIT-20 rule 5. BackupExclusionTest used to plant
# files, back up, delete them, restore, and assert none came back. That assertion
# could not survive: `bmgr restore` kills the target process, and the
# instrumentation runs inside it. It was also vacuous-or-fatal by construction —
# a restore only kills the process when the framework has something to restore,
# so the assertion passed exactly when nothing had been backed up. The suite now
# creates the conditions and proves it created them; this script decides.
#
# This check needs no restore at all, and no surviving instrumentation process.
# If wallet material reached the set, the bytes are on disk under the transport's
# own directory and a grep finds them. That is why it still answers on a red run.
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
# FOUR OUTCOMES, AND ONLY ONE OF THEM IS EVIDENCE
#
#   1. Wallet marker found in the transport's tree -> exit 1. Wallet material
#      reached a real backup set. Unambiguous, and the BIT-20 §5.3 halt on
#      `match -> keep`.
#   2. No wallet marker, AND THE CANARY IS PRESENT -> exit 0, and this is the
#      only one that is evidence: the set was reachable, searched, provably
#      non-empty, and carried no wallet material.
#   3. No wallet marker and NO canary -> exit 0 with a ::warning::. NOT evidence.
#      See below; this is the outcome this file was extended for (BIT-109).
#   4. `adb root` refused, or no candidate directory exists on this image
#      -> exit 0 with a ::warning::. NOT evidence. A green BackupExclusionTest
#      from such a run rests on bmgr's report alone, and saying so is the whole
#      point — a check that cannot distinguish "clean" from "did not look" is
#      worse than no check, because it reads as the first.
#
# WHY OUTCOME 3 IS NOT OUTCOME 2 (BIT-109)
#
# Outcome 2 used to be reported for any run where the grep came back empty, and
# that is the same failure this file's header already refuses, arrived at from a
# different direction. `allowBackup="false"` makes the package ineligible, and an
# ineligible package produces an EMPTY SET. An empty set excludes wallet material
# trivially: no marker, no warning, and a ::notice:: claiming the set was
# searched and clean. "The rules excluded our wallet files" and "the framework
# never offered this package to the transport" are different facts, only one of
# them is evidence for rule 5, and they were producing the same green.
#
# And it is the LIKELY case, not an exotic one — `allowBackup="false"` is
# precisely what we ship. So BackupExclusionTest plants a canary in `files/`,
# which no rule excludes, under its own prefix. Canary in the set means the
# exclusion rules were actually consulted. No canary means there was nothing to
# consult them about, and the grep proved nothing.
#
# THE DECOYS ARE REPORTED, NEVER A HALT
#
# The `dataExtractionRules` `<exclude domain="file">` entries are rooted at
# getFilesDir(), while the wallet directory is under getNoBackupFilesDir() — a
# sibling, not a child. If those entries are a no-op, the `no_backup` siting is
# carrying rule 5 alone. BackupExclusionTest plants a decoy at each path those
# entries name, under a third prefix. Finding one is a finding about the RULES,
# not wallet material escaping, so it is printed alongside whatever outcome the
# run got and never trips the halt. The three prefixes are deliberately distinct
# strings so the canary and the decoys can be found without counting as outcome 1.
#
# A backup-set DIRECTORY existing for the package is deliberately NOT a failure.
# The platform creates and prunes those for its own reasons; only the wallet
# marker means our bytes are in there. It is printed so a person can see it.
set -euo pipefail

# Must match BackupExclusionTest's MARKER_PREFIX. test_check_backup_set.sh reads
# both files and fails in the `build` job if these two drift, because a drift
# would make the grep below match nothing for ever — a permanent silent pass on
# the one check that reads a real backup set.
MARKER_PREFIX="BIT101-WALLET-MARKER-"

# The canary's prefix. Its PRESENCE is what makes a clean grep evidence, so a
# drift here fails in the opposite direction to MARKER_PREFIX's: the grep below
# matches nothing for ever, no run ever reaches the evidence outcome, and every
# run warns that the set was empty. That is loud rather than silent — the safe
# direction for a drift to fail in — but it is still a permanently wrong verdict,
# so test_check_backup_set.sh pins this one against the test too.
CANARY_PREFIX="BIT101-CANARY-MARKER-"

# The decoys' prefix. Reported, never a halt — see the header.
DECOY_PREFIX="BIT101-DECOY-MARKER-"

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
canaries=$(adb shell "grep -rl '$CANARY_PREFIX' $present 2>/dev/null" | tr -d '\r' || true)
decoys=$(adb shell "grep -rl '$DECOY_PREFIX' $present 2>/dev/null" | tr -d '\r' || true)

# Printed before any verdict, so the decoy finding survives every exit path
# below — including the halt, where it is a second fact about the same set and
# not a reason to say anything less about the first.
if [ -n "$decoys" ]; then
  echo "::warning title=Backup rules::A DECOY ($DECOY_PREFIX) is in the backup set."\
    " The <exclude domain=\"file\"> entries in dataExtractionRules are rooted at"\
    " getFilesDir() and did NOT exclude a file at the path they name, so those"\
    " entries are a no-op and the getNoBackupFilesDir() siting is carrying BIT-20"\
    " rule 5 on its own. This is a finding about the RULES, not wallet material"\
    " escaping, and it is deliberately NOT the §5.3 halt. The fix is to correct"\
    " the rules, never to relax the rule. Files containing it:"
  printf '%s\n' "$decoys"
else
  echo "No decoy ($DECOY_PREFIX) in the set: the <exclude domain=\"file\"> entries"\
    " excluded the paths they name."
fi

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

# Outcome 3: no wallet marker, but nothing of ours is in the set at all, so the
# grep above searched a set that never had anything to exclude. Exit 0 — an
# ineligible package is a legitimate and in fact EXPECTED result of shipping
# `allowBackup="false"`, and failing the build for it would be reporting the
# wrong thing, exactly as with "could not gain root" above. But it is not
# evidence, and it must not be reported in the same words as outcome 2.
if [ -z "$canaries" ]; then
  echo "::warning title=Backup set inspection::The set was searched and carried no"\
    " wallet marker ($MARKER_PREFIX) — but it carried no canary ($CANARY_PREFIX)"\
    " either, and BackupExclusionTest plants the canary in files/, which no rule"\
    " excludes. So the set this run produced was EMPTY, almost certainly because"\
    " allowBackup=\"false\" made the package ineligible and the framework never"\
    " offered it to the transport. An empty set excludes wallet material"\
    " trivially. This is NOT evidence for BIT-20 rule 5: the exclusion rules were"\
    " never consulted, so nothing was proven about whether they work. It is also"\
    " NOT a failure — it is what shipping allowBackup=\"false\" is supposed to look"\
    " like. To get the evidence outcome instead, the run needs a set the framework"\
    " actually populated."
  exit 0
fi

# Outcome 2, and now it earns the name. A ::notice:: rather than a plain echo,
# and the asymmetry that fixes is the other half of this script's point. Of the
# four outcomes above, the three that are NOT evidence emit annotations (an
# ::error:: for the halt, ::warning::s for "did not look" and "nothing to look
# at"), while this one — the only one that is evidence — was a bare echo into the
# job log. On this public repo that log answers 403 and artifacts answer 401, so
# the run that PROVED something was the one run nobody could read without
# credentials, and the finding had to be taken on trust.
#
# It matters most exactly when the suite is red: this check reads the
# transport's tree from the host with no restore and no surviving instrumentation
# process, so it still answers when the in-process assertions cannot. See the
# empty-<failure> block in check-wallet-instrumented-results.py.
echo "::notice title=Backup set inspection::Looked inside the backup transport's own"\
  " on-disk tree from the host. The canary ($CANARY_PREFIX) IS in the set, so the"\
  " set is provably non-empty and the exclusion rules were actually consulted; and"\
  " NO wallet marker ($MARKER_PREFIX) is under any of the transport directories"\
  " present on this image. This is the evidence outcome for BIT-20 rule 5 — the set"\
  " was reachable, searched, non-empty, and carried no wallet material. It is"\
  " independent of whether the instrumentation process survived, so it holds even on"\
  " a red run. Canary found in:"
printf '%s\n' "$canaries"
echo "Looked inside the backup set: canary present, no wallet marker under any of the above."
exit 0
