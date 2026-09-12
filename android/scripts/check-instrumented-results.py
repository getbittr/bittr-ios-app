#!/usr/bin/env python3
"""Fail a green `connectedDebugAndroidTest` that did not actually run the tests.

    android/scripts/check-instrumented-results.py
    android/scripts/check-instrumented-results.py --results-dir <dir>

Exit codes: 0 the required tests ran and passed · 1 they did not.

WHY THIS EXISTS

BIT-62 is "run the S-36 instrumented tests", and the failure mode it names first
is a **vacuously green run**. There are three separate ways to get one, and
Gradle's exit code catches none of them.

1. *Zero tests ran.* `connectedDebugAndroidTest` succeeds when it matched
   nothing. Break the runner declaration, mis-merge the test manifest, filter on
   a package that no longer exists, and the task prints BUILD SUCCESSFUL having
   installed an APK and executed no test at all. This is the big one: the whole
   premise of BIT-62 is that a test nobody has run might be asserting nothing,
   and "the task went green" is precisely the evidence that does not distinguish
   those cases.

2. *A test was silently skipped.* `@Ignore`, or an assumption that fails, is
   reported as skipped, and a skipped test does not fail a build. A green run
   with `theCrossOriginIframeActuallyRan` skipped is the exact state BIT-58 wrote
   that test to prevent.

3. *The one that matters got renamed away.* Nothing else in the repo asserts that
   these specific tests exist. `assembleDebugAndroidTest` in the build job proves
   the source set compiles; a file that compiles can have had its canary deleted.

So the gate is not "did Gradle succeed" but "did these named tests run, and
pass". REQUIRED below is the list, and it is deliberately a hard-coded literal:
deriving it from the XML would make it a description of whatever happened to run,
which is the property being checked.

Adding a test does not break this — extras are reported and allowed. Renaming or
deleting one does, which is the point.

NO DEPENDENCIES, DELIBERATELY

stdlib only, matching ci-runs.py and shared/test-ids/*.py: these checks run on a
runner, on a Mac and in a container, with no pip step in front of them.
"""

import argparse
import pathlib
import sys
import xml.etree.ElementTree as ElementTree

# Annotation message limit is generous but not unlimited, and a problem block is
# a handful of test ids plus one truncated message each.
MAX_ANNOTATION = 4000


def annotate(text):
    """Encode a multi-line problem so all of it survives into an annotation.

    A workflow command is ONE line: everything after the first newline is
    ordinary log output. That matters more here than it looks, because on this
    PUBLIC repo the job log answers 403 "Must have admin rights to Repository"
    and artifacts answer 401 — so anything that falls out of the annotation is
    readable by a signed-in human and by nothing else.

    This function exists because the previous code took `splitlines()[0]`, which
    is a correct way to make a one-line annotation and threw away the only part
    anyone needed: the annotation for a red run read "These tests failed:" with
    an empty list under it, which looks exactly like "no tests ran" and is not.
    `%` is escaped BEFORE `%0A` is introduced, or a percent sign in a test's own
    failure message would corrupt the escapes added after it.
    """
    text = text.rstrip()
    if len(text) > MAX_ANNOTATION:
        text = text[:MAX_ANNOTATION] + "\n… truncated; full text is above this line."
    return text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


PACKAGE = "com.bittr.android.feature.website"

