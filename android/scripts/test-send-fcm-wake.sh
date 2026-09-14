#!/usr/bin/env bash
#
# Tests for send-fcm-wake.sh — BIT-135.
#
#     bash android/scripts/test-send-fcm-wake.sh
#
# WHY THIS EXISTS, AND WHY IT IS NOT OPTIONAL
#
# send-fcm-wake.sh encodes the two properties of K2's wake message that NO TEST
# ON ANDROID CAN ASSERT. `BittrMessagingService` and `BackgroundWake` both say so
# in their class comments and both point at the sender; `FcmWakeTest` drives
# `deliver()` directly and therefore never sees a priority or a notification block
# at all. This file is the only place in the repository where either claim is
# falsifiable.
#
# Both failure modes are silent in the worst way:
#
#   * A message that lost `priority: high` sends fine and is accepted fine. The
#     only symptom is that the foreground promotion is refused — which is exactly
#     what the promotion legitimately does on a device that was not allowlisted,
#     so the run would read as a real platform finding rather than as a typo.
#   * A message that gained a `notification` block is delivered to the system tray
#     and `onMessageReceived` is never called. The run reads as "the wake did not
#     fire" about a message the app never saw.
#
# So the cases below are mostly negative controls: the script is DOCTORED and must
# refuse its own output. A test that only checked the happy payload would pass on
# a version of assert_payload_shape that did nothing.
#
# No network, no key, no device: --print-payload is the seam. Runs in the `build`
# job, seconds in.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

SENDER="android/scripts/send-fcm-wake.sh"
WAKE_SOURCE="android/core/wallet-ldk/src/main/kotlin/com/bittr/android/core/wallet/ldk/host/BackgroundWake.kt"

FAILURES=0

check() {
	what=$1
	ok=$2
	detail=${3:-}
	if [ "$ok" = "yes" ]; then
		echo "ok    $what"
	else
		echo "FAIL  $what${detail:+: $detail}"
		FAILURES=$((FAILURES + 1))
	fi
}

contains() {
	case "$1" in
	*"$2"*) echo yes ;;
	*) echo no ;;
	esac
}

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
# 1. The wake payload carries both load-bearing properties
# ---------------------------------------------------------------------------

WAKE_PAYLOAD=$(bash "$SENDER" --print-payload --wake-reason ci-delivery)

check "the wake message is high priority" \
	"$(contains "$WAKE_PAYLOAD" '"priority":"high"')" \
	"payload: $WAKE_PAYLOAD"

check "the wake message carries no notification block" \
	"$([ "$(contains "$WAKE_PAYLOAD" '"notification"')" = no ] && echo yes || echo no)" \
	"a notification block means onMessageReceived is never called"

check "the wake message carries a data payload" \
	"$(contains "$WAKE_PAYLOAD" '"data":{')"

check "the wake message carries the wake key and the reason" \
	"$(contains "$WAKE_PAYLOAD" '"bittr_wake":"ci-delivery"')"

check "the wake message does not ask FCM to store and retry" \
	"$(contains "$WAKE_PAYLOAD" '"ttl":"0s"')" \
	"a retried message can arrive during a LATER run and be attributed to it"

# ---------------------------------------------------------------------------
# 2. The negative control differs in exactly one thing
# ---------------------------------------------------------------------------
#
# The point of --no-wake-key is to tell "the app woke and declined" apart from
# "the app never woke". If it also dropped the priority, a device that failed to
# wake for it would be evidence about priority rather than about the wake key,
# and the control would prove nothing while looking like it did.

CONTROL_PAYLOAD=$(bash "$SENDER" --print-payload --no-wake-key)

check "the negative control carries no wake key" \
	"$([ "$(contains "$CONTROL_PAYLOAD" 'bittr_wake')" = no ] && echo yes || echo no)" \
	"payload: $CONTROL_PAYLOAD"

check "the negative control is STILL high priority" \
	"$(contains "$CONTROL_PAYLOAD" '"priority":"high"')" \
	"a control that also changed the priority would be testing two things at once"

check "the negative control is STILL data-only" \
	"$([ "$(contains "$CONTROL_PAYLOAD" '"notification"')" = no ] && echo yes || echo no)"

