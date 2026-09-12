#!/usr/bin/env python3
"""Tests for check-wallet-instrumented-results.py — the gate on BIT-59's evidence.

    android/scripts/test_check_wallet_instrumented_results.py

WHY THIS EXISTS

The same argument as test_check_instrumented_results.py, with more riding on it.
A gate whose entire job is to refuse a green run that proved nothing does not
fail visibly when it is buggy — it fails as a pass.

Here that pass would be read as closing the one wallet claim
`wallet-security-properties.md` §4 records as unproven, and BIT-20 rule 5 makes
that claim a *precondition* of the `match -> keep` guard rather than a
follow-up. So a false green does not leave the claim unproven-and-known; it
converts it into proven-and-wrong, and unblocks the path whose failure mode is
publishing a revoked commitment.

The cases below are therefore mostly the *bad* ones, and two of them are
specific to this suite spanning two modules:

  - the :app half missing entirely, which is how the backup claim would go
    unchecked behind a job that stayed green, and
  - the transport canary skipped or red, which is how every "the backup set
    excluded our files" assertion passes on an image that produced no backup
    set for any package at all.

No Gradle, no emulator: the seam is the results directory, so the fixtures are
XML files in a temp dir. That is also why this runs in the `build` job, seconds
in, rather than only after an emulator has booted.
"""

import contextlib
import importlib.util
import io
import pathlib
import sys
import tempfile

MODULE = pathlib.Path(__file__).with_name("check-wallet-instrumented-results.py")
spec = importlib.util.spec_from_file_location("check_wallet_instrumented_results", MODULE)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

FAILURES = []

CANARY = checker.CANARY
APP_PACKAGE = checker.APP_PACKAGE
LDK_PACKAGE = checker.LDK_PACKAGE

LDK_REQUIRED = sorted(t for t in checker.REQUIRED if t.startswith(LDK_PACKAGE))
APP_REQUIRED = sorted(
    # Both :app classes: BackupExclusionTest (the bmgr behaviour) and
    # InstalledBackupConfigurationTest (the installed configuration). Filtering
    # on the module's package rather than on one class name is deliberate —
    # splitting the suite into a second class must not silently halve what these
    # tests build a fixture for.
    #
    # LDK_PACKAGE is a sub-package of APP_PACKAGE, so the exclusion is what
    # keeps the two lists disjoint; test_the_required_set_spans_both_modules
    # asserts that they are.
    t for t in checker.REQUIRED
    if t.startswith(f"{APP_PACKAGE}.") and not t.startswith(f"{LDK_PACKAGE}.")
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
        "failed": '<failure message="bmgr backupnow reported the package was backed up"/>',
        "failed-without-message": "<failure/>",
        "failed-text-only": (
            "<failure>java.lang.AssertionError: the installed rules did not "
            "exclude the wallet directory\n\tat com.bittr.android.Backup...</failure>"
        ),
    }[outcome]
    return f'<testcase classname="{classname}" name="{name}">{body}</testcase>'


def write_results(tmp, cases, filename="TEST-results.xml", system_out=None):
    """Write one AGP-shaped result file into a connected/<device>/ layout."""
    device = tmp / "connected" / "debug" / "Pixel_6_API_34(AVD) - 14"
    device.mkdir(parents=True, exist_ok=True)
    tail = f"<system-out>{system_out}</system-out>\n" if system_out else ""
    (device / filename).write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<testsuite name="wallet-instrumented" tests="{len(cases)}">\n'
        + "\n".join(cases)
        + "\n"
        + tail
        + "</testsuite>\n"
    )
    return tmp / "connected"


def both_modules(tmp, outcomes=None, drop=()):
    """Two results dirs — one per module — as the real job produces.

    Mirrors the shape the gate defaults to: :core:wallet-ldk's tests in one
    directory and :app's in another. Returns the pair of directories.
    """
    outcomes = outcomes or {}

    def cases(ids):
        return [
            testcase(t, outcomes.get(t.split("#")[1], "passed"))
            for t in ids
            if t not in drop
        ]

    ldk = write_results(tmp / "wallet-ldk", cases(LDK_REQUIRED))
    app = write_results(tmp / "app", cases(APP_REQUIRED))
    return [ldk, app]


