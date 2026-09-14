#!/usr/bin/env bash
#
# Send one FCM HTTP v1 message to a device, for K2's delivery leg (BIT-135).
#
#     android/scripts/send-fcm-wake.sh --key-file key.json --token-file tok.txt
#     android/scripts/send-fcm-wake.sh ... --wake-reason ci-delivery
#     android/scripts/send-fcm-wake.sh ... --no-wake-key        # the negative control
#     android/scripts/send-fcm-wake.sh --print-payload          # no network, no key
#
# Exit codes: 0 FCM accepted the message · 1 it refused it, or the inputs are
#             wrong · 2 could not find out (no network, missing openssl).
#
# WHY THIS IS ITS OWN SCRIPT
#
# Two properties of this message are load-bearing and NEITHER IS ASSERTABLE FROM
# ANDROID — `BittrMessagingService` and `BackgroundWake` both say so in their
# class comments, and both point here:
#
#   1. `android.priority: "high"`. A normal-priority data message is deferred by
#      Doze, and — the part that matters more — does not put the app on the
#      temporary allowlist that permits a foreground-service start from the
#      background on Android 12+. The promotion would be refused and the node
#      would start unprotected.
#   2. `data` and NO `notification` block. A message carrying `notification` is
#      handled by the system tray when the app is backgrounded and
#      `onMessageReceived` IS NEVER CALLED AT ALL. A test driven by such a message
#      would report "the wake did not fire" about a message the app never saw.
#
# A property that only exists inside a JSON literal in a `run:` block is a
# property nothing can check. Here it is built by `payload()`, asserted by
# `assert_payload_shape` on every send, and negative-controlled by
# test-send-fcm-wake.sh in the build job — which is the only place either claim
# is ever falsifiable.
#
# WHY IT SIGNS WITH openssl RATHER THAN A LIBRARY
#
# Same rule as the rest of android/scripts: no pip step in front of a check.
# FCM v1 needs an OAuth2 bearer token minted from an RS256-signed JWT, which
# python3's stdlib cannot sign. verify-fcm-service-account.sh already does exactly
# this with `openssl dgst -sign`, and the two agree deliberately: if the signing
# here worked and there did not, the human check would stop matching the machine
# one.
#
# THE CREDENTIAL
#
# --key-file takes a path, never the JSON on the command line: argv is world
# readable through /proc on the runner. The caller is responsible for having run
# `verify-fcm-service-account.sh --expect regtest` over it; this script re-asserts
# the project name anyway, because it is one `case` statement and the failure it
# prevents is a regtest CI run reaching real devices.
set -euo pipefail

# The only project this script will send through. Not a parameter.
#
# BIT-123's standing note — never mainnet keys, never production node access,
# never real funds — covers pushing through the production sender: bittr-prod's
# tokens are real user devices. There is no flag to override this and there
# should not be one; a caller who needs to send through prod needs a different
# script and a different conversation.
REGTEST_PROJECT="bittr-regtest"

SCOPE="https://www.googleapis.com/auth/firebase.messaging"
TOKEN_URI="https://oauth2.googleapis.com/token"

# The data key BackgroundWake looks for. Must equal BackgroundWake.WAKE_KEY;
# test-send-fcm-wake.sh reads the Kotlin and fails if the two drift.
WAKE_KEY="bittr_wake"

usage() {
	cat >&2 <<'USAGE'
usage: send-fcm-wake.sh --key-file <service-account.json> --token-file <file>
                        [--wake-reason R] [--no-wake-key] [--validate-only]
       send-fcm-wake.sh --print-payload [--wake-reason R] [--no-wake-key]

  --key-file F      service account JSON for bittr-regtest (a PATH, not the JSON)
  --token-file F    file whose LAST line is the registration token to address
  --wake-reason R   the value of the bittr_wake data field (default: ci-delivery)
  --no-wake-key     send a data message with NO bittr_wake field — the negative
                    control. Everything else about the message is identical.
  --validate-only   ask FCM to validate the message without delivering it
  --print-payload   print the message body and exit; no key and no network
USAGE
	exit 2
}

