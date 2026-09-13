#!/usr/bin/env python3
"""Tests for decode-backup-set.py.

    python3 android/scripts/test_decode_backup_set.py

WHY THESE EXIST

decode-backup-set.py is what makes the BIT-20 §5.3 halt able to fire at all. The
grep it replaces could not have found wallet material in a compressed set, so it
reported "no marker" on every run regardless of what was in there -- a gate that
fails as a pass. Replacing one unfalsifiable search with another would be worse
than leaving it alone, because the new one *reads* like it looked.

So every case here builds a REAL archive -- real tar headers, real gzip, real
zlib -- rather than stubbing the decode. The seam is a directory of bytes, so
that costs nothing: no emulator, no device, no adb.

The cases that matter most are the two that are easy to get wrong in the
reassuring direction:

  * `truncated_tar_still_yields_its_members` -- the transport writes what it
    receives from a socket, so the sets this runs on in CI are PREFIXES of a
    stream. A decoder that called a truncated tar "not a tar" would report an
    unreadable set for every real run, i.e. it would never work in production
    while passing every well-formed test.
  * `an_undecodable_blob_is_not_readable` -- READABLE=no is the honest answer
    when we could not decode, and the shell turns its verdict on that field. A
    decoder that defaulted to `yes` would restore the exact bug being fixed.
"""

import io
import os
import gzip
import zlib
import shutil
import tarfile
import tempfile
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "decode-backup-set.py")

MARKER_PREFIX = "BIT101-WALLET-MARKER-"
CANARY_PREFIX = "BIT101-CANARY-MARKER-"
DECOY_PREFIX = "BIT101-DECOY-MARKER-"

failures = []


