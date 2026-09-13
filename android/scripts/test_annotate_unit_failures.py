#!/usr/bin/env python3
"""Tests for annotate-unit-failures.py — the reporter on the unit-test step.

    android/scripts/test_annotate_unit_failures.py

WHY THIS EXISTS

The same argument as test_check_instrumented_results.py, one step earlier in the
job. This reporter's entire value is that a red unit-test step says *which* test
failed in the annotation, because the annotation is the only part of a run that
is readable without repository credentials. A reporter that goes quiet does not
look broken — it looks exactly like the state it was written to replace, which is
what run 98 was.

So the cases below are mostly about the reporter staying audible: a failure in a
nested module, a failure recorded in the element body rather than the attribute,
a truncated file from an OOM-killed JVM, and — the one that matters most — no
failures at all, where the absence of a finding is itself the finding.

No Gradle: the seam is the results directory, so the fixtures are XML files in a
temp dir.
"""

import contextlib
import importlib.util
import io
import pathlib
import sys
import tempfile

MODULE = pathlib.Path(__file__).with_name("annotate-unit-failures.py")
spec = importlib.util.spec_from_file_location("annotate_unit_failures", MODULE)
reporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporter)

FAILURES = []


def check(what, ok, detail=""):
    print(f"{'ok  ' if ok else 'FAIL'}  {what}")
    if not ok:
        FAILURES.append(f"{what}{(': ' + str(detail)) if detail else ''}")


def write_results(android_dir, module, cases, variant="testDebugUnitTest",
                  filename="TEST-Guard.xml", raw=None):
    """Write one Gradle-shaped unit-test result file under a module."""
    out = android_dir / module / "build" / "test-results" / variant
    out.mkdir(parents=True, exist_ok=True)
    (out / filename).write_text(raw if raw is not None else (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<testsuite name="unit" tests="{len(cases)}">\n'
        + "\n".join(cases)
        + "\n</testsuite>\n"
    ))
    return out


def passing(test_id):
    classname, name = test_id.split("#")
    return f'<testcase classname="{classname}" name="{name}"/>'


def failing(test_id, message="expected:&lt;false&gt; but was:&lt;true&gt;"):
    classname, name = test_id.split("#")
    return (f'<testcase classname="{classname}" name="{name}">'
            f'<failure message="{message}"/></testcase>')


def run(android_dir):
    """Invoke main(); return (exit_code, combined output)."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        try:
            code = reporter.main(["--android-dir", str(android_dir)])
        except SystemExit as exc:
            code = exc.code
    return code, out.getvalue()


def annotation(out, level="error"):
    for line in out.splitlines():
        if line.startswith(f"::{level} "):
            return line
    return ""


def test_a_failing_test_is_named_in_the_annotation():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        write_results(root, "app", [
            passing("com.bittr.android.AppLaunchTest#itLaunches"),
            failing("com.bittr.android.JavascriptInterfaceGuardTest#itIsBanned",
                    "addJavascriptInterface found in HardenedWebView.kt"),
        ])
        code, out = run(root)
        line = annotation(out)
        check("a failing unit test still exits 0 — it reports, it does not gate",
              code == 0, code)
        check("and its name reaches the annotation, not just the log",
              "JavascriptInterfaceGuardTest#itIsBanned" in line, line)
        check("and so does its message, which is the part that diagnoses it",
              "addJavascriptInterface found in HardenedWebView.kt" in line, line)
        check("and the passing test beside it is not reported",
              "AppLaunchTest" not in line, line)


def test_a_failure_in_a_nested_module_is_found():
    # feature/website is two levels deep. A glob anchored at */build/ misses it,
    # and the miss is silent — which is the failure mode this whole file guards.
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        write_results(root, "feature/website", [
            failing("com.bittr.android.feature.website.FirstPartyOriginsTest#itAllows"),
        ])
        code, out = run(root)
        check("a failure under feature/website is reported",
              "FirstPartyOriginsTest#itAllows" in annotation(out), out)


def test_a_failure_recorded_in_the_body_is_read():
    # Not every writer sets message=. Reused from check-instrumented-results.py
    # via failure_message, and asserted here so a change there cannot quietly
    # make this reporter print "(no message)" again.
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        write_results(root, "app", [
            '<testcase classname="com.bittr.android.CurrencyDefaultGuardTest" '
            'name="itIsNotEuro"><failure>java.lang.AssertionError: a euro default '
            'reached the port\n\tat org.junit.Assert.fail(Assert.java:88)\n'
            '</failure></testcase>',
        ])
        code, out = run(root)
        line = annotation(out)
        check("a failure message in the element body is read",
              "a euro default reached the port" in line, line)
        check("and the stack frames under it are not carried into the annotation",
              "org.junit.Assert.fail" not in line, line)


def test_a_truncated_result_file_is_reported_not_skipped():
    # An OOM-killed JVM leaves exactly this. Reporting nothing would say "no test
    # failed", which is the opposite of what a half-written file means.
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        write_results(root, "app", [], raw=(
            '<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="unit"><testc'
        ))
        code, out = run(root)
        line = annotation(out)
        check("an unparseable result file is itself reported as a failure",
              "unparseable XML" in line, line)
        check("and the annotation says which file",
              "TEST-Guard.xml" in line, line)


def test_no_failure_anywhere_says_so_out_loud():
    # Run 98. The step was red and no test was; that distinction is the entire
    # reason this script exists, so it must be stated, not left to silence.
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        write_results(root, "app", [passing("com.bittr.android.AppLaunchTest#itLaunches")])
        code, out = run(root)
        line = annotation(out, "notice")
        check("a red step with no failing test emits a notice", bool(line), out)
        check("and names the toolchain rather than the tests",
              "toolchain failure" in line, line)
        check("and reports how many files it searched, so a glob that matched "
              "nothing is distinguishable from a genuine all-green",
              "1 result file(s)" in line, line)
        check("and emits no ::error::, which would be a red herring",
              annotation(out) == "", out)


def test_no_results_at_all_is_distinguished_from_results_with_no_failures():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        code, out = run(root)
        line = annotation(out, "notice")
        check("no result files at all is called out specifically",
              "no result files at all" in line, line)
        check("and points at the step dying before any test task ran",
              "before any test task" in line, line)


def test_androidtest_results_are_not_read():
    # The emulator job's evidence lives in outputs/androidTest-results/ and
    # check-instrumented-results.py is careful that `./gradlew test` can never
    # satisfy it. The same care in reverse: a stale connected-test failure on
    # disk must not be reported as a unit-test failure.
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        out_dir = (root / "feature/website/build/outputs/androidTest-results/"
                   "connected/debug")
        out_dir.mkdir(parents=True)
        (out_dir / "TEST-stale.xml").write_text(
            '<testsuite name="instrumented">'
            + failing("com.bittr.android.feature.website.ThirdPartyIsolationTest#x")
            + "</testsuite>\n"
        )
        code, out = run(root)
        check("a connected-test result is not reported by the unit-test reporter",
              "ThirdPartyIsolationTest#x" not in out, out)
        check("and the run reads as 'no unit-test failure' instead",
              "no result files at all" in annotation(out, "notice"), out)


def test_a_percent_in_a_failure_message_survives_escaping():
    # GitHub eats the two characters after a literal % in command data.
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        write_results(root, "app", [
            failing("com.bittr.android.CoverageTest#itIsHighEnough",
                    "coverage was 41%, below the floor"),
        ])
        code, out = run(root)
        line = annotation(out)
        check("a % in the message is escaped as %25 in the annotation",
              "41%25, below the floor" in line, line)


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
