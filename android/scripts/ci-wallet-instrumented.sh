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
# BackupExclusionTest.backupManagerAndTheLocalTransportAreLiveOnThisDevice
# asserts this from inside the suite too — and asserts the LOCAL transport by
# name, not merely that some transport is selected — so a green run cannot have
# skipped it. Doing it here as
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

# Tee'd rather than left to the job log, because the job log is not readable.
# /actions/jobs/{id}/logs answers 403 "Must have admin rights to Repository" on
# this PUBLIC repo, and artifacts answer 401, so from outside the runner the only
# anonymous channel is the check-run annotation list. Gradle failing BEFORE any
# test runs — install rejected, no connected device, a missing SDK component —
# produces no JUnit XML, so the results gate can only say "the required tests did
# not run" with an empty list of failures under it. That is the exact shape of
# the two runs this was added for: it distinguishes "no test asked" from "the
# wallet claim is false", and those are the two outcomes this job exists to keep
# apart.
#
# Written by the emulator runner; fall back so the script stays runnable locally.
RUNNER_TEMP_DIR=${RUNNER_TEMP:-${TMPDIR:-/tmp}}

# `run_gradle <label> <task>`: stream to the log as before, keep a copy, and on
# failure re-state the tail INSIDE an ::error:: so it lands in the annotations.
#
# The encoding is the point and is easy to get wrong. A workflow command is one
# line: everything after the first newline is ordinary log output, i.e. invisible
# again. Literal newlines therefore have to be sent as the `%0A` escape, and `%`
# itself has to be escaped first or a `%` in Gradle's output would corrupt the
# ones we add. Order matters — `%` before `%0A`.
run_gradle() {
  label=$1
  task=$2
  shift 2
  log="$RUNNER_TEMP_DIR/$(echo "$task" | tr ':' '_').log"

  echo "--- $task ($label)"
  # `set -o pipefail` is on, so this takes Gradle's status and not tee's.
  if (cd android && ./gradlew "$task" "$@" --no-daemon 2>&1) | tee "$log"; then
    return 0
  fi

  # 40 lines: enough for a Gradle "What went wrong" block plus its cause chain,
  # short enough to stay well inside the annotation message limit.
  tail_encoded=$(tail -40 "$log" | sed -e 's/%/%25/g' | awk '{printf "%s%%0A", $0}')

  echo "::error::$task FAILED — Gradle's own output, not a test failure. If the"\
    " tail below shows an install, device or SDK error then no test ran, and the"\
    " results gate's empty failure list means 'nothing executed' rather than"\
    " 'nothing broke'. Last 40 lines:%0A$tail_encoded"
  return 1
}

run_gradle "Keystore — what the platform gave us" \
  :core:wallet-ldk:connectedDebugAndroidTest || status=$?

# `leaveApksInstalledAfterRun` — the app has to still BE there afterwards.
#
# AGP uninstalls both APKs when connectedAndroidTest finishes. That was harmless
# while the suite drove its own backup, and it is fatal now that the
# device-transfer backup is driven below: an uninstall takes the planted wallet
# material with it, and `bmgr backupnow` on a package that is not installed
# produces nothing. The host phase would then inspect an empty set and
# check-backup-set.sh would report "no wallet marker" — true, meaningless, and
# indistinguishable from the real result.
#
# If this option is ever dropped or renamed by AGP, the phase below says so out
# loud rather than grepping an empty set: it checks `pm list packages` first.
run_gradle "installed app — backup exclusion under bmgr" \
  :app:connectedDebugAndroidTest \
  -Pandroid.injected.androidTest.leaveApksInstalledAfterRun=true || status=$?

test_end=$(date +%s)
duration=$((test_end - test_start))

