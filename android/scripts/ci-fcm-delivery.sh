#!/usr/bin/env bash
#
# BIT-135: K2's FCM delivery leg — prove Google delivers a wake to this app.
#
# Invoked by .github/workflows/fcm-delivery.yml as the `script:` input to
# reactivecircus/android-emulator-runner, from the repository root, with a
# `google_apis` emulator already booted.
#
# WHY THIS IS A FILE AND NOT AN INLINE `script:` BLOCK
#
# Same reason as ci-wallet-instrumented.sh: the action hands that input to
# /usr/bin/sh, which on the Ubuntu images is dash, and `set -o pipefail` below
# would die on it AFTER the emulator has booted.
# android/scripts/check-action-scripts.sh enforces the `bash <file>` shape in the
# build job, seconds in rather than an emulator boot in.
#
# WHAT THIS PROVES THAT NO ANDROID TEST CAN
#
# `FcmWakeTest` drives `WalletWake.deliver()` directly, because the
# platform will not let a test start a background service on API 26+. That leaves
# exactly one call untested, and it is the one with Google in it: the framework
# receiving a real message and dispatching it to our `<service>`.
#
# So this script closes it from the outside, in the only order that can:
#
#   1. Gradle runs FcmDeliveryTest, which leaves a wallet on the device and hands
#      off a registration token.
#   2. `am kill` ends the app's process. NOT `am force-stop` — see below.
#   3. send-fcm-wake.sh sends a high-priority, data-only message from the host.
#   4. logcat says what the app did when the framework brought it back.
#
# Step 4 is the verdict and it lives HERE rather than in a test, for the same
# reason check-backup-set.sh's verdict does: the event happens after Gradle has
# exited, in a process no instrumentation is running in. `am instrument` would
# not help — ActivityManager force-stops the target package before starting
# instrumentation, which both destroys the in-memory `BackgroundWake.last` and
# puts the package in the stopped state that blocks FCM delivery outright.
#
# `am kill` AND NOT `am force-stop`, WHICH IS THE WHOLE OF SECTION 2
#
# `wallet-node-device-tests.md` §2 withdrew the force-stop row because a
# force-stopped package is in Android's STOPPED STATE and the framework does not
# deliver broadcasts — FCM's included — to it until something launches it again.
# That has been the platform's behaviour since Android 3.1. A force-stop here
# would produce a guaranteed non-delivery and a red run that says nothing.
#
# `am kill` reproduces the event that IS interesting — the system reclaiming the
# process under memory pressure — and leaves the package in its normal state, so
# a later message really does restart it.
#
# WHAT THIS DELIBERATELY DOES NOT PROVE
#
# **The foreground promotion.** This job installs the ordinary debug APK, which
# has no `LdkEnvironment` — `WalletModule` binds `ForegroundPresence.None` in that
# build and says so in a comment. So `presence.promote()` is a no-op here and
# nothing is promoted, refused or allowlisted. The Android 12+ background-start
# restriction is therefore NOT measured by this job, and a green run must not be
# read as saying it was. That half needs the *configured* regtest APK on a
# `google_apis` image, which is BIT-132's territory and a different job again;
# §1 of the doc carries the row.
#
# Locally, with a google_apis emulator up and a regtest key on disk:
#   JOB_START_EPOCH=$(date +%s) \
#   FCM_REGTEST_SERVICE_ACCOUNT="$(base64 -w0 key.json)" \
#   bash android/scripts/ci-fcm-delivery.sh
set -euo pipefail

job_start=${JOB_START_EPOCH:-0}
emulator_ready=$(date +%s)

# The INSTALLED package, which is not the namespace: build.gradle.kts sets
# applicationId "com.bittr.android" and the debug build type adds
# applicationIdSuffix ".regtest". Getting this wrong is silent in the worst
# direction — `am kill` on a package that does not exist exits 0 — so the
# workflow exports APP_ID from the same value and test_ci_wallet_host_phase.sh
# pins both against build.gradle.kts.
APP_PACKAGE="${APP_ID:-com.bittr.android.regtest}"

