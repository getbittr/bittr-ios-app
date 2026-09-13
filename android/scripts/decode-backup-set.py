#!/usr/bin/env python3
"""Read a pulled backup set, rather than grepping its bytes.

    python3 android/scripts/decode-backup-set.py <dir-of-pulled-set-files>

WHY THIS EXISTS (BIT-116)

check-backup-set.sh decided the BIT-20 §5.3 halt with `grep -rl` over the
transport's on-disk blob. The run for 9dc0b64 measured that blob for the first
time: 4608 bytes under

    /data/data/com.android.localtransport/files/1/_full/com.bittr.android.regtest

and NONE of the three BIT101 prefixes was greppable in it -- not the wallet
marker, not the canary, not the decoys. The canary is planted in `files/`, which
no rule excludes, so it belongs in any set that carries file contents verbatim.
Its absence from a set that demonstrably holds 4608 bytes says the search was
wrong, not that the set was clean.

That is the serious part, and it is why this file is not an enhancement. A full
backup reaches the transport as a stream, and nothing guarantees the bytes on
disk hold file contents as plaintext -- a header-prefixed archive puts the name
somewhere a content grep still finds, but compression puts NOTHING where a
literal search finds it. The `grep -rl "$MARKER_PREFIX"` that decides the halt is
the same search over the same bytes. So wallet material could have been sitting
in that set and the check would have reported exactly what it reported: no
marker, exit 0. **A gate that cannot fail is not a gate**, and a non-halt from
one is not evidence of no leak.

So: decode the container, enumerate what is actually in it, and search the
DECODED members. Then a clean result means something and a halt can fire.

WHY A SEPARATE FILE, AND WHY PYTHON

Same argument as check-backup-set.sh's own header. This decides a halt, so it
gets tested for it, and the seam has to be something a test can drive without an
emulator. check-backup-set.sh's seam is `adb`; this file's seam is a DIRECTORY OF
BYTES, which means test_decode_backup_set.py can hand it real tar, real gzip and
real zlib built in-process and assert on what comes back. Every branch below is
reachable in milliseconds. Inline in the shell script, the decode would be
reachable only by booting an emulator and hoping the device produced the shape
you wanted to test.

Python because the decoding is the whole job and `tarfile`/`gzip`/`zlib` do it
correctly, including the truncation case that matters here (see TRUNCATION).

WHAT IT REPORTS, AND WHY THE SHELL STILL DECIDES

Only `KEY=value` lines, one per line, values flattened to a single line. The
verdict stays in check-backup-set.sh because that file's header says it decides
the halt and everything about how it says so -- annotations, exit codes, the
four outcomes -- lives there. This one answers "what is in the set", which is
the question that had no instrument.

Exit status is 0 whenever the input was read, INCLUDING when nothing could be
decoded. Failing here would turn "we could not read the set" into a red build,
and the whole point of this exercise is that those two are different facts.
Non-zero is reserved for being unable to do its job at all (bad arguments).

TRUNCATION IS THE EXPECTED CASE, NOT AN ERROR

LocalTransport writes the bytes it receives from the framework's socket
(`sendBackupData`), so what lands on disk is a PREFIX of the stream. A tar
written that way need not carry the two zero blocks that mark end-of-archive,
and `tarfile` raises when it runs off the end. Treating that as "not a tar" would
put us straight back to reporting an unreadable set -- so members are read one at
a time and whatever was read before the exception is kept and reported, with the
truncation noted. A partial answer about a real set beats a clean answer about
nothing, which is the mistake this whole issue is a record of.
"""

import os
import re
import sys
import gzip
import zlib
import tarfile
import io

# The three prefixes, which must agree with BackupExclusionTest.kt and with
# check-backup-set.sh. test_decode_backup_set.py pins them against both files for
# the same reason test_check_backup_set.sh does: a drift makes the searches below
# match nothing for ever, and "matched nothing" is precisely the reading that
# this file exists because it cannot be trusted.
MARKER_PREFIX = "BIT101-WALLET-MARKER-"
CANARY_PREFIX = "BIT101-CANARY-MARKER-"
DECOY_PREFIX = "BIT101-DECOY-MARKER-"

# A decoded set is a backup of an app, not a disk image. If a member is larger
# than this the interesting part is that it is there at all, and reading all of
# it into memory to search for a 21-byte prefix buys nothing. Sets seen so far
# are measured in kilobytes.
MAX_MEMBER_BYTES = 8 * 1024 * 1024

# How much of an UNDECODABLE file to describe in the report. The point of the
# sample is to answer "what is this, then?" on the next run without the job log,
# which answers 403 on this public repo -- so it has to be small enough to sit in
# a one-line annotation and still show a magic number.
SAMPLE_BYTES = 64

# Entry names are the single most useful thing in the report: `apps/<pkg>/f/...`
# tells you the domain each file was backed up under, which is what the exclusion
# rules operate on. Capped so one large set cannot push everything else out of
# the annotation.
MAX_ENTRY_NAMES = 40