KEY_FILE=""
TOKEN_FILE=""
WAKE_REASON="ci-delivery"
SEND_WAKE_KEY=1
VALIDATE_ONLY=0
PRINT_PAYLOAD=0

while [ $# -gt 0 ]; do
	case "$1" in
	--key-file)
		[ $# -ge 2 ] || usage
		KEY_FILE="$2"
		shift 2
		;;
	--token-file)
		[ $# -ge 2 ] || usage
		TOKEN_FILE="$2"
		shift 2
		;;
	--wake-reason)
		[ $# -ge 2 ] || usage
		WAKE_REASON="$2"
		shift 2
		;;
	--no-wake-key)
		SEND_WAKE_KEY=0
		shift
		;;
	--validate-only)
		VALIDATE_ONLY=1
		shift
		;;
	--print-payload)
		PRINT_PAYLOAD=1
		shift
		;;
	-h | --help) usage ;;
	*) usage ;;
	esac
done

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# ---------------------------------------------------------------------------
# The message, built in one place
# ---------------------------------------------------------------------------
#
# `$1` is the target token, or the literal `PRINT` under --print-payload so the
# shape can be inspected without a device in existence.
#
# `"ttl":"0s"` is deliberate and is the other half of "high priority": it tells
# FCM not to store and retry this message. A delivery that arrives four minutes
# later, after the host phase has already declared a timeout and torn the
# emulator down, is not a pass arriving late — it is a result nobody reads, and
# on a retried message it could arrive during a LATER run and be attributed to
# it. One shot, now, or a legible failure.
#
# `data` values are strings. FCM v1 rejects a non-string value outright, which is
# worth knowing because the obvious future edit — adding an amount or a count —
# fails with a 400 that names the field.
payload() {
	target=$1
	if [ "$SEND_WAKE_KEY" -eq 1 ]; then
		data="{\"$WAKE_KEY\":\"$WAKE_REASON\",\"sent_by\":\"send-fcm-wake.sh\"}"
	else
		# The negative control. Same priority, same shape, same absence of a
		# notification block — the ONLY difference is the missing wake key, which
		# is what makes "the app woke and declined" distinguishable from "the app
		# never woke". A control that also changed the priority would be testing
		# two things and proving neither.
		data="{\"title\":\"Payment received\",\"body\":\"1,000 sats\",\"sent_by\":\"send-fcm-wake.sh\"}"
	fi

	printf '{"validate_only":%s,"message":{"token":"%s","android":{"priority":"high","ttl":"0s"},"data":%s}}' \
		"$([ "$VALIDATE_ONLY" -eq 1 ] && echo true || echo false)" \
		"$target" \
		"$data"
}

# ---------------------------------------------------------------------------
# The two claims, re-asserted on every send
# ---------------------------------------------------------------------------
#
# Not belt-and-braces. `payload()` is one printf and the two properties it
# encodes are invisible in the job log — a message that silently lost its
# priority sends fine, is accepted fine, and produces a run whose only symptom is
# that the foreground promotion was refused, which is indistinguishable from the
# platform refusing it for a real reason. This turns that into a red before the
# message leaves the host.
assert_payload_shape() {
	body=$1

	case "$body" in
	*'"priority":"high"'*) ;;
	*) fail "the message is not high priority. A normal-priority data message does not grant the temporary allowlist that lets a backgrounded app start a foreground service on Android 12+, so the promotion would be refused and the node would start unprotected — and Doze would defer the message besides. See BackgroundWake's class comment." ;;
	esac

	case "$body" in
	*'"notification"'*) fail "the message carries a notification block. The system tray handles those when the app is backgrounded and onMessageReceived is NEVER CALLED, so this send would prove nothing and would read as a wake failure. Data-only, always." ;;
	*) ;;
	esac

	case "$body" in
	*'"data":{'*) ;;
	*) fail "the message carries no data payload. BackgroundWake reads RemoteMessage.getData(); a message with nothing in it cannot be a wake." ;;
	esac

	if [ "$SEND_WAKE_KEY" -eq 1 ]; then
		case "$body" in
		*"\"$WAKE_KEY\":"*) ;;
		*) fail "the message carries no $WAKE_KEY field, so BackgroundWake would answer NotAWake. If this was meant to be the negative control, pass --no-wake-key so the host phase expects that outcome." ;;
		esac
	else
		case "$body" in
		*"\"$WAKE_KEY\":"*) fail "--no-wake-key was passed and the payload still carries $WAKE_KEY. The negative control would send a real wake and pass by starting the node it is supposed to prove is NOT started." ;;
		*) ;;
		esac
	fi
}

