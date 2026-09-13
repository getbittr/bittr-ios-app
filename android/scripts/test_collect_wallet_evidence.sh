#!/usr/bin/env bash
#
# Tests for collect-wallet-evidence.sh.
#
#   bash android/scripts/test_collect_wallet_evidence.sh
#
# The seam is `adb`, so each case puts a stub `adb` on PATH and asserts on the
# file that lands and on what was said about it. No emulator, no device, no
# Gradle — which is the point: in the wallet job only the branch that device
# happens to take would ever run, and the branches that matter here are the ones
# a healthy device never reaches.
#
# WHY THESE EXIST
#
# BIT-114 is the defect of shipping a channel nobody checks. The gate read the
# suites' observations off <system-out> in the result XML; the XML writer AGP
# uses has no <system-out> element at all, so nothing was ever there, and thirty
# runs reported the absence without anyone reading it as a bug — because the
# failure mode is a GREEN run that says it could not see.
#
# Replacing that with a second unchecked channel would be the same mistake with a
# different file name. So every branch of the replacement is driven here:
#
#   1. The file is read, and its lines land in the destination.
#   2. Both packages are read — :app's installed app and :core:wallet-ldk's
#      self-instrumenting test APK — because the gate's whole job is refusing a
#      run where one module's half went missing.
#   3. `adb root` refused falls back to logcat, and SAYS it fell back, because
#      logcat's buffer rolls and a possibly-incomplete record must not be read as
#      a complete one.
#   4. Neither channel answering leaves an EMPTY file and a warning, rather than
#      no file. The gate distinguishes "the device said nothing" from "nobody
#      read the device" by whether it was handed a file at all.
#   5. The device-side clear actually names the evidence file, since a stale file
#      from a cached AVD snapshot would otherwise be reported as this run's.
#
# It never exits non-zero on a device problem, and that is pinned too: an
# observation that could not be collected is a "did not look", and a red here
# would be claiming a result the run did not get.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/collect-wallet-evidence.sh"

failures=0
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

stub_dir="$work_dir/bin"
mkdir -p "$stub_dir"

APP_PACKAGE="com.bittr.android.regtest"
LDK_PACKAGE="com.bittr.android.core.wallet.ldk.test"

APP_LINE="BACKUP_EXCLUSION path=cloud-backup api=34 package=$APP_PACKAGE result=Success setLeftOnTransport=false"
LDK_LINE="KEYSTORE_KEY_INFO api=34 device=Google/sdk_gphone64 userAuthenticationRequired=false"
LEVEL_LINE="KEYSTORE_SECURITY_LEVEL api=34 device=Google/sdk_gphone64 level=TEE"

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

ok() {
  echo "ok   $*"
}

# The stub models the device as a directory tree under $stub_dir/data, so the
# script's own `for d in /data/data/com.bittr.android*` loop runs for real
# against it — the glob, the `[ -f ]` guard and the `cat` are the code under
# test, not something the stub stands in for. `adb shell` is handed one string
# and runs it through a shell, which is exactly what this does after rewriting
# the device root to the fake one.
#
# Behaviour is set by two files:
#   root_ok — "yes" or "no", what `adb root` does. "no" also makes the data
#             directory unreadable, which is what a refused root means in
#             practice: the command runs and finds nothing.
#   logcat  — what `adb logcat -d` prints.
write_stub() {
  cat > "$stub_dir/adb" <<'STUB'
#!/usr/bin/env bash
dir=$(dirname "$0")
case "$1" in
  root)
    [ "$(cat "$dir/root_ok")" = "yes" ] && exit 0
    echo "adbd cannot run as root in production builds" >&2
    exit 1
    ;;
  wait-for-device) exit 0 ;;
  logcat)
    # `-c` clears; anything else is a dump.
    for argument in "$@"; do
      if [ "$argument" = "-c" ]; then
        : > "$dir/logcat"
        exit 0
      fi
    done
    cat "$dir/logcat" 2>/dev/null
    exit 0
    ;;
  shell)
    shift
    joined="$*"
    # Record what the device shell was handed, so a case can assert on the
    # command itself where the command IS the behaviour (the clear).
    printf '%s\n' "$joined" >> "$dir/cmdlog"
    if [ "$(cat "$dir/root_ok")" != "yes" ]; then
      # A refused root does not error — the paths simply are not readable, which
      # is why this failure is silent on a real device and has to be caught by
      # what does NOT come back.
      exit 0
    fi
    # Run the real command against the fake device root. CRLF on the way out,
    # because adbd puts the device's line discipline on the wire and the script
    # is expected to strip it.
    rewritten=${joined//\/data\/data/$dir/data/data}
    sh -c "$rewritten" | sed -e 's/$/\r/'
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "$stub_dir/adb"
}

# configure <root_ok> <logcat contents>
configure() {
  rm -rf "$stub_dir/data" "$stub_dir/cmdlog"
  mkdir -p "$stub_dir/data/data"
  printf '%s' "$1" > "$stub_dir/root_ok"
  printf '%s' "${2:-}" > "$stub_dir/logcat"
  write_stub
}

# plant <package> <line>…: the file EvidenceLog would have written.
plant() {
  package=$1
  shift
  mkdir -p "$stub_dir/data/data/$package/no_backup"
  printf '%s\n' "$@" > "$stub_dir/data/data/$package/no_backup/instrumentation_evidence.txt"
}

