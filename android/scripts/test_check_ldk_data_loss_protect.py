#!/usr/bin/env python3
"""Negative controls for check-ldk-data-loss-protect.py.

    python3 android/scripts/test_check_ldk_data_loss_protect.py

Runs in the `build` job, seconds in, for the reason the other script tests give:
the thing being guarded against is a checker that passes without checking, and
that is invisible to every run where the real binary happens to be fine.

The case this exists for specifically: every marker this script looks for is
currently present, so the ONLY runs it will ever have are green ones, and a
green run of a broken checker is indistinguishable from a green run of a working
one. These build AARs that are deliberately wrong and require a red.
"""

import importlib.util
import io
import pathlib
import subprocess
import sys
import tempfile
import zipfile

SCRIPT = pathlib.Path(__file__).resolve().parent / "check-ldk-data-loss-protect.py"


def _load_checker():
    """The checker module, loaded from a filename `import` cannot spell.

    The marker lists are read from the checker rather than re-typed here: a copy
    would drift, and a drifted copy would make these controls pass against a
    checker that looks for something else entirely. The hyphens in the script's
    name are why this is a loader dance and not an `import`.
    """
    spec = importlib.util.spec_from_file_location("check_ldk_data_loss_protect", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CHECKER = _load_checker()


def library(required=None, extra=b""):
    """A fake libldk_node.so carrying `required` markers plus `extra`."""
    markers = CHECKER.REQUIRED_MARKERS if required is None else required
    return b"\x7fELF" + b"".join(m for m, _ in markers) + extra + b"\x00" * 64


def aar(blob, path, abis=("arm64-v8a", "armeabi-v7a", "x86_64")):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for abi in abis:
            archive.writestr(f"jni/{abi}/libldk_node.so", blob)
    path.write_bytes(buffer.getvalue())
    return path


def run(path):
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--aar", str(path)],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


def main():
    failures = []
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)

        # 1. The positive control. Without this, every case below could be
        #    passing because the script errors out on ANY input, which would make
        #    the whole file a check that the script is broken.
        status, output = run(aar(library(), root / "good.aar"))
        if status != 0:
            failures.append(
                "A library carrying every required marker and no forbidden one "
                f"was rejected (exit {status}). The negative controls below prove "
                f"nothing if the positive one fails.\n{output}"
            )

        # 2. Each required marker, dropped one at a time. Dropping only the first
        #    would let the other four rot unchecked — which is the shape of the
        #    BdkAccountXpubParityTest bug this repo has already paid for once.
        for index, (marker, _) in enumerate(CHECKER.REQUIRED_MARKERS):
            without = [m for i, m in enumerate(CHECKER.REQUIRED_MARKERS) if i != index]
            status, output = run(aar(library(without), root / f"missing{index}.aar"))
            if status == 0:
                failures.append(
                    f"A library MISSING {marker.decode()!r} was accepted. That "
                    "marker is load-bearing for wallet-security-properties.md §5 "
                    "and its disappearance has to be a red."
                )

        # 3. The forbidden marker, which is the assertion that
        #    option_data_loss_protect is REQUIRED rather than merely offered.
        for marker, _ in CHECKER.FORBIDDEN_MARKERS:
            status, output = run(aar(library(extra=marker), root / "forbidden.aar"))
            if status == 0:
                failures.append(
                    f"A library containing {marker.decode()!r} was accepted. The "
                    "absence of the optional setter is the entire evidence that "
                    "the feature bit is compulsory; without this case the script "
                    "would say 'required' about a binary that says 'optional'."
                )

        # 4. An AAR with no native library at all. The failure mode this rules
        #    out is the worst one available: a packaging change that removes the
        #    .so would leave zero libraries to check, zero markers missing, and a
        #    green run reporting "0 ABI(s) checked".
        empty = root / "empty.aar"
        with zipfile.ZipFile(empty, "w") as archive:
            archive.writestr("classes.jar", b"not a library")
        status, output = run(empty)
        if status == 0:
            failures.append(
                "An AAR with no libldk_node.so was accepted. Nothing was read, so "
                "nothing was checked, and the run would have reported a pass."
            )

        # 5. One ABI good, one stripped. The check has to be per-library: a
        #    32-bit build that lost the behaviour while arm64 kept it would ship
        #    to exactly the cheap handsets least able to absorb a lost channel.
        mixed = root / "mixed.aar"
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("jni/arm64-v8a/libldk_node.so", library())
            archive.writestr(
                "jni/armeabi-v7a/libldk_node.so",
                library(list(CHECKER.REQUIRED_MARKERS)[1:]),
            )
        mixed.write_bytes(buffer.getvalue())
        status, output = run(mixed)
        if status == 0:
            failures.append(
                "An AAR whose armeabi-v7a library is missing a required marker "
                "was accepted because arm64-v8a had it. Every shipped ABI has to "
                "carry the behaviour."
            )

    if failures:
        for failure in failures:
            print(f"::error::{failure}")
            print(failure)
        print(f"test_check_ldk_data_loss_protect: {len(failures)} FAILED.")
        return 1

    print("test_check_ldk_data_loss_protect: all cases passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