def run(files):
    """Write `files` (name -> bytes) into a temp dir and decode it.

    Returns the report as a dict. Parsed with a single split on the first `=`,
    the same way the shell reads it, so a value that broke across lines would
    break here too rather than being tolerated by a more forgiving parser.
    """
    root = tempfile.mkdtemp()
    try:
        for name, data in files.items():
            path = os.path.join(root, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as handle:
                handle.write(data)
        proc = subprocess.run(
            [sys.executable, SCRIPT, root],
            capture_output=True, text=True,
        )
        assert proc.returncode == 0, (
            "decode exited %d: %s" % (proc.returncode, proc.stderr))
        report = {}
        for line in proc.stdout.splitlines():
            assert "=" in line, "line is not KEY=value: %r" % line
            key, value = line.split("=", 1)
            assert key not in report, "duplicate key %s" % key
            report[key] = value
        return report
    finally:
        shutil.rmtree(root)


def make_tar(members, end=True):
    """A real tar. `end=False` omits the end-of-archive blocks.

    The framework's full-backup stream is tar, and the copy LocalTransport
    persists is however much of it arrived -- which is why `end=False` is a
    supported shape here and not a malformed-input case.
    """
    buf = io.BytesIO()
    tar = tarfile.open(fileobj=buf, mode="w")
    for name, content in members:
        info = tarfile.TarInfo(name)
        info.size = len(content)
        tar.addfile(info, io.BytesIO(content))
    if end:
        tar.close()
    else:
        # Flush the member blocks without the two 512-byte zero blocks close()
        # would append.
        tar.fileobj.flush()
    return buf.getvalue()


def check(name, condition, detail=""):
    if condition:
        print("ok   %s" % name)
    else:
        print("FAIL %s%s" % (name, (": " + detail) if detail else ""))
        failures.append(name)


# A set shaped like the one the framework really produces: a manifest, then the
# app's files under the `f` (getFilesDir) domain. The canary is planted in
# files/, which no exclusion rule covers.
CANARY_BODY = (CANARY_PREFIX + "run-1757736000").encode()
WALLET_BODY = (MARKER_PREFIX + "ldk-channel-manager").encode()
DECOY_BODY = (DECOY_PREFIX + "files-domain-decoy").encode()
PKG = "com.bittr.android.regtest"

CLEAN_MEMBERS = [
    ("apps/%s/_manifest" % PKG, b"1\n%s\n1\n" % PKG.encode()),
    ("apps/%s/f/backup_canary.txt" % PKG, CANARY_BODY),
]

# --- A plain tar is read, and the canary in it is found -----------------------
r = run({"1/_full/%s" % PKG: make_tar(CLEAN_MEMBERS)})
check("a_plain_tar_is_readable", r["READABLE"] == "yes", r["READABLE"])
check("a_plain_tar_is_identified_as_tar", ":tar" in r["CONTAINERS"], r["CONTAINERS"])
check("a_plain_tar_reports_its_entry_count", r["ENTRIES"] == "2", r["ENTRIES"])
check("the_canary_inside_a_tar_is_found",
      CANARY_PREFIX in r["CANARY"], r["CANARY"])
check("the_canary_hit_names_the_member_it_was_in",
      "backup_canary.txt" in r["CANARY"], r["CANARY"])
check("a_clean_tar_reports_no_wallet_marker",
      r["WALLET"] == "(none)", r["WALLET"])

# THE POINT OF THE WHOLE EXERCISE. The on-device `grep -rl` found nothing in a
# 4608-byte set; the decoded search has to find what is actually in one. Entry
# names carry the backup DOMAIN (`f/` is getFilesDir), which is the thing the
# exclusion rules operate on and was invisible before.
check("entry_names_are_reported_so_the_domains_are_visible",
      "apps/%s/f/backup_canary.txt" % PKG in r["ENTRY_NAMES"], r["ENTRY_NAMES"])

# --- The halt: a wallet marker in a decoded member ----------------------------
r = run({"1/_full/%s" % PKG: make_tar(
    CLEAN_MEMBERS + [("apps/%s/f/ldk/manager" % PKG, WALLET_BODY)])})
check("a_wallet_marker_inside_a_tar_is_found",
      MARKER_PREFIX in r["WALLET"], r["WALLET"])
check("the_wallet_hit_identifies_which_planted_file_reached_the_set",
      "ldk-channel-manager" in r["WALLET"], r["WALLET"])

# ...and it has to name the MEMBER, not just the blob. A tar stores contents
# verbatim, so a flat scan of the whole file finds the marker too and looks
# identical in a pass/fail sense -- but "a marker is somewhere in this 4608-byte
# file" is not a finding BIT-20 can act on, and `apps/<pkg>/f/ldk/manager` is:
# it names the domain, which is what the exclusion rules operate on. This is the
# assertion that makes the per-member read load-bearing rather than decorative.
check("the_wallet_hit_names_the_member_it_was_in",
      "!apps/%s/f/ldk/manager" % PKG in r["WALLET"], r["WALLET"])

# ...and the three prefixes stay separate. Collapsing any two of them would make
# the test's own canary fire the §5.3 halt, which is a spurious empirical result
# escalated to BIT-20.
check("a_canary_is_not_reported_as_a_wallet_marker",
      MARKER_PREFIX not in r["CANARY"], r["CANARY"])
r = run({"1/_full/%s" % PKG: make_tar(
    CLEAN_MEMBERS + [("apps/%s/f/decoy" % PKG, DECOY_BODY)])})
check("a_decoy_is_found_and_is_not_a_wallet_marker",
      DECOY_PREFIX in r["DECOY"] and r["WALLET"] == "(none)",
      "%s / %s" % (r["DECOY"], r["WALLET"]))

# --- A marker in a member NAME, with no content -------------------------------
#
# A file reaching the set with its contents empty is still that file reaching the
# set. A content-only search reports a clean run.
r = run({"1/_full/%s" % PKG: make_tar(
    [("apps/%s/f/%sname-only" % (PKG, MARKER_PREFIX), b"")])})
check("a_marker_in_a_member_name_is_found",
      MARKER_PREFIX in r["WALLET"], r["WALLET"])

# --- TRUNCATION: the shape every real CI run produces -------------------------
#
# LocalTransport writes the bytes it gets from the framework's socket, so what
# lands on disk has no end-of-archive blocks. If this case failed, the decoder
# would report an unreadable set on every genuine run while passing every
# well-formed case above -- green in the suite, useless on the device.
full = make_tar(CLEAN_MEMBERS + [("apps/%s/f/second" % PKG, b"x" * 900)],
                end=False)
r = run({"1/_full/%s" % PKG: full[:1800]})
check("truncated_tar_still_yields_its_members",
      int(r["ENTRIES"]) >= 2, r["ENTRIES"])
check("truncated_tar_is_still_readable", r["READABLE"] == "yes", r["READABLE"])
check("truncated_tar_says_it_was_truncated",
      "truncated" in r["NOTES"], r["NOTES"])
check("truncated_tar_still_finds_the_canary_it_did_carry",
      CANARY_PREFIX in r["CANARY"], r["CANARY"])

# A tar cut before its first member ends is NOT readable -- there is nothing to
# enumerate, and saying "readable, no marker" there is the failure this file
# exists to refuse.
r = run({"1/_full/%s" % PKG: full[:200]})
check("a_tar_cut_inside_its_first_header_is_not_readable",
      r["READABLE"] == "no", r["READABLE"])

# --- Compressed containers ----------------------------------------------------
#
# The hypothesis BIT-116 opened with: the bytes on disk need not hold contents
# verbatim, and compression alone defeats a literal search. Whether or not the
# real set turns out to be compressed, the decoder has to handle it, because a
# `no` from an unhandled container is indistinguishable from a `no` from a clean
# set.
r = run({"1/_full/%s" % PKG: gzip.compress(make_tar(CLEAN_MEMBERS))})
check("a_gzipped_tar_is_decoded", r["READABLE"] == "yes", r["READABLE"])
check("a_gzipped_tar_reports_both_layers",
      ":gzip" in r["CONTAINERS"] and ":tar" in r["CONTAINERS"], r["CONTAINERS"])
check("the_canary_inside_a_gzipped_tar_is_found",
      CANARY_PREFIX in r["CANARY"], r["CANARY"])
check("a_gzipped_canary_is_not_findable_in_the_raw_bytes",
      "#raw" not in r["CANARY"], "raw hit means the fixture was not compressed")

r = run({"1/_full/%s" % PKG: zlib.compress(make_tar(CLEAN_MEMBERS))})
check("a_zlib_deflated_tar_is_decoded", r["READABLE"] == "yes", r["READABLE"])
check("a_zlib_deflated_tar_reports_both_layers",
      ":zlib" in r["CONTAINERS"] and ":tar" in r["CONTAINERS"], r["CONTAINERS"])
check("the_wallet_marker_inside_a_deflated_tar_is_found",
      MARKER_PREFIX in run({"s": zlib.compress(make_tar(
          CLEAN_MEMBERS + [("apps/%s/f/ldk/manager" % PKG, WALLET_BODY)]))})["WALLET"])

# --- Undecodable input is reported as undecodable, never as clean -------------
r = run({"1/_full/%s" % PKG: bytes(range(256)) * 18})
check("an_undecodable_blob_is_not_readable", r["READABLE"] == "no", r["READABLE"])
check("an_undecodable_blob_is_named", "1/_full" in r["UNDECODED"], r["UNDECODED"])
check("an_undecodable_blob_reports_a_sample_so_the_format_is_identifiable",
      "\\x00\\x01\\x02" in r["SAMPLES"], r["SAMPLES"])

# A marker sitting in plaintext in a blob we could NOT decode must still be
# found. This is the control on the premise: if the on-device grep really was
# blind only because of the format, a raw hit here proves the raw search still
# works where it can.
r = run({"1/_full/%s" % PKG: b"\x00\xff\x01" + WALLET_BODY + b"\xfe" * 400})
check("a_plaintext_marker_in_an_undecodable_blob_is_still_found",
      MARKER_PREFIX in r["WALLET"], r["WALLET"])
check("a_raw_hit_is_tagged_as_raw", "#raw" in r["WALLET"], r["WALLET"])
check("finding_a_raw_marker_does_not_make_the_blob_readable",
      r["READABLE"] == "no", r["READABLE"])

# One decodable file and one that is not: READABLE must be `no`. The marker
# could be in the half that did not decode, so clearing the set on the strength
# of the half that did is the same unfalsifiable pass in a new shape.
r = run({"a/set": make_tar(CLEAN_MEMBERS), "b/blob": bytes(range(256)) * 4})
check("a_partly_undecodable_set_is_not_readable", r["READABLE"] == "no",
      r["READABLE"])
check("a_partly_undecodable_set_still_reports_what_it_did_decode",
      CANARY_PREFIX in r["CANARY"], r["CANARY"])

# --- The states that are not failures ----------------------------------------
#
# A zero-byte file is a set with nothing in it, which check-backup-set.sh already
# reports on its own terms. It is READ, so it is readable; calling it unreadable
# would relabel a real and understood state as a mystery.
r = run({"1/_full/%s" % PKG: b""})
check("a_zero_byte_set_is_readable_and_empty",
      r["READABLE"] == "yes" and ":empty" in r["CONTAINERS"],
      "%s / %s" % (r["READABLE"], r["CONTAINERS"]))
check("a_zero_byte_set_holds_no_markers", r["CANARY"] == "(none)", r["CANARY"])

# Nothing pulled at all is NOT readable: no file was searched, so no claim about
# markers can rest on it.
r = run({})
check("an_empty_directory_is_not_readable", r["READABLE"] == "no", r["READABLE"])
check("an_empty_directory_reports_zero_files", r["FILES"] == "0", r["FILES"])

# --- Every value is one line --------------------------------------------------
#
# The shell reads this output with `while read`, so a newline inside a value
# would become a new KEY=value line and a filename would be parsed as a field
# name. That is the same class of bug as the newline in `$present` that made the
# halt grep search only the first root (check-backup-set.sh, fifth pinned bug):
# it changes what is searched while looking identical in the result.
r = run({"1/_full/%s" % PKG: make_tar(
    [("apps/%s/f/two\nlines" % PKG, b"a\nb\nc" + CANARY_BODY)])})
check("a_newline_in_a_member_name_does_not_break_the_report",
      r["READABLE"] == "yes" and CANARY_PREFIX in r["CANARY"],
      "%s / %s" % (r["READABLE"], r["CANARY"]))
check("a_newline_in_a_member_name_stays_on_one_line",
      "\n" not in r["ENTRY_NAMES"], r["ENTRY_NAMES"])

# --- The prefixes are joined across three files now, not two ------------------
#
# BackupExclusionTest.kt writes them, check-backup-set.sh greps the device for
# them, and this file searches the decoded set for them. A drift in any one makes
# its search match nothing for ever, which reads as evidence and is not --
# exactly the argument test_check_backup_set.sh already makes for the first two.
def prefix_in(path, pattern):
    with open(os.path.join(HERE, path), encoding="utf-8") as handle:
        text = handle.read()
    import re
    found = re.search(pattern, text)
    return found.group(1) if found else None


for const in ("MARKER_PREFIX", "CANARY_PREFIX", "DECOY_PREFIX"):
    mine = prefix_in("decode-backup-set.py", r'%s = "([^"]+)"' % const)
    shell = prefix_in("check-backup-set.sh", r'%s="([^"]+)"' % const)
    kotlin = prefix_in(
        "../app/src/androidTest/kotlin/com/bittr/android/BackupExclusionTest.kt",
        r'%s = "([^"]+)"' % const)
    check("%s_agrees_across_all_three_files" % const,
          mine is not None and mine == shell == kotlin,
          "decoder=%s shell=%s test=%s" % (mine, shell, kotlin))

print()
if failures:
    print("%d test(s) failed: %s" % (len(failures), ", ".join(failures)))
    sys.exit(1)
print("All decode-backup-set.py tests passed.")