HANDOFF_FILE="fcm_delivery_handoff.txt"
HANDOFF_MARKER="FCM_DELIVERY_HANDOFF ready"
WAKE_REASON="ci-delivery"
# For messages only. The sender owns the real copy and test-send-fcm-wake.sh pins
# that one against BackgroundWake.WAKE_KEY; this is here so a warning can name the
# field a reader has to go and look at.
WAKE_KEY_NAME="bittr_wake"

# How long to wait for a message after FCM accepted it. Generous: the send is
# one round trip but the delivery is GMS's, and the process has to be created
# from cold. Short enough that two of them plus a boot stay inside the job's
# timeout.
WAKE_TIMEOUT_SECONDS=90

RUNNER_TEMP_DIR=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
WORK_DIR="$(mktemp -d "$RUNNER_TEMP_DIR/fcm-delivery.XXXXXX")"
chmod 700 "$WORK_DIR"
# The hand-off and the decoded key both live here and both are secrets of a kind.
# Removed on every exit path including failure.
trap 'rm -rf "$WORK_DIR"' EXIT

adb devices

# --- Preflight: this image has to have Play services --------------------------
#
# The vacuity guard, and the same shape as ci-wallet-instrumented.sh's transport
# check. On an AOSP image no token can be minted and no message can arrive, so
# every "the wake did not fire" observation below would be true and meaningless.
# FcmDeliveryTest#playServicesAreOnThisImage asserts it from the inside as well;
# doing it here buys a legible failure seconds in rather than one buried in a
# test report, and catches the case where Gradle never gets that far.

echo "--- Play services preflight (BIT-135)"

gms_version=$(adb shell dumpsys package com.google.android.gms 2>/dev/null \
  | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1 | tr -d '\r' || true)

if [ -z "$gms_version" ]; then
  echo "::error::com.google.android.gms is not installed on this emulator, so no FCM"\
    " registration token can be minted and no message can be delivered to this app."\
    " Every delivery observation from this run would be vacuous. This job must boot a"\
    " google_apis image; 'default' and 'aosp_atd' are AOSP and carry no Play services."\
    " Fix the image in .github/workflows/fcm-delivery.yml, and remember the AVD cache"\
    " key has to change with it or the old snapshot is restored under the new config."\
    " Note that the wallet-instrumented job's image CANNOT be changed to match: it"\
    " needs com.android.localtransport, which is AOSP-only. The two jobs are separate"\
    " for exactly this reason."
  exit 1
fi

echo "Play services: $gms_version"

# The mirror of the above, recorded rather than asserted. This image is expected
# to have NO local backup transport — that is the mutual exclusion that makes
# this a second job — and saying so out loud is what stops someone later
# "simplifying" the two jobs into one.
transports=$(adb shell bmgr list transports 2>/dev/null | tr -d '\r' || true)
if printf '%s' "$transports" | grep -qF 'com.android.localtransport'; then
  echo "::notice title=FCM delivery::This google_apis image unexpectedly carries"\
    " com.android.localtransport. That does not affect this job, but it undercuts the"\
    " argument in wallet-node-device-tests.md §1 that the two suites cannot share an"\
    " AVD. Worth re-deriving before anyone acts on it."
else
  echo "No local backup transport on this image, as expected for google_apis."
fi

# --- The instrumented half ----------------------------------------------------
#
# `|| status=$?` rather than letting set -e kill the script: the host phase below
# must still run and still report, because "the device was never prepared" and
# "the message was not delivered" are the two outcomes this job exists to keep
# apart and only the second is a finding.
status=0
test_start=$(date +%s)

run_gradle() {
  label=$1
  task=$2
  shift 2
  log="$RUNNER_TEMP_DIR/$(echo "$task" | tr ':' '_').fcm.log"

  echo "--- $task ($label)"
  if (cd android && ./gradlew "$task" "$@" --no-daemon 2>&1) | tee "$log"; then
    return 0
  fi

  tail_encoded=$(tail -40 "$log" | sed -e 's/%/%25/g' | awk '{printf "%s%%0A", $0}')
  echo "::error::$task FAILED — Gradle's own output, not a test failure. If the"\
    " tail below shows an install, device or SDK error then no test ran, and the"\
    " results gate's empty failure list means 'nothing executed' rather than"\
    " 'nothing broke'. Last 40 lines:%0A$tail_encoded"
  return 1
}

