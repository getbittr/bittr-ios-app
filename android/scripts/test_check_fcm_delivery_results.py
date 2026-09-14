#!/usr/bin/env python3
"""Tests for check-fcm-delivery-results.py — BIT-135's gate on its own evidence.

    android/scripts/test_check_fcm_delivery_results.py

WHY THIS EXISTS

The same argument as test_check_wallet_instrumented_results.py: a gate whose only
job is to refuse a green run that proved nothing does not fail visibly when it is
buggy — it fails as a pass.

This gate has one failure mode the wallet gate does not, and it is the likely
one. Its job selects tests by ANNOTATION rather than by running everything, so
the empty-run case is one typo away rather than a rename away — and an empty
instrumented run here does not merely prove less. It means the host phase is
about to send a real message to a device that has no wallet and no hand-off,
observe no wake, and be right about a device nothing prepared.

Two of the cases below are not about XML at all:

  * every REQUIRED entry must name a method that exists in FcmDeliveryTest.kt —
    the rename trap, caught in seconds here rather than after an AVD boot, and
  * REQUIRED must be disjoint from check-wallet-instrumented-results.py's, which
    is the constraint that keeps the annotation split honest: a method listed in
    both would be required by a job whose image can never satisfy it.

No Gradle, no emulator: the seam is a results directory, so the fixtures are XML
in a temp dir.
"""

import contextlib
import importlib.util
import io
import pathlib
import re
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent


