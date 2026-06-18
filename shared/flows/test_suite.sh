#!/usr/bin/env bash
#
# Runs the full Maestro suite (suite.yaml) against the regtest app on the
# currently booted simulator/emulator.
#
# The suite needs two local helper servers that Maestro can't start itself
# (its JS sandbox can't shell out): push_server.js (incoming-payment pushes,
# used by buy_incoming / buy_more) and clipboard_server.js (the in-app Paste
# button, used by send_lightning). This script starts whichever isn't already
# running, runs the suite, then stops the ones it started.
#
# Prerequisites it does NOT handle: the app must be built and installed, and a
# simulator/emulator booted. See shared/flows/README.md.
#
# Usage:
#   shared/flows/test_suite.sh                       # uses the booted device
#   shared/flows/test_suite.sh --device "iPhone 15"  # extra args pass to maestro
#
set -euo pipefail

FLOWS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$FLOWS_DIR/scripts"

# restore_wallet.yaml's fixed test mnemonic — forgot_pin.yaml reads it via --env.
MNEMONIC="attack urge across cupboard year armor list vital outer leader anxiety endorse"

# PIDs of servers WE start (so cleanup only kills ours, not a pre-existing one).
STARTED_PIDS=()

cleanup() {
    for pid in "${STARTED_PIDS[@]:-}"; do
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT

# start_server <port> <script> <label>
start_server() {
    local port="$1" script="$2" label="$3"
    if nc -z 127.0.0.1 "$port" 2>/dev/null; then
        echo "✓ $label already running on :$port — leaving it alone"
        return
    fi
    echo "→ starting $label on :$port"
    node "$SCRIPTS/$script" &
    STARTED_PIDS+=("$!")
}

start_server 8888 push_server.js      "push helper"
start_server 8889 clipboard_server.js "clipboard helper"

# Give freshly-started servers a moment to bind before the flows hit them.
sleep 1

echo "→ running suite.yaml"
maestro test "$@" --env MNEMONIC="$MNEMONIC" "$FLOWS_DIR/suite.yaml"
