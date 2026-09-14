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
#   4. BIT-114's evidence channel: the file name both EvidenceLog copies write
#      and collect-wallet-evidence.sh reads, the directory it lives in, and the
#      prefix list the logcat fallback greps against the gate's EVIDENCE_PREFIXES.
#      Same class of silence again, and the one BIT-114 was: a gate reading a
#      channel nothing writes to reports an absence on a green run, and thirty
#      runs went by. What collect-wallet-evidence.sh DOES with those strings is
#      test_collect_wallet_evidence.sh's job — it drives the real script against
#      a stub `adb`. This file only pins that the strings agree.
#
# No device, no emulator, no Gradle: greps and comparisons.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

SCRIPT="$SCRIPT_DIR/ci-wallet-instrumented.sh"
GRADLE="$REPO_ROOT/android/app/build.gradle.kts"
WORKFLOW="$REPO_ROOT/.github/workflows/android-maestro.yml"
TEST_KT="$REPO_ROOT/android/app/src/androidTest/kotlin/com/bittr/android/BackupExclusionTest.kt"
# BIT-114's channel: the file the suites record their observations to and the
# host reads back. Both modules keep their own copy on purpose — see either
# file's header — so both are pinned, against each other and against the host.
APP_EVIDENCE_KT="$REPO_ROOT/android/app/src/androidTest/kotlin/com/bittr/android/EvidenceLog.kt"
LDK_EVIDENCE_KT="$REPO_ROOT/android/core/wallet-ldk/src/androidTest/kotlin/com/bittr/android/core/wallet/ldk/seed/EvidenceLog.kt"
CHECKER="$SCRIPT_DIR/check-wallet-instrumented-results.py"
COLLECTOR="$SCRIPT_DIR/collect-wallet-evidence.sh"

# BIT-135 added a second host phase with the same dependency on the installed
# package name and a worse failure mode: `am kill` on a package that does not
# exist exits 0, so a drifted name there means the app is never killed, the
# message reaches a LIVE process, a wake line appears, and the run reports a
# delivered wake having proved nothing whatever about process restart. Pinned
# here rather than in a second file because what is being pinned is one value in
# build.gradle.kts and, now, two readers of it.
FCM_SCRIPT="$SCRIPT_DIR/ci-fcm-delivery.sh"
FCM_WORKFLOW="$REPO_ROOT/.github/workflows/fcm-delivery.yml"

failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

for f in "$SCRIPT" "$GRADLE" "$WORKFLOW" "$TEST_KT" "$APP_EVIDENCE_KT" \
  "$LDK_EVIDENCE_KT" "$CHECKER" "$COLLECTOR" "$FCM_SCRIPT" "$FCM_WORKFLOW"; do
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

# --- 1 and 2. Every host script's default, and every workflow's APP_ID --------
#
# Two readers each, since BIT-135. A correct default with a drifted APP_ID is the
# same bug wearing the other hat — both scripts prefer $APP_ID when the step
# exported it — so both halves are checked for both jobs.

check_script_default() {
  script=$1
  script_default=$(grep -oE 'APP_PACKAGE="\$\{APP_ID:-[^}]+\}"' "$script" \
    | head -1 | sed -E 's/.*:-([^}]+)\}"/\1/')

  if [ -z "$script_default" ]; then
    fail "could not find an APP_PACKAGE=\"\${APP_ID:-…}\" assignment in $script."\
      "If the shape changed, update this pin in the same commit — dropping it"\
      "silently restores a bug that reads as a pass."
  elif [ "$script_default" != "$expected" ]; then
    fail "$(basename "$script") defaults APP_PACKAGE to '$script_default', but"\
      "Gradle installs '$expected'. In ci-wallet-instrumented.sh the"\
      "device-transfer phase would find no such package, skip the backup and leave"\
      "check-backup-set.sh grepping an empty set; in ci-fcm-delivery.sh the app"\
      "would never be killed and the wake would be delivered to a live process."\
      "Both measure nothing while reading as a pass."
  else
    echo "PASS: $(basename "$script") defaults to $script_default"
  fi
}