# The annotation filter is what keeps this suite and the wallet suite apart in
# one APK — see RequiresPlayServices.kt for why that is the switch rather than an
# @Assume or a conditional source set. Spelled with the full package: the runner
# matches the annotation's binary name, and a bare `RequiresPlayServices` matches
# nothing and produces a vacuously green task. check-fcm-delivery-results.py is
# what refuses that.
#
# leaveApksInstalledAfterRun, for the same reason BIT-108 needed it: AGP
# uninstalls both APKs when connectedAndroidTest finishes, and an uninstall takes
# the planted wallet AND the FCM registration with it. The send would then get
# UNREGISTERED from a device that was addressable thirty seconds earlier.
run_gradle "the device-side preconditions for a wake" \
  :app:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.annotation=com.bittr.android.RequiresPlayServices \
  -Pandroid.injected.androidTest.leaveApksInstalledAfterRun=true || status=$?

test_end=$(date +%s)
duration=$((test_end - test_start))

check_status=0
python3 android/scripts/check-fcm-delivery-results.py || check_status=$?

# --- The delivery, driven from the host ---------------------------------------

echo "--- FCM delivery (host-driven — BIT-135)"

# Every exit from this phase that is not a completed observation ends in a
# ::warning:: and leaves the verdict as "did not look". Turning any of them into
# a red would be claiming a result this job did not get — the same rule
# ci-wallet-instrumented.sh's host phase follows, and for the same reason.
delivery_verdict="not attempted"
delivery_detail=""
control_verdict="not attempted"

