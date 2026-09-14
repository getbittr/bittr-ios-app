#!/usr/bin/env bash
#
# BIT-132: run the wallet's regtest suite against a real node and a real private
# Lightning network.
#
# Invoked by .github/workflows/wallet-regtest-nightly.yml as the `script:` input
# to reactivecircus/android-emulator-runner, from the repository root, with an
# emulator already booted and the regtest network already up.
#
# WHY THIS IS A FILE AND NOT AN INLINE `script:` BLOCK
#
# Same reason as ci-wallet-instrumented.sh, ci-instrumented.sh and ci-smoke.sh:
# the action hands that input to /usr/bin/sh, which on the Ubuntu images is dash,
# and `set -o pipefail` below would die on it AFTER the emulator has booted.
# android/scripts/check-action-scripts.sh enforces the `bash <file>` shape.
#
# WHAT MAKES THIS JOB DIFFERENT FROM `wallet-instrumented`
#
# The APK. That job builds the repository's normal, unconfigured wallet — no
# LdkEnvironment, no ldk-node, SeedWalletService — and it is right to. This job
# builds one with all six BITTR_LDK_* values supplied, which is the only kind of
# build any payment claim can be made about.
#
# The values arrive in the ENVIRONMENT, not as -P arguments. The workflow writes
# them to $GITHUB_ENV before the emulator step, app/build.gradle.kts reads
# BITTR_LDK_* as the fallback for each Gradle property, and
# `providers.environmentVariable` makes them configuration-cache inputs — so a
# changed value re-runs configuration rather than baking yesterday's URL into
# today's APK.
#
# THE PREFLIGHT IS NOT OPTIONAL
#
# Every assertion in this suite is of the form "the node reached X". On a runner
# where the regtest containers died after `up.sh` returned, the tests fail — which
# is correct but expensive and unreadable: five reds that all say "connection
# refused" and none of which is about the wallet. So the four endpoints are
# checked from the host first, in seconds, and a dead network fails in one legible
# line naming which service.
#
# Locally, with an emulator up and `bash android/regtest/up.sh` done:
#   eval "$(python3 android/scripts/regtest-ldk-env.py | sed 's/^/export /')"
#   JOB_START_EPOCH=$(date +%s) bash android/scripts/ci-wallet-regtest.sh
set -euo pipefail

job_start=${JOB_START_EPOCH:-0}
emulator_ready=$(date +%s)

adb devices

# --- Preflight 1: the build really is configured -------------------------------
#
# Before Gradle, because an unconfigured build here is not a red suite, it is a
# suite that COMPILES OUT: the regtest tests live in src/androidTestRegtest/,
# which app/build.gradle.kts only adds when a value was supplied. So a missing
# environment variable produces a test APK with no regtest classes in it,
# `connectedDebugAndroidTest` matches nothing, and it exits 0.
#
# check-wallet-regtest-results.py catches that afterwards — it is exactly the
# "no TEST-*.xml" case — but catching it here saves an emulator's worth of time
# and names the variable rather than the symptom.
missing=""
for name in BITTR_LDK_CHAIN_SOURCE_URL BITTR_LDK_ELECTRUM_URL \
            BITTR_LDK_LIGHTNING_NODE_ID BITTR_LDK_LIGHTNING_NODE_ADDRESS; do
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    missing="$missing $name"
  fi
done
if [ -n "$missing" ]; then
  echo "::error::Not configured for regtest; unset:$missing. Without all four, LdkEnvironmentConfig.fromBuildConfig() returns null, the app composes SeedWalletService, and src/androidTestRegtest/ is not compiled into the test APK — so this job would go GREEN having run no test at all. Run android/regtest/up.sh and android/scripts/regtest-ldk-env.py."
  exit 1
fi