check_workflow_app_id() {
  workflow=$1
  workflow_app_id=$(grep -oE '^[[:space:]]*APP_ID:[[:space:]]*[^[:space:]#]+' "$workflow" \
    | head -1 | sed -E 's/.*APP_ID:[[:space:]]*//')

  if [ -z "$workflow_app_id" ]; then
    fail "could not find an APP_ID: entry in $workflow."
  elif [ "$workflow_app_id" != "$expected" ]; then
    fail "$(basename "$workflow") sets APP_ID=$workflow_app_id but Gradle installs"\
      "$expected. The host scripts prefer \$APP_ID over their own defaults, so this"\
      "drift defeats the default being right."
  else
    echo "PASS: $(basename "$workflow") sets APP_ID=$workflow_app_id"
  fi
}

check_script_default "$SCRIPT"
check_script_default "$FCM_SCRIPT"
check_workflow_app_id "$WORKFLOW"
check_workflow_app_id "$FCM_WORKFLOW"

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

# --- 4. The evidence channel — BIT-114 ----------------------------------------
#
# The hand-off above is an interlock; this is the record. Same shape, same
# silence when it drifts: the tests append their BACKUP_EXCLUSION and KEYSTORE_*
# lines to a file in the app's data directory, and the host reads that file back
# by name. There is no compiler between the two names either.
#
# It is pinned for a sharper reason than symmetry. The defect BIT-114 fixed was
# the gate reading a channel nothing writes to — <system-out>, which the AGP
# result writer has no element for — and it survived thirty runs because its
# failure mode is a green run that reports an absence. A drift here restores
# exactly that: the host reads a file name nothing writes, finds nothing, and
# the gate says the tests did not get that far.
kt_app_evidence=$(grep -oE 'const val FILE_NAME = "[^"]+"' "$APP_EVIDENCE_KT" \
  | head -1 | cut -d'"' -f2)
kt_ldk_evidence=$(grep -oE 'const val FILE_NAME = "[^"]+"' "$LDK_EVIDENCE_KT" \
  | head -1 | cut -d'"' -f2)
sh_evidence=$(grep -oE 'EVIDENCE_FILE_NAME="[^"]+"' "$COLLECTOR" | head -1 | cut -d'"' -f2)

if [ -z "$kt_app_evidence" ] || [ -z "$kt_ldk_evidence" ] || [ -z "$sh_evidence" ]; then
  fail "could not read the evidence file name from all three sides"\
    "(:app='${kt_app_evidence:-not found}', :core:wallet-ldk='${kt_ldk_evidence:-not found}',"\
    "collect-wallet-evidence.sh='${sh_evidence:-not found}'). If a declaration changed"\
    "shape, update this pin in the same commit."
elif [ "$kt_app_evidence" != "$sh_evidence" ] || [ "$kt_ldk_evidence" != "$sh_evidence" ]; then
  fail "the evidence file name drifted: :app writes '$kt_app_evidence',"\
    ":core:wallet-ldk writes '$kt_ldk_evidence', the host reads '$sh_evidence'."\
    "The host would find nothing and the gate would report the observations as"\
    "never recorded — a green run that says it could not see, which is the state"\
    "BIT-114 existed to end."
else
  echo "PASS: both modules and the host use the evidence file '$sh_evidence'"
fi

# Both copies must write it where the host looks: under noBackupFilesDir, which
# is what keeps a file naming MARKER_PREFIX out of the set check-backup-set.sh
# greps, and is the directory the host's glob reads.
for evidence_kt in "$APP_EVIDENCE_KT" "$LDK_EVIDENCE_KT"; do
  if ! grep -q 'noBackupFilesDir' "$evidence_kt"; then
    fail "$(basename "$(dirname "$evidence_kt")")/$(basename "$evidence_kt") does not"\
      "write under noBackupFilesDir. The host reads"\
      "/data/data/com.bittr.android*/no_backup/, so the file would not be found —"\
      "and a file quoting MARKER_PREFIX outside no_backup/ could reach the set the"\
      "halt grep searches."
  fi