check "the negative control still carries data, so it is a real push" \
	"$(contains "$CONTROL_PAYLOAD" '"data":{')"

# ---------------------------------------------------------------------------
# 3. The wake key matches the Kotlin that reads it
# ---------------------------------------------------------------------------
#
# The two are separated by a network hop and by a language, so nothing else would
# catch a rename. BackgroundWake.WAKE_KEY drifting from the sender's copy would
# make every delivery answer NotAWake — the app would wake, decline, and the run
# would report "delivered but not a wake", which is a true sentence that reads as
# a product finding and is a typo.

KOTLIN_KEY=$(sed -n 's/.*const val WAKE_KEY = "\([^"]*\)".*/\1/p' "$WAKE_SOURCE" | head -1)
SENDER_KEY=$(sed -n 's/^WAKE_KEY="\([^"]*\)".*/\1/p' "$SENDER" | head -1)

check "BackgroundWake.WAKE_KEY was found in the Kotlin" \
	"$([ -n "$KOTLIN_KEY" ] && echo yes || echo no)" \
	"looked in $WAKE_SOURCE — if that moved, this check is now vacuous"

check "the sender's wake key equals BackgroundWake.WAKE_KEY" \
	"$([ -n "$KOTLIN_KEY" ] && [ "$KOTLIN_KEY" = "$SENDER_KEY" ] && echo yes || echo no)" \
	"Kotlin says '$KOTLIN_KEY', sender says '$SENDER_KEY'"

# ---------------------------------------------------------------------------
# 4. NEGATIVE CONTROLS: the shape assertion must refuse a doctored payload
# ---------------------------------------------------------------------------
#
# Each of these is the bug the corresponding assertion exists to catch, written
# into a copy of the script. Without them, an assert_payload_shape whose every
# `case` fell through would pass every test above.

doctor() {
	label=$1
	pattern=$2
	replacement=$3
	copy="$WORK_DIR/doctored.sh"
	sed "s|$pattern|$replacement|" "$SENDER" >"$copy"

	if [ "$(cmp -s "$copy" "$SENDER" && echo same || echo different)" = same ]; then
		check "$label (the doctoring actually changed the script)" no \
			"the sed pattern matched nothing, so this control is vacuous: $pattern"
		return
	fi

	output=$(bash "$copy" --print-payload 2>&1)
	status=$?
	check "$label" \
		"$([ "$status" -ne 0 ] && echo yes || echo no)" \
		"exit $status, output: $output"
}

# Anchored on the `{"priority":"high","ttl"` fragment, which occurs only in the
# printf that BUILDS the message. The bare string `"priority":"high"` also occurs
# in assert_payload_shape's own `case` pattern, and doctoring both at once
# produces a script that looks for what it now emits — a control that passes for
# the wrong reason, which is the shape of bug this whole file exists to refuse.
doctor "a payload that lost priority:high is refused" \
	'{"priority":"high","ttl"' '{"priority":"normal","ttl"'

doctor "a payload that gained a notification block is refused" \
	'"data":%s}}' '"notification":{"title":"x"},"data":%s}}'

doctor "a payload with no data at all is refused" \
	'"data":%s}}' '"unused":%s}}'

doctor "a wake payload that lost the wake key is refused" \
	'\\"\$WAKE_KEY\\":\\"\$WAKE_REASON\\"' '\\"not_the_wake_key\\":\\"$WAKE_REASON\\"'

# The mirror of the one above: the control must not silently become a real wake.
CONTROL_DOCTORED="$WORK_DIR/control.sh"
# `title` occurs exactly once in the sender, in the control's own data map, so
# renaming it to the wake key turns the control into a real wake and nothing else.
sed 's|title|bittr_wake|' "$SENDER" >"$CONTROL_DOCTORED"
if cmp -s "$CONTROL_DOCTORED" "$SENDER"; then
	check "a negative control that regained the wake key is refused (doctoring applied)" no \
		"the sed pattern matched nothing, so this control is vacuous"
else
	control_out=$(bash "$CONTROL_DOCTORED" --print-payload --no-wake-key 2>&1)
	control_status=$?
	check "a negative control that regained the wake key is refused" \
		"$([ "$control_status" -ne 0 ] && echo yes || echo no)" \
		"exit $control_status, output: $control_out"
