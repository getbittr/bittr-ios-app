#!/usr/bin/env bash
# Negative control for the guard tests' Gradle input declarations (BIT-113).
#
# The guard tests open their subject by path at runtime, so Gradle only re-runs
# them if each module declares what they read (`sourcesReadAtRuntime`). A
# declaration that is too narrow fails silently and green — which is the one
# outcome these guards exist to refuse — and no test can prove its own width.
# This does, empirically: break a guarded file, run WITHOUT `--rerun`, require
# red. Run it whenever you add a guard that reads a file, or widen a scan.
#
# Three things it refuses to get wrong, each the same mistake in a new place:
#
#   * The verdict is never the build's exit code. An exit code cannot tell "the
#     guard ran and passed" from "the guard never ran", which is the whole
#     subject. It reads the guard's own JUnit XML and requires the `timestamp`
#     attribute to MOVE. A cache hit unpacks that file and updates its mtime
#     while leaving the timestamp on the run that produced it, so the timestamp
#     is the only field that answers "did this execute".
#
#   * Every break carries TOKEN, so its tree has a build-cache key that has
#     never been stored. Without that, a green entry left by an earlier run of
#     the same break answers in the guard's place, and the control passes while
#     measuring nothing. That happened on BIT-113 and cost most of a day.
#
#   * flock, because a second invocation against the same worktree is what
#     stored that entry — two builds, one tree, one of them editing it. The
#     tell in a log is "N busy Daemons could not be reused".
#
# Protocol per case:
#   1. clean tree; run until the task settles (UP-TO-DATE or FROM-CACHE), and
#      require that it does. Without that a red cannot be attributed to the
#      break — the task might have been going to run anyway.
#   2. record the guard XML's internal timestamp
#   3. apply the break the guard exists to catch
#   4. run the SAME task, NO --rerun
#   5. verdict from the XML: timestamp moved => it ran; failures>0 => it caught it
#   6. revert
#
# Usage: scripts/guard-negative-control.sh <case-number>...   (run from android/)
set -u

ANDROID="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ANDROID" || exit 2

# Output lives under build/, which sourcesReadAtRuntime excludes. Anywhere else
# and writing a log would invalidate the very task being measured.
OUT="${OUT_DIR:-$ANDROID/build/guard-negative-control}"
mkdir -p "$OUT"

exec 9>"$OUT/.lock"
flock -n 9 || { echo "another run holds the lock; refusing to contaminate it"; exit 3; }

# Every break carries this. Change it and every case gets a build-cache key that
# has never been stored, so a stale entry cannot answer in the guard's place.
TOKEN="${TOKEN:-BIT113D}"

G() { ./gradlew --console=plain "$@" 2>&1; }

break_1() { python3 - "$TOKEN" <<'PY'
import sys,pathlib
p=pathlib.Path("app/src/androidTest/kotlin/com/bittr/android/BackupExclusionTest.kt")
s=p.read_text()
n=s.replace('device-transfer-plant-ready"','device-transfer-plant-ready-%s"'%sys.argv[1])
assert n!=s, "break 1 did not apply"; p.write_text(n)
PY
}
revert_1() { git checkout -- app/src/androidTest/kotlin/com/bittr/android/BackupExclusionTest.kt; }

break_2() { python3 - "$TOKEN" <<'PY'
import sys,pathlib
p=pathlib.Path("scripts/ci-wallet-instrumented.sh")
s=p.read_text()
assert 'backup_handoff.txt' in s, "break 2: HANDOFF_PATH shape changed"
n=s.replace('backup_handoff.txt','backup_handoff_%s.txt'%sys.argv[1])
assert n!=s; p.write_text(n)
PY
}
revert_2() { git checkout -- scripts/ci-wallet-instrumented.sh; }

break_3() { python3 - "$TOKEN" <<'PY'
import sys,pathlib
p=pathlib.Path("app/src/main/res/xml/data_extraction_rules.xml")
s=p.read_text()
n=s.replace('    </cloud-backup>','        <include domain="file" path="%s" />\n    </cloud-backup>'%sys.argv[1],1)
assert n!=s, "break 3 did not apply"; p.write_text(n)
PY
}
revert_3() { git checkout -- app/src/main/res/xml/data_extraction_rules.xml; }

break_4() { python3 - "$TOKEN" <<'PY'
import sys,pathlib
p=pathlib.Path("core/lnurl/src/test/kotlin/com/bittr/android/core/lnurl/LnurlDetectorTest.kt")
p.write_text(p.read_text()+
 '\n// BIT-113 negative control (%s): a test in an undeclared module reading a\n'
 '// file by path. GuardInputsDeclaredTest must notice core/lnurl has no\n'
 '// withPropertyName("sourcesReadAtRuntime") in its build.gradle.kts.\n'
 'private val bit113Probe = java.io.File("src/main/kotlin")\n'%sys.argv[1])
PY
}
revert_4() { git checkout -- core/lnurl/src/test/kotlin/com/bittr/android/core/lnurl/LnurlDetectorTest.kt; }