done
# shellcheck disable=SC2016  # the literal `$EVIDENCE_FILE_NAME` is the pattern.
if ! grep -q 'no_backup/\$EVIDENCE_FILE_NAME' "$COLLECTOR"; then
  fail "collect-wallet-evidence.sh no longer reads the evidence file from"\
    "no_backup/, but both EvidenceLog copies write it there."
else
  echo "PASS: both sides agree the evidence file lives under no_backup/"
fi

# The logcat fallback's prefixes against the gate's EVIDENCE_PREFIXES. The
# fallback is what answers on an image that refuses `adb root`, and a prefix
# added to the gate but not to the grep narrows it silently — the run reports
# fewer observations than it made, with nothing to say it did.
gate_prefixes=$(grep -A6 '^EVIDENCE_PREFIXES = (' "$CHECKER" \
  | grep -oE '"[A-Z_]+"' | tr -d '"' | sort | tr '\n' ' ')
fallback_prefixes=$(grep -oE "\\^\\((BACKUP|KEYSTORE)[A-Z_|]*\\)" "$COLLECTOR" \
  | head -1 | tr -d '^()' | tr '|' '\n' | sort | tr '\n' ' ')

if [ -z "$gate_prefixes" ] || [ -z "$fallback_prefixes" ]; then
  fail "could not read the evidence prefixes from both sides"\
    "(gate='${gate_prefixes:-not found}', logcat fallback='${fallback_prefixes:-not found}')."
elif [ "$gate_prefixes" != "$fallback_prefixes" ]; then
  fail "the evidence prefixes drifted: check-wallet-instrumented-results.py reads"\
    "[$gate_prefixes], collect-wallet-evidence.sh's logcat fallback greps"\
    "[$fallback_prefixes]. Whichever is missing is dropped on any run that falls"\
    "back to logcat, silently and only there."
else
  echo "PASS: the gate and the logcat fallback agree on [$gate_prefixes]"
fi

# EvidenceLog truncates its file once per instrumentation PROCESS, which is
# right for one `am instrument` invocation per module and wrong under the Android
# Test Orchestrator, which gives every test method its own invocation. Enabling
# it would leave the file holding only the last test's lines — the earlier ones
# clobbered, on a green run, with nothing to say so. That is BIT-114's failure
# mode exactly, so the assumption is pinned rather than trusted.
#
# Not a ban. If the orchestrator is wanted, the fix is to drop the truncate and
# rely on collect-wallet-evidence.sh --clear, which already runs before the first
# Gradle task and is covered by test_collect_wallet_evidence.sh. This check is
# what makes that a decision rather than an accident.
orchestrator=$(grep -rlE 'ANDROIDX_TEST_ORCHESTRATOR|androidx\.test:orchestrator|execution[[:space:]]*=' \
  "$REPO_ROOT/android/app/build.gradle.kts" \
  "$REPO_ROOT/android/core/wallet-ldk/build.gradle.kts" \
  "$REPO_ROOT/android/build.gradle.kts" 2>/dev/null)

if [ -n "$orchestrator" ]; then
  fail "the Android Test Orchestrator appears to be configured in:"\
    "$(printf '%s' "$orchestrator" | tr '\n' ' ')."\
    "It runs each test method in its own instrumentation process, and"\
    "EvidenceLog truncates its file once per process — so every test but the last"\
    "would have its BACKUP_EXCLUSION and KEYSTORE_* lines clobbered, silently, on"\
    "a green run. Drop the truncate in both EvidenceLog copies and rely on"\
    "collect-wallet-evidence.sh --clear instead, then delete this check."
else
  echo "PASS: no test orchestrator, so one instrumentation process per module run"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "All host-phase pins hold."
  exit 0
fi
echo "$failures failure(s)."
exit 1
