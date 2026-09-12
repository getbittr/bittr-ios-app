#!/usr/bin/env bash
#
# Tests `annotate` from k1-ci.sh: the escaping that carries the K1 table through
# a GitHub workflow command.
#
# WHY THIS EXISTS
#
# The annotation is the only copy of the table a reader without repository admin
# can get — job logs are 403, artefact zips are 401, and the job summary is not
# in the REST API at all (k1-ci.sh, "Publishing the table somewhere it can
# actually be read"). That makes the escaping load-bearing, and it fails in the
# specific way this whole test suite exists to catch: a workflow command is ONE
# line, so an unescaped newline does not error, it silently truncates the table
# to its first line. The annotation still arrives, still looks like a result, and
# says nothing. Same shape as a green row from a run that measured nothing.
#
# The ordering bug is the other one worth a test. `%` has to be substituted
# before the newline and carriage-return escapes are introduced, or it rewrites
# their `%` and the reader gets `%250A` — a literal "%0A" in the text instead of
# a line break.
#
# No device, no network, no SDK. About a second:
#   bash android/scripts/test-k1-annotation.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SCRIPT="android/scripts/k1-ci.sh"

# Extracted by line range rather than sourced: k1-ci.sh shells out to adb at the
# top level, so sourcing it needs a device. Same approach as test-k1-verdict.sh.
eval "$(sed -n '/^annotate() {$/,/^}$/p' "$SCRIPT")"

if ! declare -f annotate >/dev/null; then
  echo "test-k1-annotation: could not extract annotate() from $SCRIPT." >&2
  echo "  If it was renamed or reshaped, fix this extraction — do not delete the test." >&2
  exit 2
fi

K1_ANNOTATION_LIMIT=4000

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

failures=0
check() {
  # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "  ok    $1"
  else
    echo "  FAIL  $1"
    echo "        expected: $2"
    echo "        actual:   $3"
    failures=$((failures + 1))
  fi
}

# The decoder a reader applies — GitHub does this server-side and returns real
# newlines from the annotations API, so asserting the round-trip is asserting
# what k1-result.py will print.
decode() {
  printf '%s' "$1" | sed 's/%0A/\n/g; s/%0D/\r/g; s/%25/%/g'
}

# Counts actual newline BYTES. `grep -c` counts matching lines, not occurrences,
# and `wc -l` on a $(...) capture is off by one because command substitution
# strips the trailing newline — both give the wrong answer to "is this one line?".
raw_newlines() {
  printf '%s' "$1" | tr -cd '\n' | wc -c | tr -d ' '
}

body="$workdir/body"

echo "test-k1-annotation: a multi-line table survives as one line"
cat >"$body" <<'EOF'
### sdk_gphone64_x86_64 (API 34)

| case | result | mutation witness | key security level |
|---|---|---|---|
| M1 | PASS | keyguard-transition+new-credential-set | TRUSTED_ENVIRONMENT |
| M5 | ERROR | - | the start credential did not verify before mutating
EOF
got=$(annotate error "K1 API 34 — not every row is PASS" "$body")
check "exactly one physical line" "0" "$(raw_newlines "$got")"
# Six lines in the fixture, so five separators: $(cat) drops the trailing one.
check "every row separator became %0A" "5" "$(printf '%s' "$got" | grep -o '%0A' | wc -l | tr -d ' ')"
check "command prefix is intact" \
  "::error title=K1 API 34 — not every row is PASS::" \
  "$(printf '%s' "$got" | sed 's/\(::error title=[^:]*::\).*/\1/')"

# The payload, decoded, must be the file back — byte for byte apart from the
# trailing newline that $(cat) drops.
payload=${got#*"::"}          # strip ::error
payload=${payload#*"::"}      # strip title=...::
check "round-trips to the original table" "$(cat "$body")" "$(decode "$payload")"

echo
echo "test-k1-annotation: a literal % is not double-escaped"
printf 'battery at 100%% and a newline\nsecond row\n' >"$body"
got=$(annotate notice "t" "$body")
payload=${got#*::}; payload=${payload#*::}
check "percent survives as a percent" "battery at 100% and a newline
second row" "$(decode "$payload")"
check "no %250A in the wire form (the ordering bug)" "0" \
  "$(printf '%s' "$payload" | grep -c '%250A' || true)"

echo
echo "test-k1-annotation: a carriage return is escaped too"
printf 'adb output\r\nnext\r\n' >"$body"
got=$(annotate notice "t" "$body")
payload=${got#*::}; payload=${payload#*::}
check "CRLF became %0D%0A" "1" "$(printf '%s' "$payload" | grep -c '%0D%0A' || true)"

echo
echo "test-k1-annotation: the title's delimiters are escaped"
printf 'x\n' >"$body"
got=$(annotate error "API 34: rows, not PASS" "$body")
check "colon and comma escaped in the title" \
  "::error title=API 34%3A rows%2C not PASS::x" "$got"

echo
echo "test-k1-annotation: over-long tables say they were cut"
# A limit low enough to trip without generating a 4KB fixture. The property under
# test is that truncation is announced, not the exact number.
K1_ANNOTATION_LIMIT=60
printf 'aaaaaaaaaa\nbbbbbbbbbb\ncccccccccc\ndddddddddd\neeeeeeeeee\nffffffffff\ngggggggggg\n' >"$body"
got=$(annotate error "t" "$body")
payload=${got#*::}; payload=${payload#*::}
case "$payload" in
  *"[truncated at 60 characters"*) echo "  ok    truncation is announced in the text" ;;
  *) echo "  FAIL  truncation was silent — a cut table reads as a short one"
     echo "        actual: $payload"
     failures=$((failures + 1)) ;;
esac
check "still one line after truncation" "0" "$(raw_newlines "$got")"

echo
echo "test-k1-annotation: a real-sized table is left alone"
# The size that matters is a full K1 table: six rows plus the per-row ERROR notes,
# which run long on purpose ("the mutation reported success and the old credential
# is gone, but..."). Roughly 1.5KB, and it must arrive whole — a default limit set
# below a real result would truncate every red run, which is exactly the run whose
# detail is wanted.
#
# shellcheck disable=SC2034  # read by annotate(), which arrives via eval above
K1_ANNOTATION_LIMIT=4000
{
  echo "### sdk_gphone64_x86_64 (API 34)"
  echo
  echo "| case | result | mutation witness | key security level |"
  echo "|---|---|---|---|"
  for c in M1 M2 M3 M4 M5 M6; do
    echo "| $c | ERROR | mutate | - |"
  done
  echo
  for c in M1 M2 M3 M4 M5 M6; do
    echo "**$c** — the mutation reported success and the old credential is gone, but the credential $c aimed for does not verify either — the device is in an unknown state and this row would not describe the mutation it names"
  done
} >"$body"
check "the fixture is the size of a real red table" "yes" \
  "$([ "$(wc -c <"$body")" -gt 1200 ] && echo yes || echo no)"
got=$(annotate error "t" "$body")
case "$got" in
  *truncated*) echo "  FAIL  a full K1 table hit the default limit — raise K1_ANNOTATION_LIMIT"
               failures=$((failures + 1)) ;;
  *) echo "  ok    a full K1 table fits under the default limit" ;;
esac
payload=${got#*::}; payload=${payload#*::}
check "and round-trips whole" "$(cat "$body")" "$(decode "$payload")"

echo
if [ "$failures" -ne 0 ]; then
  echo "test-k1-annotation: $failures check(s) failed." >&2
  echo "  The annotation is the only copy of the K1 table readable without repo admin." >&2
  exit 1
fi
echo "test-k1-annotation: all checks passed."
