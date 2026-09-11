#!/usr/bin/env bash
#
# BIT-59: run the wallet layer's instrumented tests on a real Android image.
#
# Invoked by .github/workflows/android-maestro.yml as the `script:` input to
# reactivecircus/android-emulator-runner, from the repository root, with an
# emulator already booted.
#
# WHY THIS IS A FILE AND NOT AN INLINE `script:` BLOCK
#
# Same reason as ci-smoke.sh and ci-instrumented.sh: the action hands that input
# to /usr/bin/sh, which on the Ubuntu images is dash, and `set -o pipefail`
# below would die on it AFTER the emulator has booted.
# android/scripts/check-action-scripts.sh enforces the `bash <file>` shape in the
# build job, seconds in rather than an emulator boot in.
#
# WHY TWO GRADLE TASKS AND NOT THE ONE BIT-59 ASKED FOR
#
# BIT-59 says `:core:wallet-ldk:connectedAndroidTest`. That is right for
# KeystoreKeyInfoTest and wrong for BackupExclusionTest, and the difference is
# not a preference.
#
# A library module's instrumented tests run in a self-instrumenting test APK
# built from the library's own manifest. :core:wallet-ldk has no
# AndroidManifest.xml, so that APK gets AGP's generated stub: no
# allowBackup="false", no dataExtractionRules, and therefore backup ENABLED.
# Running BackupExclusionTest there would measure the opposite configuration
# from the one we ship, and would most likely go red for a reason that has
# nothing to do with the wallet — or, worse, green for one.
#
# KeystoreKeyInfoTest does not care: the Android Keystore is a device service
# and the package calling it is irrelevant to what KeyInfo reports.
#
# So the suite splits by what each test is a property OF:
#   :core:wallet-ldk  — the Keystore, i.e. the platform's answer to our key spec.
#   :app              — the installed application, i.e. its manifest and its
#                       data directory as `bmgr` sees them.
#
# Locally, with an emulator up:
#   JOB_START_EPOCH=$(date +%s) bash android/scripts/ci-wallet-instrumented.sh
set -euo pipefail

job_start=${JOB_START_EPOCH:-0}
emulator_ready=$(date +%s)

adb devices

# --- Preflight: the backup transport has to be alive --------------------------
#
# This is the vacuity guard for the bmgr half, and it is the same shape as
# ci-instrumented.sh's WebView check for the same reason. Every backup assertion
# in BackupExclusionTest is of the form "the backup set does not contain the
# wallet material". On an image where the Backup Manager is off, or where no
# transport is selected, no backup set is produced for ANY package — so all of
# them pass, having proved nothing about our manifest.
#
# BackupExclusionTest.theBackupTransportIsActuallyAvailable asserts this from
# inside the suite too, so a green run cannot have skipped it. Doing it here as
# well buys a legible failure seconds in rather than one buried in a test report,
# and is where the transport actually gets turned on.

echo "--- Backup transport setup"

# `bmgr enable true` is idempotent and is the state the emulator images do not
# reliably start in.
adb shell bmgr enable true || true

# The local transport is the one that exists on a non-Play image. It writes its
# backup sets to local storage instead of to a Google account, which is what
# makes the question askable on CI at all. On google_apis images the GMS
# transport is selected by default and would try to talk to a real account.
#
# TWO NAMES, because AOSP has shipped it under both and which one you get is a
# property of the image rather than of the API level:
#
#   com.android.localtransport/.LocalTransport              (standalone package)
#   android/com.android.internal.backup.LocalTransport      (in the framework)
#
# Matching only the first would mean silently not selecting a transport that is
# right there, and then failing the '*' check below with a message blaming the
# image. Whatever is actually present is selected; if neither is, that is a real
# finding about the image and the check below reports it as one.
transports=$(adb shell bmgr list transports 2>/dev/null || true)

for local_transport in \
  "com.android.localtransport/.LocalTransport" \
  "android/com.android.internal.backup.LocalTransport"
do
  if printf '%s' "$transports" | grep -qF "$local_transport"; then
    echo "Selecting local backup transport: $local_transport"
    adb shell bmgr transport "$local_transport" || true
    transports=$(adb shell bmgr list transports 2>/dev/null || true)
    break
  fi
done

printf '%s\n' "$transports"