# Every test that must have run and passed for the S-36 isolation claim to hold.
#
# The comments are not decoration: this list is the only place in the repo that
# says what the emulator job is *for*, and a future reader deciding whether a
# rename is safe needs to know which of these is load-bearing.
REQUIRED = {
    # BIT-58 DoD 2 — the cross-origin iframe. theCrossOriginIframeActuallyRan is
    # the canary: it is the reason the other three in this class mean anything,
    # because "no bridge was found" and "the iframe never loaded" are otherwise
    # the same result.
    f"{PACKAGE}.CrossOriginIframeIsolationTest#theCrossOriginIframeActuallyRan",
    f"{PACKAGE}.CrossOriginIframeIsolationTest#aCrossOriginIframeFindsNoBridgeToPostTo",
    f"{PACKAGE}.CrossOriginIframeIsolationTest#aCrossOriginIframeCannotNavigateTheTopFrameToALightningUrl",
    f"{PACKAGE}.CrossOriginIframeIsolationTest#aCrossOriginIframeTriggersNoNetworkCallToAnLnurlEndpoint",
    # BIT-33 Acceptance 3 and 4 — the hostile page as the main frame.
    f"{PACKAGE}.ThirdPartyIsolationTest#aThirdPartyPageFindsNoBridgeToPostTo",
    f"{PACKAGE}.ThirdPartyIsolationTest#aThirdPartyPageCannotNavigateToALightningUrl",
    f"{PACKAGE}.ThirdPartyIsolationTest#aThirdPartyPageTriggersNoNetworkCallToAnLnurlEndpoint",
    f"{PACKAGE}.ThirdPartyIsolationTest#aThirdPartyPageCannotTriggerLnurlAuth",
    # The half the source-scanning guards in :app cannot cover: this one reads the
    # live WebSettings off the real object rather than reading the source that set
    # them, so it catches a setting applied and then overwritten.
    f"{PACKAGE}.ThirdPartyIsolationTest#theHardeningBaselineIsAppliedToTheRealWebView",
}

MODULE_BUILD_DIR = (
    pathlib.Path(__file__).resolve().parents[1] / "feature/website/build"
)

# AGP has moved this directory between major versions — `androidTest-results/`
# gained a `connected/` level, then a variant level under it — and the failure
# mode of hard-coding the wrong one is a FALSE RED after a twenty-minute emulator
# boot, which is the most expensive kind of wrong this file could be. So the
# default is the first of these that exists, and `--results-dir` overrides.
#
# Only `outputs/` is searched, never `build/` wholesale: unit-test XML lands in
# `build/test-results/` and is written by a task that needs no device. Reading it
# here would let `./gradlew test` satisfy a gate whose entire claim is "these ran
# on a real Android image".
DEFAULT_RESULTS_CANDIDATES = (
    MODULE_BUILD_DIR / "outputs/androidTest-results/connected",
    MODULE_BUILD_DIR / "outputs/androidTest-results",
    MODULE_BUILD_DIR / "outputs/connected_android_test_additional_output",
)


def default_results_dir():
    for candidate in DEFAULT_RESULTS_CANDIDATES:
        if candidate.is_dir():
            return candidate
    return DEFAULT_RESULTS_CANDIDATES[0]


class Case:
    """One <testcase>, reduced to the three things this gate has an opinion about."""

    def __init__(self, element):
        self.id = f"{element.get('classname', '?')}#{element.get('name', '?')}"
        # AGP writes <skipped/> for @Ignore and for a failed assumption alike;
        # both mean "this did not run", which is what is being checked.
        self.skipped = element.find("skipped") is not None
        problems = list(element.findall("failure")) + list(element.findall("error"))
        # `or "(no message)"` is load-bearing rather than cosmetic: a <failure/>
        # with no message attribute would otherwise store "", which is falsy, and
        # a failed test would read as passed — a bug of exactly the kind this file
        # exists to catch, in the file that catches it.
        self.problem = None
        if problems:
            self.problem = (problems[0].get("message") or "").strip() or "(no message)"

    @property
    def passed(self):
        return not self.skipped and self.problem is None

    @property
    def state(self):
        if self.skipped:
            return "SKIPPED"
        return "FAILED" if self.problem else "passed"


