#!/usr/bin/env bash
#
# Check an FCM HTTP v1 service account key before it goes into an env var.
#
#     android/scripts/verify-fcm-service-account.sh ~/Downloads/bittr-regtest-....json
#     android/scripts/verify-fcm-service-account.sh key.json --expect regtest
#     android/scripts/verify-fcm-service-account.sh key.json --print-env
#
# Exit codes: 0 the key is valid and belongs to a known Bittr project ·
#             1 the key is wrong, or is the wrong project's key ·
#             2 could not find out (no network, missing openssl).
#
# WHY THIS EXISTS
#
# BIT-39 provisioned two Firebase projects, bittr-regtest and bittr-prod, precisely
# so that a regtest credential cannot reach a production device. That guarantee is
# only as good as which of two near-identical JSON files someone pastes into which
# environment's settings, and nothing about the files makes the difference visible:
# both are named `<project>-firebase-adminsdk-<hash>.json`, both are ~2.3KB of the
# same fourteen keys, and the project name appears once, in the middle.
#
# This already went wrong once on this issue. The two `google-services.json` files
# the board uploaded arrived with the names reversed — `google-services.json` was
# the regtest config and `google-services(1).json` was prod. That was caught because
# those files are committed and testable (`GoogleServicesConfigTest`). A service
# account key is a secret, so it is never committed and never testable that way: a
# swap would surface as production pushes silently failing, or — worse, and the
# reason two projects were chosen — as a regtest run reaching real devices.
#
# So the check has to happen at the moment of handling, on a file sitting in a
# Downloads folder. That is what this is: the last point where a human still has
# both files in front of them and can still tell them apart.
#
# WHY IT TALKS TO GOOGLE
#
# Reading `project_id` out of the JSON would catch the swap, and steps 1-3 below do
# exactly that. But it would not catch a key that was revoked, or one downloaded
# from a project whose Cloud Messaging API is off — both of which look like a
# perfectly well-formed file and fail only when the first real push is attempted,
# by which point the person who pasted it has moved on. Step 4 mints a real OAuth2
# access token and step 5 puts it through `messages:send`, so a pass here means the
# credential actually sends, not merely that it parses.
#
# Nothing is sent to a device: step 5 sets `validate_only: true` and aims at a
# deliberately invalid token. FCM rejecting the *target* is the success signal —
# it can only have got that far by accepting the *credential*.

set -euo pipefail

# The projects BIT-39 provisioned, keyed by the environment name this script
# accepts for --expect. These are the authorities for what a valid key looks like;
# they are cross-checked against the committed client configs in step 3 rather than
# trusted on their own.
REGTEST_PROJECT="bittr-regtest"
PROD_PROJECT="bittr-prod"

SCOPE="https://www.googleapis.com/auth/firebase.messaging"
TOKEN_URI="https://oauth2.googleapis.com/token"

usage() {
	cat >&2 <<'USAGE'
usage: verify-fcm-service-account.sh <service-account.json> [--expect regtest|prod] [--print-env] [--offline]

  --expect ENV   fail unless the key belongs to that environment's project
  --print-env    on success, print the env var lines to paste (contains the secret)
  --offline      skip steps 4 and 5; check the file's shape and project only
USAGE
	exit 2
}

KEY_FILE=""
EXPECT=""
PRINT_ENV=0
OFFLINE=0

while [ $# -gt 0 ]; do
	case "$1" in
	--expect)
		[ $# -ge 2 ] || usage
		EXPECT="$2"
		shift 2
		;;
	--print-env)
		PRINT_ENV=1
		shift
		;;
	--offline)
		OFFLINE=1
		shift
		;;
	-h | --help) usage ;;
	-*) usage ;;
	*)
		[ -z "$KEY_FILE" ] || usage
		KEY_FILE="$1"
		shift
		;;
	esac
done

[ -n "$KEY_FILE" ] || usage

case "$EXPECT" in
"" | regtest | prod) ;;
*)
	echo "error: --expect takes 'regtest' or 'prod', not '$EXPECT'" >&2
	exit 2
	;;
esac

if [ ! -f "$KEY_FILE" ]; then
	echo "error: no such file: $KEY_FILE" >&2
	exit 2
fi

command -v openssl >/dev/null 2>&1 || {
	echo "error: openssl is required to sign the token request" >&2
	exit 2
}
command -v python3 >/dev/null 2>&1 || {
	echo "error: python3 is required to read the key file" >&2
	exit 2
}

