#!/usr/bin/env bash
#
# The emulator half of the Android Maestro smoke run: install the APK, record the
# screen, run the flow, and write the wall-clock table BIT-5 asks for.
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
#   JOB_START_EPOCH=$(date +%s) bash android/scripts/ci-smoke.sh
set -euo pipefail

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
video="$PWD/maestro-video/scaffold_smoke.webm"
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
  --debug-output maestro-debug \
  --format junit \
  --output maestro-report.xml \
  shared/flows/android/scaffold_smoke.yaml
status=$?
flow_end=$(date +%s)
set -e

if [ "$recording" = yes ]; then
  adb emu screenrecord stop \
    || echo "::warning::Screen recording did not stop cleanly; the video may be truncated."
fi

if [ "$status" -eq 0 ]; then
  # Green runs keep the junit report and the flow's own screenshot. The
  # definition of done is three consecutive green dispatches, and paying
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
# Every expansion here is defaulted and the whole block is non-fatal,
# for the same reason the recorder above is: this runs AFTER the flow
# has already produced its verdict, so a fault in the reporting must
# not be able to change it. Under `set -euo pipefail` an unset
# JOB_START_EPOCH — one skipped step, one typo'd variable — would
# abort here and turn a green flow into a red job, which is the most
# confusing failure this workflow could possibly emit.
if [ "$status" -eq 0 ]; then result="green"; else result="RED (exit $status)"; fi
job_start="${JOB_START_EPOCH:-0}"
if [ "$job_start" = 0 ]; then
  boot="unknown"; total="unknown"
else
  boot=$((emulator_ready - job_start)); total=$(($(date +%s) - job_start))
fi
{
  echo "### Maestro smoke — wall clock"
  echo
  echo "| stage | seconds |"
  echo "|---|---:|"
  echo "| emulator boot + SDK setup | $boot |"
  echo "| APK install | $((installed - emulator_ready)) |"
  echo "| **flow** (\`scaffold_smoke.yaml\`) | **$((flow_end - flow_start))** |"
  echo "| emulator job, total | $total |"
  echo
  echo "Result: **$result** · Maestro \`${MAESTRO_VERSION:-unpinned}\` · runner \`${RUNNER_ENVIRONMENT:-unknown}\`"
  echo
  echo "The \`build\` job runs before this one; its duration is on the run page."
  echo "BIT-5 closes on three consecutive green dispatches — compare the flow row across all three."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || echo "::warning::Could not write the wall-clock summary. The flow's own result is unaffected."

exit "$status"
