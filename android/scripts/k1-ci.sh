#!/usr/bin/env bash
#
# The emulator half of the K1 run: drive the lock-screen matrix against the
# booted emulator and publish the table.
#
# Invoked by .github/workflows/k1-keystore-lockscreen.yml as the `script:` input
# to reactivecircus/android-emulator-runner, from the repository root.
#
# WHY THIS IS A FILE AND NOT AN INLINE `script:` BLOCK
#
# The action hands that input to /usr/bin/sh — dash on the runner images — not
# to bash, and the failure lands AFTER the emulator has booted. ci-smoke.sh
# carries the full story; android/scripts/check-action-scripts.sh enforces it.
#
# WHAT THIS ADDS OVER CALLING THE MATRIX SCRIPT DIRECTLY
#
# Three things, all of which exist so a run that went wrong cannot be mistaken
# for a run that went right:
#
#   1. It records which emulator produced the table. A K1 row is a claim about
#      a specific image; `google/sdk_gphone64_x86_64 (API 34)` in the table
#      header is the difference between evidence and an anecdote.
#   2. It writes the table into the job summary as well as the artefact, so the
#      result is readable from the run page without downloading anything.
#   3. It fails the job when any row is not PASS. An ERROR row means the harness
#      could not establish what happened, which is not a pass and must not go
#      green — see "How a row avoids being a false green" in
#      android/docs/k1-keystore-lockscreen.md.
#
# Runnable outside CI with an emulator up:
#   K1_OUT=/tmp/k1.md bash android/scripts/k1-ci.sh
set -euo pipefail

out="${K1_OUT:-k1-results/k1.md}"
mkdir -p "$(dirname "$out")"

args=""
if [ "${K1_WITH_DEVICE_OWNER:-0}" = "1" ]; then
  # M6 needs `dpm set-device-owner`, which cannot be undone without a factory
  # reset. That is safe here only because the workflow creates the AVD fresh for
  # this run and never saves a snapshot — a cached AVD would carry the device
  # owner into every later run on this host, and the symptom would be M6 failing
  # to set up on a machine nobody had touched. The workflow's
  # force-avd-creation/-no-snapshot-save pair is load-bearing for this flag.
  args="--with-device-owner"
fi

echo "k1: driving the matrix against $(adb shell getprop ro.build.fingerprint | tr -d '\r')"

status=0
# shellcheck disable=SC2086
bash android/scripts/k1-lockscreen-matrix.sh $args --out "$out" || status=$?

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## K1 — API ${K1_API_LEVEL:-unknown}"
    echo
    if [ -s "$out" ]; then
      cat "$out"
    else
      echo "The matrix produced no table. The run failed before any row could be"
      echo "written — read the step log above, not this summary."
    fi
    echo
    if [ "$status" -eq 0 ]; then
      echo "_Every row PASS. This is evidence for BIT-8 rule 2 on this image and no other._"
    else
      echo "_Not every row is PASS (matrix exit \`$status\`). A FAIL row contradicts"
      echo "BIT-8 rule 2 and must be reported on BIT-18 and BIT-8 before anything is"
      echo "redesigned; an ERROR row means the harness could not establish what"
      echo "happened and is not a result either way._"
    fi
  } >>"$GITHUB_STEP_SUMMARY"
fi

exit "$status"