# The private key is written to disk to be handed to `openssl dgst -sign`, which
# takes a file and not a pipe. Keep it in a 0700 directory for the few lines it
# lives, and remove it on every exit path including failure.
WORK_DIR="$(mktemp -d)"
chmod 700 "$WORK_DIR"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# Called from both exit paths, --offline and full. Only ever after the project
# checks have passed, so what it prints can only be the environment it says.
print_env_block() {
	[ "$PRINT_ENV" -eq 1 ] || return 0
	ENCODED="$(openssl base64 -A <"$KEY_FILE")"
	echo
	echo "--- paste into the $ENV_NAME environment's settings (this is the secret) ---"
	echo "FCM_PROJECT_ID=$PROJECT_ID"
	echo "FCM_SERVICE_ACCOUNT_JSON_B64=$ENCODED"
	echo "--- end ---"
	echo
	echo "Paste into the $ENV_NAME environment only. Put neither line in the repo." >&2
}

# base64url, no padding — what JWT requires and what plain base64 does not give.
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

echo "Checking $(basename "$KEY_FILE")"

# ---------------------------------------------------------------------------
# 1. Is it a service account key at all
# ---------------------------------------------------------------------------

FIELDS="$(
	python3 - "$KEY_FILE" <<'PY' 2>/dev/null || true
import json, sys

try:
    with open(sys.argv[1]) as handle:
        key = json.load(handle)
except (OSError, ValueError) as exc:
    print("ERR not valid JSON: %s" % exc)
    raise SystemExit(0)

if not isinstance(key, dict):
    print("ERR the file is JSON but not an object")
    raise SystemExit(0)

# A google-services.json is the file most likely to be confused with this one:
# it is JSON, it is Firebase, and it names the same project. It has no
# credential in it at all, so say so specifically rather than listing fields.
if "project_info" in key and "client" in key:
    print("ERR this is a google-services.json (client config), not a service account key")
    raise SystemExit(0)

if key.get("type") != "service_account":
    print("ERR expected \"type\": \"service_account\", found %r" % key.get("type"))
    raise SystemExit(0)

missing = [f for f in ("project_id", "client_email", "private_key") if not key.get(f)]
if missing:
    print("ERR missing or empty: %s" % ", ".join(missing))
    raise SystemExit(0)

if "BEGIN PRIVATE KEY" not in key["private_key"]:
    print("ERR private_key does not contain a PEM block")
    raise SystemExit(0)

print("OK")
print(key["project_id"])
print(key["client_email"])
PY
)"

[ -n "$FIELDS" ] || fail "could not read $KEY_FILE"

if [ "${FIELDS%%$'\n'*}" != "OK" ]; then
	fail "${FIELDS#ERR }"
fi

PROJECT_ID="$(printf '%s\n' "$FIELDS" | sed -n '2p')"
CLIENT_EMAIL="$(printf '%s\n' "$FIELDS" | sed -n '3p')"

echo "  [1/5] service account key, well formed"
echo "        project ....... $PROJECT_ID"
echo "        account ....... $CLIENT_EMAIL"

# ---------------------------------------------------------------------------
# 2. Is it one of ours, and the one that was asked for
# ---------------------------------------------------------------------------

case "$PROJECT_ID" in
"$REGTEST_PROJECT") ENV_NAME="regtest" ;;
"$PROD_PROJECT") ENV_NAME="prod" ;;
*) fail "project '$PROJECT_ID' is neither $REGTEST_PROJECT nor $PROD_PROJECT — this key is not from a Bittr Firebase project" ;;
esac

if [ -n "$EXPECT" ] && [ "$ENV_NAME" != "$EXPECT" ]; then
	fail "expected the $EXPECT key, but this is the $ENV_NAME key ($PROJECT_ID). This is the swap the two-project split exists to prevent — do not paste it."
fi

echo "  [2/5] belongs to the $ENV_NAME environment"

# ---------------------------------------------------------------------------
# 3. Does it agree with the client config committed for that build type
# ---------------------------------------------------------------------------
#
# The constants above could drift from the repo. The committed google-services.json
# files cannot: they are what the app is actually built with, and a test already
# pins each one to its build type. Reconcile against those.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
case "$ENV_NAME" in
regtest) CLIENT_CONFIG="$REPO_ROOT/android/app/src/debug/google-services.json" ;;
prod) CLIENT_CONFIG="$REPO_ROOT/android/app/src/release/google-services.json" ;;
esac

if [ -f "$CLIENT_CONFIG" ]; then
	CONFIG_PROJECT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["project_info"]["project_id"])' "$CLIENT_CONFIG")"
	[ "$CONFIG_PROJECT" = "$PROJECT_ID" ] ||
		fail "the $ENV_NAME client config ($CLIENT_CONFIG) is for '$CONFIG_PROJECT', but this key is for '$PROJECT_ID'. One of the two is from the wrong project."
	echo "  [3/5] agrees with $(basename "$(dirname "$CLIENT_CONFIG")")/google-services.json"