# Containers we unwrap, deepest first in the report. Two levels is enough for
# every shape the framework produces (tar, or a compressed tar); the depth guard
# is there so a crafted or corrupt input cannot loop.
MAX_DEPTH = 3


def _flatten(value):
    """One line, always. These lines are parsed by a shell `while read`.

    A newline in a value would silently become a new KEY=value line and the
    shell would read a filename as a key -- the same class of bug as the
    newline-in-$present one that made the halt grep search one root (see
    check-backup-set.sh). Tabs and CRs go too, so a filename cannot fake a field
    separator.
    """
    return re.sub(r"\s+", " ", str(value).replace("\x00", " ")).strip()


def _sample(data):
    """A printable description of bytes we could not decode.

    Printable ASCII kept as-is and everything else hex-escaped, so a magic
    number is legible (`\\x1f\\x8b` reads as gzip at a glance) without the
    annotation carrying raw control characters.
    """
    out = []
    for byte in data[:SAMPLE_BYTES]:
        char = chr(byte)
        if 32 <= byte < 127 and char not in "\\":
            out.append(char)
        else:
            out.append("\\x%02x" % byte)
    return "".join(out)


def _find_markers(where, data, hits):
    """Record every BIT101 marker in `data`, tagged with where it was found.

    Searched as bytes so this works on a decoded member and on an undecodable
    blob alike. The matched text is captured up to 32 characters past the prefix
    and reported, not just the fact of a match: BackupExclusionTest stamps each
    marker, so the captured value identifies WHICH planted file reached the set.
    That is what a halt has to hand back to BIT-20 -- "a marker was found" is not
    a finding anyone can act on.
    """
    for name, prefix in (
        ("WALLET", MARKER_PREFIX),
        ("CANARY", CANARY_PREFIX),
        ("DECOY", DECOY_PREFIX),
    ):
        for match in re.finditer(
            re.escape(prefix.encode()) + rb"[\x20-\x7e]{0,32}", data
        ):
            hits[name].append(
                "%s=%s" % (where, match.group(0).decode("ascii", "replace"))
            )


def _read_tar(label, data, report, hits, depth):
    """Enumerate a tar, keeping whatever was read before it ran out.

    Returns True if this really was a tar (at least one member came back).
    `r|` rather than `r:` deliberately: the stream reader does not seek to the
    end for a member index, so it yields the members a truncated archive DOES
    have instead of failing on the ones it does not.
    """
    entries = 0
    try:
        stream = tarfile.open(fileobj=io.BytesIO(data), mode="r|")
    except (tarfile.TarError, EOFError):
        return False

    try:
        while True:
            # `TarFile.next()` rather than iteration: in stream mode each
            # member's data must be read before the next header, and next() is
            # the API that guarantees that order. It returns None at
            # end-of-archive, which a COMPLETE tar reaches and a truncated one
            # does not -- the truncated one throws instead, and that is the
            # case handled below.
            member = stream.next()
            if member is None:
                break
            entries += 1
            report["entry_names"].append(
                "%s(%d)" % (member.name, member.size)
            )
            # The name is searched as well as the content. A backup of a file
            # called BIT101-CANARY-MARKER-... with its contents stripped is
            # still that file reaching the set, and a content-only search would
            # miss it.
            _find_markers("%s!%s#name" % (label, member.name),
                          member.name.encode(), hits)
            if not member.isfile() or member.size > MAX_MEMBER_BYTES:
                continue
            handle = stream.extractfile(member)
            if handle is None:
                continue
            content = handle.read()
            report["decoded_bytes"] += len(content)
            _find_markers("%s!%s" % (label, member.name), content, hits)
            # A tar inside a tar is not a shape the framework produces, but
            # nesting is cheap to allow and the alternative is a silent miss.
            if depth + 1 < MAX_DEPTH and content[:2] in (b"\x1f\x8b",):
                _analyze("%s!%s" % (label, member.name), content,
                         report, hits, depth + 1)
    except (tarfile.TarError, EOFError, OSError, zlib.error):
        # See TRUNCATION in the module docstring. This is the EXPECTED end of a
        # set the transport wrote from a live socket, not a failure: everything
        # counted above is real and stays in the report.
        if entries:
            report["notes"].append("%s:truncated-after-%d-entries" % (label, entries))
        else:
            return False

    if not entries:
        return False
    report["containers"].append("%s:tar" % label)
    report["entries"] += entries
    return True


