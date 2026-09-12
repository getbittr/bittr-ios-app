#!/usr/bin/env bash
#
# The emulator half of the Android Maestro smoke run: install the APK, record the
# screen, run the flow, and write the wall-clock table BIT-5 asks for.
#
# THE FLOW IS A SHARED ONE. `shared/flows/onboarding/smoke.yaml` is the same file
# iOS runs, not an Android copy of it — the only difference between the two runs
# is `--env APP_ID`, which is the whole point of BIT-102. This used to be
# `shared/flows/android/scaffold_smoke.yaml`, an Android-only duplicate that
# existed solely because the shared flows hardcoded the iOS bundle id and used
# `clearKeychain`. Both reasons are gone: the id is parameterised, and Maestro's
# AndroidDriver implements clearKeychain as a no-op (the only no-op in that
# driver, and nothing in it throws "unsupported"), so the shared file runs here
# unmodified. A flow that reappears under shared/flows/android/ is a real parity
# gap and belongs in shared/docs/parity.md.
#
# Invoked by .github/workflows/android-maestro.yml as the `script:` input to
# reactivecircus/android-emulator-runner, from the repository root.
#
# WHY THIS IS A FILE AND NOT AN INLINE `script:` BLOCK
#
# The action does not run that input under bash. It hands it to `/usr/bin/sh`,
# which on the Ubuntu runner images is dash. This script's first line used to be
# the `script:` input's first line, and the run died on it:
#
#   /usr/bin/sh: 1: set: Illegal option -o pipefail
#   Error: The process '/usr/bin/sh' failed with exit code 2
#
# That is a dash without pipefail support (it landed in dash 0.5.12; the runner
# has an older one), and the failure happens AFTER the emulator has booted — so
# the most expensive part of the job is paid in full before the first command
# runs. Nothing caught it beforehand: actionlint shellchecks every `run:` block,
# but `script:` is an input to a third-party action and is opaque to it.
#
# Being a file fixes it at the root rather than by rewriting bashisms: the
# workflow's `script:` is now the POSIX one-liner `bash android/scripts/ci-smoke.sh`,
# and everything below runs under a shell chosen here instead of one chosen by
# whichever image the runner happens to be. android/scripts/check-action-scripts.sh
# keeps it that way, and runs in the build job long before an emulator boots.
#
# It is also now executable outside CI. With an emulator up and an APK in apk/:
#   APP_ID=com.bittr.android.regtest JOB_START_EPOCH=$(date +%s) bash android/scripts/ci-smoke.sh
set -euo pipefail

# The shared flow reads its app id from the environment, so an unset APP_ID does
# not fail at parse time — it fails inside the flow, after an emulator boot, as a
# launch against a package that is not installed. Fail here instead, and do NOT
# default it: the literal already lives in two places that must agree
# (android/app/build.gradle.kts and the workflow's env), and a third copy hidden
# in a fallback is how those drift apart without anyone noticing.
: "${APP_ID:?APP_ID is unset. The workflow sets it (env.APP_ID in .github/workflows/android-maestro.yml, which must match applicationId + the debug applicationIdSuffix in android/app/build.gradle.kts). Running this by hand? Prefix the command with APP_ID=com.bittr.android.regtest.}"

# The emulator is booted by the time this script starts, so this is
# the first moment the job can observe how long booting took.
emulator_ready=$(date +%s)

adb install -r apk/*.apk
installed=$(date +%s)

# Video of the run, kept when the flow fails.
#
# --debug-output already gives a screenshot and a view hierarchy dump at
# the moment of failure, and for a missing test tag that is the whole
# answer. It is the wrong instrument for anything transient: a splash
# that never dismisses, a dialog that steals focus for 400ms, an
# animation still settling. Those leave a final frame that looks
# unremarkable, and the hierarchy dump agrees with it.
#
# `adb emu screenrecord`, not `adb shell screenrecord`. The console
# command records the emulator's display pipeline straight to a file on
# the HOST: no /sdcard space, no adb pull, and no SIGINT-to-finalise
# dance (device-side screenrecord writes an unplayable file if the
# process is killed any other way). It also works headless under
# swiftshader, which is the only configuration this job runs in.
#
# Every recorder call below is non-fatal by construction. A diagnostic
# must not be able to fail the thing it is diagnosing — the worst case
# here is "no video, plus a warning saying so", which is exactly the
# behaviour that existed before this block.
mkdir -p maestro-video
video="$PWD/maestro-video/smoke.webm"
recording=no
if rec_out=$(adb emu screenrecord start "$video" 2>&1) \
   && ! printf '%s' "$rec_out" | grep -qi '^KO'; then
  recording=yes
else
  echo "::warning::Could not start emulator screen recording (${rec_out:-no output}). The flow still runs; if it fails there will be no video, only maestro-debug/."
fi

# The flow's exit status is the job's result, but the recorder has to be
# stopped on the failing path too — that is the path the video exists for.
set +e
flow_start=$(date +%s)
maestro test \
  --env APP_ID="$APP_ID" \
  --debug-output maestro-debug \
  --format junit \
  --output maestro-report.xml \
  shared/flows/onboarding/smoke.yaml
status=$?
flow_end=$(date +%s)
set -e

if [ "$recording" = yes ]; then
  adb emu screenrecord stop \
    || echo "::warning::Screen recording did not stop cleanly; the video may be truncated."
fi

if [ "$status" -eq 0 ]; then
  # Green runs keep the junit report and the flow's own screenshot. The
  # definition of done is three consecutive green runs, and paying
  # an upload for a video nobody opens on all three is pure overhead.
  rm -f "$video"
elif [ ! -s "$video" ]; then
  echo "::warning::Flow failed and no video was captured (${video##*/} missing or empty). Use maestro-debug/ for the screenshot and view hierarchy."
