#!/usr/bin/env bash
#
# The emulator half of BIT-62: run the S-36 isolation tests on a real Android
# image, and refuse to report a green that proved nothing.
#
# Invoked by .github/workflows/android-maestro.yml as the `script:` input to
# reactivecircus/android-emulator-runner, from the repository root, with an
# emulator already booted.
#
# WHY THIS IS A FILE AND NOT AN INLINE `script:` BLOCK
#
# Same reason as ci-smoke.sh: the action hands that input to /usr/bin/sh, which
# on the Ubuntu images is dash, and the first line below would die on it AFTER
# the emulator has booted. android/scripts/check-action-scripts.sh enforces the
# `bash <file>` shape in the build job, seconds in.
#
# WHAT THIS RUNS, AND WHY IT IS NOT `am instrument`
#
# `./gradlew :feature:website:connectedDebugAndroidTest` — the same command an
# engineer runs locally with a device plugged in, which is the point: the thing
# CI does and the thing a person does to reproduce it should not be two different
# things. It also writes JUnit XML, which is what the vacuity check downstream
# reads. Driving `am instrument` directly would save the Gradle configuration
# time and cost us both of those.
#
# Locally, with an emulator up:
#   JOB_START_EPOCH=$(date +%s) bash android/scripts/ci-instrumented.sh
set -euo pipefail

job_start=${JOB_START_EPOCH:-0}
emulator_ready=$(date +%s)

adb devices

# --- Preflight: this image must actually have a WebView -----------------------
#
# Every test in this suite constructs a real android.webkit.WebView. On an image
# with no WebView provider installed, that throws
# android.webkit.WebViewFactory$MissingWebViewPackageException at construction —
# so all nine tests fail, in a class-level error that says nothing about the
# image, and the obvious reading is "the hardening tests broke".
#
# This is not hypothetical bad luck: it is the specific reason this job does not
# reuse the Maestro job's aosp_atd AVD. ATD images are stripped for speed, and
# what is stripped varies by API level. The Maestro flow drives the app's own
# Compose UI and does not care; this suite is *entirely* about the WebView. So
# the job runs a `default` image and checks the assumption out loud rather than
# inheriting a snapshot chosen for a different test's needs.
webview_state=$(adb shell dumpsys webviewupdate 2>/dev/null || true)
webview_line=$(printf '%s\n' "$webview_state" | grep -i 'Current WebView package' | head -1 || true)

if [ -z "$webview_line" ] || printf '%s' "$webview_line" | grep -qi 'null'; then
  if ! adb shell pm list packages 2>/dev/null | grep -qiE 'webview|com\.android\.chrome'; then
    echo "::error::No WebView provider on this emulator image. Every test in"\
      ":feature:website's androidTest suite builds a real WebView, so all of them"\
      " would fail with MissingWebViewPackageException and none of the failures"\
      " would mention the image. Use a system image that ships a WebView (target:"\
      " default or google_apis), not a stripped ATD image."
    printf '%s\n' "$webview_state"
    exit 1
  fi
fi
echo "WebView provider: ${webview_line:-present (reported by pm list packages)}"

# --- The run ------------------------------------------------------------------
#
# `|| status=$?` rather than letting set -e kill the script: a red test run must
# still reach the results check and the summary below, because "which test failed"
# is the entire value of the job and it is written by the step after this one.
status=0
test_start=$(date +%s)
(cd android && ./gradlew :feature:website:connectedDebugAndroidTest --no-daemon) || status=$?
test_end=$(date +%s)
duration=$((test_end - test_start))

# --- The vacuity check --------------------------------------------------------
#
# Deliberately runs whatever Gradle said. On a red run it adds which tests failed;
# on a GREEN run it is the load-bearing half, because connectedDebugAndroidTest
# exits 0 when it matched no tests at all. BIT-62's first named risk is a
# vacuously green run, and Gradle's exit code cannot tell one from a real pass.
check_status=0
python3 android/scripts/check-instrumented-results.py || check_status=$?

if [ "$status" -eq 0 ] && [ "$check_status" -ne 0 ]; then
  echo "::error::Gradle reported success but the required tests did not all run and"\
    " pass. A green task with no evidence behind it is what BIT-62 was opened to"\
    " rule out; the job is red on the evidence, not on the exit code."
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
  echo "### S-36 instrumented isolation tests — on a real Android image"
  echo
  echo "| stage | seconds |"
  echo "|---|---:|"
  echo "| setup + emulator boot | $setup |"
  echo "| \`:feature:website:connectedDebugAndroidTest\` | $duration |"
  echo
  echo "Result: **$result** · ${webview_line:-WebView provider not reported}"
  echo
  echo "These are BIT-58 DoD 2 and BIT-33 Acceptance 3-4. Until BIT-62 they had"
  echo "only ever been compiled. The per-test table is in the job log, and the"
  echo "HTML report is attached to the run as \`instrumented-test-report\`."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || echo "::warning::Could not write the summary. The test result itself is unaffected."

echo "::notice title=S-36 isolation tests — $result::${duration}s on a real WebView · 9 required tests · vacuity check $([ "$check_status" -eq 0 ] && echo passed || echo FAILED)"

if [ "$status" -ne 0 ]; then
  exit "$status"
fi
exit "$check_status"
