#!/usr/bin/env bash
#
# Tear the private regtest network down, including its chain (BIT-132).
#
# Separate from up.sh on purpose: a failed K7 or K8 run leaves a network holding
# the channel, the payment and the HTLC that failed, and that state is the whole
# diagnosis. The nightly job calls this in an `if: always()` step so a human
# debugging locally can leave it running.
#
# `--volumes` is not optional here, and that is the difference between this and
# `docker compose down`. The volumes hold a regtest chain, an electrs index and
# an LND wallet, and every one of them is state the next run must not inherit:
#
#   * a chain at height 400 makes "mine to 101" a no-op and leaves the funding
#     UTXO already spent by the previous run;
#   * an LND wallet carries the previous run's node id, so the facts file and the
#     APK built from it would name a peer whose channel is already closed;
#   * an electrs index built against a chain that is gone answers, wrongly.
#
# All three fail late and quietly rather than at start-up. So the default is a
# clean slate, and keeping state is an explicit flag.
#
# Locally:
#   bash android/regtest/down.sh          # remove containers AND state
#   bash android/regtest/down.sh --keep   # stop containers, keep the chain
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)

keep=no
if [ "${1:-}" = "--keep" ]; then
  keep=yes
fi

if ! command -v docker > /dev/null 2>&1; then
  # Not a failure. This runs in an `if: always()` step, and a job that already
  # failed because Docker was missing must not fail a second time here and
  # replace its own cause with this one.
  echo "docker is not on PATH; nothing to tear down."
  exit 0
fi

echo "--- Service state before teardown"
docker compose --project-directory "$here" ps || true

if [ "$keep" = yes ]; then
  docker compose --project-directory "$here" down --remove-orphans
  echo "--- Containers removed; volumes kept. Next up.sh inherits this chain."
else
  docker compose --project-directory "$here" down --volumes --remove-orphans
  echo "--- Containers and volumes removed."
fi

# The facts file describes a network that no longer exists, and a stale one is
# worse than a missing one: regtest-ldk-env.py would happily build an APK
# pointing at a node id that is gone, and the failure arrives as a peer that
# never connects.
rm -f "$here/regtest-facts.json"
