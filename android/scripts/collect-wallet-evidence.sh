#!/usr/bin/env bash
#
# BIT-114: get the wallet suites' per-run observations off the device.
#
#   android/scripts/collect-wallet-evidence.sh --clear
#   android/scripts/collect-wallet-evidence.sh <phase> <destination-directory>
#
# Always exits 0. Read the destination file, and the ::warning:: annotations.
#
# WHY THIS EXISTS
#
# `BackupExclusionTest` prints a BACKUP_EXCLUSION line per path and per plant —
# which prefixes were planted, where, what finding each one in a backup set would
# mean, and `setLeftOnTransport`. `KeystoreKeyInfoTest` prints what the platform
# reported for a key it really generated, and the security level it was given.
# Those lines are the only per-path detail the run produces, and
# check-wallet-instrumented-results.py lifts them into an annotation because on
# this PUBLIC repo the job log answers 403 and artifacts answer 401.
#
# They never arrived. Every run from 110 to 140 reported "no BACKUP_EXCLUSION or
# KEYSTORE_KEY_INFO line reached <system-out>", including 139 and 140, which were
# green with the vacuity check passed — so every test ran and every print was
# reached.
#
# The cause was not on the device and was not a runner setting. The JUnit XML for
# a connected test is written by com.android.ddmlib.testrunner.XmlTestRunListener
# (AGP's CustomTestRunListener extends it and overrides no part of this), and in
# the ddmlib this AGP is built against that class has a `system-err` element and
# NO `system-out` element at all: no constant, no writer. The gate was reading a
# channel nothing writes to, which is a failure that presents as a green run
# reporting an absence — which is how it survived thirty runs.
#
# So the observations come off the device the way BIT-108's hand-off does: the
# suites append them to a file in the app's own data directory (see EvidenceLog
# in both modules' androidTest sources) and this reads it back with `adb root`,
# after Gradle has exited.
#
# WHY A SEPARATE FILE FROM ci-wallet-instrumented.sh
#
# The same reason check-backup-set.sh is one: the seam is `adb`, so with a stub
# on PATH every branch here is reachable in milliseconds, where inside the
# emulator job only the branch that device happens to take would ever run.
# test_collect_wallet_evidence.sh is that suite, and it runs in the build job.
#
# It is also where EVIDENCE_FILE_NAME and the prefix list live for the host side,
# so test_ci_wallet_host_phase.sh has one file to pin them against rather than a
# copy in each caller.
#
# WHY IT NEVER FAILS
#
# An observation that could not be collected is a "did not look", not a wallet
# finding, and this job's whole discipline is that the two must not be confused.
# Every exit that is not a collected file ends in a ::warning:: naming which of
# the causes it was, and the gate reports the absence from the other end. A red
# here would be claiming a result the run did not get.
set -uo pipefail

# Pinned against both EvidenceLog.kt copies by test_ci_wallet_host_phase.sh.
EVIDENCE_FILE_NAME="instrumentation_evidence.txt"

# Pinned against EVIDENCE_PREFIXES in check-wallet-instrumented-results.py by the
# same test. A prefix added there and not here is dropped by the logcat fallback
# silently, and only on the runs that need the fallback.
EVIDENCE_PREFIXES='^(BACKUP_EXCLUSION|KEYSTORE_KEY_INFO|KEYSTORE_SECURITY_LEVEL)'

# One glob rather than two package names. :app's suite writes into the INSTALLED
# app, com.bittr.android.regtest — applicationId plus the debug
# applicationIdSuffix, not the namespace, which is the drift
# test_ci_wallet_host_phase.sh exists for — while a library module's tests are
# self-instrumenting, so :core:wallet-ldk's write into their own test APK,
# com.bittr.android.core.wallet.ldk.test. The glob covers both and survives a
# rename of either.
DATA_GLOB='/data/data/com.bittr.android*'

# `adb root` is what makes an app's data directory readable from here, and it is
# the same call check-backup-set.sh depends on: a userdebug image grants it, a
# user build does not, and a refusal is a "cannot look" rather than a finding.
become_root() {
  adb root >/dev/null 2>&1 || true
  adb wait-for-device >/dev/null 2>&1 || true
}