fi

# The wall-clock number BIT-5 asks to be told, written where it is read
# without opening a log. Emitted on the failing path too: "it went red
# after 28 minutes" and "it went red after 40 seconds" are different
# failures, and the timeout case is only legible with the number.
#
# Boot dominates and that is the point of splitting it out — the flow
# itself is a launch and three assertions, so if anyone ever finds this
# job too slow to wait for, the answer is in the boot row, not the flow
# row, and no amount of flow tuning will touch it.
#
# SETUP IS SPLIT OUT FROM BOOT, and that split is a correction. This
# block used to report `emulator_ready - job_start` under the single
# label "emulator boot". It is not: JOB_START_EPOCH is marked at the top
# of the job, so that span also contains the JDK setup, Maestro's
# installer and the AVD cache restore. Checked against the step
# durations of the three BIT-5 evidence runs, 20-34s of an 88-107s
# figure was not the emulator booting — enough to send someone tuning
# emulator flags when the actual repeat cost is re-downloading Maestro
# on every run. A number with the wrong name on it is worse than no
# number, because it gets acted on.
#
# Every expansion here is defaulted and the whole block is non-fatal,
# for the same reason the recorder above is: this runs AFTER the flow
# has already produced its verdict, so a fault in the reporting must
# not be able to change it. Under `set -euo pipefail` an unset
# JOB_START_EPOCH — one skipped step, one typo'd variable — would
# abort here and turn a green flow into a red job, which is the most
# confusing failure this workflow could possibly emit.
if [ "$status" -eq 0 ]; then result="green"; else result="RED (exit $status)"; fi
job_start="${JOB_START_EPOCH:-0}"
# Marked by the workflow step immediately before the emulator action. Absent when
# the script is run by hand, and absent if that step is ever removed — in which
# case setup and boot collapse back into one honestly-labelled figure rather than
# being split on a guess.
emu_start="${EMULATOR_START_EPOCH:-0}"
install=$((installed - emulator_ready))
flow=$((flow_end - flow_start))
# The `_h` variants are what goes into the one-line annotation, where a bare
# "unknown" needs to read as a missing measurement rather than as a typo — and,
# specifically, must not have a unit stuck to it. `setup ${setup}s` renders as
# "setup not measureds" the moment setup is a word instead of a number, so the
# annotation takes setup_h (which is empty when there is nothing to say) rather
# than interpolating the table's value with an `s` appended.
if [ "$job_start" = 0 ]; then
  setup="unknown"; boot="unknown"; total="unknown"
  boot_label="emulator boot + setup"; boot_h="unknown"; total_h="unknown"; setup_h=""
elif [ "$emu_start" = 0 ] || [ "$emu_start" -lt "$job_start" ]; then
  # No usable emulator mark: report the combined span under the combined label
  # instead of splitting it on a guess, and say nothing about setup at all.
  setup="not measured"; boot=$((emulator_ready - job_start))
  boot_label="emulator boot + setup"; boot_h="${boot}s"; setup_h=""
  total=$(($(date +%s) - job_start)); total_h="${total}s"
else
  setup=$((emu_start - job_start)); boot=$((emulator_ready - emu_start))
  boot_label="emulator boot"; boot_h="${boot}s"; setup_h="setup ${setup}s · "
  total=$(($(date +%s) - job_start)); total_h="${total}s"
fi
{
  echo "### Maestro smoke — wall clock"
  echo
  echo "| stage | seconds |"
  echo "|---|---:|"
  echo "| setup (JDK, Maestro install, AVD cache) | $setup |"
  echo "| $boot_label | $boot |"
  echo "| APK install | $install |"
  echo "| **flow** (\`onboarding/smoke.yaml\`, shared with iOS) | **$flow** |"
  echo "| emulator job, total | $total |"
  echo
  echo "Result: **$result** · Maestro \`${MAESTRO_VERSION:-unpinned}\` · \`APP_ID=$APP_ID\` · runner \`${RUNNER_ENVIRONMENT:-unknown}\`"
  echo
  echo "This is the emulator job only. The \`build\` job runs before it, and on the"
  echo "BIT-5 evidence runs it was the LONGER half — end-to-end run time is both."
  echo "\`android/scripts/ci-runs.py\` prints the end-to-end number for real runs."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || echo "::warning::Could not write the wall-clock summary. The flow's own result is unaffected."

# The same numbers again, as a workflow annotation. This is not redundancy for its
# own sake: the first green run of this workflow produced the table above and the
# number still did not reach the person who needed it, because a step summary lives
# at the BOTTOM of the run page behind a scroll, and reading it means knowing it is
# there. An annotation renders in the box at the TOP of the run page, above the job
# list, and is the first thing on screen when the run is opened.
#
# One line, because annotations are single-line — %0A is the escape GitHub decodes
# as a newline, and a multi-line annotation is harder to copy than the table it is
# summarising. Somebody reading a run should be able to answer "how long?" without
# scrolling and without being told where to look.
echo "::notice title=Maestro smoke — $result in $total_h::flow ${flow}s · $boot_label $boot_h · ${setup_h}APK install ${install}s · emulator job total $total_h (build job is separate and longer)"

exit "$status"
