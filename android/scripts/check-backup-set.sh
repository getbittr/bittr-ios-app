#!/usr/bin/env bash
#
# BIT-59: read the backup SET, not bmgr's report of it.
#
#   bash android/scripts/check-backup-set.sh
#
# Exit codes:
#   0  clean, OR the set could not be inspected (see below — these are printed
#      very differently and only one of them is evidence)
#   1  wallet material was found inside a real backup set — the BIT-20 §5.3 HALT
#
# WHY THIS IS SEPARATE FROM THE TEST
#
# Since BIT-108 it is not merely separate from the test — it is the ONLY thing
# that returns a verdict on BIT-20 rule 5. BackupExclusionTest used to plant
# files, back up, delete them, restore, and assert none came back. That assertion
# could not survive: `bmgr restore` kills the target process, and the
# instrumentation runs inside it. It was also vacuous-or-fatal by construction —
# a restore only kills the process when the framework has something to restore,
# so the assertion passed exactly when nothing had been backed up. The suite now
# creates the conditions and proves it created them; this script decides.
#
# This check needs no restore at all, and no surviving instrumentation process.
# If wallet material reached the set, the bytes are on disk under the transport's
# own directory and a grep finds them. That is why it still answers on a red run.
#
# The set lives under the transport's data directory, mode 0700 to another uid,
# and UiAutomation's shell runs as `shell` — so the test process cannot read it
# no matter how it is written. From the host, after `adb root`, it can be.
#
# WHY IT IS ITS OWN FILE RATHER THAN A BLOCK IN ci-wallet-instrumented.sh
#
# It decides a HALT, and everything else in this repo that decides something
# gets tested for it — ci-runs.py, check-instrumented-results.py,
# check-wallet-instrumented-results.py, report-test-failures.py. Inline in a
# script that runs Gradle against a booted emulator, this logic is reachable
# only by booting an emulator; as a file with a seam at `adb`, it is reachable
# by test_check_backup_set.sh with a stub on PATH. The first draft of it WAS
# inline, and it shipped the exact vacuity bug described below — grepping three
# paths that may not exist on this image and reporting the empty result as
# "clean". That is the bug this whole job exists to refuse, and it took a
# re-read rather than a test to catch.
#
# HOW THE SET IS SEARCHED: TWICE, WITH DIFFERENT BLIND SPOTS (BIT-116)
#
# A literal `grep` on the device, AND a host-side decode. The grep covers the
# whole transport tree, including journals and pending directories that are not
# part of any set; the decode covers only the set files, but it can see inside
# the container. Neither subsumes the other and either one finding the wallet
# marker is the halt. See decode-backup-set.py for why the grep alone was not
# enough: it reported "no marker" on a 4608-byte set that it could not read, and
# a gate that cannot fail is not a gate.
#
# FIVE OUTCOMES, AND ONLY ONE OF THEM IS EVIDENCE
#
#   1. Wallet marker found, by either search -> exit 1. Wallet material reached a
#      real backup set. Unambiguous, and the BIT-20 §5.3 halt on `match -> keep`.
#   2. No wallet marker, AND THE CANARY IS PRESENT -> exit 0, and this is the
#      only one that is evidence: the set was reachable, searched, provably
#      non-empty, and carried no wallet material. The annotation states whether
#      the canary came from the decode (strong) or the plaintext grep alone
#      (weaker — a literal search cannot see into a compressed container).
#   3. No wallet marker and NO canary, in a set that is measurably EMPTY -> exit 0
#      with a ::warning::. NOT evidence. This is the outcome this file was
#      extended for (BIT-109).
#   3b. No wallet marker and no canary, in a non-empty set THE DECODER READ ->
#      exit 0 with its own ::warning::. Not evidence either — a set without the
#      canary is a set the exclusion rules were never consulted about — but the
#      halt search did run over decoded members, so it is a real negative rather
#      than a failed search. Added by BIT-116.
#   3c. No wallet marker and no canary, in a non-empty set the decoder COULD NOT
#      read -> exit 0 with its own ::warning::. The worst outcome to mistake for
#      any of the others: nothing was searched successfully, so it is neither
#      evidence nor a clean bill of health. The annotation carries the container
#      identification and a byte sample so the next run can name the format.
#   4. `adb root` refused, or no candidate directory exists on this image
#      -> exit 0 with a ::warning::. NOT evidence. A green BackupExclusionTest
#      from such a run rests on bmgr's report alone, and saying so is the whole
#      point — a check that cannot distinguish "clean" from "did not look" is
#      worse than no check, because it reads as the first.
#
# WHY OUTCOME 3 IS NOT OUTCOME 2 (BIT-109)
#
# Outcome 2 used to be reported for any run where the grep came back empty, and
# that is the same failure this file's header already refuses, arrived at from a
# different direction. An EMPTY SET excludes wallet material trivially: no
# marker, no warning, and a ::notice:: claiming the set was searched and clean.
# "The rules excluded our wallet files" and "there was nothing in the set to
# exclude" are different facts, only one of them is evidence for rule 5, and they
# were producing the same green.
#
# And it is the LIKELY case, not an exotic one. So BackupExclusionTest plants a
# canary in `files/`, which no rule excludes, under its own prefix. Canary in the
# set means the exclusion rules were actually consulted. No canary means there
# was nothing to consult them about, and the grep proved nothing.
#
# WHAT AN EMPTY SET DOES *NOT* TELL YOU: WHICH PATH LEFT IT EMPTY
#
# This script runs once, from the host, after both backup paths have been driven,
# and it reads one tree. It cannot attribute an empty set to a path, and the two
# paths do not go empty for the same reason:
#
#   * CLOUD path — `allowBackup="false"` makes the package ineligible and the
#     framework never offers it to the transport. Expected: that flag is what we
#     ship.
#   * DEVICE-TRANSFER path — `allowBackup` does NOT apply here. That is the whole
#     reason the path exists, so ineligibility does not explain an empty set on
#     it. What does is a backup that never completed: the framework binds a backup
#     agent inside the TARGET process, and when that process dies mid-backup
#     nothing is written (BIT-108 — the instrumentation lives in that same
#     process, which is why the suite goes red with an empty <failure> in the same
#     run).
#
# So the warning below names both and asserts neither. Naming only the first was
# the bug corrected here: it reads as "expected, nothing to see" on a run whose
# set was empty because the process died.
#
# THE DECOYS ARE REPORTED, NEVER A HALT
#
# The `dataExtractionRules` `<exclude domain="file">` entries are rooted at
# getFilesDir(), while the wallet directory is under getNoBackupFilesDir() — a
# sibling, not a child. If those entries are a no-op, the `no_backup` siting is
# carrying rule 5 alone. BackupExclusionTest plants a decoy at each path those
# entries name, under a third prefix. Finding one is a finding about the RULES,
# not wallet material escaping, so it is printed alongside whatever outcome the
# run got and never trips the halt. The three prefixes are deliberately distinct
# strings so the canary and the decoys can be found without counting as outcome 1.
#
# A backup-set DIRECTORY existing for the package is deliberately NOT a failure.
# The platform creates and prunes those for its own reasons; only the wallet
# marker means our bytes are in there. It is printed so a person can see it.
set -euo pipefail