# Anything already on the device under this name belongs to an earlier run. The
# AVD is restored from a cached snapshot and an app's data directory can outlive
# a run, so without this a run whose tests never executed would hand the gate the
# previous run's observations to report as its own — the same hazard
# BackupExclusionTest clears its hand-off for, and the same fix. The logcat
# buffer is cleared for the same reason, since the fallback reads it.
clear_device() {
  become_root
  adb shell "for d in $DATA_GLOB; do rm -f \$d/no_backup/$EVIDENCE_FILE_NAME; done" \
    >/dev/null 2>&1 || true
  adb logcat -c >/dev/null 2>&1 || true
  echo "Cleared any earlier run's $EVIDENCE_FILE_NAME and the logcat buffer."
}

collect() {
  phase=$1
  dest="$2/$phase.txt"

  mkdir -p "$2"
  become_root

  # `tr -d '\r'` on every adb capture, for the reason the device-transfer phase
  # documents at length: adbd puts the device's line discipline on the wire, so
  # output arrives CRLF, and the carriage returns would travel into an
  # annotation.
  adb shell "for d in $DATA_GLOB; do f=\$d/no_backup/$EVIDENCE_FILE_NAME; [ -f \$f ] && cat \$f; done" \
    2>/dev/null | tr -d '\r' > "$dest" || true

  if [ -s "$dest" ]; then
    echo "Evidence ($phase): $(grep -c '' "$dest") line(s) from $EVIDENCE_FILE_NAME."
    return 0
  fi

  # The fallback, and a real one rather than a gesture: Android redirects a
  # process's System.out to the log, so the same `println` that could not reach
  # the XML is in logcat under the System.out tag. It is second rather than first
  # because the ring buffer rolls — a long instrumentation run can push the
  # earliest lines out — so it is the channel that may be INCOMPLETE, where the
  # file is the one that may be ABSENT. Saying which one answered is therefore
  # part of the result. `-v raw` prints the message without the metadata, which
  # is what makes the prefix match anchorable.
  adb logcat -d -v raw -s System.out:I 2>/dev/null | tr -d '\r' \
    | grep -E "$EVIDENCE_PREFIXES" > "$dest" || true

  if [ -s "$dest" ]; then
    echo "::warning title=Instrumentation evidence::The $phase phase's"\
      " $EVIDENCE_FILE_NAME could not be read off the device, so its"\
      " BACKUP_EXCLUSION and KEYSTORE_* lines came from logcat instead. logcat's"\
      " buffer rolls, so read that list as possibly incomplete rather than as the"\
      " full record — and note it may also carry an earlier phase's lines, which"\
      " the gate deduplicates. Causes: 'adb root' was refused on this image, or the"\
      " APKs were uninstalled before this ran, which would mean"\
      " -Pandroid.injected.androidTest.leaveApksInstalledAfterRun stopped being"\
      " honoured by this AGP version."
    return 0
  fi

  echo "::warning title=Instrumentation evidence::The $phase phase produced no"\
    " observations on either channel — no $EVIDENCE_FILE_NAME under"\
    " $DATA_GLOB/no_backup/, and no line under the expected prefixes in logcat. If"\
    " the tests for this phase ran at all, this is a harness failure and NOT a"\
    " device finding: it is 'nobody read the device', not 'the device said"\
    " nothing'. The gate's 'What the device reported' annotation reports the same"\
    " absence from the other end, and an empty file is what tells it the host"\
    " looked."
  return 0
}

case "${1:-}" in
  --clear)
    clear_device
    ;;
  "")
    echo "usage: $0 --clear | $0 <phase> <destination-directory>" >&2
    exit 2
    ;;
  *)
    if [ "$#" -ne 2 ]; then
      echo "usage: $0 --clear | $0 <phase> <destination-directory>" >&2
      exit 2
    fi
    collect "$1" "$2"
    ;;
esac

exit 0