def run(results_dirs):
    """Invoke main() with explicit --results-dir args; return (code, output)."""
    argv = []
    for path in results_dirs:
        argv += ["--results-dir", str(path)]
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        try:
            code = checker.main(argv)
        except SystemExit as exc:
            code = exc.code
    return code, out.getvalue()


def test_a_full_green_run_across_both_modules_passes():
    with tempfile.TemporaryDirectory() as tmp:
        code, out = run(both_modules(pathlib.Path(tmp)))
    check("both modules green exits 0", code == 0, out)
    check("and says so", "ran and passed" in out, out)


def test_the_required_set_spans_both_modules():
    # If this ever became single-module, the two-directory plumbing above would
    # still pass while covering nothing — so assert the premise directly.
    check("required tests exist in :core:wallet-ldk", len(LDK_REQUIRED) > 0)
    check("required tests exist in :app", len(APP_REQUIRED) > 0)
    check(
        "every required test belongs to one of the two",
        len(LDK_REQUIRED) + len(APP_REQUIRED) == len(checker.REQUIRED),
        sorted(checker.REQUIRED),
    )


def test_the_app_half_missing_entirely_fails():
    # The headline case for this suite. :core:wallet-ldk runs, :app does not, and
    # the backup claim — the whole reason BIT-59 exists — goes unchecked while
    # Gradle exits 0.
    with tempfile.TemporaryDirectory() as tmp:
        ldk = write_results(pathlib.Path(tmp) / "wallet-ldk",
                            [testcase(t) for t in LDK_REQUIRED])
        code, out = run([ldk])
    check("only the library module's results exits 1", code == 1, out)
    check("and names the missing backup tests",
          "BackupExclusionTest#cloudBackupOfAWalletBearingInstallCarriesNoWalletMaterial" in out,
          out)


def test_a_missing_results_directory_fails():
    with tempfile.TemporaryDirectory() as tmp:
        code, out = run([pathlib.Path(tmp) / "nothing-here"])
    check("a nonexistent results directory exits 1", code == 1, out)
    check("and names the directory", "nothing-here" in out, out)


def test_an_empty_results_directory_fails():
    with tempfile.TemporaryDirectory() as tmp:
        empty = pathlib.Path(tmp) / "connected"
        empty.mkdir()
        code, out = run([empty])
    check("a results directory with no TEST-*.xml exits 1", code == 1, out)
    check("and explains that zero matched tests is a green task", "vacuous" in out, out)


def test_zero_testcases_in_a_wellformed_file_fails():
    with tempfile.TemporaryDirectory() as tmp:
        results = write_results(pathlib.Path(tmp), [])
        code, out = run([results])
    check("a result file containing no <testcase> exits 1", code == 1, out)
    check("and reports every required test as missing", "did not run at all" in out, out)


def test_a_skipped_transport_canary_fails():
    # @Ignore on backupManagerAndTheLocalTransportAreLiveOnThisDevice, else green.
    # Gradle exits 0, and every backup assertion in the run is then unfalsifiable.
    with tempfile.TemporaryDirectory() as tmp:
        dirs = both_modules(pathlib.Path(tmp), {CANARY.split("#")[1]: "skipped"})
        code, out = run(dirs)
    check("a skipped transport canary exits 1", code == 1, out)
    check("and says a skipped test does not fail a build", "skipped" in out.lower(), out)


def test_a_red_transport_canary_invalidates_the_rest():
    with tempfile.TemporaryDirectory() as tmp:
        dirs = both_modules(pathlib.Path(tmp), {CANARY.split("#")[1]: "failed"})
        code, out = run(dirs)
    check("a red transport canary exits 1", code == 1, out)
    check(
        "and says the other backup results are not evidence",
        "unproven rather than as evidence" in out,
        out,
    )


def test_a_renamed_required_test_fails():
    with tempfile.TemporaryDirectory() as tmp:
        dirs = both_modules(
            pathlib.Path(tmp),
            drop=(f"{APP_PACKAGE}.InstalledBackupConfigurationTest#everyWalletFileLandedUnderNoBackup",),
        )
        extra = testcase(f"{APP_PACKAGE}.InstalledBackupConfigurationTest#filesAreUnderNoBackup")
        app_dir = dirs[1]
        next(app_dir.rglob("TEST-*.xml")).write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="w" tests="1">\n'
            + "\n".join(
                [testcase(t) for t in APP_REQUIRED
                 if not t.endswith("everyWalletFileLandedUnderNoBackup")]
                + [extra]
            )
            + "\n</testsuite>\n"
        )
        code, out = run(dirs)
    check("a renamed required test exits 1", code == 1, out)
    check("and points at REQUIRED as the review point", "update REQUIRED" in out, out)