def collect(results_dir):
    """Every <testcase> under results_dir, plus the files they came from."""
    files = sorted(results_dir.rglob("TEST-*.xml"))
    cases = []
    for path in files:
        try:
            root = ElementTree.parse(path).getroot()
        except ElementTree.ParseError as exc:
            # A truncated result file means the run died mid-write — usually the
            # emulator going away. That is a failure, not something to skip past.
            print(f"::error::{path} is not parseable XML ({exc}). The test run did "
                  "not finish writing its results; treat this as a failed run.")
            raise SystemExit(1)
        # <testsuites> wrapping <testsuite>, or a bare <testsuite>. Both occur.
        for case in root.iter("testcase"):
            cases.append(Case(case))
    return files, cases


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--results-dir",
        type=pathlib.Path,
        default=None,
        help="Gradle's androidTest-results directory. Defaults to the first of "
             "the known AGP layouts that exists under :feature:website.",
    )
    args = parser.parse_args(argv)
    results_dir = args.results_dir or default_results_dir()

    if not results_dir.is_dir():
        print(f"::error::No instrumented-test results at {results_dir}. Gradle "
              "reported success without writing any, which means no test ran. The "
              "S-36 isolation claim is unverified — see BIT-62.")
        return 1

    files, cases = collect(results_dir)

    if not files:
        print(f"::error::No TEST-*.xml under {results_dir}. connectedDebugAndroidTest "
              "goes green when it matches no tests, so this is the vacuous-green case "
              "BIT-62 exists to catch, not an empty-directory quirk.")
        return 1

    by_id = {}
    for case in cases:
        # A test that appears more than once — a second device, or a re-run — has
        # to pass every time it appears, so the worse outcome is the one kept. The
        # alternative silently lets one green attempt paper over a red one, which
        # is the retry-as-a-pass habit shared/flows/README.md rules out.
        existing = by_id.get(case.id)
        if existing is None or (existing.passed and not case.passed):
            by_id[case.id] = case

    print(f"{len(files)} result file(s), {len(by_id)} test(s), from {results_dir}")
    for test_id in sorted(by_id):
        marker = "required" if test_id in REQUIRED else "extra"
        print(f"  [{by_id[test_id].state:>7}] {test_id}  ({marker})")

    problems = []

    missing = sorted(REQUIRED - set(by_id))
    if missing:
        problems.append(
            "These tests did not run at all. Either they were renamed or deleted, or "
            "the run never reached them:\n"
            + "".join(f"    {test_id}\n" for test_id in missing)
            + "  If a rename was intended, update REQUIRED in this file in the same "
            "commit — that edit is the review point for dropping a check."
        )

    skipped = sorted(t for t, c in by_id.items() if c.skipped)
    if skipped:
        problems.append(
            "These tests were skipped. A skipped test does not fail a build, which is "
            "how a green run comes to prove nothing:\n"
            + "".join(f"    {test_id}\n" for test_id in skipped)
        )

    failed = sorted(t for t, c in by_id.items() if c.problem)
    if failed:
        problems.append(
            "These tests failed:\n"
            + "".join(f"    {t}\n      {by_id[t].problem.splitlines()[0][:300]}\n"
                      for t in failed)
        )

    canary = f"{PACKAGE}.CrossOriginIframeIsolationTest#theCrossOriginIframeActuallyRan"
    if canary in by_id and not by_id[canary].passed:
        problems.append(
            "theCrossOriginIframeActuallyRan did not pass, so read every other result "
            "in this run as unproven rather than as evidence. It asserts the "
            "cross-origin iframe loaded and reported in; without that, "
            '"no bridge was found" and "the iframe never got to look" are the same '
            "tick. Check that both LocalTestServer ports are reachable from inside "
            "the emulator and that cleartext to 127.0.0.1 is permitted for the test "
            "APK (feature/website/src/androidTest/AndroidManifest.xml)."
        )

    if problems:
        print()
        for problem in problems:
            print(f"::error::{annotate(problem)}")
            print(problem)
        print("check-instrumented-results: FAILED.")
        return 1

    print(f"\ncheck-instrumented-results: all {len(REQUIRED)} required tests ran and "
          "passed on a real Android image.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
