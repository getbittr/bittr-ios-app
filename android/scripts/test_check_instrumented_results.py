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
        # How AGP actually writes a connected-test failure: no `message`, no
        # `type`, the whole stack trace in the body. Run 68's two reds were this
        # shape and the reader called them "(no message)".
        "failed-in-body": (
            "<failure>org.junit.ComparisonFailure: A page on a non-allowlisted "
            "origin must find no bridge object at all. Found: "
            "[&quot;postMessage:frames&quot;] expected:&lt;...&gt; but was:&lt;...&gt;\n"
            "\tat org.junit.Assert.assertEquals(Assert.java:117)\n"
            "\tat com.bittr.android.feature.website.ThirdPartyIsolationTest."
            "aThirdPartyPageFindsNoBridgeToPostTo(ThirdPartyIsolationTest.kt:198)\n"
            "</failure>"
        ),
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
    check(
        f"a run with all {len(checker.REQUIRED)} required tests passing exits 0",
        code == 0,
        out,
    )
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


def test_a_failure_whose_message_is_in_the_body_is_read_from_the_body():
    # The reason run 68 cost an extra emulator run. AGP's connected-test reporter
    # writes no `message` attribute at all, so the annotation — the only artefact
    # readable without repository auth — said "(no message)" for both reds. The
    # cause was named in the body, three inches away.
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(
            pathlib.Path(tmp),
            all_required({"aThirdPartyPageFindsNoBridgeToPostTo": "failed-in-body"}),
        )
        code, out = run(results)
    check("a <failure> with its message in the body exits 1", code == 1, out)
    blob = "\n".join(annotations(out))
    check("and the annotation carries the finding, not '(no message)'",
          "postMessage:frames" in blob and "(no message)" not in blob, blob)
    check("and stops before the stack frames",
          "org.junit.Assert.assertEquals" not in blob, blob)


def test_a_long_assertion_message_is_not_cut_before_its_finding():
    # These assertions state the rule first and the observed value last, so a
    # 300-character cut kept the paragraph and dropped the answer.
    prose = "why this matters, at length. " * 12  # ~350 chars before the finding
    with tempfile.TemporaryDirectory() as tmp:
        classname = f"{PACKAGE}.ThirdPartyIsolationTest"
        name = "aThirdPartyPageFindsNoBridgeToPostTo"
        verbose = (f'<testcase classname="{classname}" name="{name}">'
                   f'<failure message="{prose}Found: [SOME_BRIDGE]"/></testcase>')
        cases = [c for c in all_required() if name not in c] + [verbose]
        results = write_results(pathlib.Path(tmp), cases)
        code, out = run(results)
    check("a verbose assertion message still exits 1", code == 1, out)
    blob = "\n".join(annotations(out))
    check("and the tail of the message survives into the annotation",
          "Found: [SOME_BRIDGE]" in blob, blob)


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


def annotations(out):
    """Just the ::error:: lines — what a reader without repository auth gets."""
    return [line for line in out.splitlines() if line.startswith("::error")]


def test_a_failure_annotation_names_the_failing_tests():
    # Run 27 (518cdd7) annotated exactly "These tests failed:" and nothing else,
    # because GitHub cuts a workflow command at the first newline. The names were
    # in the job log and the uploaded report, both of which need repository auth.
    # An annotation is the one artefact of a run that does not, so the detail has
    # to survive the escape — this asserts it does.
    with tempfile.TemporaryDirectory() as tmp:
        cases = all_required({"theHardeningBaselineIsAppliedToTheRealWebView": "failed"})
        results = write_results(pathlib.Path(tmp), cases)
        code, out = run(results)
    check("a failing required test exits 1", code == 1, out)
    lines = annotations(out)
    check("it produces exactly one ::error:: annotation", len(lines) == 1, lines)
    blob = "\n".join(lines)
    check(
        "and the annotation names the failing test, not just a heading",
        "theHardeningBaselineIsAppliedToTheRealWebView" in blob,
        blob,
    )
    check(
        "and carries its message, with newlines escaped as %0A",
        "%0A" in blob and "bittrLnurl" in blob,
        blob,
    )
    check("and the annotation is a single physical line", len(blob.splitlines()) == 1, blob)


def test_a_percent_in_a_failure_message_is_escaped():
    # A literal % would otherwise eat the next two characters as an escape, so a
    # message like "expected 0% but was 50%" would arrive mangled or truncated.
    with tempfile.TemporaryDirectory() as tmp:
        classname = f"{PACKAGE}.ThirdPartyIsolationTest"
        broken = (f'<testcase classname="{classname}" '
                  'name="aThirdPartyPageFindsNoBridgeToPostTo">'
                  '<failure message="expected 0% but was 50%"/></testcase>')
        cases = [c for c in all_required()
                 if "aThirdPartyPageFindsNoBridgeToPostTo" not in c] + [broken]
        results = write_results(pathlib.Path(tmp), cases)
        code, out = run(results)
    check("a % in a failure message still exits 1", code == 1, out)
    blob = "\n".join(annotations(out))
    check("and reaches the annotation escaped as %25", "0%25 but was 50%25" in blob, blob)


def test_the_verdict_line_distinguishes_the_failure_modes():
    # "vacuity check FAILED" was run 27's entire headline, and it reads the same
    # whether nothing ran or nine ran and one failed. Those are opposite findings:
    # one says the evidence is absent, the other says the evidence is bad.
    with tempfile.TemporaryDirectory() as tmp:
        cases = all_required({"aThirdPartyPageCannotTriggerLnurlAuth": "failed"})
        results = write_results(pathlib.Path(tmp), cases)
        _, ran_but_failed = run(results)
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(pathlib.Path(tmp), [])
        _, nothing_ran = run(results)

    def verdict(out):
        for line in out.splitlines():
            if line.startswith("check-instrumented-results: verdict "):
                return line
        return ""

    got = verdict(ran_but_failed)
    check("a real red reports 0 missing and 1 failed",
          "0 missing" in got and "1 failed" in got, got)
    check("and reports the canary as passed, because it did",
          "canary passed" in got, got)
    check("a vacuous run reports every required test missing",
          f"{len(checker.REQUIRED)} missing" in verdict(nothing_ran), verdict(nothing_ran))
    check("and reports the canary as FAILED, because it never ran",
          "canary FAILED" in verdict(nothing_ran), verdict(nothing_ran))


def test_an_oversized_failure_message_is_truncated_not_dropped():
    with tempfile.TemporaryDirectory() as tmp:
        classname = f"{PACKAGE}.ThirdPartyIsolationTest"
        cases = [
            f'<testcase classname="{classname}" name="t{i}">'
            f'<failure message="{"x" * 280}"/></testcase>'
            for i in range(40)
        ] + all_required()
        results = write_results(pathlib.Path(tmp), cases)
        code, out = run(results)
    check("a very large failure set still exits 1", code == 1, out)
    blob = "\n".join(annotations(out))
    check("and the annotation stays within GitHub's limit",
          len(blob) <= checker.ANNOTATION_LIMIT + 200, len(blob))
    check("and says it was truncated rather than silently ending",
          "truncated" in blob, blob)


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