def test_an_extra_test_is_allowed():
    with tempfile.TemporaryDirectory() as tmp:
        dirs = both_modules(pathlib.Path(tmp))
        extra = write_results(pathlib.Path(tmp) / "extra",
                              [testcase(f"{APP_PACKAGE}.SomeNewTest#somethingElse")])
        code, out = run(dirs + [extra])
    check("adding a test does not break the gate", code == 0, out)
    check("and it is labelled extra", "(extra)" in out, out)


def test_a_failure_without_a_message_is_still_a_failure():
    # "" is falsy. Storing the message directly would make this test read as
    # passed — the bug the gate is supposed to catch, inside the gate.
    with tempfile.TemporaryDirectory() as tmp:
        dirs = both_modules(
            pathlib.Path(tmp),
            {"cloudBackupOfAWalletBearingInstallCarriesNoWalletMaterial": "failed-without-message"},
        )
        code, out = run(dirs)
    check("a <failure/> with no message exits 1", code == 1, out)
    check("and is reported as FAILED", "FAILED" in out, out)


def test_a_pass_does_not_override_a_failure_for_the_same_test():
    # Two devices, or a re-run: one red, one green. The red one wins. A red
    # BackupExclusionTest is a BIT-20 halt, and a retry must not erase it.
    with tempfile.TemporaryDirectory() as tmp:
        dirs = both_modules(
            pathlib.Path(tmp),
            {"cloudBackupOfAWalletBearingInstallCarriesNoWalletMaterial": "failed"},
        )
        retry = write_results(
            pathlib.Path(tmp) / "retry",
            [testcase(
                f"{APP_PACKAGE}.BackupExclusionTest"
                "#cloudBackupOfAWalletBearingInstallCarriesNoWalletMaterial",
                "passed",
            )],
        )
        code, out = run(dirs + [retry])
    check("a green second attempt cannot mask a red first one", code == 1, out)


