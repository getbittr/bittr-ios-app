#!/usr/bin/env python3
"""Tests for check-instrumented-results.py — the gate on BIT-62's evidence.

    android/scripts/test_check_instrumented_results.py

WHY THIS EXISTS

The same reason test_ci_runs.py does, and it is worth restating because it is the
whole argument of BIT-62 turned on the tooling: a gate that misreports is worse
than no gate. This one's entire job is to refuse a green run that proved nothing,
so a bug in it does not look like a bug — it looks like a pass.

The cases below are therefore mostly the *bad* ones: no results at all, zero
tests, a skipped canary, a <failure/> with no message. Every one of them is a way
a real run could be green while the S-36 isolation claim is unverified.

No Gradle, no emulator: the seam is the results directory, so the fixtures are
XML files in a temp dir. That is also why this can run in the `build` job, seconds
in, rather than only after an emulator has booted.
"""

import importlib.util
import io
import contextlib
import pathlib
import sys
import tempfile

MODULE = pathlib.Path(__file__).with_name("check-instrumented-results.py")
spec = importlib.util.spec_from_file_location("check_instrumented_results", MODULE)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

FAILURES = []

PACKAGE = checker.PACKAGE
CANARY = "theCrossOriginIframeActuallyRan"


def check(what, ok, detail=""):
    print(f"{'ok  ' if ok else 'FAIL'}  {what}")
    if not ok:
        FAILURES.append(f"{what}{(': ' + str(detail)) if detail else ''}")


def testcase(test_id, outcome="passed"):
    classname, name = test_id.split("#")
    body = {
        "passed": "",
        "skipped": "<skipped/>",
        "failed": '<failure message="expected:&lt;[]&gt; but was:&lt;[bittrLnurl]&gt;"/>',
        "failed-without-message": "<failure/>",
    }[outcome]
    return f'<testcase classname="{classname}" name="{name}">{body}</testcase>'


def write_results(tmp, cases, filename="TEST-results.xml"):
    """Write one AGP-shaped result file into a connected/<device>/ layout."""
    device = tmp / "connected" / "debug" / "Pixel_6_API_34(AVD) - 14"
    device.mkdir(parents=True, exist_ok=True)
    (device / filename).write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<testsuite name="instrumented" tests="{len(cases)}">\n'
        + "\n".join(cases)
        + "\n</testsuite>\n"
    )
    return tmp / "connected"


def all_required(outcomes=None):
    """Every REQUIRED test as a <testcase>, with per-test outcome overrides."""
    outcomes = outcomes or {}
    return [testcase(t, outcomes.get(t.split("#")[1], "passed")) for t in checker.REQUIRED]


def run(results_dir):
    """Invoke main(); return (exit_code, combined output)."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        try:
            code = checker.main(["--results-dir", str(results_dir)])
        except SystemExit as exc:
            code = exc.code
    return code, out.getvalue()


def test_a_full_green_run_passes():
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(pathlib.Path(tmp), all_required())
        code, out = run(results)
    check("a run with all 9 required tests passing exits 0", code == 0, out)
    check("and says so", "ran and\npassed" in out or "ran and passed" in out, out)


def test_a_missing_results_directory_fails():
    # The headline case: Gradle green, nothing written. Before this gate existed
    # that was indistinguishable from a real pass.
    with tempfile.TemporaryDirectory() as tmp:
        code, out = run(pathlib.Path(tmp) / "connected")
    check("no results directory exits 1", code == 1, out)
    check("and names the vacuous-green failure", "no test ran" in out, out)


def test_an_empty_results_directory_fails():
    with tempfile.TemporaryDirectory() as tmp:
        empty = pathlib.Path(tmp) / "connected"
        empty.mkdir()
        code, out = run(empty)
    check("a results directory with no TEST-*.xml exits 1", code == 1, out)
    check("and explains that zero matched tests is a green task", "vacuous" in out, out)


def test_zero_testcases_in_a_wellformed_file_fails():
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(pathlib.Path(tmp), [])
        code, out = run(results)
    check("a result file containing no <testcase> exits 1", code == 1, out)
    check("and reports every required test as missing", "did not run at all" in out, out)


def test_a_skipped_canary_fails():
    # @Ignore on theCrossOriginIframeActuallyRan, everything else green. Gradle
    # exits 0. This is the precise state BIT-58 wrote that test to prevent.
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(pathlib.Path(tmp), all_required({CANARY: "skipped"}))
        code, out = run(results)
    check("a skipped canary exits 1", code == 1, out)
    check("and says a skipped test does not fail a build", "skipped" in out.lower(), out)
    check("and explains what the canary is for", "the iframe never got to look" in out, out)


def test_a_renamed_canary_fails():
    cases = [c for c in all_required() if CANARY not in c]
    cases.append(testcase(f"{PACKAGE}.CrossOriginIframeIsolationTest#theIframeRan"))
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(pathlib.Path(tmp), cases)
        code, out = run(results)
    check("a renamed required test exits 1", code == 1, out)
    check("and points at REQUIRED as the review point", "update REQUIRED" in out, out)


def test_an_extra_test_is_allowed():
    cases = all_required() + [testcase(f"{PACKAGE}.SomeNewTest#somethingElse")]
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(pathlib.Path(tmp), cases)
        code, out = run(results)
    check("adding a test does not break the gate", code == 0, out)
    check("and it is labelled extra", "(extra)" in out, out)


def test_a_failure_without_a_message_is_still_a_failure():
    # "" is falsy. Storing the message directly would make this test read as
    # passed — the bug the gate is supposed to catch, inside the gate.
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(
            pathlib.Path(tmp), all_required({CANARY: "failed-without-message"})
        )
        code, out = run(results)
    check("a <failure/> with no message exits 1", code == 1, out)
    check("and is reported as FAILED", "FAILED" in out, out)


def test_a_pass_does_not_override_a_failure_for_the_same_test():
    # Two devices, or a re-run: one red, one green. The red one wins.
    cases = all_required({CANARY: "failed"}) + [
        testcase(f"{PACKAGE}.CrossOriginIframeIsolationTest#{CANARY}", "passed")
    ]
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(pathlib.Path(tmp), cases)
        code, out = run(results)
    check("a green second attempt cannot mask a red first one", code == 1, out)


def test_results_are_found_across_multiple_files():
    # AGP writes one file per device, and has moved the directory between
    # versions; the reader globs rather than assuming a path.
    with tempfile.TemporaryDirectory() as tmp:
        required = sorted(checker.REQUIRED)
        write_results(pathlib.Path(tmp), [testcase(t) for t in required[:4]],
                      filename="TEST-part-one.xml")
        results = write_results(pathlib.Path(tmp), [testcase(t) for t in required[4:]],
                                filename="TEST-part-two.xml")
        code, out = run(results)
    check("required tests split across two files still pass", code == 0, out)


def test_a_truncated_result_file_fails():
    # The emulator went away mid-run. A parse error must be a failed run, not a
    # file the reader shrugs past on its way to reporting green.
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(pathlib.Path(tmp), all_required())
        broken = next(results.rglob("TEST-*.xml"))
        broken.write_text(broken.read_text()[: len(broken.read_text()) // 2])
        code, out = run(results)
    check("unparseable XML exits 1", code == 1, out)
    check("and blames an unfinished run", "did not finish writing" in out, out)


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("all green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
