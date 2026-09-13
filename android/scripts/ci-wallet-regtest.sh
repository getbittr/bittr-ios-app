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
log=$(mktemp)
if (cd android && ./gradlew :app:connectedDebugAndroidTest --no-daemon 2>&1) | tee "$log"; then
  gradle_outcome=passed
else
  gradle_outcome=failed
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
verdict=0
python3 android/scripts/check-wallet-regtest-results.py || verdict=1

echo "--- Timing"
echo "Emulator ready after $((emulator_ready - job_start))s; suite finished after $(( $(date +%s) - job_start ))s."

if [ "$gradle_outcome" = failed ]; then
  echo "::error:::app:connectedDebugAndroidTest failed. The gate's output above says which tests, if the results were written at all."
  exit 1
fi
exit "$verdict"