def test_a_truncated_result_file_fails():
    # The emulator went away mid-run. A parse error must be a failed run, not a
    # file the reader shrugs past on its way to reporting green.
    with tempfile.TemporaryDirectory() as tmp:
        dirs = both_modules(pathlib.Path(tmp))
        broken = next(dirs[0].rglob("TEST-*.xml"))
        broken.write_text(broken.read_text()[: len(broken.read_text()) // 2])
        code, out = run(dirs)
    check("unparseable XML exits 1", code == 1, out)
    check("and blames an unfinished run", "did not finish writing" in out, out)


def test_a_green_run_says_how_to_tell_a_real_pass_from_an_ineligible_one():
    # The caveat must be stated on the runs people actually read, which are the
    # green ones. `allowBackup="false"` makes the package ineligible outright,
    # and an ineligible package produces an empty set that satisfies "nothing of
    # ours came back" without the <device-transfer> rules being consulted. That
    # is a pass for BIT-20 rule 5 and it is not a proof that the rules work, so
    # a green run has to point the reader at the line that distinguishes them.
    with tempfile.TemporaryDirectory() as tmp:
        code, out = run(both_modules(pathlib.Path(tmp)))
    check(
        "a green run points at the BACKUP_EXCLUSION lines",
        code == 0 and "canaryReturned" in out and "BACKUP_EXCLUSION" in out,
        out,
    )
    check("and points at where it is tracked",
          "wallet-security-properties.md §4" in out, out)


def test_the_failure_annotation_carries_the_test_names():
    # THE BUG THIS PINS. The emitted annotation used to be
    # `problem.splitlines()[0]`, so a red run's annotation read "These tests
    # failed:" with nothing under it. On this PUBLIC repo the job log answers
    # 403 and artifacts answer 401, so the annotation is the only thing readable
    # from outside the runner — and an empty failure list there is not merely
    # unhelpful, it looks exactly like "no tests ran", which is a different
    # finding with a different owner.
    with tempfile.TemporaryDirectory() as tmp:
        dirs = both_modules(
            pathlib.Path(tmp),
            {"cloudBackupOfAWalletBearingInstallCarriesNoWalletMaterial": "failed"},
        )
        code, out = run(dirs)

    annotations = [ln for ln in out.splitlines() if ln.startswith("::error::")]
    check("a red run emits an annotation", annotations, out)
    joined = "".join(annotations)
    check(
        "and the failing test's name is inside the annotation itself",
        "cloudBackupOfAWalletBearingInstallCarriesNoWalletMaterial" in joined,
        joined,
    )
    check("and it stays one line, or the rest falls into the unreadable log",
          all("\n" not in a for a in annotations), joined)
    check("with the newlines encoded rather than dropped", "%0A" in joined, joined)


def test_a_percent_in_a_failure_message_cannot_corrupt_the_escapes():
    # `%` must be escaped BEFORE `%0A` is introduced. Done the other way round,
    # a test whose message contains a literal "%0A" — or any percent sign —
    # rewrites the encoding of the annotation around it.
    check("a bare percent is escaped", checker.annotate("100% used") == "100%25 used")
    check(
        "and a literal %0A in the text does not become a newline",
        checker.annotate("a%0Ab") == "a%250Ab",
    )
    check(
        "while real newlines do",
        checker.annotate("a\nb") == "a%0Ab",
    )


def test_a_very_long_problem_is_truncated_rather_than_dropped():
    # An over-long annotation is rejected wholesale, which would put us back at
    # an empty failure list by a different route.
    encoded = checker.annotate("x" * (checker.MAX_ANNOTATION + 500))
    check("an over-long problem is truncated", len(encoded) < checker.MAX_ANNOTATION + 200, len(encoded))
    check("and says so", "truncated" in encoded, encoded)


def test_a_failure_with_text_but_no_message_attribute_is_reported():
    # THE BUG THIS PINS. AGP routinely omits the `message` attribute on connected
    # tests and puts the assertion in the element body. Reading only the attribute
    # named run 34692523156's two real failures and then said "(no message)" about
    # both — the names without the reason, which is one step short of useless when
    # the job log is 403 and the whole diagnosis has to fit in an annotation.
    with tempfile.TemporaryDirectory() as tmp:
        dirs = both_modules(
            pathlib.Path(tmp),
            {"theInstalledRulesExcludeTheWalletDirectoryFromBothPaths": "failed-text-only"},
        )
        code, out = run(dirs)
    check("a <failure> carrying only body text exits 1", code == 1, out)
    check("and the assertion text is reported rather than '(no message)'",
          "the installed rules did not exclude" in out, out)
    check("so it does not fall back to the placeholder",
          "(no message)" not in out, out)



def test_the_evidence_lines_are_lifted_into_the_log():
    # BIT-59's definition of done is that the tests' RESULTS appear in the run.
    # The lines that say which of the two green outcomes a run got live in
    # instrumentation stdout, i.e. in <system-out> in the XML and in the HTML
    # report — both artefacts, and downloading an artefact from this public repo
    # needs a token that reading the run does not. So the gate reprints them.
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        dirs = both_modules(root)
        out_file = next((root / "app").rglob("TEST-*.xml"))
        out_file.write_text(
            out_file.read_text().replace(
                "</testsuite>",
                "<system-out>BACKUP_EXCLUSION path=device-transfer api=34 "
                "package=com.bittr.android.regtest result=Success canaryReturned=true\n"
                "noise that is not evidence\n"
                "KEYSTORE_KEY_INFO api=34 unlockedDeviceRequired=&lt;not exposed&gt;\n"
                "</system-out>\n</testsuite>",
            )
        )
        code, out = run(dirs)
    check("a run with evidence lines still exits 0", code == 0, out)
    check("the backup evidence line is in the log", "canaryReturned=true" in out, out)
    check("the keystore evidence line is in the log", "KEYSTORE_KEY_INFO" in out, out)
    check(
        "and unprefixed stdout is not dragged in with it",
        "noise that is not evidence" not in out,
        out,
    )


def test_absent_evidence_lines_are_reported_not_omitted():
    # The tests print these unconditionally, so none arriving means they did not
    # reach the print — which a silently empty section would hide.
    with tempfile.TemporaryDirectory() as tmp:
        code, out = run(both_modules(pathlib.Path(tmp)))
    check("a run with no evidence lines still exits 0", code == 0, out)
    check(
        "and says so rather than printing nothing",
        "did not get that far" in out,
        out,
    )

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
