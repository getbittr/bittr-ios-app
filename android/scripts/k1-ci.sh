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
# Four things, all of which exist so a run that went wrong cannot be mistaken
# for a run that went right:
#
#   1. It records which emulator produced the table. A K1 row is a claim about
#      a specific image; `google/sdk_gphone64_x86_64 (API 34)` in the table
#      header is the difference between evidence and an anecdote.
#   2. It writes the table into the job summary as well as the artefact, so the
#      result is readable from the run page without downloading anything.
#   3. It emits the table as an ANNOTATION, which is the only one of those
#      channels readable without repository admin. See "Publishing the table
#      somewhere it can actually be read" below — this is why the first K1 run
#      could be seen to fail and not be seen to say why.
#   4. It fails the job when any row is not PASS. An ERROR row means the harness
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

# ---------------------------------------------------------------------------
# Publishing the table somewhere it can actually be read
# ---------------------------------------------------------------------------
#
# The steps around this script put the table in three places: the step log, an
# uploaded artefact, and the job summary. On `getbittr/bittr-ios-app` all three
# need credentials nobody running this has:
#
#   job log      -> 403 {"message": "Must have admin rights to Repository."}
#   artefact zip -> 401 {"message": "Requires authentication"}
#   job summary  -> not exposed by the REST API at all
#
# Annotations are the exception. On a public repo
# /repos/:owner/:repo/check-runs/:id/annotations is readable with no token, which
# is the same fact android/scripts/ci-runs.py is built on. So the table goes out
# as an annotation as well, and android/scripts/k1-result.py reads it back.
#
# This is not belt-and-braces. BIT-5 lost three rounds to results that existed
# and never reached whoever needed them — ci-runs.py's own "WHY THIS EXISTS" —
# and the first K1 run failed with every readable channel saying only "The
# process '/usr/bin/sh' failed with exit code 1". A row that cannot be read is
# not evidence, and K1's rows are the evidence for a funds-safety rule.
#
# GitHub caps a job at 10 annotations per level, so the whole table goes out as
# ONE annotation rather than one per row.
K1_ANNOTATION_LIMIT="${K1_ANNOTATION_LIMIT:-4000}"

annotate() {
  # annotate <level> <title> <file-to-send>
  #
  # A workflow command occupies a single line, so every newline in the table has
  # to become the %0A escape or the annotation silently stops at the first row —
  # the same shape of bug as a false green, a result that looks present and says
  # nothing. `%` is substituted first; do it in any other order and it mangles
  # the escapes introduced here.
  level="$1"
  title="$2"
  msg=$(cat "$3")

  msg=${msg//'%'/'%25'}
  msg=${msg//$'\r'/'%0D'}
  msg=${msg//$'\n'/'%0A'}

  # Over-long annotations are truncated by GitHub without saying so. Truncate
  # here instead, and name it in the text: "the table continues" is readable,
  # a table that just stops is indistinguishable from a short one.
  if [ "${#msg}" -gt "$K1_ANNOTATION_LIMIT" ]; then
    msg="${msg:0:$K1_ANNOTATION_LIMIT}%0A%0A[truncated at ${K1_ANNOTATION_LIMIT} characters — the full table is the k1-api-* artefact]"
  fi

  # Title is a workflow-command property, where `:` and `,` are delimiters and
  # need escaping too.
  title=${title//'%'/'%25'}
  title=${title//':'/'%3A'}
  title=${title//','/'%2C'}

  printf '::%s title=%s::%s\n' "$level" "$title" "$msg"
}

echo "k1: driving the matrix against $(adb shell getprop ro.build.fingerprint | tr -d '\r')"

# The matrix's own output is captured as well as shown. Not for the rows — those
# are in "$out" — but for the refusals that happen BEFORE any row exists: a
# failed install, an APK with no registered instrumentation, an image that
# cannot hold a lock screen. Each of those exits with its reason on stderr, and
# stderr on this repository is the step log, which is the 403. Without this the
# annotation for every one of them reads "The matrix produced no table", which
# is the same dead end as run #1's "failed with exit code 1" wearing a longer
# sentence.
matrix_log=$(mktemp)
trap 'rm -f "$matrix_log"' EXIT

# `set +e` around the pipeline rather than `|| true` after it: `|| true` runs a
# command of its own, and running any command resets PIPESTATUS — so the status
# read back would be `true`'s, and every failed matrix would publish itself as
# "every row PASS". That is the exact false green this script's fourth job is to
# prevent, and test-k1-driver.sh pins it.
status=0
set +e
# shellcheck disable=SC2086
bash android/scripts/k1-lockscreen-matrix.sh $args --out "$out" 2>&1 | tee "$matrix_log"
status=${PIPESTATUS[0]}
set -e

# The annotation goes out before the summary, so that a failure in the summary
# block cannot cost the one copy of the table that is readable without a token.
# Built outside "$(dirname "$out")" deliberately — that directory is what the
# workflow uploads, and a near-duplicate of the table sitting next to it invites
# someone to quote the wrong file.
annotation_body=$(mktemp)
trap 'rm -f "$annotation_body" "$matrix_log"' EXIT
{
  echo "K1 — API ${K1_API_LEVEL:-unknown} — matrix exit $status"
  echo
  if [ -s "$out" ]; then
    cat "$out"
  else
    echo "The matrix produced no table: it stopped before any row could be written."
    echo "That is a refusal, not a verdict on BIT-8 rule 2 — the last lines of its"
    echo "output are below and they name the reason."
    echo
    echo '```'
    tail -n 40 "$matrix_log"
    echo '```'
  fi
} >"$annotation_body"

if [ "$status" -eq 0 ]; then
  annotate notice "K1 API ${K1_API_LEVEL:-unknown} — every row PASS" "$annotation_body"
else
  annotate error "K1 API ${K1_API_LEVEL:-unknown} — not every row is PASS" "$annotation_body"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## K1 — API ${K1_API_LEVEL:-unknown}"
    echo
    if [ -s "$out" ]; then
      cat "$out"
    else
      echo "The matrix produced no table: it stopped before any row could be written."
      echo
      echo '```'
      tail -n 40 "$matrix_log"
      echo '```'
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
