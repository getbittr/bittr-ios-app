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
#
# Captured rather than streamed straight through so the verdict line can be
# lifted into the job's ::notice::. The output is echoed immediately below, so
# the log still reads in order; `2>&1` keeps a traceback in the same stream
# rather than letting it arrive out of band and unexplained.
check_status=0
check_output=$(python3 android/scripts/check-instrumented-results.py 2>&1) || check_status=$?
printf '%s\n' "$check_output"
verdict=$(printf '%s\n' "$check_output" \
  | sed -n 's/^check-instrumented-results: verdict //p' | tail -1)

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
  echo "\`${verdict:-no verdict: check-instrumented-results did not complete}\`"
  echo
  echo "These are BIT-58 DoD 2 and BIT-33 Acceptance 3-4. Until BIT-62 they had"
  echo "only ever been compiled. The per-test table is in the job log, and the"
  echo "HTML report is attached to the run as \`instrumented-test-report\`."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || echo "::warning::Could not write the summary. The test result itself is unaffected."

# The verdict names counts and the canary's state, so the one line a reader gets
# without repository auth distinguishes "nothing ran" from "nine ran, one failed".
# The fallback matters: if the checker died before printing a verdict, saying so
# is right and claiming a clean vacuity result would not be.
echo "::notice title=S-36 isolation tests — $result::${duration}s on a real WebView · ${verdict:-no verdict: check-instrumented-results did not complete}"

if [ "$status" -ne 0 ]; then
  exit "$status"
fi
exit "$check_status"
# The emulator half of BIT-33 §Acceptance 3 and 4: run the S-36 isolation tests
# against a real WebView on a real device.
#
# Invoked by .github/workflows/android-maestro.yml as the `script:` input to
# reactivecircus/android-emulator-runner, from the repository root.
#
# WHY THIS IS A FILE AND NOT AN INLINE `script:` BLOCK
#
# The action hands that input to /usr/bin/sh — dash on the Ubuntu images — not
# bash. android/scripts/check-action-scripts.sh enforces that every `script:` is
# either POSIX or delegates here with `bash <file>`; see ci-smoke.sh's header for
# the run this rule was bought with.
#
# WHY THIS JOB EXISTS AT ALL
#
# The build job compiles the androidTest source set and stops. That was honest
# about itself — "Compiled, not run" — but it left the two tests that ARE the
# acceptance evidence for this feature in a state where nothing ever executed
# them. A security control whose only proof is a file that compiles is a comment
# with a test framework's syntax.
#
# What runs here:
#
#   ThirdPartyIsolationTest        — §Acceptance 3 and 4. A page on a
#                                    non-allowlisted origin probes for every
#                                    bridge name, posts to anything with a
#                                    postMessage, navigates to lightning:, and
#                                    tries an LNURL-auth URL. Nothing may happen.
#   CrossOriginIframeIsolationTest — BIT-58. The same, from a cross-origin iframe
#                                    on a first-party page, which is the boundary
#                                    an origin-only gate gets wrong.
#
# Both stand up http servers on 127.0.0.1 and point a real HardenedWebView at
# them. Cleartext to loopback is permitted for the TEST APK only, by
# feature/website/src/androidTest/res/xml/network_security_config_test.xml.
#
# NO RETRIES, deliberately, matching the rest of this workflow: a security test
# that needs a second attempt to pass has not passed. If the emulator itself is
# unreliable that is a blocker to report, not something to paper over.
set -euo pipefail

cd android

echo "--- Device under test"
adb devices -l
adb shell getprop ro.build.version.sdk

echo "--- :feature:website:connectedDebugAndroidTest"
# `--no-daemon` for the same reason as the build job: one Gradle invocation per
# job, so a daemon is pure startup cost. Not `--offline`; this job does not share
# the build job's Gradle cache.
./gradlew :feature:website:connectedDebugAndroidTest --no-daemon

echo "--- Result"
# The XML is the artefact a reviewer reads, so its absence is a failure rather
# than a quiet pass. connectedDebugAndroidTest exiting 0 having run zero tests is
# a real outcome — a filter that matches nothing, or a test APK that installed
# but registered no class — and it is indistinguishable from success without this.
results_dir=feature/website/build/outputs/androidTest-results/connected
if ! ls "$results_dir"/*.xml >/dev/null 2>&1; then
  echo "::error::No instrumented test results under android/$results_dir. The Gradle task reported success without producing a report, which means it ran no tests. §Acceptance 3 and 4 are unproven by this run."
  exit 1
fi

python3 - "$results_dir" <<'PY'
import glob
import sys
import xml.etree.ElementTree as ET

total = failures = errors = skipped = 0
for path in sorted(glob.glob(f"{sys.argv[1]}/*.xml")):
    suite = ET.parse(path).getroot()
    total += int(suite.get("tests", 0))
    failures += int(suite.get("failures", 0))
    errors += int(suite.get("errors", 0))
    skipped += int(suite.get("skipped", 0))

print(f"{total} instrumented tests, {failures} failures, {errors} errors, {skipped} skipped")

# A green run of nothing is the failure mode this guard is for.
if total == 0:
    sys.exit("::error::The instrumented run contained zero tests.")

# Gradle has already failed the build on a red test; this is belt and braces for
# the case where the report disagrees with the exit status.
if failures or errors:
    sys.exit("::error::Instrumented tests failed. See the uploaded androidTest-results artefact.")

with open("summary.txt", "w") as handle:
    handle.write(f"{total} instrumented tests passed on the emulator.\n")
PY

echo "--- Done"