# decode-backup-set.py lives beside this file and is invoked from wherever CI
# happens to be standing. Resolved rather than assumed relative to $PWD: this
# script is run as `bash android/scripts/check-backup-set.sh` from the repo root
# today, and a decoder that could not be found would degrade to "the set could
# not be read" — a plausible-looking result that is really a path bug.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Must match BackupExclusionTest's MARKER_PREFIX. test_check_backup_set.sh reads
# both files and fails in the `build` job if these two drift, because a drift
# would make the grep below match nothing for ever — a permanent silent pass on
# the one check that reads a real backup set.
MARKER_PREFIX="BIT101-WALLET-MARKER-"

# The canary's prefix. Its PRESENCE is what makes a clean grep evidence, so a
# drift here fails in the opposite direction to MARKER_PREFIX's: the grep below
# matches nothing for ever, no run ever reaches the evidence outcome, and every
# run warns that the set was empty. That is loud rather than silent — the safe
# direction for a drift to fail in — but it is still a permanently wrong verdict,
# so test_check_backup_set.sh pins this one against the test too.
CANARY_PREFIX="BIT101-CANARY-MARKER-"

# The decoys' prefix. Reported, never a halt — see the header.
DECOY_PREFIX="BIT101-DECOY-MARKER-"

# Where the local transport keeps its sets. Image-dependent, and which of the
# two LocalTransport packagings is present varies too, so this is a candidate
# list rather than a path. Anything not present is skipped, and ALL of them
# being absent is outcome 3 above, not outcome 2.
SET_ROOTS="/data/data/com.android.localtransport/files /data/system/backup /data/backup"

