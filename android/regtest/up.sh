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
# about to write.
#
# THE BUDGET IS 4096 CHARACTERS, AND THAT IS MEASURED.
#
# This used to say annotations are capped "(~64 KB)" and dump `--tail=40` for
# every service interleaved. The cap is 4096 characters on the decoded message:
# the annotation the second run produced is 4086 characters and ends mid-word, in
# the middle of a timestamp. At 40 lines each across three services the dump was
# several times over budget before it was written.
#
# What that cost is the whole reason this function exists. bitcoind is by far the
# most verbose of the three and was, on that run, the only service that was
# HEALTHY — so its startup chatter consumed the entire budget, and of the two
# services that had actually failed, electrs contributed one line and LND
# contributed none. The reader was handed four kilobytes of a working daemon.
#
# So: name the unhealthy services first, and spend the budget only on those,
# split evenly, keeping the END of each log — in a bring-up failure the useful
# line is the last thing the daemon said, not the first.
fail_with_state() {
  local summary="$1" dir svc
  dir=$(mktemp -d)

  compose ps -a --format json > "$dir/ps.json" 2> /dev/null || true
  for svc in $(compose ps -a --services 2> /dev/null); do
    compose logs --no-color --tail=60 "$svc" > "$dir/log-$svc.txt" 2>&1 || true
  done

  SUMMARY="$summary" DIR="$dir" python3 - <<'PY'
import json
import os
import sys

# The decoded-message cap is 4096; aim under it so the escaping and GitHub's own
# trailing trim cannot push a complete annotation back over the line.
CAP = 4000
summary, d = os.environ["SUMMARY"], os.environ["DIR"]


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


def logged_services():
    return [n[4:-4] for n in sorted(os.listdir(d)) if n.startswith("log-")]


# `compose ps --format json` emits a JSON array on some versions and one object
# per line on others, and both have shipped in v2. Accept either.
raw = read(os.path.join(d, "ps.json")).strip()
rows = []
if raw:
    try:
        rows = (
            json.loads(raw)
            if raw.startswith("[")
            else [json.loads(line) for line in raw.splitlines() if line.strip()]
        )
    except ValueError:
        rows = []

verdict, unhealthy = [], []
for row in rows:
    service = row.get("Service") or row.get("Name") or "?"
    health = row.get("Health") or ""
    verdict.append(
        "  %-10s %-12s %s" % (service, row.get("State") or "?", health or "no healthcheck")
    )
    if health != "healthy":
        unhealthy.append(service)

if not rows:
    verdict.append("  (docker compose ps reported nothing)")

head = [summary, "", "--- service health"] + verdict
if unhealthy:
    head += ["", "--- logs for the NOT-healthy services: " + ", ".join(unhealthy)]
else:
    # Either compose told us nothing or everything claims to be healthy and the
    # caller still failed. Both are worth all the logs rather than none.
    unhealthy = logged_services()
    head += ["", "--- no service reports unhealthy; all logs follow"]

out = "\n".join(head)
share = max(200, (CAP - len(out) - 40 * (len(unhealthy) + 1)) // max(1, len(unhealthy)))

for service in unhealthy:
    body = read(os.path.join(d, "log-%s.txt" % service)).rstrip()
    if len(body) > share:
        body = "...[earlier lines dropped]...\n" + body[-share:]
    out += "\n\n--- %s\n%s" % (service, body)

# Keep the plain copy too, for anyone who CAN read the job log.
print(out)

if len(out) > CAP:
    out = out[: CAP - 16].rstrip() + "\n...[truncated]"

escaped = out.replace("%", "%25").replace("\n", "%0A").replace("\r", "%0D")
sys.stderr.write("::error::%s\n" % escaped)
PY

  rm -rf "$dir"
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

# --- Build ----------------------------------------------------------------------
#
# Its own step rather than `up --build`, so the cold ~12-minute Rust build has a
# line of its own and a failure here is not reported as "the network did not come
# up healthy". See electrs/Dockerfile for why electrs is built and not pulled.
echo "--- Building images (a cold runner compiles electrs from source)"
compose build \
  || fail "Building the regtest images failed. On a cold runner this is the electrs Rust build; see android/regtest/electrs/Dockerfile."

# --- Start bitcoind, AND MINE, BEFORE THE OTHER TWO ARE STARTED AT ALL ----------
#
# The ordering below is load-bearing, and the first two runs of this network both
# died because it was not. It used to be one `compose up --wait` over all three
# services followed, forty lines later, by the mining. That can never return:
# NEITHER dependent will report healthy on a chain that is still sitting on the
# genesis block, and mining was on the far side of the wait.
#
# Checked in the pinned sources rather than inferred from the symptom:
#
#   electrs never binds its HTTP port. `Daemon::new` (src/rest.rs' caller, in
#   src/daemon.rs) loops on `getblockchaininfo` while `initialblockdownload` is
#   true and only then returns, so the `/blocks/tip/height` the compose
#   healthcheck curls is not answering-but-empty — nothing is listening.
#
#   LND never starts its RPC server. lnd.go blocks on `Wallet.IsSynced()` before
#   `SetServerActive`, and lnwallet/btcwallet's implementation returns false
#   while the best block header's timestamp is more than two hours old — so
#   `lncli getinfo`, which is that container's healthcheck, is refused.
#
# Bitcoin's genesis block is timestamped 2011-02-02, and on a fresh regtest chain
# it is the tip. So bitcoind reports `initialblockdownload: true` and the tip
# reads as fifteen years stale, and both dependents wait — correctly — for a
# chain nobody has mined. Both predicates are about the tip, and mining is the
# only thing that clears either.
#
# Hence: bitcoind alone, then coins, then the rest.
echo "--- Starting bitcoind"
compose up -d --wait --wait-timeout 300 bitcoind \
  || fail_with_state "bitcoind did not come up healthy."

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

# A TALL CHAIN IS NOT THE SAME AS A RECENT ONE.
#
# The height check above is about spendable coinbase. This one is about the two
# predicates in the header, which are both about the tip's *timestamp* — and this
# script is documented as idempotent, so the warm case is real: a network left up
# overnight has a chain 101 blocks tall whose tip is nine hours old. That passes
# the height check and fails LND's two-hour one exactly like a fresh chain does.
# One regtest block costs nothing and is the entire fix for that case.
tip_time=$(btc getblockheader "$(btc getbestblockhash)" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["time"])')
tip_age=$(( $(date +%s) - tip_time ))
if [ "$tip_age" -gt 3600 ]; then
  echo "--- Tip is ${tip_age}s old; mining one block so electrs and LND can start"
  btc generatetoaddress 1 "$mining_address" > /dev/null
fi

# Assert the dependents' precondition instead of hoping for it.
#
# If this is wrong, the next thing that happens is a ten-minute healthcheck
# timeout and an annotation full of a daemon patiently reporting that it is
# waiting — which is precisely how the first two runs of this network were spent.
# One RPC call says so now instead.
ibd=$(btc getblockchaininfo \
  | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["initialblockdownload"]).lower())')
[ "$ibd" = "false" ] \
  || fail "bitcoind still reports initialblockdownload=true at height $(btc getblockcount). electrs would never bind its HTTP port and LND would never start its RPC server, so starting them would only spend the healthcheck timeout."

# --- Now the two that needed a chain --------------------------------------------
echo "--- Starting electrs and LND"
compose up -d --wait --wait-timeout 600 electrs lnd \
  || fail_with_state "electrs or LND did not come up healthy."

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
