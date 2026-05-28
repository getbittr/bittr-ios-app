#!/usr/bin/env bash
# Wrapper that reads the bittr-regtest wallet's cached 12-word mnemonic from
# the booted simulator's UserDefaults and invokes the forgot_pin Maestro flow
# with it passed in as the MNEMONIC env var.
#
# Why this exists: forgot_pin.yaml has to type the user's mnemonic to verify
# it on the RestoreVC screen, but Maestro's runScript runtime has no shell
# or filesystem access to read it itself. Fetching it on the host side and
# passing it via --env keeps the flow file state-preserving like the other
# feature tests.
#
# Run from the repo root:
#
#   ./shared/flows/scripts/run_forgot_pin.sh
#
# Prereqs: a booted iOS simulator with the bittr-regtest app installed and a
# wallet already onboarded (the usual fresh_install + buy_incoming sequence).
# DEVELOPER_DIR is set so xcrun can find simctl on macs where xcode-select
# points at CommandLineTools.

set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

BUNDLE_ID="com.bittr.bittr-regtest"
FLOW="shared/flows/features/forgot_pin.yaml"

DEVICE_ID="$(xcrun simctl list devices booted -j \
    | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((dev["udid"] for runtime,devs in d["devices"].items() for dev in devs if dev.get("state")=="Booted"), ""))')"

if [[ -z "$DEVICE_ID" ]]; then
    echo "No booted simulator found. Boot one in Xcode (Window > Devices and Simulators), then re-run." >&2
    exit 1
fi

# Regtest cacheKeyPrefix is empty, so the mnemonic lives at key "mnemonic".
MNEMONIC="$(xcrun simctl spawn "$DEVICE_ID" defaults read "$BUNDLE_ID" mnemonic 2>/dev/null || true)"

if [[ -z "$MNEMONIC" ]]; then
    echo "No mnemonic in UserDefaults for $BUNDLE_ID on device $DEVICE_ID." >&2
    echo "Onboard the wallet first (maestro test shared/flows/onboarding/fresh_install.yaml)." >&2
    exit 1
fi

WORD_COUNT="$(echo "$MNEMONIC" | wc -w | tr -d ' ')"
if [[ "$WORD_COUNT" != "12" ]]; then
    echo "Expected 12 mnemonic words, got $WORD_COUNT. Cache may be corrupted." >&2
    exit 1
fi

exec maestro test --env "MNEMONIC=$MNEMONIC" "$FLOW"