# --- The device-transfer backup, driven from HERE and not from the test -------
#
# BIT-108. `bmgr backupnow` on the device-transfer path binds a backup agent
# inside the target process and the framework kills that process when it tears
# the agent down. The instrumentation runs in that process, so a test that drives
# this backup kills itself: runs 107 and 133 both ended at exactly this point
# with an empty <failure> and every subsequent test unrun.
#
# Dropping the in-process `bmgr restore` (a1fbe36) was necessary and not
# sufficient — run 133 carried that fix and died identically. The backup is the
# other half, and it has the same shape as the restore did: it cannot be driven
# from the process it acts on, and writing it more carefully does not change
# that. Here there is no instrumentation process left to kill.
#
# The division of labour, which the test's class comment states from the other
# side: BackupExclusionTest plants the wallet material, the canary and the
# decoys, arms the transport's is_device_transfer hook, clears the stale dataset
# and writes a hand-off file. This drives the backup. check-backup-set.sh reads
# the set. None of the three is evidence alone.
echo "--- Device-transfer backup (host-driven — see BIT-108)"

# The INSTALLED package, which is not the namespace. build.gradle.kts sets
# `applicationId = "com.bittr.android"` and the debug build type adds
# `applicationIdSuffix = ".regtest"`, and connectedDebugAndroidTest installs the
# debug variant — so everything below has to address `com.bittr.android.regtest`.
#
# Getting this wrong is silent in the worst available direction, and the first
# draft of this phase got it wrong: `pm list packages` does not match, the phase
# reports the app as not installed, the backup is skipped, and
# check-backup-set.sh greps a set nothing ever wrote. The run is green with one
# warning, and that warning blames AGP for an uninstall that never happened.
#
# $APP_ID is the workflow's copy of the same value (see its `env:` block, which
# carries the same "must match build.gradle.kts" note) and is preferred when the
# step exported it; the literal is the fallback for a local invocation.
# test_ci_wallet_host_phase.sh pins both against build.gradle.kts, so a rename
# there fails in the build job rather than here, where the failure is a warning
# nobody reads as a bug.
APP_PACKAGE="${APP_ID:-com.bittr.android.regtest}"
HANDOFF_MARKER="BACKUP_EXCLUSION_HANDOFF device-transfer-plant-ready"
HANDOFF_PATH="/data/data/$APP_PACKAGE/no_backup/backup_handoff.txt"

echo "Target package: $APP_PACKAGE (APP_ID is ${APP_ID:-unset in this step})"

# `|| true` throughout this phase, and no `status=$?` anywhere in it: a host
# phase that cannot run is a "did not look", not a wallet finding. Every exit
# from it that is not a completed backup ends in a ::warning:: and leaves
# check-backup-set.sh to report that it has nothing to stand on. Turning any of
# these into a red would be claiming a result this job did not get.
device_transfer_backed_up=no

# `tr -d '\r'` on every `adb shell` capture in this phase, not decoration.
# adbd puts the device's line discipline on the wire, so output arrives CRLF.
# An anchored match like `^package:…$` then never matches — the line ends in a
# carriage return, not at the package name — and the failure is the worst kind
# available here: it reads as "the app is not installed", skips the backup, and
# leaves check-backup-set.sh grepping an empty set. Silent, and green apart from
# a warning that would be blaming the wrong thing.
installed_packages=$(adb shell pm list packages 2>/dev/null | tr -d '\r' || true)