attempt_delivery() {
  installed=$(adb shell pm list packages 2>/dev/null | tr -d '\r' || true)
  if ! printf '%s\n' "$installed" | grep -q "^package:$APP_PACKAGE$"; then
    bittr_packages=$(printf '%s\n' "$installed" | grep -i 'bittr' | tr '\n' ' ' \
      | sed 's/[[:space:]]*$//' || true)
    echo "::warning title=FCM delivery::$APP_PACKAGE is not installed after"\
      " connectedAndroidTest, so there is no app to deliver to. The bittr packages this"\
      " device DOES have are: ${bittr_packages:-(none)}. If that is (none), AGP stopped"\
      " honouring -Pandroid.injected.androidTest.leaveApksInstalledAfterRun and took the"\
      " planted wallet and the FCM registration with it. If a package IS listed, this"\
      " script is addressing the wrong name. Either way this is a harness failure and"\
      " NOT evidence about delivery."
    delivery_detail="the app was not installed"
    return
  fi

  # `run-as` rather than `adb root`: the debug build is debuggable, so this works
  # on any image, and it does not depend on the emulator being userdebug. Fall
  # back to root + cat, which is what google_apis (unlike google_apis_playstore)
  # still allows.
  handoff=$(adb shell "run-as $APP_PACKAGE cat no_backup/$HANDOFF_FILE" 2>/dev/null | tr -d '\r' || true)
  if ! printf '%s' "$handoff" | grep -qF "$HANDOFF_MARKER"; then
    adb root >/dev/null 2>&1 || true
    adb wait-for-device >/dev/null 2>&1 || true
    handoff=$(adb shell "cat /data/data/$APP_PACKAGE/no_backup/$HANDOFF_FILE" 2>/dev/null | tr -d '\r' || true)
  fi

  if ! printf '%s' "$handoff" | grep -qF "$HANDOFF_MARKER"; then
    echo "::warning title=FCM delivery::No hand-off from"\
      " FcmDeliveryTest#aWalletAndARegistrationTokenAreLeftForTheHostToWake at"\
      " no_backup/$HANDOFF_FILE, so there is no registration token to address and no"\
      " wallet was planted for a wake to find. Sending anyway would produce a"\
      " non-delivery that is indistinguishable from a real one. Read this run as 'did"\
      " not look'. Causes: the test was filtered out, renamed, or failed before it"\
      " finished; or neither run-as nor adb root could read the app's data directory."
    delivery_detail="no hand-off from the device"
    return
  fi

  printf '%s\n' "$handoff" >"$WORK_DIR/handoff.txt"

  # Mask BEFORE anything else touches it. shared/docs/privacy-disclosure.md lists
  # the registration token as a per-install device identifier, and on this PUBLIC
  # repo annotations answer 200 to anonymous readers even though the job log does
  # not. ::add-mask:: is a workflow command, so this only does anything on a
  # runner; locally it prints a harmless line and the token stays in the file.
  device_token=$(printf '%s\n' "$handoff" | grep -v '^[[:space:]]*$' | tail -1)
  echo "::add-mask::$device_token"
  echo "Hand-off found: a registration token of ${#device_token} characters (masked)."

  if [ -z "${FCM_REGTEST_SERVICE_ACCOUNT:-}" ]; then
    # The expected state until Ruben provisions the secret. A warning and not an
    # error: everything this job CAN do without a credential has just been done
    # and passed, and failing here would make a job that is working correctly
    # look broken for the length of the wait.
    echo "::warning title=FCM delivery::FCM_REGTEST_SERVICE_ACCOUNT is not set, so no"\
      " message was sent and the delivery leg of K2 is STILL UNRUN. Everything upstream"\
      " of the send did pass: this image has Play services $gms_version, the APK is"\
      " registered against bittr-regtest, a wallet is planted and Google minted a"\
      " registration token for this install — which is more than the wallet-instrumented"\
      " job can establish on an AOSP image. What is missing is the credential. It must be"\
      " the bittr-regtest service-account key and never bittr-prod's; only Ruben can"\
      " provision it, and android/scripts/verify-fcm-service-account.sh --expect regtest"\
      " is what tells the two apart before it is pasted. See BIT-135 and"\
      " android/docs/wallet-node-device-tests.md §1."
    delivery_detail="no credential in this run"
    return
  fi

  # The secret is base64 of the JSON — that is what verify-fcm-service-account.sh
  # --print-env emits, and GitHub secrets round-trip a single line far more
  # reliably than a PEM with embedded newlines. Raw JSON is accepted too, because
  # the failure mode of guessing wrong is a key that "does not parse" and a
  # person re-pasting a secret they cannot see.
  key_file="$WORK_DIR/regtest-key.json"
  if printf '%s' "$FCM_REGTEST_SERVICE_ACCOUNT" | base64 -d >"$key_file" 2>/dev/null &&
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$key_file" 2>/dev/null; then
    echo "Credential: decoded from base64."
  else
    printf '%s' "$FCM_REGTEST_SERVICE_ACCOUNT" >"$key_file"
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$key_file" 2>/dev/null; then
      echo "::error title=FCM delivery::FCM_REGTEST_SERVICE_ACCOUNT is set but is neither"\
        " base64-encoded JSON nor JSON. Re-run"\
        " 'android/scripts/verify-fcm-service-account.sh <key.json> --expect regtest"\
        " --print-env' and paste the FCM_SERVICE_ACCOUNT_JSON_B64 line's value."
      delivery_detail="the credential did not parse"
      return
    fi
    echo "Credential: read as raw JSON."
  fi
  chmod 600 "$key_file"

  # The swap check, run in CI as well as by the human who pasted it. --offline
  # because the send itself is about to exercise the network half, and a script
  # that mints an access token twice is a script that holds a credential longer
  # than it needs to. What --offline still does is the part that matters here:
  # refuse a bittr-prod key, and cross-check it against the committed
  # google-services.json for the build type this job installs.
  if ! bash android/scripts/verify-fcm-service-account.sh "$key_file" --expect regtest --offline; then
    echo "::error title=FCM delivery::The credential in FCM_REGTEST_SERVICE_ACCOUNT is not"\
      " the bittr-regtest key. Nothing was sent. This is the swap the two-project split"\
      " exists to prevent, and BIT-123's standing note forbids the other side of it"\
      " outright: bittr-prod's registration tokens are real user devices."
    delivery_detail="the credential was not the regtest key"
    return
  fi

  # --- The negative control, first --------------------------------------------
  #
  # Sent BEFORE the wake, and it is not optional. "The app woke and started the
  # node" and "any push starts a node" are the same green from the host's side,
  # and the FCM project this app registers in also carries ordinary payment
  # notifications — each of which would otherwise put a permanent foreground
  # notification in front of a user. FcmWakeTest#aMessageWithoutTheWakeKeyIsDropped
  # makes the same claim at the deliver() seam; this one makes it through Google,
  # which is the only place the framework's own dispatch is in the loop.
  #
  # Ordering matters: if the control ran second, a device that had already been
  # woken would be running, and "no new wake line" would be ambiguous.
  deliver_and_observe "control" "--no-wake-key" "NotAWake" "Waking"
  control_verdict=$observed

  # --- The wake ---------------------------------------------------------------
  deliver_and_observe "wake" "--wake-reason $WAKE_REASON" "Waking(reason=$WAKE_REASON)" ""
  delivery_verdict=$observed
}

