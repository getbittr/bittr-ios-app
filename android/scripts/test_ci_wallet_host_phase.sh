#!/usr/bin/env bash
#
# Pins the strings ci-wallet-instrumented.sh's host-driven device-transfer phase
# uses to reach the device, against the files that actually define them.
#
#   bash android/scripts/test_ci_wallet_host_phase.sh
#
# WHY THIS EXISTS
#
# BIT-108 moved the device-transfer backup out of the instrumentation process
# and onto the host, where it is driven by `adb`. Everything on that side names
# the package as a string — `pm list packages`, the hand-off path under
# /data/data/<pkg>/, `bmgr backupnow <pkg>`, and the per-package result line
# parsed back out of its output. There is no compiler and no manifest between
# that string and the device.
#
# The first version of that phase used `com.bittr.android`, which is the
# `namespace` in build.gradle.kts and NOT what gets installed: `applicationId`
# is com.bittr.android, the debug build type adds `applicationIdSuffix =
# ".regtest"`, and connectedDebugAndroidTest installs the debug variant. So the
# phase addressed a package that does not exist on the device.
#
# That failure is silent, and it fails toward green. The anchored `pm list
# packages` match simply misses, the phase reports "not installed", skips the
# backup, and check-backup-set.sh greps a set that nothing ever wrote — which
# under BIT-109's canary rule now reads as "the set was empty", a warning at
# exit 0. A run in that state has measured nothing about BIT-20 rule 5 while
# looking like a run that measured something and shrugged.
#
# It is also exactly the drift test_check_backup_set.sh already guards against
# for MARKER_PREFIX, arrived at from the other end: there, the grep string can
# drift away from what the test plants; here, the package name can drift away
# from what Gradle installs. Same class, same silence, same fix — pin it in the
# build job, where a mismatch is a red on a machine with no emulator, seconds
# after the rename that caused it.
#
# WHAT IS PINNED
#
#   1. The script's APP_PACKAGE default == applicationId + debug
#      applicationIdSuffix, read out of build.gradle.kts.
#   2. The workflow's APP_ID env == the same, because the script prefers $APP_ID
#      when the step exported it. A correct default with a drifted APP_ID is the
#      same bug wearing the other hat, and the workflow's own comment already
#      claims this equality — this is what makes the claim true.
#   3. The hand-off marker and file name == BackupExclusionTest's HANDOFF and
#      HANDOFF_FILE. The hand-off is the whole interlock between the two halves:
#      the test plants the wallet material and writes the file, the host refuses
#      to back up until it reads it. A drift there fails the same silent way —
#      the host never finds the hand-off, declines to drive the backup, and
#      warns that the plant never happened when it did.
#
# No device, no emulator, no Gradle: greps and comparisons.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

SCRIPT="$SCRIPT_DIR/ci-wallet-instrumented.sh"
GRADLE="$REPO_ROOT/android/app/build.gradle.kts"
WORKFLOW="$REPO_ROOT/.github/workflows/android-maestro.yml"
TEST_KT="$REPO_ROOT/android/app/src/androidTest/kotlin/com/bittr/android/BackupExclusionTest.kt"

failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

for f in "$SCRIPT" "$GRADLE" "$WORKFLOW" "$TEST_KT"; do
  [ -f "$f" ] || { fail "missing file: $f"; }
done
[ "$failures" -eq 0 ] || { echo; echo "$failures failure(s)."; exit 1; }

# --- What Gradle installs -----------------------------------------------------
#
# Matched loosely on purpose. These two lines are ordinary Kotlin DSL assignments
# and the point is to follow a rename, so the patterns tolerate spacing but not
# ambiguity: if either match comes back empty or doubled, that is reported rather
# than silently resolved, because a wrong answer here re-creates the exact bug
# this file exists to end.
application_id=$(grep -oE '^[[:space:]]*applicationId[[:space:]]*=[[:space:]]*"[^"]+"' "$GRADLE" \
  | grep -oE '"[^"]+"' | tr -d '"')
suffix=$(grep -oE '^[[:space:]]*applicationIdSuffix[[:space:]]*=[[:space:]]*"[^"]+"' "$GRADLE" \
  | grep -oE '"[^"]+"' | tr -d '"')

if [ "$(printf '%s\n' "$application_id" | grep -c .)" -ne 1 ]; then
  fail "expected exactly one applicationId in build.gradle.kts, found: ${application_id:-none}"
fi
if [ "$(printf '%s\n' "$suffix" | grep -c .)" -ne 1 ]; then
  fail "expected exactly one applicationIdSuffix in build.gradle.kts, found: ${suffix:-none}"\
    "— if the debug suffix was removed, this file and ci-wallet-instrumented.sh both need updating"
fi
[ "$failures" -eq 0 ] || { echo; echo "$failures failure(s)."; exit 1; }

expected="${application_id}${suffix}"
echo "build.gradle.kts installs the debug variant as: $expected"

# --- 1. The script's default --------------------------------------------------
script_default=$(grep -oE 'APP_PACKAGE="\$\{APP_ID:-[^}]+\}"' "$SCRIPT" \
  | head -1 | sed -E 's/.*:-([^}]+)\}"/\1/')