break_5() { python3 - "$TOKEN" <<'PY'
import sys,pathlib
p=pathlib.Path("core/wallet-ldk/src/main/kotlin/com/bittr/android/core/wallet/ldk/state/SeedDiscriminator.kt")
# A block comment: DiscriminatorSpecTest filters lines starting with "*" or
# "//", so this survives its filter and trips the banned-token check, while the
# bytecode is byte-identical -- source changes, classpath does not.
p.write_text(p.read_text()+'\n/* BIT-113 negative control (%s): Arrays.equals named in a comment. */\n'%sys.argv[1])
PY
}
revert_5() { git checkout -- core/wallet-ldk/src/main/kotlin/com/bittr/android/core/wallet/ldk/state/SeedDiscriminator.kt; }

break_6() { python3 - "$TOKEN" <<'PY'
import sys,json,pathlib,collections
p=pathlib.Path("../shared/strings/en.json")
d=json.loads(p.read_text(),object_pairs_hook=collections.OrderedDict)
d["mapvcpoweredbyalert"]=d["mapvcpoweredbyalert"]+" "+sys.argv[1]
p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+"\n")
PY
}
revert_6() { git checkout -- ../shared/strings/en.json; }

task_for() { case "$1" in 1|2|3|4) echo ":app:testDebugUnitTest";; 5) echo ":core:wallet-ldk:testDebugUnitTest";; 6) echo ":feature:map:testDebugUnitTest";; esac; }
guard_for() { case "$1" in 1|2) echo "BackupExclusionInstrumentationGuardTest";; 3) echo "BackupExclusionRulesTest";; 4) echo "GuardInputsDeclaredTest";; 5) echo "DiscriminatorSpecTest";; 6) echo "SharedStringsTest";; esac; }
xml_for() {
  local g="$1" d
  case "$g" in
    BackupExclusion*|GuardInputsDeclaredTest) d="app/build/test-results/testDebugUnitTest";;
    DiscriminatorSpecTest) d="core/wallet-ldk/build/test-results/testDebugUnitTest";;
    SharedStringsTest) d="feature/map/build/test-results/testDebugUnitTest";;
  esac
  ls "$d"/TEST-*."$g".xml 2>/dev/null | head -1
}
# The `timestamp` attribute, i.e. when this class last actually executed.
stamp_of() { [ -n "${1:-}" ] && [ -f "$1" ] && sed -n 's/.*timestamp="\([^"]*\)".*/\1/p' "$1" | head -1; }
attr_of() { [ -n "${1:-}" ] && [ -f "$1" ] && sed -n "s/.*$2=\"\([^\"]*\)\".*/\1/p" "$1" | head -1; }

run_case() {
  local n="$1" task guard xml before after
  task="$(task_for "$n")"; guard="$(guard_for "$n")"
  "revert_$n" >/dev/null 2>&1

  echo "======== case $n | $task | $guard | token=$TOKEN"
  local attempt=0 settled=""
  while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt+1))
    G "$task" > "$OUT/case$n-before.log"
    grep -E "^> Task $task( |$)|^> Task $task (UP-TO-DATE|FROM-CACHE|FAILED)|BUILD " "$OUT/case$n-before.log" | tail -2
    grep -q "BUILD SUCCESSFUL" "$OUT/case$n-before.log" || {
      echo "!!! case $n PRECONDITION FAILED: clean run is not green; case measures nothing"
      echo "$n|$guard|clean run RED|NOT MEASURED" >> "$OUT/summary.txt"; return 1; }
    if grep -qE "^> Task $task (UP-TO-DATE|FROM-CACHE)" "$OUT/case$n-before.log"; then
      settled="settled after $attempt run(s)"; break
    fi
  done
  [ -n "$settled" ] || { echo "!!! case $n PRECONDITION FAILED: never settles"
    echo "$n|$guard|never settles|NOT MEASURED" >> "$OUT/summary.txt"; return 1; }

  xml="$(xml_for "$guard")"
  before="$(stamp_of "$xml")"
  echo "-------- precondition: $settled | guard xml stamp before: ${before:-<none>}"

  "break_$n" || { echo "!!! case $n: the break did not apply"; echo "$n|$guard|break failed|NOT MEASURED" >> "$OUT/summary.txt"; return 1; }
  G "$task" > "$OUT/case$n-after.log"
  grep -E "^> Task $task( |$)|^> Task $task (UP-TO-DATE|FROM-CACHE|FAILED)|BUILD " "$OUT/case$n-after.log" | tail -3

  xml="$(xml_for "$guard")"; after="$(stamp_of "$xml")"
  local fails tests verdict
  fails="$(attr_of "$xml" failures)"; tests="$(attr_of "$xml" tests)"
  if [ -z "$after" ]; then verdict="NO XML — guard never ran, here or ever"
  elif [ "$after" = "$before" ]; then verdict="DID NOT RUN (xml timestamp still $before)"
  elif [ "${fails:-0}" != "0" ]; then verdict="RED (ran at $after, $fails of $tests failed)"
  else verdict="RAN BUT PASSED (at $after) — the break is not one this guard catches"
  fi
  echo "-------- case $n verdict: $verdict"
  echo "$n|$guard|$settled|$verdict" >> "$OUT/summary.txt"
  "revert_$n" >/dev/null 2>&1
  echo
}

for n in "$@"; do run_case "$n"; done
echo "======== summary"; cat "$OUT/summary.txt"