echo "--- Backup set inspection (the half the test cannot reach)"

if ! adb root >/dev/null 2>&1 || ! adb wait-for-device; then
  echo "::warning::Could not gain root on this device, so the backup set itself"\
    " was NOT inspected — only bmgr's report of it was. A green"\
    " BackupExclusionTest from this run is therefore weaker evidence than one"\
    " from a run where this check executed. It is not a failure: 'adb root' is"\
    " refused on a production image, and reporting that as a wallet finding"\
    " would be reporting the wrong thing."
  exit 0
fi

# $SET_ROOTS expands inside the double quotes, so the HOST shell does no
# splitting — the device shell splits it into separate arguments, which is the
# intent. Quoting it further would hand `ls` one path with spaces in it.
present=$(adb shell "ls -d $SET_ROOTS 2>/dev/null" | tr -d '\r' || true)

if [ -z "$present" ]; then
  echo "::warning::None of the candidate backup-transport directories exist on"\
    " this image, so the backup set itself was NOT inspected — only bmgr's"\
    " report of it was. This is NOT evidence that the set was clean. Looked in:"\
    " $SET_ROOTS. If this image keeps its sets elsewhere, add that path to"\
    " SET_ROOTS in this script; until then this run's BackupExclusionTest green"\
    " rests on bmgr's report alone."
  adb shell bmgr list transports 2>/dev/null | tr -d '\r' || true
  exit 0
fi

echo "Transport directories present on this image:"
printf '%s\n' "$present"

# `$present` comes from `ls -d`, so it is NEWLINE-separated, and every use below
# interpolates it into a command string handed to the device shell. A newline
# there does not separate arguments — it separates COMMANDS. Interpolating it
# raw turns
#     grep -rl 'MARKER' /data/backup /data/data/com.android.localtransport/files
# into
#     grep -rl 'MARKER' /data/backup
#     /data/data/com.android.localtransport/files
# — a grep of the FIRST root only, plus a second line the shell tries to execute
# as a program and whose failure `2>/dev/null` swallows. On an image with both
# roots present that silently skipped the LocalTransport tree, which is where the
# sets actually live, so the §5.3 halt grep could not have found wallet material
# even if it were sitting there: the gate failed as a pass. Observed on the run
# for ecd2e5e, where `find` returned an unfiltered listing of /data/backup and
# not one path matching its own -name filter.
#
# The $SET_ROOTS expansion above is a different case and is correct: that literal
# is space-separated, so the device shell splits it into arguments as intended.
# Flatten to the same shape here rather than quoting, for the same reason.
present_args=$(printf '%s' "$present" | tr '\n' ' ' | tr -s ' ')

sets=$(adb shell "find $present_args -maxdepth 3 -name '*bittr*' 2>/dev/null" | tr -d '\r' || true)
echo "Backup-set paths mentioning this package (recorded, not asserted):"
printf '%s\n' "${sets:-  (none)}"

# Flattened for the annotation. These two facts are the difference between "the
# transport wrote a set and it had nothing in it" and "the transport never wrote
# a set here at all", which is the first question anyone asks about an empty
# result — and until now they existed only in the two echoes above, i.e. only in
# the job log, which answers 403 on this public repo. Same reasoning as every
# other verdict in this file: if it is not in an annotation it is not readable.
# One line: annotations are one line unless newlines are %0A-encoded. The roots
# reuse $present_args, which is already flattened and is the exact string the
# greps above were handed — so the annotation reports what was really searched
# rather than what was intended to be.
sets_inline=$(printf '%s' "$sets" | tr '\n' ' ' | tr -s ' ')
[ -n "${sets_inline// /}" ] || sets_inline="(none)"

