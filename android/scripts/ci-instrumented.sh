#!/usr/bin/env bash
#
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