if ! printf '%s\n' "$installed_packages" | grep -q "^package:$APP_PACKAGE$"; then
  # Which of the two causes it was. The anchored match fails identically whether
  # AGP uninstalled the app or this script is addressing the wrong name, and
  # those call for opposite fixes — so the warning quotes what the device
  # actually has rather than asserting the cause. `(none)` is the uninstall;
  # anything listed is a naming drift this script lost a run to once already.
  bittr_packages=$(printf '%s\n' "$installed_packages" | grep -i 'bittr' || true)
  bittr_packages=$(printf '%s' "${bittr_packages:-  (none)}" | tr '\n' ' ')

  echo "::warning title=Device-transfer backup::$APP_PACKAGE is not installed after"\
    " connectedAndroidTest, so there is nothing to back up on the device-transfer"\
    " path and no set for check-backup-set.sh to read. The bittr packages this device"\
    " DOES have are:$bittr_packages. If that is (none), the cause is that"\
    " -Pandroid.injected.androidTest.leaveApksInstalledAfterRun stopped being honoured"\
    " by this AGP version, which would mean AGP uninstalled the app and the planted"\
    " wallet material with it. If a package IS listed, this script is addressing the"\
    " wrong name and test_ci_wallet_host_phase.sh should have caught it. Either way this"\
    " is a harness failure, NOT evidence about rule 5: any 'no wallet marker' below is"\
    " a grep of an empty set."
else
  # `adb root` is what makes the app's data directory readable from here. It is
  # also what check-backup-set.sh needs, and the same caveat applies: a userdebug
  # image grants it, a user build does not, and a refusal is a "cannot look".
  adb root >/dev/null 2>&1 || true
  adb wait-for-device >/dev/null 2>&1 || true

  handoff=$(adb shell cat "$HANDOFF_PATH" 2>/dev/null | tr -d '\r' || true)

  if ! printf '%s' "$handoff" | grep -qF "$HANDOFF_MARKER"; then
    echo "::warning title=Device-transfer backup::No hand-off from"\
      " BackupExclusionTest#deviceTransferOfAWalletBearingInstallCarriesNoWalletMaterial"\
      " at $HANDOFF_PATH, so the wallet material was never planted on this run and the"\
      " backup below is NOT being driven. Backing up anyway would write an empty set,"\
      " and an empty set reads identically to a clean one — the vacuous green this job"\
      " exists to refuse. Read any 'no wallet marker' result from this run as 'did not"\
      " look'. Causes: the test was filtered out, renamed, or failed before it finished"\
      " planting; or 'adb root' was refused on this image so the file cannot be read."
  else
    echo "Hand-off found. The plant is on disk and the stale dataset is cleared."

    # Re-assert rather than trust. The test armed the hook and selected the
    # transport before it exited, and @After deliberately leaves both alone once
    # it has handed off — but "deliberately left alone" is a claim about code
    # that ran on the other side of a Gradle exit. The cost of setting them again
    # is two adb calls; the cost of being wrong is a cloud backup reported as a
    # device-transfer one, which is the single failure mode this whole second
    # path exists to rule out.
    adb shell settings put secure backup_local_transport_parameters is_device_transfer=true || true
    adb shell bmgr transport com.android.localtransport/.LocalTransport >/dev/null 2>&1 || true

    parameters=$(adb shell settings get secure backup_local_transport_parameters 2>/dev/null | tr -d '\r' || true)
    echo "Transport parameters: $parameters"

    if ! printf '%s' "$parameters" | grep -qF 'is_device_transfer=true'; then
      echo "::warning title=Device-transfer backup::The local transport's"\
        " is_device_transfer hook did not take — the settings provider reports"\
        " \"$parameters\". A backup driven now would take the CLOUD path while being"\
        " reported as the device-transfer one, which is the one confusion that would"\
        " make a green here meaningless: allowBackup=\"false\" is expected to cover the"\
        " cloud path, and the whole point of this path is that it may not cover D2D."\
        " Not backing up."
    else
      backup_output=$(adb shell bmgr backupnow "$APP_PACKAGE" 2>&1 | tr -d '\r' || true)
      printf '%s\n' "$backup_output"

      # The same per-package result line BackupExclusionTest parses on the cloud
      # path, checked here for the same reason: a transport error leaves no set,
      # and a grep of no set is not evidence of anything.
      result=$(printf '%s' "$backup_output" \
        | sed -n "s/.*Package $APP_PACKAGE with result:[[:space:]]*//p" | head -1)

      if [ -z "$result" ]; then
        echo "::warning title=Device-transfer backup::\`bmgr backupnow $APP_PACKAGE\`"\
          " returned no per-package result line, so the framework never reported what it"\
          " did with this package and no set can be assumed to exist. check-backup-set.sh"\
          " would be grepping a set that was never written."
      elif printf '%s' "$result" | grep -Eqi 'transport error|transport not initial'; then
        echo "::warning title=Device-transfer backup::The backup transport failed —"\
          " the framework reported \"$result\". Nothing was written, so nothing can be"\
          " inspected. This is an infrastructure failure to fix, not the BIT-20 §5.3 halt."
      else
        device_transfer_backed_up=yes
        echo "::notice title=Device-transfer backup::Driven from the host (BIT-108)."\
          " The framework reported \"$result\" for $APP_PACKAGE on the device-transfer"\
          " path, with is_device_transfer=true and the wallet material planted. The set"\
          " this produced is what the backup-set inspection below reads. This is the"\
          " first run shape in which the device-transfer path produces an inspectable"\
          " set without killing the test process that made it."
      fi
    fi
  fi