# With the roots actually searched, the run for d823265 found the set directory
# at .../files/1/_full/<pkg> — so "did the transport write a set here" is
# answered YES, and the next question is whether anything is IN it. A directory
# the framework created and then wrote nothing into looks identical, from the
# canary grep alone, to one whose contents were all excluded; the first is a
# backup that produced no data, the second would be evidence. Sizes tell them
# apart, and like everything else here they are useless in the job log.
#
# Guarded on $sets being non-empty: `find` with no starting path walks the
# working directory, which on the device is / — an expensive way to report
# nothing. Failure is non-fatal, hence the fallback: this is diagnostics hanging
# off a verdict that has already been decided above.
if [ -n "${sets_inline// /}" ] && [ "$sets_inline" != "(none)" ]; then
  set_files=$(adb shell "find $sets_inline -type f -exec ls -l {} + 2>/dev/null" \
    | tr -d '\r' | awk '{n++; print} END {if (!n) print "  (no regular files under the set paths)"}' \
    | head -40 || true)
else
  set_files="  (no set paths to size)"
fi
set_files_inline=$(printf '%s' "$set_files" | tr '\n' ' ' | tr -s ' ')

# Total bytes of the regular files under the set paths. Field 5 of `ls -l`, and
# the guard on it being all digits is what keeps the "(no regular files...)"
# placeholder and any stray line out of the sum.
#
# This decides whether the no-canary result may be called an EMPTY SET. Until
# the roots were searched properly there was no way to ask, and "no canary"
# was treated as "nothing in the set" -- a sound inference only while the set
# could not be measured. The run for 9dc0b64 measured it: 4608 bytes under
# .../files/1/_full/<pkg>. The framework wrote real data and the canary was
# still not greppable, so the inference is false and this script must stop
# making it.
set_bytes=$(printf '%s\n' "$set_files" | awk '$5 ~ /^[0-9]+$/ {t+=$5} END {print t+0}')

# --- READ the set, rather than grepping its bytes (BIT-116) -------------------
#
# Everything above this point searches the set as a literal string on the
# device. The run for 9dc0b64 showed what that is worth: 4608 bytes on disk and
# not one of the three prefixes greppable in them, including the canary, which is
# planted in files/ and which no rule excludes. A set that holds real data and
# yields no canary is not a clean set, it is an unreadable one.
#
# The consequence that makes this a fix rather than an improvement: the
# $MARKER_PREFIX grep below is the SAME search over the SAME bytes, and it is
# what decides the §5.3 halt. If the container hides contents from a literal
# search -- compression alone does -- then that grep could not have found wallet
# material sitting in the set, and every run reported "no marker" regardless. A
# gate that cannot fail is not a gate.
#
# So pull the set to the host and decode it. decode-backup-set.py identifies the
# container (tar, gzip, zlib, or none of those), enumerates the members, and
# searches the DECODED content -- see its header. It reports, and this file still
# decides, because the outcomes and what they mean live here.
#
# Kept ALONGSIDE the on-device greps rather than replacing them. They cover the
# transport tree outside the set paths -- journals, pending dirs, /data/backup --
# which is not pulled, and a marker in plaintext anywhere under there is still
# the halt. Two searches with different blind spots, and either one firing is a
# finding.
pull_dir=$(mktemp -d)
trap 'rm -rf "$pull_dir"' EXIT

pulled=0
pull_failed=0
if [ -n "${sets_inline// /}" ] && [ "$sets_inline" != "(none)" ]; then
  # A fresh `find` for paths rather than parsing the `ls -l` above: field 8 of
  # `ls -l` is only the path when nothing in the listing has a space in it, and
  # the one thing worse than not pulling the set is pulling the wrong file and
  # reporting a clean decode of it.
  while IFS= read -r device_file; do
    [ -n "$device_file" ] || continue
    # Flattened into a unique local name. Two sets can hold a file of the same
    # name in different directories, and collapsing them would silently drop
    # one from the search -- the same "searched less than it looked like"
    # failure as the newline bug above.
    local_name=$(printf '%s' "${device_file#/}" | tr '/' '_')
    # The file has to EXIST afterwards, not merely have been asked for. `adb
    # pull` exits 0 in situations where nothing lands on the host, and counting
    # those would report "pulled 1 file" next to a decode of an empty directory
    # — a run that read nothing, described as a run that read something. Same
    # failure this whole script is a record of, one layer down.
    if adb pull "$device_file" "$pull_dir/$local_name" >/dev/null 2>&1 \
       && [ -f "$pull_dir/$local_name" ]; then
      pulled=$((pulled + 1))
    else
      pull_failed=$((pull_failed + 1))
      rm -f "$pull_dir/$local_name"
    fi
  done <<EOF
