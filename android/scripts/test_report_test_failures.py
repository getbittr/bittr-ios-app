#!/usr/bin/env python3
"""Tests for report-test-failures.py.

    python3 android/scripts/test_report_test_failures.py

Same argument as test_check_wallet_instrumented_results.py: this script is a
diagnosis channel, and a broken diagnosis channel does not look broken — it
looks like a failure with nothing to say, which is indistinguishable from the
state it exists to fix. Run 47 lost a round of work to exactly that, so the
thing that fixes it gets tests.

The seam is a directory of JUnit XML, so the fixtures are files in a temp dir
and this needs no Gradle, no emulator and no network.

stdlib only, for the reason every other script in here gives.
"""

import importlib.util
import pathlib
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "report-test-failures.py"

# The hyphen in the filename means it cannot be imported by name. Same loader
# dance as test_check_wallet_instrumented_results.py.
_spec = importlib.util.spec_from_file_location("report_test_failures", SCRIPT)
report = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(report)


PASSING_XML = """<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="com.bittr.android.GreenTest" tests="1" skipped="0" failures="0" errors="0">
  <testcase name="itPasses" classname="com.bittr.android.GreenTest" time="0.01"/>
</testsuite>
"""

FAILING_XML = """<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="com.bittr.android.RedTest" tests="1" skipped="0" failures="1" errors="0">
  <testcase name="itFails" classname="com.bittr.android.RedTest" time="0.01">
    <failure message="expected: &lt;36&gt; but was: &lt;37&gt;" type="java.lang.AssertionError">
java.lang.AssertionError: Package targetSdkVersion=37 &gt; maxSdkVersion=36
	at org.robolectric.Whatever.run(Whatever.java:1)
    </failure>
  </testcase>
</testsuite>
"""

ERRORED_XML = """<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="com.bittr.android.BoomTest" tests="1" skipped="0" failures="0" errors="1">
  <testcase name="itErrors" classname="com.bittr.android.BoomTest" time="0.01">
    <error message="boom, 50%% of the time" type="java.lang.IllegalStateException">stack</error>
  </testcase>
</testsuite>
"""


def write_report(root, module, variant, filename, body):
    """Put an XML file where Gradle would put it, and return the root."""
    directory = root / module / "build" / "test-results" / variant
    directory.mkdir(parents=True, exist_ok=True)
    (directory / filename).write_text(body)
    return root


class ReportTestFailuresTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def run_script(self, *extra):
        """Run main() against the fixture root, returning (exit code, stdout)."""
        import contextlib
        import io

        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = report.main(["--root", str(self.root), *extra])
        return code, out.getvalue()

    def test_no_reports_at_all_is_reported_as_a_compile_failure(self):
        """The case the artifact upload could not cover: nothing was written."""
        code, out = self.run_script()
        self.assertEqual(code, 0)
        self.assertIn("::error title=Unit tests failed with no test results::", out)
        self.assertIn("before any test ran", out)

    def test_all_green_reports_say_the_failure_is_elsewhere(self):
        """A red task with no failing testcase is a finding, not silence."""
        write_report(self.root, "app", "testDebugUnitTest", "TEST-Green.xml", PASSING_XML)
        code, out = self.run_script()
        self.assertEqual(code, 0)
        self.assertIn("::error title=Unit tests failed but every test passed::", out)
        self.assertIn("outside the tests themselves", out)

    def test_a_failure_becomes_an_annotation_naming_the_test(self):
        write_report(self.root, "app", "testDebugUnitTest", "TEST-Red.xml", FAILING_XML)
        code, out = self.run_script()
        self.assertEqual(code, 0)
        self.assertIn("::error title=com.bittr.android.RedTest.itFails (failure)::", out)
        # The assertion message must survive, because it is the diagnosis.
        self.assertIn("maxSdkVersion=36", out)

    def test_errors_are_reported_as_well_as_failures(self):
        """<error> is the Robolectric-blew-up-at-init shape, i.e. run 42's."""
        write_report(self.root, "core/wallet-ldk", "testDebugUnitTest", "TEST-Boom.xml", ERRORED_XML)
        code, out = self.run_script()
        self.assertEqual(code, 0)
        self.assertIn("::error title=com.bittr.android.BoomTest.itErrors (error)::", out)

    def test_both_result_layouts_are_scanned(self):
        """Plain `test/` for the pure-Kotlin modules, `testDebugUnitTest/` for the rest.

        The regression this guards is real: a glob written for one layout finds
        nothing when the module that broke uses the other, and the script then
        reports "no test results" — blaming a compile error for an assertion
        failure, which is worse than saying nothing.
        """
        write_report(self.root, "core/wallet", "test", "TEST-Red.xml", FAILING_XML)
        code, out = self.run_script()
        self.assertEqual(code, 0)
        self.assertIn("com.bittr.android.RedTest", out)

    def test_newlines_are_escaped_so_the_whole_message_reaches_the_annotation(self):
        """An un-escaped newline ends the workflow command.

        Everything after it would be printed into the step log, which is the
        one channel that cannot be read without repository admin — so the most
        useful half of a stack trace would land in the only place it is no use.
        """
        write_report(self.root, "app", "testDebugUnitTest", "TEST-Red.xml", FAILING_XML)
        _, out = self.run_script()
        command = [line for line in out.splitlines() if line.startswith("::error")][0]
        self.assertIn("%0A", command)
        # The last line of the fixture's stack trace, i.e. the part that would
        # have been orphaned into the log by an un-escaped newline.
        self.assertIn("org.robolectric", command)

    def test_percent_is_escaped_before_the_newline_substitution(self):
        """Order matters: escaping % after inserting %0A would corrupt it into %250A."""
        self.assertEqual(report.escape("100%\n"), "100%25%0A")

    def test_the_annotation_count_is_capped_and_the_remainder_is_announced(self):
        """A wholesale breakage must not bury its own first, most diagnostic failure."""
        for index in range(12):
            write_report(
                self.root, f"module{index}", "test", "TEST-Red.xml", FAILING_XML
            )
        code, out = self.run_script("--max", "3")
        self.assertEqual(code, 0)
        annotations = [line for line in out.splitlines() if line.startswith("::error")]
        # Three failures plus the one that says how many were dropped.
        self.assertEqual(len(annotations), 4)
        self.assertIn("::error title=More failures than annotations::", out)
        self.assertIn("9 further failing test(s)", out)

    def test_an_unparseable_report_is_reported_rather_than_raising(self):
        """Half a result file means the run died mid-test — which is the news."""
        write_report(self.root, "app", "test", "TEST-Truncated.xml", "<testsuite><testcase")
        code, out = self.run_script()
        self.assertEqual(code, 0)
        self.assertIn("::error", out)
        self.assertIn("unparseable", out)

    def test_exit_code_is_always_zero(self):
        """The step that ran the tests has already failed the job.

        Failing here too would replace one uninformative failure with another,
        and on the all-green path it would invent a failure outright.
        """
        write_report(self.root, "app", "test", "TEST-Red.xml", FAILING_XML)
        self.assertEqual(self.run_script()[0], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