enabled=$(adb shell bmgr enabled 2>/dev/null || true)
echo "bmgr enabled: $enabled"

if ! printf '%s' "$enabled" | grep -qi 'currently enabled'; then
  echo "::error::The Backup Manager is not enabled on this emulator, so no backup"\
    " set can be produced for any package and every exclusion assertion in"\
    " BackupExclusionTest would pass vacuously. 'bmgr enable true' did not take."\
    " Reported: $enabled"
  exit 1
fi

if ! printf '%s' "$transports" | grep -q '\*'; then
  echo "::error::No backup transport is selected ('*' marks it), so bmgr backupnow"\
    " produces nothing for any package and BackupExclusionTest would be vacuously"\
    " green. Expected a local transport — com.android.localtransport/.LocalTransport"\
    " or android/com.android.internal.backup.LocalTransport — on a non-Play image."\
    " If neither is listed below, this image ships no backup transport at all and"\
    " the job needs a fuller system image than the one it booted. Reported:"
  printf '%s\n' "$transports"
  exit 1
fi

# --- The runs -----------------------------------------------------------------
#
# `|| status=$?` rather than letting set -e kill the script: a red run must still
# reach the results check and the summary below, because "which test failed" is
# the entire value of this job — and for BackupExclusionTest specifically, a RED
# result is a valid, reportable outcome of BIT-59 (the BIT-20 §5.3 halt), not a
# thing to retry until it goes away.
status=0
test_start=$(date +%s)

echo "--- :core:wallet-ldk:connectedDebugAndroidTest (Keystore — what the platform gave us)"
(cd android && ./gradlew :core:wallet-ldk:connectedDebugAndroidTest --no-daemon) || status=$?

echo "--- :app:connectedDebugAndroidTest (installed app — backup exclusion under bmgr)"
(cd android && ./gradlew :app:connectedDebugAndroidTest --no-daemon) || status=$?

test_end=$(date +%s)
duration=$((test_end - test_start))

# --- The vacuity check --------------------------------------------------------
#
# Deliberately runs whatever Gradle said. connectedDebugAndroidTest exits 0 when
# it matched no tests at all, so on a green run this is the load-bearing half.
check_status=0
python3 android/scripts/check-wallet-instrumented-results.py || check_status=$?

if [ "$status" -eq 0 ] && [ "$check_status" -ne 0 ]; then
  echo "::error::Gradle reported success but the required wallet tests did not all"\
    " run and pass. A green task with no evidence behind it is exactly what"\
    " wallet-security-properties.md §4 says must not be mistaken for proof."
fi

result="green"
if [ "$status" -ne 0 ] || [ "$check_status" -ne 0 ]; then
  result="RED"
fi

setup="not measured"
if [ "$job_start" -ne 0 ]; then
  setup=$((emulator_ready - job_start))
fi

{
  echo "### Wallet instrumented tests — on a real Android image"
  echo
  echo "| stage | seconds |"
  echo "|---|---:|"
  echo "| setup + emulator boot | $setup |"
  echo "| both \`connectedDebugAndroidTest\` runs | $duration |"
  echo
  echo "Result: **$result**"
  echo
  echo "\`KeystoreKeyInfoTest\` is BIT-8 rule 2 on a device: what the platform"
  echo "gave us, not what we asked for. \`BackupExclusionTest\` is the claim"
  echo "\`wallet-security-properties.md\` §4 calls the one not yet proven."
  echo
  echo "**A red \`BackupExclusionTest\` is a reportable outcome, not a flake.**"
  echo "Per BIT-20 §5.3 it is a halt on \`match → keep\`, and the result goes"
  echo "back to BIT-20 rather than being worked around here."
  echo
  echo "The device-to-device transfer path is NOT proven by this job — \`bmgr\`"
  echo "has no D2D mode. Grep the log for \`BACKUP_EXCLUSION_D2D\` for what was"
  echo "observed, and see \`wallet-security-properties.md\` §4 for why that gap"
  echo "is tracked rather than closed."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || echo "::warning::Could not write the summary. The test result itself is unaffected."

echo "::notice title=Wallet instrumented tests — $result::${duration}s · vacuity check $([ "$check_status" -eq 0 ] && echo passed || echo FAILED)"

if [ "$status" -ne 0 ]; then
  exit "$status"
fi
exit "$check_status"