fi

# ---------------------------------------------------------------------------
# 5. It refuses to send through anything but the regtest project
# ---------------------------------------------------------------------------
#
# The project check runs BEFORE any network call, which is what makes this
# testable offline — and is the right order for a different reason: a script that
# minted an access token for bittr-prod before deciding not to use it has already
# held a production credential in a CI process.

cat >"$WORK_DIR/prod-key.json" <<'JSON'
{
  "type": "service_account",
  "project_id": "bittr-prod",
  "client_email": "not-a-real-account@bittr-prod.iam.gserviceaccount.com",
  "private_key": "-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n-----END PRIVATE KEY-----\n"
}
JSON

cat >"$WORK_DIR/regtest-key.json" <<'JSON'
{
  "type": "service_account",
  "project_id": "bittr-regtest",
  "client_email": "not-a-real-account@bittr-regtest.iam.gserviceaccount.com",
  "private_key": "-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n-----END PRIVATE KEY-----\n"
}
JSON

# 152 characters of plausible-looking token, so the length guard is not what
# stops the prod key — the project check has to be the thing that does.
{
	echo "FCM_DELIVERY_HANDOFF ready"
	printf 'c%s\n' "$(head -c 151 /dev/zero | tr '\0' 'A')"
} >"$WORK_DIR/token.txt"

prod_out=$(bash "$SENDER" --key-file "$WORK_DIR/prod-key.json" \
	--token-file "$WORK_DIR/token.txt" 2>&1)
prod_status=$?

check "a bittr-prod key is refused before anything is sent" \
	"$([ "$prod_status" -eq 1 ] && echo yes || echo no)" \
	"exit $prod_status, output: $prod_out"

check "the refusal names the standing note rather than just erroring" \
	"$(contains "$prod_out" "BIT-123")" \
	"output: $prod_out"

# ---------------------------------------------------------------------------
# 6. It refuses a target that is not a registration token
# ---------------------------------------------------------------------------
#
# An invalid target and an undelivered message produce the same silence on the
# device. Sending to the hand-off file's MARKER line — the first draft's bug —
# would have produced a 400 that reads exactly like a delivery failure.

printf 'FCM_DELIVERY_HANDOFF ready\n' >"$WORK_DIR/marker-only.txt"
marker_out=$(bash "$SENDER" --key-file "$WORK_DIR/regtest-key.json" \
	--token-file "$WORK_DIR/marker-only.txt" 2>&1)
marker_status=$?

check "a hand-off file with only the marker line is refused" \
	"$([ "$marker_status" -eq 1 ] && echo yes || echo no)" \
	"exit $marker_status, output: $marker_out"

printf '\n' >"$WORK_DIR/empty.txt"
empty_out=$(bash "$SENDER" --key-file "$WORK_DIR/regtest-key.json" \
	--token-file "$WORK_DIR/empty.txt" 2>&1)
empty_status=$?

check "an empty hand-off file is refused" \
	"$([ "$empty_status" -eq 1 ] && echo yes || echo no)" \
	"exit $empty_status, output: $empty_out"

# ---------------------------------------------------------------------------
# 7. The token never reaches stdout
# ---------------------------------------------------------------------------
#
# shared/docs/privacy-disclosure.md lists the registration token as a per-install
# device identifier. On this PUBLIC repo the job log is 403 to anonymous readers,
# but annotations are not, and a `set -x` or an echoed curl command line would put
# it in both. The script's own guard is that the body goes to curl via @file and
# the echoed copy is redacted; this checks the redaction exists.

check "the sender redacts the token out of the message it echoes" \
	"$(contains "$(cat "$SENDER")" 'token withheld')" \
	"send-fcm-wake.sh must not print the registration token it is addressing"

check "the sender passes the body as a file, not on the command line" \
	"$(contains "$(cat "$SENDER")" '--data-binary "@$WORK_DIR/body.json"')" \
	"argv is world readable through /proc on the runner"

echo
if [ "$FAILURES" -ne 0 ]; then
	echo "test-send-fcm-wake: $FAILURES check(s) FAILED."
	exit 1
fi
echo "test-send-fcm-wake: all checks passed."