# run_collect <phase>: returns the script's own exit code; output in $OUTPUT and
# the collected file in $COLLECTED.
run_collect() {
  OUTPUT=$(PATH="$stub_dir:$PATH" bash "$SCRIPT" "$1" "$work_dir/out" 2>&1)
  collect_status=$?
  COLLECTED="$work_dir/out/$1.txt"
  return $collect_status
}

echo "--- both halves of the suite are read"
configure yes ""
plant "$APP_PACKAGE" "$APP_LINE"
plant "$LDK_PACKAGE" "$LDK_LINE" "$LEVEL_LINE"
run_collect both
status=$?
[ "$status" -eq 0 ] || fail "a healthy collection exited $status, expected 0"
[ -f "$COLLECTED" ] || fail "no file was written to $COLLECTED"
if [ -f "$COLLECTED" ]; then
  grep -qF "$APP_LINE" "$COLLECTED" || fail ":app's line is missing from the collected file"
  grep -qF "$LDK_LINE" "$COLLECTED" || fail ":core:wallet-ldk's line is missing — the glob only read one package, which is the half-missing run the gate exists to refuse"
  grep -qF "$LEVEL_LINE" "$COLLECTED" || fail "the security-level line is missing"
  # The gate reads these into an annotation. A carriage return travels all the
  # way there and is invisible until someone greps for a field and misses.
  if grep -q $'\r' "$COLLECTED"; then
    fail "the collected file still carries CR — adbd's CRLF was not stripped"
  fi
fi
case "$OUTPUT" in
  *"::warning"*) fail "a healthy collection emitted a warning: $OUTPUT" ;;
  *) ok "a healthy collection reads both packages, strips CR, and warns about nothing" ;;
esac

echo
echo "--- a refused \`adb root\` falls back to logcat, and says so"
configure no "$APP_LINE
some unrelated System.out chatter
$LEVEL_LINE"
plant "$APP_PACKAGE" "$APP_LINE"
run_collect fallback
status=$?
[ "$status" -eq 0 ] || fail "the logcat fallback exited $status, expected 0 — a cannot-look is not a finding"
if [ -f "$COLLECTED" ]; then
  grep -qF "$APP_LINE" "$COLLECTED" || fail "the fallback did not recover the line from logcat"
  grep -qF "$LEVEL_LINE" "$COLLECTED" \
    || fail "the fallback dropped KEYSTORE_SECURITY_LEVEL — its prefix list has drifted from the gate's"
  if grep -qF "unrelated System.out chatter" "$COLLECTED"; then
    fail "the fallback dragged in unprefixed logcat output"
  fi
else
  fail "the fallback wrote no file"
fi
case "$OUTPUT" in
  *"::warning title=Instrumentation evidence"*"logcat"*)
    ok "the fallback answers and declares itself as the incomplete channel" ;;
  *) fail "the fallback did not warn that it was a fallback: $OUTPUT" ;;
esac

echo
echo "--- neither channel answering leaves an empty file, not no file"
configure no ""
run_collect silent
status=$?
[ "$status" -eq 0 ] || fail "a silent device exited $status, expected 0"
# The empty file is the interface. check-wallet-instrumented-results.py treats a
# file it was handed and could read as "the host looked", and a path it cannot
# read as a disagreement between the two halves — so writing nothing here would
# turn a device that said nothing into a gate error.
[ -f "$COLLECTED" ] || fail "no file was written, so the gate cannot tell 'the device said nothing' from 'nobody read the device'"
[ -s "$COLLECTED" ] && fail "a silent device produced a non-empty file"
case "$OUTPUT" in
  *"::warning title=Instrumentation evidence"*"either channel"*)
    ok "a silent device leaves an empty file and a warning naming both channels" ;;
  *) fail "a silent device did not warn about both channels: $OUTPUT" ;;
esac

echo
echo "--- the clear names the evidence file and the logcat buffer"
configure yes "$APP_LINE"
plant "$APP_PACKAGE" "$APP_LINE"
OUTPUT=$(PATH="$stub_dir:$PATH" bash "$SCRIPT" --clear 2>&1)
status=$?
[ "$status" -eq 0 ] || fail "--clear exited $status, expected 0"
if [ -s "$stub_dir/data/data/$APP_PACKAGE/no_backup/instrumentation_evidence.txt" ]; then
  fail "--clear left the previous run's evidence file on the device; a run whose tests never executed would report it as its own"
else
  ok "--clear removes an earlier run's evidence file"
fi
if [ -s "$stub_dir/logcat" ]; then
  fail "--clear left the logcat buffer, which the fallback reads"
else
  ok "--clear empties the logcat buffer the fallback reads"
fi

echo
echo "--- misuse is a usage error, not a silent empty collection"
OUTPUT=$(PATH="$stub_dir:$PATH" bash "$SCRIPT" 2>&1)
[ $? -eq 2 ] || fail "no arguments should be a usage error, so a mistyped call in the job cannot look like a device that said nothing"
OUTPUT=$(PATH="$stub_dir:$PATH" bash "$SCRIPT" phase-without-a-destination 2>&1)
[ $? -eq 2 ] || fail "a missing destination should be a usage error"
ok "a mistyped invocation is a usage error rather than an empty collection"

echo
if [ "$failures" -eq 0 ]; then
  echo "All collect-wallet-evidence.sh tests passed."
  exit 0
fi
echo "$failures failure(s)."
exit 1