if [ -z "$script_default" ]; then
  fail "could not find an APP_PACKAGE=\"\${APP_ID:-…}\" assignment in $SCRIPT."\
    "If the shape changed, update this pin in the same commit — dropping it"\
    "silently restores a bug that reads as a pass."
elif [ "$script_default" != "$expected" ]; then
  fail "ci-wallet-instrumented.sh defaults APP_PACKAGE to '$script_default',"\
    "but Gradle installs '$expected'. The device-transfer phase would find no"\
    "such package, skip the backup, and leave check-backup-set.sh grepping an"\
    "empty set — a run that measures nothing while reading as a pass."
else
  echo "PASS: ci-wallet-instrumented.sh defaults to $script_default"
fi

# --- 2. The workflow's APP_ID -------------------------------------------------
workflow_app_id=$(grep -oE '^[[:space:]]*APP_ID:[[:space:]]*[^[:space:]#]+' "$WORKFLOW" \
  | head -1 | sed -E 's/.*APP_ID:[[:space:]]*//')

if [ -z "$workflow_app_id" ]; then
  fail "could not find an APP_ID: entry in $WORKFLOW."
elif [ "$workflow_app_id" != "$expected" ]; then
  fail "the workflow sets APP_ID=$workflow_app_id but Gradle installs $expected."\
    "ci-wallet-instrumented.sh prefers \$APP_ID over its own default, so this"\
    "drift defeats the default being right."
else
  echo "PASS: the workflow sets APP_ID=$workflow_app_id"
fi

# --- 3. The hand-off interlock ------------------------------------------------
#
# Matched exactly, in both directions. The host greps for the marker with
# `grep -qF`, so a drift on either side is not a near miss that degrades — the
# host simply never sees a hand-off and reports the plant as never having
# happened. That reads as "the test was filtered out or failed", which is a
# plausible enough sentence to be believed.
kt_handoff=$(grep -oE 'const val HANDOFF = "[^"]+"' "$TEST_KT" | head -1 | cut -d'"' -f2)
kt_handoff_file=$(grep -oE 'const val HANDOFF_FILE = "[^"]+"' "$TEST_KT" | head -1 | cut -d'"' -f2)

sh_handoff=$(grep -oE 'HANDOFF_MARKER="[^"]+"' "$SCRIPT" | head -1 | cut -d'"' -f2)
sh_handoff_path=$(grep -oE 'HANDOFF_PATH="[^"]+"' "$SCRIPT" | head -1 | cut -d'"' -f2)
sh_handoff_file=${sh_handoff_path##*/}

if [ -z "$kt_handoff" ] || [ -z "$sh_handoff" ]; then
  fail "could not read the hand-off marker from both sides"\
    "(BackupExclusionTest HANDOFF='${kt_handoff:-not found}',"\
    "ci-wallet-instrumented.sh HANDOFF_MARKER='${sh_handoff:-not found}')."\
    "If either declaration changed shape, update this pin in the same commit."
elif [ "$kt_handoff" != "$sh_handoff" ]; then
  fail "the hand-off marker drifted: the test writes '$kt_handoff', the host"\
    "greps for '$sh_handoff'. The host would never see a hand-off and would"\
    "report the wallet material as never planted on every run."
else
  echo "PASS: both sides use the hand-off marker '$kt_handoff'"
fi

if [ -z "$kt_handoff_file" ] || [ -z "$sh_handoff_file" ]; then
  fail "could not read the hand-off file name from both sides"\
    "(HANDOFF_FILE='${kt_handoff_file:-not found}', HANDOFF_PATH='${sh_handoff_path:-not found}')."
elif [ "$kt_handoff_file" != "$sh_handoff_file" ]; then
  fail "the hand-off file name drifted: the test writes '$kt_handoff_file' into"\
    "noBackupFilesDir, the host reads '$sh_handoff_path'."
else
  echo "PASS: both sides use the hand-off file '$kt_handoff_file'"
fi

# The hand-off must live under the package the rest of this phase addresses, or
# the host reads a path belonging to no installed app — the package pin above
# would hold and the phase would still find nothing.
case "$sh_handoff_path" in
  */no_backup/*) : ;;
  *) fail "the hand-off path '$sh_handoff_path' is not under no_backup/, but the"\
       "test writes it to noBackupFilesDir. It must also stay there for another"\
       "reason: no_backup/ is excluded from the set, so the hand-off cannot"\
       "contaminate what check-backup-set.sh greps." ;;
esac
if ! printf '%s' "$sh_handoff_path" | grep -qF "\$APP_PACKAGE"; then
  fail "the hand-off path '$sh_handoff_path' does not interpolate \$APP_PACKAGE,"\
    "so a package rename would leave it pointing at another app's data directory."
else
  echo "PASS: the hand-off path is rooted at \$APP_PACKAGE and under no_backup/"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "All host-phase pins hold."
  exit 0
fi
echo "$failures failure(s)."
exit 1