$(adb shell "find $sets_inline -type f 2>/dev/null" | tr -d '\r' || true)
EOF
fi

# `|| true` and a captured exit code: a decoder that crashes must not take the
# build down, and must not be mistaken for a decoder that looked and found
# nothing. An empty report reads as READABLE=no below, which is the correct and
# conservative answer to "we could not read the set".
decode_status=0
decode_report=$(python3 "$SCRIPT_DIR/decode-backup-set.py" "$pull_dir" 2>&1) \
  || decode_status=$?
if [ "$decode_status" -ne 0 ]; then
  decode_report=""
fi

# Reads one KEY=value line out of the report. decode-backup-set.py guarantees
# every value is a single line, so there is no continuation case to handle.
decoded_field() {
  printf '%s\n' "$decode_report" \
    | awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }'
}

decoded_readable=$(decoded_field READABLE)
decoded_containers=$(decoded_field CONTAINERS)
decoded_entries=$(decoded_field ENTRIES)
decoded_names=$(decoded_field ENTRY_NAMES)
decoded_samples=$(decoded_field SAMPLES)
decoded_notes=$(decoded_field NOTES)
decoded_wallet=$(decoded_field WALLET)
decoded_canary=$(decoded_field CANARY)
decoded_decoy=$(decoded_field DECOY)
: "${decoded_readable:=no}"
: "${decoded_containers:=(decoder did not run)}"
: "${decoded_entries:=0}"
: "${decoded_names:=(none)}"
: "${decoded_samples:=(none)}"
: "${decoded_notes:=(none)}"

# A file the decoder never received cannot have been searched, and the decoder
# cannot know it was supposed to get one — its input is the directory, so a set
# file that failed to pull is invisible to it. So a failed pull demotes the whole
# set to unreadable HERE, for the same reason decode-backup-set.py demotes a set
# where one blob would not decode: the marker could be in the part that is
# missing, and clearing the set on the strength of the parts that did arrive is
# the unfalsifiable pass this issue is about, reassembled out of different parts.
if [ "$pull_failed" -gt 0 ]; then
  decoded_readable="no"
  decoded_notes="$decoded_notes; $pull_failed file(s) under the set paths could NOT be pulled to the host"
fi

echo "Pulled $pulled file(s) from the set and decoded them:"
printf '%s\n' "${decode_report:-  (the decoder did not run — see above)}"

# `(none)` is decode-backup-set.py's explicit spelling for "searched, found
# nothing", chosen so an empty value can never be confused with an absent field.
# Normalised to the empty string here so the tests below read the same way as
# the on-device ones.
[ "$decoded_wallet" != "(none)" ] || decoded_wallet=""
[ "$decoded_canary" != "(none)" ] || decoded_canary=""
[ "$decoded_decoy" != "(none)" ] || decoded_decoy=""

leaks=$(adb shell "grep -rl '$MARKER_PREFIX' $present_args 2>/dev/null" | tr -d '\r' || true)
canaries=$(adb shell "grep -rl '$CANARY_PREFIX' $present_args 2>/dev/null" | tr -d '\r' || true)
decoys=$(adb shell "grep -rl '$DECOY_PREFIX' $present_args 2>/dev/null" | tr -d '\r' || true)

# Printed before any verdict, so the decoy finding survives every exit path
# below — including the halt, where it is a second fact about the same set and
# not a reason to say anything less about the first.
if [ -n "$decoys" ] || [ -n "$decoded_decoy" ]; then
  echo "::warning title=Backup rules::A DECOY ($DECOY_PREFIX) is in the backup set."\
    " The <exclude domain=\"file\"> entries in dataExtractionRules are rooted at"\
    " getFilesDir() and did NOT exclude a file at the path they name, so those"\
    " entries are a no-op and the getNoBackupFilesDir() siting is carrying BIT-20"\
    " rule 5 on its own. This is a finding about the RULES, not wallet material"\
    " escaping, and it is deliberately NOT the §5.3 halt. The fix is to correct"\
    " the rules, never to relax the rule. Files containing it:"
  printf '%s\n' "  on-device grep: ${decoys:-(no plaintext hit)}"
  printf '%s\n' "  decoded set:    ${decoded_decoy:-(no hit in a decoded member)}"