# `deliver_and_observe <label> <sender-args> <expected> <forbidden>`
#
# Kill, clear logcat, send, poll. Leaves one word — delivered / not delivered /
# wrong outcome / not attempted — in the global `observed`.
#
# A global rather than a value on stdout, deliberately: a command substitution
# would put every line of narration below into a subshell's stdout, which would
# then have to be split from the verdict. That is how a verdict comes to be the
# tail of a log rather than a decision, and the first draft of this function got
# it wrong. Narration goes to the job log in order; the answer goes here.
observed=""

deliver_and_observe() {
  label=$1
  sender_args=$2
  expected=$3
  forbidden=$4
  observed="not attempted"

  echo "--- $label: killing $APP_PACKAGE"

  # `am kill`, never `am force-stop`. See the header: a force-stopped package is
  # in the stopped state and the framework will not deliver to it at all, so that
  # would guarantee the non-delivery this is trying to measure.
  adb shell am kill "$APP_PACKAGE" >/dev/null 2>&1 || true

  # `am kill` only kills a process the system considers safe to kill, and it
  # reports success either way. Verify, because a surviving process would make the
  # whole run meaningless in the direction that looks like a pass: an
  # already-running app receives the message through the same service, so the wake
  # line appears and nothing whatever about PROCESS RESTART was proved.
  alive=""
  for _ in 1 2 3 4 5; do
    alive=$(adb shell pidof "$APP_PACKAGE" 2>/dev/null | tr -d '\r' || true)
    if [ -z "$alive" ]; then
      break
    fi
    sleep 2
    adb shell am kill "$APP_PACKAGE" >/dev/null 2>&1 || true
  done

  if [ -n "$alive" ]; then
    echo "::warning title=FCM delivery::$APP_PACKAGE is still running (pid $alive) after"\
      " five 'am kill' attempts, so this send would reach a LIVE process. A wake line from"\
      " that is not evidence about waking a dead one, which is the claim. 'am kill' refuses"\
      " processes the system does not consider safe to kill; something is holding this one"\
      " up."
    return
  fi

  echo "Process is gone. Clearing logcat and sending."
  adb logcat -c >/dev/null 2>&1 || true

  # shellcheck disable=SC2086
  # $sender_args is two words on purpose — `--wake-reason ci-delivery` — and every
  # value in it is a literal from this file, never from the device.
  if ! bash android/scripts/send-fcm-wake.sh \
    --key-file "$WORK_DIR/regtest-key.json" \
    --token-file "$WORK_DIR/handoff.txt" \
    $sender_args; then
    echo "::warning title=FCM delivery::The $label message was not accepted by FCM, so"\
      " nothing was delivered and nothing can be concluded about the app. The sender's own"\
      " output above says whether that was the credential, the target or the payload — all"\
      " three are findings about this harness rather than about the wake."
    return
  fi

  echo "Waiting up to ${WAKE_TIMEOUT_SECONDS}s for the app to say what it did."

  deadline=$(($(date +%s) + WAKE_TIMEOUT_SECONDS))
  seen=""
  while [ "$(date +%s)" -lt "$deadline" ]; do
    # Both tags. BittrMessaging is BittrMessagingService's own, and it is the
    # stronger evidence because only the framework dispatching to OUR service
    # produces it — firebase-messaging's fallback base class logs nothing at all,
    # which is the silent regression FcmWakeTest#theAppsOwnServiceOutranksThe
    # LibraryFallback exists for. WalletModule is BackgroundWake's `report`
    # callback in an unconfigured build, kept as a second reading.
    seen=$(adb logcat -d -s BittrMessaging:I WalletModule:I 2>/dev/null | tr -d '\r' || true)
    if printf '%s' "$seen" | grep -qF "Background wake"; then
      break
    fi
    sleep 3
  done

  wake_lines=$(printf '%s\n' "$seen" | grep -F "Background wake" || true)
  if [ -n "$wake_lines" ]; then
    echo "What the app logged:"
    printf '%s\n' "$wake_lines"
  else
    echo "Nothing under BittrMessaging or WalletModule mentioned a background wake."
  fi

  if [ -n "$forbidden" ] && printf '%s' "$wake_lines" | grep -qF "$forbidden"; then
    echo "::error title=FCM delivery::The $label message produced '$forbidden'. For the"\
      " negative control that means a push carrying no $WAKE_KEY_NAME field started the"\
      " wallet, so every ordinary payment notification this app is sent would start a"\
      " Lightning node and put a permanent foreground notification in front of the user."\
      " That is a product finding, not a harness one."
    observed="wrong outcome"
    return
  fi

  if printf '%s' "$wake_lines" | grep -qF "$expected"; then
    observed="delivered"
    return
  fi

  if [ -z "$wake_lines" ]; then
    observed="not delivered"
    return
  fi

  observed="wrong outcome"
}