# --- Preflight 2: the four endpoints answer from the host ----------------------
#
# From the host, not from the device. The device's view is what the suite itself
# asserts (RegtestEnvironmentTest), and the two are different claims: if the HOST
# cannot reach a published port then no device can, and that is a container
# problem rather than an emulator-networking one. Separating them is what makes a
# red here mean "the network is down" and a red there mean "10.0.2.2 is not
# reaching it".
esplora_port=${BITTR_LDK_CHAIN_SOURCE_URL##*:}
electrum_port=${BITTR_LDK_ELECTRUM_URL##*:}
peer_port=${BITTR_LDK_LIGHTNING_NODE_ADDRESS##*:}

tip=$(curl -sf --max-time 10 "http://127.0.0.1:${esplora_port}/blocks/tip/height" || true)
case "$tip" in
  ''|*[!0-9]*)
    echo "::error::Esplora on 127.0.0.1:${esplora_port} did not answer a tip height (got '${tip}'). electrs is down, still indexing, or not published. Check \`docker compose --project-directory android/regtest ps\`."
    exit 1
    ;;
esac
if [ "$tip" -lt 101 ]; then
  echo "::error::The regtest chain is at height ${tip}, below the 101 blocks android/regtest/up.sh mines. Coinbase outputs mature at 100 confirmations, so nothing on this chain can fund a channel — every payment test would fail for a reason that is not about payments."
  exit 1
fi

# `nc -z` for the two TCP-only endpoints. Speaking Electrum and BOLT 8 from a
# shell script would be reimplementing what the suite does properly from the
# device; what is needed here is only "is anything listening".
for probe in "Electrum:${electrum_port}" "Lightning peer:${peer_port}"; do
  label=${probe%%:*}
  probe_port=${probe##*:}
  if ! nc -z -w 5 127.0.0.1 "$probe_port" > /dev/null 2>&1; then
    echo "::error::${label} on 127.0.0.1:${probe_port} is not accepting connections. The regtest network is not up, or that port is not published — see android/regtest/docker-compose.yml."
    exit 1
  fi
done

echo "Regtest preflight OK: chain height ${tip}, Electrum ${electrum_port} and Lightning ${peer_port} listening."
echo "Peer node id: ${BITTR_LDK_LIGHTNING_NODE_ID}"

# --- The suite -----------------------------------------------------------------
#
# :app only. Every test here is a property of the installed application — its
# BuildConfig, its foreground service, its process being killed and restarted —
# and a library module's instrumented tests run in a self-instrumenting APK built
# from the library's own manifest, which :core:wallet-ldk does not have. See
# check-wallet-regtest-results.py's MODULES.
#
# No class filter. Filtering to a named class is how a suite silently stops
# running the test somebody added last week; the source set is already the filter,
# and it is one a build can be checked against.
#
# ONE EXCLUSION, AND IT IS AN ANNOTATION RATHER THAN A NAME
#
# K7's four phases are `@HostDriven`. They are one sequence — fund, open, pay,
# kill, assert — with the host doing half the work between them, so running them
# here would run them out of order and in one process: phase 4 would assert about
# a payment phase 3 had not sent, and its red would be read as a fund-safety
# result. They are run, in order, by k7-interrupted-payment.sh below.
#
# `notAnnotation` rather than a `-Pandroid...class=` exclusion list for the same
# reason the suite has no class filter: a list is a thing to forget to update. A
# phase added without the annotation would run here; test_k7_host_phase.sh fails
# the build job on exactly that.
#
# And notAnnotation rather than @Ignore: AndroidX applies this filter while
# building the test description, so an excluded method is never created and never
# appears in the XML. @Ignore would emit <skipped/>, which
# check-wallet-regtest-results.py treats as a failed run — correctly, because a
# skip is the quietest way for a suite to stop measuring anything.
log=$(mktemp)
if (cd android && ./gradlew :app:connectedDebugAndroidTest --no-daemon \
      -Pandroid.testInstrumentationRunnerArguments.notAnnotation=com.bittr.android.HostDriven \
      2>&1) | tee "$log"; then
  gradle_outcome=passed
else
  gradle_outcome=failed
fi

# The suite's results, moved out of the way BEFORE K7 runs.
#
# Every `connectedDebugAndroidTest` invocation writes to .../connected, and K7 is
# four more of them. Leaving these here would mean the gate reading phase 4's
# results in place of the suite's and reporting RegtestEnvironmentTest's six
# required tests as never run — a red that names the wrong thing, after a green
# suite.
#
# Created even when there is nothing to put in it. An absent directory is an
# error to the gate — "No such results directory" — where an empty one is the
# message that actually diagnoses this run: "No TEST-*.xml under ...
# connectedDebugAndroidTest goes green when it matches no tests, so this is the
# vacuous-green case this gate exists to catch."
suite_results=android/app/build/outputs/androidTest-results/suite
rm -rf "$suite_results"
mkdir -p "$suite_results"
if [ -d android/app/build/outputs/androidTest-results/connected ]; then
  cp -R android/app/build/outputs/androidTest-results/connected/. "$suite_results/" || true
fi

# --- K7, which needs the host between its phases -------------------------------
#
# Run whatever the suite above did. The suite is the vacuity guard — a configured
# APK reaching a live network — and K7 is the claim; a red guard makes K7's result
# unreadable, but skipping K7 would leave the gate reporting four required tests
# that "did not run at all", which is a worse verdict than the true one.
#
# Its own results are preserved per phase under androidTest-results/k7/phaseN,
# because every Gradle run overwrites .../connected. That is also why the gate is
# given both locations explicitly below.
#
# An exit of 2 is the script saying it could not set the experiment up — no
# channel, no HTLC, no kill. That is NOT a K7 finding and must not be reported as
# one, so it becomes a warning here and the gate then fails the job for the four
# required tests that did not run. The distinction is the same one this job's
# preflight makes: "did not look" and "looked and found it broken" are different
# news.
k7_outcome=0
bash android/scripts/k7-interrupted-payment.sh || k7_outcome=$?
if [ "$k7_outcome" = 2 ]; then
  echo "::warning title=K7::The K7 harness could not set its experiment up (exit 2)."\
    " No claim about interrupted payments was measured on this run. The gate below"\
    " will report its four phases as not run, which is the accurate verdict."
fi

# --- K8's freshness half, which runs over the channel K7 left ------------------
#
# AFTER K7, and that ordering is the whole reason this is a separate invocation
# rather than another method in the undirected suite. K8ChannelFreshnessTest
# needs a funded, open channel, and on this network one exists only once K7's
# phase 2 has opened it and phase 3 has mined it active. The alternative — a
# second funding and a second channel open for K8's own use — costs two more
# mined-and-waited phases for a channel identical to the one already there, on a
# job with a 90-minute ceiling. android/docs/wallet-node-device-tests.md §4
# settled that trade and named its price:
#
#   a red K7 phase 2 makes the freshness half UNRUNNABLE rather than merely
#   unreadable, and the gate reports it as "did not run at all".
#
# Run whatever K7 did, for the same reason K7 runs whatever the suite did: a
# skipped run leaves the gate reporting a required test that never ran, which is
# a worse verdict than the true one. The script's own preflight fails fast when
# there is no channel to measure, and says so as a SETUP failure.
#
# K8's MACHINERY half is not here. It needs no channel and no host, so it is an
# ordinary member of the undirected suite above — and keeping it there is what
# makes it survive a K7 that never got off the ground.
#
# Exit 2 is the same contract as K7's: the harness could not set the experiment
# up. Not a claim about the wallet, so it becomes a warning and the gate then
# fails the job for the required test that did not run.
k8_outcome=0
bash android/scripts/k8-doze-soak.sh || k8_outcome=$?
if [ "$k8_outcome" = 2 ]; then
  echo "::warning title=K8::The K8 soak harness could not set its experiment up (exit 2)."\
    " No claim about node lifecycle across Doze was measured on this run. The gate"\
    " below will report its freshness half as not run, which is the accurate verdict."
fi

# --- The verdict ----------------------------------------------------------------
#
# Run whatever Gradle said, and this is the important half. `connectedAndroidTest`
# exits 0 when it matches no tests, so a green Gradle run is not yet a result —
# which in this job is the likeliest failure of all, because the suite's presence
# depends on a build-time source-set condition.
#
# `|| verdict=1` rather than `set -e` doing it: the exit code below has to be the
# gate's, and a red Gradle run with a gate that also has something to say should
# print both.
#
# EVERY RESULTS DIRECTORY, NAMED. The suite's, plus one per K7 phase.
#
# Without this the gate reads only .../connected, which by now holds K7 phase 4's
# results and nothing else — every Gradle run overwrites it. The suite's own six
# tests would be reported as "did not run at all", and three of K7's four with
# them. Directories that do not exist are an error to the gate rather than a
# shrug, so they are only passed when the phase produced them; a phase that never
# ran is caught by REQUIRED, which is the check that should catch it.
results_args="--results-dir $suite_results"
for phase in 1 2 3 4; do
  phase_dir="android/app/build/outputs/androidTest-results/k7/phase$phase"
  if [ -d "$phase_dir" ]; then
    results_args="$results_args --results-dir $phase_dir"
  fi
done
# K8's freshness half, preserved by k8-doze-soak.sh for the same reason: it is
# one more `connectedDebugAndroidTest` invocation, and that overwrites
# .../connected along with every other one. Its machinery half needs no entry
# here — it ran inside the undirected suite, so it is already in $suite_results.
k8_freshness_dir="android/app/build/outputs/androidTest-results/k8/freshness"
if [ -d "$k8_freshness_dir" ]; then
  results_args="$results_args --results-dir $k8_freshness_dir"
fi

verdict=0
# shellcheck disable=SC2086 # deliberate word splitting: one --results-dir per path.
python3 android/scripts/check-wallet-regtest-results.py $results_args || verdict=1

echo "--- Timing"
echo "Emulator ready after $((emulator_ready - job_start))s; suite finished after $(( $(date +%s) - job_start ))s."

if [ "$gradle_outcome" = failed ]; then
  echo "::error:::app:connectedDebugAndroidTest failed. The gate's output above says which tests, if the results were written at all."
  exit 1
fi

# K7's own exit, propagated explicitly rather than left to the gate.
#
# In practice the gate already catches both shapes — a failed phase is a REQUIRED
# test with a <failure/>, and a phase that never ran is a REQUIRED test missing
# from the results. This line is here for the case where those two agree and are
# both wrong: a harness that exits 1 while somehow leaving four green XMLs behind.
# A job that exits 0 on that would be reporting a fund-safety pass it did not get.
if [ "$k7_outcome" = 1 ]; then
  echo "::error::K7 reported a failure (exit 1). Its own message above says which phase."
  exit 1
fi

# K8's, for the same reason and with the same caveat.
if [ "$k8_outcome" = 1 ]; then
  echo "::error::K8's freshness half reported a failure (exit 1). Read its assertion text"\
    " before rerunning: 'the node did not catch up' is a finding about Doze and the"\
    " foreground service, and 'K7's channel was not usable before the window' is not a"\
    " K8 result at all."
  exit 1
fi
exit "$verdict"