else
  echo "No decoy ($DECOY_PREFIX) in the set: the <exclude domain=\"file\"> entries"\
    " excluded the paths they name."
fi

if [ -n "$leaks" ] || [ -n "$decoded_wallet" ]; then
  echo "::error title=Backup set inspection::WALLET MATERIAL IS IN A REAL BACKUP"\
    " SET. The marker BackupExclusionTest wrote into the LDK state files it"\
    " planted was found inside the backup transport's own tree, which means the"\
    " exclusion did not hold on this device. This is the BIT-20 §5.3 HALT on"\
    " 'match -> keep' — not a flake, and not a test to loosen. It goes back to"\
    " BIT-20 with this result attached."\
    " On-device plaintext grep: [${leaks:-(no hit)}]."\
    " Decoded set members: [${decoded_wallet:-(no hit)}]."\
    " The decoded hit names the archive member, so it says which planted file"\
    " reached the set and under which backup domain — apps/<pkg>/f/ is"\
    " getFilesDir(), apps/<pkg>/r/ is the root data dir."
  printf '%s\n' "on-device grep hits:"
  printf '%s\n' "${leaks:-  (none)}"
  printf '%s\n' "decoded-member hits:"
  printf '%s\n' "${decoded_wallet:-  (none)}"
  exit 1
fi

# Outcome 3: no wallet marker, but nothing of ours is in the set at all, so the
# grep above searched a set that never had anything to exclude. Exit 0 — neither
# cause is this script's to fail the build for. The cloud cause is the EXPECTED
# result of shipping `allowBackup="false"`; the device-transfer cause is a dead
# instrumentation process, which the suite's own red already reports. Failing
# here would be reporting the wrong thing in both cases, exactly as with "could
# not gain root" above. But it is not evidence, and it must not be reported in
# the same words as outcome 2.
if [ -z "$canaries" ] && [ -z "$decoded_canary" ] && [ "${set_bytes:-0}" -gt 0 ] \
   && [ "$decoded_readable" != "yes" ]; then
  # No canary, the set is measurably NOT empty, AND the decoder could not read
  # it either. That last condition is what BIT-116 added: before it, this branch
  # was reached by any non-empty set with no plaintext canary, which conflated
  # "we cannot read this container" with "we read it and our files are not in
  # it". They call for opposite next steps, so they are now separate outcomes
  # and this one is the honest dead end — see the readable branch below.
  #
  # These are different facts and
  # the empty-set wording below is simply false here — the run for 9dc0b64 wrote
  # 4608 bytes and none of the three prefixes was greppable in them.
  #
  # The honest reading is that a plaintext grep cannot read this set. A full
  # backup reaches the transport as a tar stream, and nothing guarantees the
  # bytes on disk hold file contents verbatim; compression alone defeats a
  # literal-string search. That applies to ALL THREE greps, so this run is not
  # evidence for rule 5 — and, far more importantly, it is NOT a clean bill of
  # health either: the $MARKER_PREFIX grep that decides the §5.3 halt is the same
  # kind of search over the same unreadable bytes, so wallet material could be in
  # this set and this check would report exactly what it just reported.
  #
  # Deliberately still exit 0 and still not the halt: the halt requires the
  # marker to be FOUND. But this must not be filed alongside "the set was empty",
  # which reads as a benign expected outcome, because the two have opposite
  # implications for whether the check can be trusted at all.
  echo "::warning title=Backup set inspection::The set is NOT empty and this check"\
    " could not read it. Regular files under the set paths total $set_bytes bytes,"\
    " so the framework wrote real data — and NONE of the three prefixes"\
    " ($MARKER_PREFIX, $CANARY_PREFIX, $DECOY_PREFIX) was greppable in it. The"\
    " canary is planted in files/, which no rule excludes, so it should be in any"\
    " set that carries file contents verbatim. It is not, which points at the"\
    " FORMAT rather than at the rules: a full backup reaches the transport as a"\
    " tar stream and the bytes on disk need not hold contents as plaintext —"\
    " compression alone defeats a literal-string search."\
    " Two consequences, and the second is the serious one."\
    " (1) This run is NOT evidence for BIT-20 rule 5: nothing was demonstrated"\
    " about whether the exclusion rules work."\
    " (2) It is NOT a clean bill of health either. The $MARKER_PREFIX grep that"\
    " decides the §5.3 halt is the same kind of search over the same unreadable"\
    " bytes, so wallet material could be sitting in this set and this check would"\
    " report what it just reported. Do not read a non-halt here as 'no leak'."\
    " The host-side decoder ran on $pulled pulled file(s) and could not decode"\
    " them either, so this is now a statement about the CONTAINER and not about"\
    " the search: containers = [$decoded_containers]; undecoded head bytes ="\
    " [$decoded_samples]; notes = [$decoded_notes]. That sample is the thing to"\
    " read — it identifies the format, and a format decode-backup-set.py does not"\
    " yet handle is a one-function fix there rather than an open question here."\
    " Set paths = [$sets_inline]. Files = [$set_files_inline]."
  exit 0