else
	echo "  [3/5] skipped — no client config at $CLIENT_CONFIG"
fi

if [ "$OFFLINE" -eq 1 ]; then
	echo
	echo "OFFLINE: the file is the right shape and the right project. Not checked:"
	echo "  whether the key is still live, and whether the project can send."
	print_env_block
	exit 0
fi

# ---------------------------------------------------------------------------
# 4. Will Google mint a messaging token for it
# ---------------------------------------------------------------------------

python3 -c 'import json,sys; sys.stdout.write(json.load(open(sys.argv[1]))["private_key"])' \
	"$KEY_FILE" >"$WORK_DIR/key.pem"

NOW="$(date +%s)"
JWT_HEADER="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
JWT_CLAIM="$(printf '{"iss":"%s","scope":"%s","aud":"%s","iat":%s,"exp":%s}' \
	"$CLIENT_EMAIL" "$SCOPE" "$TOKEN_URI" "$NOW" "$((NOW + 3600))" | b64url)"

if ! JWT_SIG="$(printf '%s.%s' "$JWT_HEADER" "$JWT_CLAIM" |
	openssl dgst -sha256 -sign "$WORK_DIR/key.pem" 2>"$WORK_DIR/openssl.err" | b64url)"; then
	fail "could not sign with private_key: $(tr -d '\n' <"$WORK_DIR/openssl.err")"
fi

TOKEN_HTTP="$(curl -sS -o "$WORK_DIR/token.json" -w '%{http_code}' \
	--max-time 30 -X POST "$TOKEN_URI" \
	--data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
	--data-urlencode "assertion=$JWT_HEADER.$JWT_CLAIM.$JWT_SIG" 2>"$WORK_DIR/curl.err")" || {
	echo "UNKNOWN: could not reach $TOKEN_URI: $(tr -d '\n' <"$WORK_DIR/curl.err")" >&2
	echo "Re-run with --offline to check the file without network." >&2
	exit 2
}

ACCESS_TOKEN="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("access_token", ""))
except ValueError:
    print("")' "$WORK_DIR/token.json")"

if [ "$TOKEN_HTTP" != "200" ] || [ -z "$ACCESS_TOKEN" ]; then
	DETAIL="$(python3 -c 'import json,sys
try:
    body = json.load(open(sys.argv[1]))
    print("%s: %s" % (body.get("error", "?"), body.get("error_description", "")))
except ValueError:
    print(open(sys.argv[1]).read()[:200])' "$WORK_DIR/token.json")"
	# invalid_grant here almost always means the key was deleted in the console
	# rather than anything wrong with this script's signing.
	fail "Google refused the key (HTTP $TOKEN_HTTP) — $DETAIL"
fi

echo "  [4/5] Google issued a messaging access token"

# ---------------------------------------------------------------------------
# 5. Will FCM accept it as a sender for this project
# ---------------------------------------------------------------------------
#
# validate_only, against a target that cannot exist. A 400/404 about the token is
# the pass: FCM only reaches the point of judging the target after it has accepted
# the credential. A 401/403 is the fail, and is what a key with the wrong role,
# or a project with the v1 API switched off, returns.

SEND_URL="https://fcm.googleapis.com/v1/projects/$PROJECT_ID/messages:send"
SEND_HTTP="$(curl -sS -o "$WORK_DIR/send.json" -w '%{http_code}' \
	--max-time 30 -X POST "$SEND_URL" \
	-H "Authorization: Bearer $ACCESS_TOKEN" \
	-H "Content-Type: application/json" \
	-d '{"validate_only":true,"message":{"token":"not-a-real-token","data":{"probe":"bit39"}}}' \
	2>"$WORK_DIR/curl.err")" || {
	echo "UNKNOWN: could not reach $SEND_URL: $(tr -d '\n' <"$WORK_DIR/curl.err")" >&2
	exit 2
}

case "$SEND_HTTP" in
401 | 403)
	DETAIL="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("error", {}).get("message", ""))
except ValueError:
    print(open(sys.argv[1]).read()[:200])' "$WORK_DIR/send.json")"
	fail "FCM rejected the credential (HTTP $SEND_HTTP) — $DETAIL
      Check Project settings -> Cloud Messaging: 'Firebase Cloud Messaging API (V1)'
      must read Enabled for $PROJECT_ID."
	;;
*)
	echo "  [5/5] FCM accepted it as a sender for $PROJECT_ID (HTTP $SEND_HTTP on a deliberately invalid target)"
	;;
esac

echo
echo "PASS — this is the $ENV_NAME key, it is live, and it can send."
echo "Send endpoint: $SEND_URL"

print_env_block