attempt_delivery

# --- Clean up the device ------------------------------------------------------
#
# The wallet planted above is a real seed on a real device image, and the hand-off
# file is a real registration token. The emulator is thrown away after this job,
# so this is belt and braces — but a cached AVD snapshot is exactly the kind of
# thing that stops being thrown away, and BackupExclusionTest's rule about not
# leaving seeds behind is a rule about habits rather than about one job.
echo "--- Clearing $APP_PACKAGE"
adb shell pm clear "$APP_PACKAGE" >/dev/null 2>&1 || true

# --- The verdict --------------------------------------------------------------

case "$delivery_verdict" in
delivered)
  if [ "$control_verdict" = "delivered" ]; then
    echo "::notice title=FCM delivery::K2's delivery leg is PROVED for the first time."\
      " A high-priority, data-only FCM HTTP v1 message sent from the host through"\
      " bittr-regtest reached a process that had been killed with 'am kill', and"\
      " BittrMessagingService logged Waking(reason=$WAKE_REASON) — so the framework"\
      " dispatched to OUR service and BackgroundWake accepted it. The negative control"\
      " passed too: an otherwise identical message with no wake key produced NotAWake,"\
      " so this is not 'any push starts a node'. NOT proved by this run: the foreground"\
      " promotion, which is ForegroundPresence.None in an unconfigured APK — see the"\
      " header of this script and wallet-node-device-tests.md §1."
  else
    echo "::warning title=FCM delivery::The wake was delivered, but the negative control"\
      " did not complete ($control_verdict). 'the wake ran' and 'every push starts a"\
      " node' are the same green without it, so this is a delivery observation and not"\
      " yet a result. Read the control's output above."
  fi
  ;;