def _analyze(label, data, report, hits, depth=0):
    """Identify one blob, decode it, and recurse into what it unwrapped to."""
    if depth >= MAX_DEPTH:
        report["notes"].append("%s:nesting-too-deep" % label)
        return False

    if not data:
        report["containers"].append("%s:empty" % label)
        # Deliberately readable. A zero-byte file is not an unreadable
        # container; it is a set with nothing in it, which is a real and
        # different state that check-backup-set.sh already reports separately.
        return True

    # Searched BEFORE any decode, so a set that does hold plaintext is reported
    # as such. That is the control on this whole file: if the markers turn out
    # to be findable in the raw bytes after all, the raw hit says so and the
    # premise that the on-device grep was blind gets checked rather than
    # assumed.
    #
    # `#raw` ONLY at depth 0, because that is the only depth where it means what
    # it says. Every layer runs this scan, so tagging an already-decompressed
    # layer `#raw` would report a canary recovered by inflating as one that was
    # sitting in plaintext on disk -- which is the precise claim this tag exists
    # to settle, inverted. Deeper layers get `#decoded`.
    _find_markers("%s%s" % (label, "#raw" if depth == 0 else "#decoded"),
                  data, hits)

    if _read_tar(label, data, report, hits, depth):
        return True

    if data[:2] == b"\x1f\x8b":
        try:
            inner = gzip.decompress(data)
        except (OSError, EOFError, zlib.error):
            # A truncated gzip member still has a decodable prefix, and a set
            # written from a socket is exactly where a truncated one would come
            # from -- so fall back to the incremental path rather than calling
            # the whole file unreadable.
            inner = _inflate_partial(data, wbits=16 + zlib.MAX_WBITS)
        if inner:
            report["containers"].append("%s:gzip" % label)
            return _analyze("%s~gunzip" % label, inner, report, hits, depth + 1)

    # zlib/deflate: the `adb backup` shape, and what a transport that compresses
    # would most plausibly produce. Checked by the header's own validity rule
    # rather than by a magic byte, because deflate has no magic number.
    if len(data) >= 2 and data[0] & 0x0F == 8 and \
            ((data[0] << 8) | data[1]) % 31 == 0:
        inner = _inflate_partial(data, wbits=zlib.MAX_WBITS)
        if inner:
            report["containers"].append("%s:zlib" % label)
            return _analyze("%s~inflate" % label, inner, report, hits, depth + 1)

    report["containers"].append("%s:unknown" % label)
    report["undecoded"].append(label)
    report["samples"].append("%s=[%s]" % (label, _sample(data)))
    return False


def _inflate_partial(data, wbits):
    """Inflate as much as decompresses, and keep it if anything did.

    `zlib.decompress` is all-or-nothing and a stream cut mid-member throws away
    everything. The object API keeps the prefix, which for our purposes is the
    whole point: the members that DID arrive are the ones a marker could be
    hiding in.
    """
    obj = zlib.decompressobj(wbits)
    out = bytearray()
    # Fed in chunks on purpose: a single `decompress(data)` that throws discards
    # everything it had already produced, which for a stream cut mid-member is
    # the entire set. Chunking keeps every byte decoded before the cut.
    for start in range(0, len(data), 4096):
        try:
            out += obj.decompress(data[start:start + 4096])
        except zlib.error:
            break
        if len(out) > MAX_MEMBER_BYTES:
            break
    return bytes(out)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: decode-backup-set.py <dir-of-pulled-set-files>\n")
        return 2
    root = argv[1]
    if not os.path.isdir(root):
        sys.stderr.write("decode-backup-set.py: not a directory: %s\n" % root)
        return 2

    report = {
        "containers": [],
        "entry_names": [],
        "entries": 0,
        "decoded_bytes": 0,
        "undecoded": [],
        "samples": [],
        "notes": [],
    }
    hits = {"WALLET": [], "CANARY": [], "DECOY": []}

    files = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for filename in sorted(filenames):
            files.append(os.path.join(dirpath, filename))
    files.sort()

    raw_bytes = 0
    for path in files:
        try:
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError as exc:
            report["notes"].append("unreadable:%s:%s" % (path, exc.__class__.__name__))
            continue
        raw_bytes += len(data)
        _analyze(os.path.relpath(path, root), data, report, hits)

    # READABLE is the field the shell's verdict turns on, and it is deliberately
    # strict: every file pulled has to have been decoded into something we can
    # enumerate. A set where one blob decoded and another did not is NOT a set
    # this check can clear -- the marker could be in the half it could not read,
    # which is the exact failure being fixed here. `no` with zero files is right
    # too: nothing was read, so nothing was searched.
    readable = "yes" if files and not report["undecoded"] else "no"

    out = [
        ("FILES", len(files)),
        ("RAW_BYTES", raw_bytes),
        ("READABLE", readable),
        ("CONTAINERS", " ".join(report["containers"]) or "(none)"),
        ("ENTRIES", report["entries"]),
        ("DECODED_BYTES", report["decoded_bytes"]),
        ("ENTRY_NAMES",
         " ".join(report["entry_names"][:MAX_ENTRY_NAMES]) or "(none)"),
        ("ENTRY_NAMES_TRUNCATED",
         "yes" if len(report["entry_names"]) > MAX_ENTRY_NAMES else "no"),
        ("UNDECODED", " ".join(report["undecoded"]) or "(none)"),
        ("SAMPLES", " ".join(report["samples"]) or "(none)"),
        ("NOTES", " ".join(report["notes"]) or "(none)"),
        ("WALLET", " ".join(hits["WALLET"]) or "(none)"),
        ("CANARY", " ".join(hits["CANARY"]) or "(none)"),
        ("DECOY", " ".join(hits["DECOY"]) or "(none)"),
    ]
    for key, value in out:
        sys.stdout.write("%s=%s\n" % (key, _flatten(value)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