if [ "$PRINT_PAYLOAD" -eq 1 ]; then
	body=$(payload "PRINT")
	assert_payload_shape "$body"
	printf '%s\n' "$body"
	exit 0
fi

[ -n "$KEY_FILE" ] || usage
[ -n "$TOKEN_FILE" ] || usage

command -v openssl >/dev/null 2>&1 || {
	echo "error: openssl is required to sign the token request" >&2
	exit 2
}
command -v python3 >/dev/null 2>&1 || {
	echo "error: python3 is required to read the key file" >&2
	exit 2
}

[ -f "$KEY_FILE" ] || fail "no such key file: $KEY_FILE"
[ -f "$TOKEN_FILE" ] || fail "no such token file: $TOKEN_FILE"

# The LAST non-empty line. The hand-off written by FcmDeliveryTest is a marker
# line followed by the token, and reading the first line would address a device
# called "FCM_DELIVERY_HANDOFF ready".
DEVICE_TOKEN=$(grep -v '^[[:space:]]*$' "$TOKEN_FILE" | tail -1 | tr -d '\r\n')

[ -n "$DEVICE_TOKEN" ] || fail "$TOKEN_FILE has no token in it. FcmDeliveryTest#aWalletAndARegistrationTokenAreLeftForTheHostToWake is what writes it; if that did not run, this send has nothing to address."

# A registration token is a long opaque string. This is not validation of the
# token — only Google can do that — it is a guard against addressing the marker
# line, a shell error message, or an empty string, each of which would produce a
# clean-looking 400 that reads as a delivery failure.
case "$DEVICE_TOKEN" in
*[[:space:]]*) fail "the token read from $TOKEN_FILE contains whitespace, so it is not a registration token — most likely a log line or an error message landed in the hand-off file." ;;
esac
if [ "${#DEVICE_TOKEN}" -lt 100 ]; then
	fail "the token read from $TOKEN_FILE is ${#DEVICE_TOKEN} characters, which is far short of an FCM registration token. Not sending: an invalid target returns the same INVALID_ARGUMENT a real delivery failure would."
fi

# ---------------------------------------------------------------------------
# The credential
# ---------------------------------------------------------------------------

WORK_DIR="$(mktemp -d)"
chmod 700 "$WORK_DIR"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

FIELDS="$(
	python3 - "$KEY_FILE" <<'PY' 2>/dev/null || true
import json, sys

try:
    with open(sys.argv[1]) as handle:
        key = json.load(handle)
except (OSError, ValueError) as exc:
    print("ERR not valid JSON: %s" % exc)
    raise SystemExit(0)

if not isinstance(key, dict) or key.get("type") != "service_account":
    print("ERR not a service account key (no \"type\": \"service_account\")")
    raise SystemExit(0)

missing = [f for f in ("project_id", "client_email", "private_key") if not key.get(f)]
if missing:
    print("ERR missing or empty: %s" % ", ".join(missing))
    raise SystemExit(0)

print("OK")
print(key["project_id"])
print(key["client_email"])
PY
)"

[ -n "$FIELDS" ] || fail "could not read $KEY_FILE"
[ "${FIELDS%%$'\n'*}" = "OK" ] || fail "${FIELDS#ERR }"

PROJECT_ID="$(printf '%s\n' "$FIELDS" | sed -n '2p')"
CLIENT_EMAIL="$(printf '%s\n' "$FIELDS" | sed -n '3p')"