fi

# BIT-116's new outcome: the set WAS decoded, and our canary is genuinely not in
# it. This is not the branch above — there the container defeated the search, so
# nothing at all could be concluded. Here the members were enumerated and the
# canary is absent from them, which is a real fact about what the framework put
# in the set.
#
# It is still NOT evidence for rule 5, and for the original BIT-109 reason: the
# canary is planted in files/, which no rule excludes, so a set without it is a
# set the exclusion rules were never consulted about. Whatever those bytes are —
# a manifest, framework metadata, an APK — they are not this app's file domains,
# so nothing was demonstrated about whether the wallet exclusion works.
#
# But unlike the branch above it IS a clean bill of health as far as it goes: the
# §5.3 grep ran over decoded members this time, so a non-halt here means wallet
# material was actually looked for and not found. That distinction is the whole
# point of BIT-116 and it has to be in the annotation, because the two states
# used to print the same words.
if [ -z "$canaries" ] && [ -z "$decoded_canary" ] && [ "${set_bytes:-0}" -gt 0 ]; then
  echo "::warning title=Backup set inspection::The set was DECODED and carried no"\
    " canary ($CANARY_PREFIX). Regular files under the set paths total"\
    " $set_bytes bytes across $pulled pulled file(s); containers ="\
    " [$decoded_containers]; $decoded_entries archive member(s) were enumerated"\
    " and searched. Members = [$decoded_names]. Notes = [$decoded_notes]."\
    " This is NOT the unreadable-set outcome: the halt search ran over decoded"\
    " members, so no wallet marker ($MARKER_PREFIX) here means none was found in"\
    " a set that was actually read. It is also still NOT evidence for BIT-20"\
    " rule 5. The canary is planted in files/, which no rule excludes, so a set"\
    " without it is a set the exclusion rules were never consulted about —"\
    " whatever these bytes are, they are not this app's file domains. Read the"\
    " member list: names under apps/<pkg>/f/ are getFilesDir() and their absence"\
    " is the finding. To reach the evidence outcome the run needs a set the"\
    " framework populated with the app's file domains."
  exit 0
fi

