#!/usr/bin/env bash
#
# Runs the full Maestro suite against the regtest app on the currently booted
# simulator/emulator — with checkpointing, so a failed run can be RESUMED
# instead of starting from scratch.
#
# suite.yaml stays the canonical, ordered list of flows; this script parses its
# `- runFlow:` lines and runs each flow as its own `maestro test`, recording
# every pass in a progress file (.suite_progress, gitignored). On the next run,
# flows already marked as passed are skipped and execution resumes at the first
# unpassed flow. The progress file is deleted after a fully green run.
#
# IMPORTANT — resuming assumes the simulator still holds the wallet state the
# passed flows left behind (the suite is a chain with deliberate balance
# handoffs). That holds for the common case (a flow failed, you fixed the cause,
# you rerun). It does NOT hold if you erased the simulator, reinstalled the app
# with clearState, or the failure itself corrupted wallet state — start fresh
# then.
#
# The suite needs two local helper servers that Maestro can't start itself
# (its JS sandbox can't shell out): push_server.js (incoming-payment pushes)
# and clipboard_server.js (the in-app Paste button). This script starts
# whichever isn't already running, and stops the ones it started.
#
# Prerequisites it does NOT handle: the app must be built and installed, and a
# simulator/emulator booted. See shared/flows/README.md.
#
# Usage:
#   shared/flows/test_suite.sh              # run, resuming from the last failure
#   shared/flows/test_suite.sh --fresh      # ignore + clear progress, start over
#   shared/flows/test_suite.sh --status     # show progress and exit
#   (extra args pass through to maestro, e.g. --device "iPhone 15")
#
set -euo pipefail

FLOWS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$FLOWS_DIR/scripts"
SUITE="$FLOWS_DIR/suite.yaml"
PROGRESS="$FLOWS_DIR/.suite_progress"

# restore_wallet.yaml's fixed test mnemonic — forgot_pin.yaml reads it via --env.
MNEMONIC="attack urge across cupboard year armor list vital outer leader anxiety endorse"

# --- Parse args ---------------------------------------------------------------
MAESTRO_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --fresh)
            rm -f "$PROGRESS"
            echo "→ progress cleared; starting from scratch"
            ;;
        --status)
            if [[ -f "$PROGRESS" ]]; then
                echo "Passed so far ($(grep -c . "$PROGRESS")):"
                sed 's/^/  ✓ /' "$PROGRESS"
            else
                echo "No progress recorded (last run was green or never ran)."
            fi
            exit 0
            ;;
        *)
            MAESTRO_ARGS+=("$arg")
            ;;
    esac
done

# --- Flow list: parsed from suite.yaml so it stays the single source of truth --
FLOWS=()
while IFS= read -r line; do
    flow="${line#*runFlow:}"          # strip the key
    flow="${flow%%#*}"                # strip trailing comment
    flow="$(echo "$flow" | xargs)"    # trim whitespace
    [[ -n "$flow" ]] && FLOWS+=("$flow")
done < <(grep -E '^\s*-\s*runFlow:' "$SUITE")

if [[ ${#FLOWS[@]} -eq 0 ]]; then
    echo "Could not parse any flows from $SUITE" >&2
    exit 1
fi

# --- Helper servers -----------------------------------------------------------
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

# --- Run, resuming past recorded passes ----------------------------------------
touch "$PROGRESS"
skipped=0
for flow in "${FLOWS[@]}"; do
    if grep -qxF "$flow" "$PROGRESS"; then
        skipped=$((skipped + 1))
        continue
    fi
    if [[ $skipped -gt 0 ]]; then
        echo "→ resumed: skipped $skipped flow(s) that already passed (see --status)"
        skipped=0
    fi

    echo ""
    echo "════ running $flow"
    if maestro test ${MAESTRO_ARGS[@]+"${MAESTRO_ARGS[@]}"} --env MNEMONIC="$MNEMONIC" "$FLOWS_DIR/$flow"; then
        echo "$flow" >> "$PROGRESS"
    else
        echo ""
        echo "✗ FAILED: $flow"
        echo "  Passed flows are checkpointed in $PROGRESS."
        echo "  Fix the cause and rerun to resume from this flow,"
        echo "  or rerun with --fresh to start over (e.g. if wallet state is corrupted)."
        exit 1
    fi
done

if [[ $skipped -gt 0 ]]; then
    echo "→ all remaining $skipped flow(s) had already passed"
fi

rm -f "$PROGRESS"
echo ""
echo "✓ suite green — progress cleared"