"not delivered")
  echo "::error title=FCM delivery::FCM accepted a high-priority, data-only message for"\
    " this device and NOTHING reached the app within ${WAKE_TIMEOUT_SECONDS}s. The"\
    " message carried ttl=0s, so there is no store-and-retry and this is a real"\
    " non-delivery rather than a slow one. The device was prepared — Play services"\
    " $gms_version, a wallet planted, a live registration token — and the process was"\
    " confirmed dead before the send. This is a finding about delivery or about the"\
    " background-start path, and it is what BIT-135 exists to surface. Do not retry it"\
    " away."
  # A red, and a real one. Not `|| true` anywhere near it: a non-delivery from a
  # prepared device is the finding this job exists to surface, and the no-retries
  # rule at the top of android-maestro.yml covers it.
  if [ "$status" -eq 0 ]; then
    status=1
  fi
  ;;
"wrong outcome")
  echo "::error title=FCM delivery::A message arrived and the app did something other"\
    " than what was asked of it. The logged outcome is above. Waking/Woken is the pass;"\
    " NotAWake means BackgroundWake.WAKE_KEY and the sender's copy have drifted"\
    " (test-send-fcm-wake.sh pins them); NoWallet means the wallet FcmDeliveryTest"\
    " planted did not survive to the wake, which is a harness failure."
  # A red, and a real one. Not `|| true` anywhere near it: a non-delivery from a
  # prepared device is the finding this job exists to surface, and the no-retries
  # rule at the top of android-maestro.yml covers it.
  if [ "$status" -eq 0 ]; then
    status=1
  fi
  ;;
*)
  echo "::warning title=FCM delivery::The delivery leg was NOT ATTEMPTED on this run"\
    " ($delivery_detail). Nothing below should be read as evidence about whether Google"\
    " delivers a wake to this app. The instrumented half — Play services present, the"\
    " APK registered against bittr-regtest, a wallet planted and a token minted — is"\
    " what this run does establish."
  ;;
esac

result="green"
if [ "$status" -ne 0 ] || [ "$check_status" -ne 0 ]; then
  result="RED"
fi

setup="not measured"
if [ "$job_start" -ne 0 ]; then
  setup=$((emulator_ready - job_start))
fi

{
  echo "### K2's FCM delivery leg — on a google_apis image"
  echo
  echo "| stage | seconds |"
  echo "|---|---:|"
  echo "| setup + emulator boot | $setup |"
  echo "| \`:app:connectedDebugAndroidTest\` | $duration |"
  echo
  echo "Result: **$result**"
  echo
  echo "| leg | outcome |"
  echo "|---|---|"
  echo "| wake message delivered | \`$delivery_verdict\` |"
  echo "| negative control (no wake key) | \`$control_verdict\` |"
  echo
  echo "**The verdict is the \`FCM delivery\` annotation, not this table.** The"
  echo "instrumented half only leaves the device in the state a wake needs; the"
  echo "delivery is driven from the host after Gradle exits, because the wake"
  echo "happens in a process no instrumentation is running in."
  echo
  echo "**\`am kill\`, never \`am force-stop\`.** A force-stopped package is in"
  echo "Android's stopped state and the framework does not deliver to it at all —"
  echo "\`wallet-node-device-tests.md\` §2 withdrew a row for exactly that reason."
  echo "\`am kill\` reproduces process death, which is the interesting event."
  echo
  echo "**What this job does NOT prove: the foreground promotion.** This installs"
  echo "the ordinary debug APK, which has no \`LdkEnvironment\`, so \`WalletModule\`"
  echo "binds \`ForegroundPresence.None\` and \`promote()\` is a no-op. The Android"
  echo "12+ background-start restriction is not measured here. That half needs the"
  echo "configured regtest APK on a Play-services image, which is a third job."
  echo
  echo "The message is high-priority and \`data\`-only. Neither property is"
  echo "assertable from Android — \`send-fcm-wake.sh\` builds them in one place,"
  echo "re-asserts them on every send, and \`test-send-fcm-wake.sh\` negative-controls"
  echo "both in the \`build\` job."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || echo "::warning::Could not write the summary. The test result itself is unaffected."

echo "::notice title=FCM delivery — $result::wake=$delivery_verdict control=$control_verdict · vacuity check $([ "$check_status" -eq 0 ] && echo passed || echo FAILED)"

if [ "$status" -ne 0 ]; then
  exit "$status"
fi
exit "$check_status"
