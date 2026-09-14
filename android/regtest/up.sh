#!/usr/bin/env bash
#
# Bring up the private regtest network and write down what it turned out to be
# (BIT-132).
#
# Two outputs, and the second is the point:
#
#   1. Three running containers — see docker-compose.yml.
#   2. android/regtest/regtest-facts.json, which is the only thing anything
#      downstream reads. The APK's six BITTR_LDK_* values are derived from it by
#      android/scripts/regtest-ldk-env.py, and the K7 host phase reads the LND
#      pubkey out of it.
#
# WHY A FACTS FILE RATHER THAN EXPORTED VARIABLES
#
# The one value here that cannot be written down in advance is LND's node id: it
# is generated when `--noseedbackup` creates the wallet, so it differs per
# bring-up. Everything else (ports, network) is fixed. Putting the whole set in a
# file keeps the fixed and the discovered values in one shape, lets
# regtest-ldk-env.py have a unit test with no network in it, and — the reason
# that matters on this repo's runner — makes the network's identity an artefact a
# red run can upload.
#
# IDEMPOTENT, AND NOT A NO-OP
#
# Running this twice is safe and is not free: it reuses running containers,
# re-mines only if the chain is short, and rewrites the facts file. It does not
# tear anything down; that is down.sh, deliberately separate so a failed test run
# leaves a network a human can poke at.
#
# Locally:
#   bash android/regtest/up.sh
#   cat android/regtest/regtest-facts.json
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
facts="$here/regtest-facts.json"

compose() { docker compose --project-directory "$here" "$@"; }
btc() {
  compose exec -T bitcoind \
    bitcoin-cli -regtest -rpcuser=bittr -rpcpassword=bittr "$@"
}
lnc() {
  compose exec -T lnd \
    lncli --network=regtest --rpcserver=localhost:10009 "$@"
}

fail() {
  echo "::error::$*" >&2
  exit 1
}