if [ -z "$canaries" ] && [ -z "$decoded_canary" ]; then
  echo "::warning title=Backup set inspection::The set was searched and carried no"\
    " wallet marker ($MARKER_PREFIX) — but it carried no canary ($CANARY_PREFIX)"\
    " either, and BackupExclusionTest plants the canary in files/, which no rule"\
    " excludes. So the set this run produced was EMPTY. This check reads one tree"\
    " after both paths have been driven and CANNOT say which of them left it"\
    " empty, and they go empty for different reasons. CLOUD path:"\
    " allowBackup=\"false\" made the package ineligible and the framework never"\
    " offered it to the transport — expected, that flag is what we ship."\
    " DEVICE-TRANSFER path:"\
    " allowBackup does NOT apply there, which is the whole reason the path exists,"\
    " so ineligibility does not explain it. TWO device-transfer causes, and the"\
    " 'Device-transfer backup' annotation on this run tells them apart. (a) The"\
    " backup did not complete — the target process died mid-backup with the"\
    " framework's backup agent bound inside it (BIT-108), which also shows up as an"\
    " empty <failure> on the suite side of the same run."\
    " (b) The backup DID report Success and the process survived,"\
    " and nothing landed in the directories"\
    " listed below anyway — in which case process death is excluded and the open"\
    " question is whether the local transport persists a device-transfer set to"\
    " these roots at all, or streams it somewhere this check never looks. Cause (b)"\
    " is not hypothetical: it is what the first run carrying both halves reported."\
    " Either way an empty set excludes wallet material trivially."\
    " This is NOT evidence for"\
    " BIT-20 rule 5: the exclusion rules were never consulted, so nothing was proven"\
    " about whether they work. It is also NOT a failure this check decides — read"\
    " the suite result to tell the causes apart. To get the evidence outcome"\
    " instead, the run needs a set the framework actually populated."\
    " OBSERVED THIS RUN, and otherwise only in the job log, which answers 403"\
    " without a token: transport directories present = [$present_args];"\
    " paths under them mentioning this package = [$sets_inline]. If that second"\
    " list is (none), no set was written to these roots and the question is WHERE,"\
    " not what was excluded from it; if it names a path, the set directory exists"\
    " and the question is whether anything is IN it."\
    " Regular files under those paths = [$set_files_inline]."\
    " A set directory the framework created and wrote"\
    " nothing into is a backup that produced no data, which is not the same as one"\
    " whose contents were excluded, and only the second would be evidence."
  exit 0
fi

# Outcome 2, and now it earns the name. A ::notice:: rather than a plain echo,
# and the asymmetry that fixes is the other half of this script's point. Of the
# four outcomes above, the three that are NOT evidence emit annotations (an
# ::error:: for the halt, ::warning::s for "did not look" and "nothing to look
# at"), while this one — the only one that is evidence — was a bare echo into the
# job log. On this public repo that log answers 403 and artifacts answer 401, so
# the run that PROVED something was the one run nobody could read without
# credentials, and the finding had to be taken on trust.
#
# It matters most exactly when the suite is red: this check reads the
# transport's tree from the host with no restore and no surviving instrumentation
# process, so it still answers when the in-process assertions cannot. See the
# empty-<failure> block in check-wallet-instrumented-results.py.
#
# Since BIT-116 this outcome can be reached two ways, and the annotation says
# which. A canary found by DECODING the set is the strong form: the container was
# identified, its members enumerated, and the halt search ran over their decoded
# contents. A canary found by the on-device plaintext grep alone is the older,
# weaker form — it proves the set holds our file contents verbatim, which is
# still a real searched-and-clean result, but it says nothing about parts of the
# set a literal search cannot reach. Reporting them identically would hide
# exactly the gap this issue was opened for.
echo "::notice title=Backup set inspection::Looked inside the backup transport's own"\
  " on-disk tree from the host. The canary ($CANARY_PREFIX) IS in the set, so the"\
  " set is provably non-empty and the exclusion rules were actually consulted; and"\
  " NO wallet marker ($MARKER_PREFIX) was found. This is the evidence outcome for"\
  " BIT-20 rule 5 — the set was reachable, searched, non-empty, and carried no"\
  " wallet material. It is independent of whether the instrumentation process"\
  " survived, so it holds even on a red run."\
  " HOW THE SET WAS READ, which is what makes this outcome worth anything:"\
  " decoder readable = $decoded_readable; containers = [$decoded_containers];"\
  " $decoded_entries member(s) enumerated; members = [$decoded_names]."\
  " Canary in decoded members = [${decoded_canary:-(none — plaintext grep only)}];"\
  " canary in the on-device plaintext grep = [${canaries:-(none)}]."\
  " If 'decoder readable' is not yes, this rests on the plaintext grep alone,"\
  " which cannot see into a compressed container — a weaker claim than a decoded"\
  " read, and the reason BIT-116 exists."
printf '%s\n' "on-device grep found the canary in:"
printf '%s\n' "${canaries:-  (none)}"
printf '%s\n' "decoded members holding the canary:"
printf '%s\n' "${decoded_canary:-  (none)}"
echo "Looked inside the backup set: canary present, no wallet marker."
exit 0