# The one check this script will not let a caller skip. See REGTEST_PROJECT.
if [ "$PROJECT_ID" != "$REGTEST_PROJECT" ]; then
	fail "this key is for '$PROJECT_ID', not $REGTEST_PROJECT. This script only sends through the regtest project — bittr-prod's registration tokens are real user devices, and BIT-123's standing note forbids reaching them from CI. Run android/scripts/verify-fcm-service-account.sh --expect regtest over the key that was provisioned; the two near-identical key files have been swapped once already."
fi

echo "Sender: $CLIENT_EMAIL ($PROJECT_ID)"
echo "Target: a registration token from the hand-off file (${#DEVICE_TOKEN} chars; not printed)"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

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
	fail "Google refused the key (HTTP $TOKEN_HTTP) — $DETAIL. invalid_grant here usually means the key was deleted in the console. Run verify-fcm-service-account.sh over it."
fi

# ---------------------------------------------------------------------------
# The send
# ---------------------------------------------------------------------------

BODY="$(payload "$DEVICE_TOKEN")"
assert_payload_shape "$BODY"

# The body is written to a file and handed to curl with @, never with -d on the
# command line: argv carries the registration token and /proc is world readable
# on the runner. What is ECHOED is the body with the token replaced, so the
# run's log shows the two load-bearing properties without showing the address.
printf '%s' "$BODY" >"$WORK_DIR/body.json"
printf 'Message: %s\n' "$(printf '%s' "$BODY" | sed "s/$DEVICE_TOKEN/<token withheld>/")"

SEND_URL="https://fcm.googleapis.com/v1/projects/$PROJECT_ID/messages:send"
SEND_HTTP="$(curl -sS -o "$WORK_DIR/send.json" -w '%{http_code}' \
	--max-time 30 -X POST "$SEND_URL" \
	-H "Authorization: Bearer $ACCESS_TOKEN" \
	-H "Content-Type: application/json" \
	--data-binary "@$WORK_DIR/body.json" 2>"$WORK_DIR/curl.err")" || {
	echo "UNKNOWN: could not reach $SEND_URL: $(tr -d '\n' <"$WORK_DIR/curl.err")" >&2
	exit 2
}

if [ "$SEND_HTTP" = "200" ]; then
	NAME="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("name", ""))
except ValueError:
    print("")' "$WORK_DIR/send.json")"
	# What a 200 does and does NOT mean, said here so the host phase's timeout is
	# read correctly. FCM has ACCEPTED the message for delivery to that token. It
	# has not delivered it, and with ttl 0s it will not retry. So a 200 followed
	# by no wake is a real finding about delivery; a non-200 is a finding about
	# this script's inputs.
	echo "ACCEPTED: $NAME"
	echo "FCM accepted the message for delivery. That is acceptance, not delivery:"
	echo "with ttl=0s there is no store-and-retry, so if the device does not wake"
	echo "within the host phase's window, the message was genuinely not delivered."
	exit 0
fi

DETAIL="$(python3 -c 'import json,sys
try:
    error = json.load(open(sys.argv[1])).get("error", {})
    print("%s / %s: %s" % (error.get("status", "?"), error.get("code", "?"), error.get("message", "")))
except ValueError:
    print(open(sys.argv[1]).read()[:300])' "$WORK_DIR/send.json")"

case "$SEND_HTTP" in
401 | 403)
	fail "FCM rejected the CREDENTIAL (HTTP $SEND_HTTP) — $DETAIL
      This is about the key, not the device. Check Project settings -> Cloud Messaging:
      'Firebase Cloud Messaging API (V1)' must read Enabled for $PROJECT_ID."
	;;
404)
	fail "FCM says the target is UNREGISTERED (HTTP $SEND_HTTP) — $DETAIL
      The token in the hand-off file is not a live registration for this project. Either
      the app was uninstalled or its data cleared between the hand-off and this send, or
      the APK is registered against a different Firebase project from the key. This is a
      finding about the harness, not about delivery."
	;;
*)
	fail "FCM refused the message (HTTP $SEND_HTTP) — $DETAIL"
	;;
esac