# Like fail(), but carries evidence INTO the annotation rather than leaving it in
# the log.
#
# "Logs are above" is a promise this repository cannot keep. On this public
# repository the job log answers 403 and artifacts answer 401
# (android/docs/ci-evidence.md), so the check-run annotation is the only channel
# a reader actually has. The first run of the regtest network ever attempted
# printed `compose ps` and eighty lines of `compose logs` into exactly the place
# nobody can read, and surfaced one sentence — "did not come up healthy" — which
# names no service and no reason. Diagnosing it took a source audit that the logs
# would have answered in a line.
#
# A workflow command reads one line, so newlines are escaped as %0A and render as
# real lines in the annotation. `%` goes first or it would eat the escapes it is
# about to write. Trimmed to the last 40 lines per service: annotations are
# capped (~64 KB), and a truncated annotation is worth more than a dropped one.
fail_with_state() {
  local summary="$1" evidence
  evidence=$(
    echo "--- docker compose ps"
    compose ps 2>&1 || true
    echo "--- docker compose logs (last 40 lines per service)"
    compose logs --no-color --tail=40 2>&1 || true
  )
  # Keep the plain copy too, for anyone who CAN read the log.
  echo "$evidence"
  evidence=${evidence//'%'/'%25'}
  evidence=${evidence//$'\n'/'%0A'}
  evidence=${evidence//$'\r'/'%0D'}
  echo "::error::$summary%0A%0A$evidence" >&2
  exit 1
}

# --- Preflight ----------------------------------------------------------------
#
# Docker is a host requirement this repository did not have before BIT-132, so
# its absence is the single most likely way this script is first run wrong. Said
# in one line, with the doc that fixes it named, rather than as `docker: command
# not found` forty lines into a nightly job.
command -v docker > /dev/null 2>&1 \
  || fail "docker is not on PATH. The regtest network needs Docker with the compose plugin; see android/docs/self-hosted-runner.md."
docker compose version > /dev/null 2>&1 \
  || fail "\`docker compose\` is not available (the v2 compose plugin, not docker-compose v1). See android/docs/self-hosted-runner.md."

# --- Start --------------------------------------------------------------------
#
# `--wait` blocks on the healthchecks in docker-compose.yml, which is what makes
# every step below able to assume a loadable chain and an unlocked LND rather
# than retry-looping for one. `--wait-timeout` is generous because a cold run
# also builds electrs from source (see electrs/Dockerfile for what that costs).
echo "--- Starting the regtest network (this builds electrs on a cold runner)"
compose up -d --build --wait --wait-timeout 1800 \
  || fail_with_state "The regtest network did not come up healthy."

# --- Coins ---------------------------------------------------------------------
#
# A wallet has to exist before `generatetoaddress` has an address to mine to, and
# bitcoind 27 creates none by default. `createwallet` fails if it already exists
# and `loadwallet` fails if it is already loaded, so both are allowed to fail and
# the thing that is checked is the outcome: an address comes back.
btc createwallet bittr > /dev/null 2>&1 || btc loadwallet bittr > /dev/null 2>&1 || true
mining_address=$(btc -rpcwallet=bittr getnewaddress) \
  || fail "bitcoind has no usable wallet, so there is nothing to mine to."

height=$(btc getblockcount)
if [ "$height" -lt 101 ]; then
  # 101, not 100. Coinbase outputs need 100 confirmations before they are
  # spendable, so block 101 is the first height at which block 1's reward can
  # fund anything — mine 100 and the funding step below fails with an
  # insufficient-funds error that says nothing about maturity.
  echo "--- Mining $((101 - height)) blocks to reach spendable coinbase"
  btc generatetoaddress "$((101 - height))" "$mining_address" > /dev/null
fi

# --- Fund LND ------------------------------------------------------------------
#
# LND is the channel counterparty and it does NOT open the channel: the app does
# (see README.md — everything is outbound from the emulator, so no adb reverse
# and no host-to-device dialling). So why fund it at all?
#
# Because an unfunded LND cannot pay the anchor reserve on its side of a channel
# it accepts, and because a counterparty with no UTXOs cannot force-close or
# sweep — which is the half of K8's "channel-monitor freshness" that is about
# what the OTHER end does while we are in Doze.
echo "--- Funding LND"
lnd_address=$(lnc newaddress p2wkh | python3 -c 'import json,sys; print(json.load(sys.stdin)["address"])')
btc -rpcwallet=bittr sendtoaddress "$lnd_address" 5 > /dev/null
btc generatetoaddress 1 "$mining_address" > /dev/null

# --- Wait for LND to agree that it happened ------------------------------------
#
# `getinfo` answering is what the compose healthcheck proved, and it is not this.
# LND reports itself up before it has caught the tip, and a channel opened
# against a counterparty that is behind is a channel that stalls at pending —
# with no error anywhere, which is the worst shape for a nightly job to fail in.
echo "--- Waiting for LND to sync and see its funds"
deadline=$(( $(date +%s) + 120 ))
while :; do
  info=$(lnc getinfo 2> /dev/null || echo '{}')
  balance=$(lnc walletbalance 2> /dev/null || echo '{}')
  read -r synced confirmed <<< "$(
    SYNC_JSON="$info" BAL_JSON="$balance" python3 - <<'PY'
import json
import os

info = json.loads(os.environ["SYNC_JSON"] or "{}")
balance = json.loads(os.environ["BAL_JSON"] or "{}")
print(
    str(bool(info.get("synced_to_chain"))).lower(),
    int(balance.get("confirmed_balance") or 0),
)
PY
  )"
  if [ "$synced" = "true" ] && [ "$confirmed" -gt 0 ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    compose logs --tail=60 lnd || true
    fail "LND did not sync to the regtest tip with a confirmed balance within 120s (synced_to_chain=$synced, confirmed_balance=$confirmed). Logs are above."
  fi
  sleep 2
done

# --- Write the facts ------------------------------------------------------------
node_id=$(lnc getinfo | python3 -c 'import json,sys; print(json.load(sys.stdin)["identity_pubkey"])')

# Every port here is duplicated from docker-compose.yml, and that duplication is
# checked rather than trusted: android/scripts/test_regtest_ldk_env.py parses the
# compose file and fails if a published port stops matching the number written
# here. Two files disagreeing about a port number produces a wallet that syncs
# and cannot pay, which is a vacuous green in the K7 sense.
python3 - "$facts" "$node_id" <<'PY'
import json
import sys

path, node_id = sys.argv[1], sys.argv[2]
json.dump(
    {
        "network": "regtest",
        "lightningNodeId": node_id,
        "lightningPort": 9735,
        "esploraPort": 3002,
        "electrumPort": 60401,
        "bitcoindRpcPort": 18443,
        "lndRpcPort": 10009,
    },
    open(path, "w"),
    indent=2,
    sort_keys=True,
)
open(path, "a").write("\n")
PY

echo "--- Network up. Facts:"
cat "$facts"