fi

echo "Device-transfer backup completed: $device_transfer_backed_up"

# --- The set itself, not bmgr's report of it ----------------------------------
#
# BackupExclusionTest can only search `bmgr backupnow`'s stdout, which is a
# report and not a backup set. check-backup-set.sh reads the set, from the host,
# after `adb root` — see its header for why that half cannot live inside the
# suite, and for the three outcomes it distinguishes. Only one of them is
# evidence; it says which one this run got.
#
# `|| status=$?` for the same reason the Gradle runs above use it: a marker in a
# real backup set is the BIT-20 §5.3 halt, and the summary below must still be
# written so the result is reportable rather than just red.
bash android/scripts/check-backup-set.sh || status=$?

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
  echo "Both backup paths are driven: cloud-backup, and device-transfer via the"
  echo "local transport's \`is_device_transfer\` hook, which is asserted back out"
  echo "of the settings provider on both sides so a renamed hook cannot turn the"
  echo "second into a second copy of the first."
  echo
  echo "**The two paths are driven from different places, and that is BIT-108.**"
  echo "The cloud backup runs inside the suite. The device-transfer backup runs"
  echo "from the host, after Gradle exits — on that path the framework binds a"
  echo "backup agent inside the app process and kills the process when it tears"
  echo "the agent down, and the instrumentation lives in that process. Runs 107"
  echo "and 133 both died there, the second one after the in-process \`bmgr"
  echo "restore\` had already been removed. Device-transfer backup completed:"
  echo "\`$device_transfer_backed_up\`."
  echo
  echo "So the suite plants and proves it planted; the host backs up and greps"
  echo "the backup transport's own on-disk tree for the planted marker, after"
  echo "\`adb root\`. Only the grep reads the backup set itself. Grep the log for"
  echo "\`Backup set inspection\` to see which outcome this run got, and for"
  echo "\`Device-transfer backup\` to see whether there was a set to read."
  echo
  echo "**A pass is not automatically evidence that the rules were exercised.**"
  echo "\`allowBackup=\"false\"\` can make the package ineligible outright, and an"
  echo "ineligible package produces an empty set that satisfies every exclusion"
  echo "assertion without the \`<device-transfer>\` rules being consulted. The"
  echo "\`BACKUP_EXCLUSION\` lines say which happened, per path —"
  echo "\`canaryReturned=true\` is a real set that excluded our material. The"
  echo "vacuity check reprints them into the job log; see"
  echo "\`wallet-security-properties.md\` §4."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || echo "::warning::Could not write the summary. The test result itself is unaffected."

echo "::notice title=Wallet instrumented tests — $result::${duration}s · vacuity check $([ "$check_status" -eq 0 ] && echo passed || echo FAILED)"

if [ "$status" -ne 0 ]; then
  exit "$status"
fi
exit "$check_status"