def load(filename, module_name):
    spec = importlib.util.spec_from_file_location(module_name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


checker = load("check-fcm-delivery-results.py", "check_fcm_delivery_results")
wallet_checker = load(
    "check-wallet-instrumented-results.py", "check_wallet_instrumented_results"
)

FAILURES = []

REQUIRED = sorted(checker.REQUIRED)
CANARY = checker.CANARY

SOURCE = (
    HERE.parents[0]
    / "app/src/androidTest/kotlin/com/bittr/android/FcmDeliveryTest.kt"
)


def check(what, ok, detail=""):
    print(f"{'ok  ' if ok else 'FAIL'}  {what}")
    if not ok:
        FAILURES.append(f"{what}{(': ' + str(detail)) if detail else ''}")


def testcase(test_id, outcome="passed"):
    classname, name = test_id.split("#")
    body = {
        "passed": "",
        "skipped": "<skipped/>",
        "failed": '<failure message="Play services is not installed on this device"/>',
    }[outcome]
    return f'<testcase classname="{classname}" name="{name}" time="0.1">{body}</testcase>'


def write_results(directory, tests, system_out=""):
    """One TEST-*.xml holding `tests`, with an optional <system-out>."""
    directory.mkdir(parents=True, exist_ok=True)
    out = f"<system-out><![CDATA[{system_out}]]></system-out>" if system_out else ""
    (directory / "TEST-fcm.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<testsuite name="fcm" tests="{len(tests)}">'
        + "".join(tests)
        + out
        + "</testsuite>\n"
    )


def run(results_dir):
    """The checker's exit code and everything it printed."""
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        status = checker.main(["--results-dir", str(results_dir)])
    return status, captured.getvalue()


def scenario(name, tests, system_out="", expect_zero=False, expect_in=()):
    with tempfile.TemporaryDirectory() as temporary:
        directory = pathlib.Path(temporary) / "connected"
        write_results(directory, tests, system_out)
        status, output = run(directory)

    if expect_zero:
        check(name, status == 0, f"exit {status}\n{output}")
    else:
        check(name, status == 1, f"exit {status} (expected 1)\n{output}")
    for fragment in expect_in:
        check(
            f"{name} — the report says '{fragment}'",
            fragment in output,
            output,
        )


# ---------------------------------------------------------------------------
# The green run
# ---------------------------------------------------------------------------

scenario(
    "a run with all three required tests passing is accepted",
    [testcase(t) for t in REQUIRED],
    system_out=(
        "FCM_DELIVERY_IMAGE playServices=24.45.19\n"
        "FCM_DELIVERY_TOKEN handed off (163 chars); value not logged.\n"
    ),
    expect_zero=True,
    expect_in=("all 3 required tests ran",),
)

# The positive control for the leak detector below: the length-only line the
# suite really prints must NOT be mistaken for a token. Without this, a detector
# that flagged everything would pass every negative case and fail every real run.
scenario(
    "the length-only token line is not mistaken for a leaked token",
    [testcase(t) for t in REQUIRED],
    system_out="FCM_DELIVERY_TOKEN handed off (163 chars); value not logged.\n",
    expect_zero=True,
)

# ---------------------------------------------------------------------------
# The empty run — the one this job is most likely to produce
# ---------------------------------------------------------------------------

scenario(
    "a run that matched no tests at all is refused",
    [],
    expect_in=("annotation", "RequiresPlayServices"),
)

with tempfile.TemporaryDirectory() as temporary:
    empty = pathlib.Path(temporary) / "connected"
    empty.mkdir(parents=True)
    status, output = run(empty)
    check(
        "a results directory with no XML in it is refused",
        status == 1,
        f"exit {status}\n{output}",
    )

with tempfile.TemporaryDirectory() as temporary:
    absent = pathlib.Path(temporary) / "never-created"
    status, output = run(absent)
    check(
        "a results directory that does not exist is refused",
        status == 1,
        f"exit {status}\n{output}",
    )

# ---------------------------------------------------------------------------
# Each required test, individually missing
# ---------------------------------------------------------------------------

for dropped in REQUIRED:
    scenario(
        f"a run missing {dropped.split('#')[1]} is refused",
        [testcase(t) for t in REQUIRED if t != dropped],
        expect_in=(dropped,),
    )

# ---------------------------------------------------------------------------
# Skipped and failed
# ---------------------------------------------------------------------------

scenario(
    "a skipped required test is refused",
    [testcase(REQUIRED[0], "skipped")] + [testcase(t) for t in REQUIRED[1:]],
    expect_in=("skipped",),
)

scenario(
    "a failed required test is refused, with its message",
    [testcase(REQUIRED[0], "failed")] + [testcase(t) for t in REQUIRED[1:]],
    expect_in=("Play services is not installed on this device",),
)

# The canary. Its failure has to say that everything else in the run — including
# the host phase's delivery verdict — is unreadable, not merely that one test
# failed.
scenario(
    "a failed canary says the delivery verdict is unreadable too",
    [testcase(CANARY, "failed")] + [testcase(t) for t in REQUIRED if t != CANARY],
    expect_in=("google_apis", "same silence"),
)

# A test that appears twice, once green and once red, is red. No retry-as-a-pass.
scenario(
    "a required test that passed once and failed once is refused",
    [testcase(t) for t in REQUIRED] + [testcase(REQUIRED[0], "failed")],
    expect_in=(REQUIRED[0],),
)

# ---------------------------------------------------------------------------
# The token must never reach the XML
# ---------------------------------------------------------------------------
#
# These results are uploaded as an artefact and quoted into annotations, and
# shared/docs/privacy-disclosure.md lists the registration token as a per-install
# device identifier. The whole reason the token route was chosen over a topic is
# that it costs no code in any shipped artefact — a promise worth nothing if a
# future diagnostic println puts the value in a result file.

FAKE_TOKEN = "cZ9" + "A" * 120 + ":APA91bH" + "x" * 40

scenario(
    "a token printed into <system-out> is refused",
    [testcase(t) for t in REQUIRED],
    system_out=f"FCM_DELIVERY_TOKEN handed off: {FAKE_TOKEN}\n",
    expect_in=("per-install device identifier",),
)

# ---------------------------------------------------------------------------
# The rename trap, and the disjointness constraint
# ---------------------------------------------------------------------------

source = SOURCE.read_text() if SOURCE.is_file() else ""
check(
    "FcmDeliveryTest.kt is where this file thinks it is",
    bool(source),
    f"looked at {SOURCE} — if the class moved, every check below is vacuous",
)

declared = set(re.findall(r"fun\s+([A-Za-z0-9_]+)\s*\(", source))
for test_id in REQUIRED:
    classname, method = test_id.split("#")
    check(
        f"REQUIRED names a method that exists: {method}",
        method in declared,
        f"{method} is not declared in {SOURCE.name}. A rename that updated only one "
        f"side leaves this gate requiring a test that can never run, which reds the "
        f"job for a reason that is not about FCM.",
    )
    check(
        f"REQUIRED names the class the source declares: {classname}",
        f"class {classname.rsplit('.', 1)[1]}" in source,
        source[:200],
    )

check(
    "the class carries the annotation the job filters on",
    "@RequiresPlayServices" in source,
    "Without it, ci-fcm-delivery.sh's annotation filter matches nothing and this "
    "job is vacuously green — and ci-wallet-instrumented.sh's notAnnotation filter "
    "stops excluding it, so the wallet job runs it on AOSP and goes red.",
)

overlap = checker.REQUIRED & wallet_checker.REQUIRED
check(
    "no test is required by both this gate and the wallet gate",
    not overlap,
    f"{sorted(overlap)} — a method required by both is required by a job whose "
    f"image can never satisfy it. The two suites run on google_apis and on "
    f"default, and the annotation filter is what keeps them apart.",
)

check(
    "the wallet gate does not require anything from FcmDeliveryTest",
    not any("FcmDeliveryTest" in t for t in wallet_checker.REQUIRED),
    "FcmDeliveryTest is excluded from that job by "
    "-Pandroid.testInstrumentationRunnerArguments.notAnnotation, so requiring it "
    "there would fail every wallet run with 'these tests did not run at all'.",
)

print()
if FAILURES:
    print(f"test_check_fcm_delivery_results: {len(FAILURES)} check(s) FAILED.")
    for failure in FAILURES:
        print(f"  - {failure}")
    sys.exit(1)
print("test_check_fcm_delivery_results: all checks passed.")
