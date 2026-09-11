#!/usr/bin/env python3
"""Fail a green wallet `connectedDebugAndroidTest` that did not actually run the tests.

    android/scripts/check-wallet-instrumented-results.py
    android/scripts/check-wallet-instrumented-results.py --results-dir <dir> ...

Exit codes: 0 the required tests ran and passed · 1 they did not.

WHY THIS EXISTS

Same argument as check-instrumented-results.py, which this is modelled on, for a
suite where the stakes are higher. BIT-59's definition of done is "both tests
execute in CI and their results appear in the run", and the thing that most
cheaply fakes that is a task that went green having matched no tests.
`connectedDebugAndroidTest` exits 0 when it matched nothing, so Gradle's exit
code cannot distinguish "the wallet's backup exclusion holds" from "no test
asked".

That matters here in a way it does not for a normal suite.
`wallet-security-properties.md` §4 records this as the one wallet claim not yet
proven, and BIT-20 rule 5 makes it a *precondition* of the `match -> keep`
guard. A vacuous green does not leave the claim unproven-and-known; it converts
it into proven-and-wrong, and the thing it would unblock is the one whose
failure mode is publishing a revoked commitment.

WHY A SECOND FILE RATHER THAN A FLAG ON THE FIRST

REQUIRED there is a hard-coded literal on purpose — deriving it from the XML
would make it a description of whatever happened to run, which is the property
being checked. The same argument applies to keeping the two lists apart: this
suite and the S-36 suite fail for unrelated reasons, run in different jobs, and
must be renameable independently. Sharing a file would mean every wallet edit
touching the list that guards the WebView tests.

TWO MODULES, DELIBERATELY

The suite spans :core:wallet-ldk and :app, and which test lives where is
load-bearing rather than incidental — see the header of
ci-wallet-instrumented.sh. Briefly: KeystoreKeyInfoTest is a property of the
platform's Keystore and does not care which package asks, so it runs in the
library. BackupExclusionTest is a property of the *installed application* — its
merged manifest and its data directory as `bmgr` sees them — and :core:wallet-ldk
has no AndroidManifest.xml, so its test APK has backup ENABLED. Running it there
would measure the opposite configuration from the one we ship.

So this gate reads both modules' result directories, and a missing directory is
a failure rather than a skip: "the :app half did not run" is precisely the
regression that would leave the backup claim unchecked while the job stayed
green.

NO DEPENDENCIES, DELIBERATELY

stdlib only, matching check-instrumented-results.py, ci-runs.py and
shared/test-ids/*.py: these checks run on a runner, on a Mac and in a container,
with no pip step in front of them.
"""

import argparse
import pathlib
import sys
import xml.etree.ElementTree as ElementTree

ANDROID_DIR = pathlib.Path(__file__).resolve().parents[1]

LDK_PACKAGE = "com.bittr.android.core.wallet.ldk.seed"
APP_PACKAGE = "com.bittr.android"

# Every test that must have run and passed for BIT-59 to have done its job.
#
# The comments are not decoration: this list is the only place in the repo that
# says what the wallet emulator job is *for*, and a future reader deciding
# whether a rename is safe needs to know which of these is load-bearing.
REQUIRED = {
    # --- :core:wallet-ldk — what the platform actually gave us (BIT-8 rule 2) ---
    #
    # KeystoreKeySpecTest already proves what we ASKED for, on the JVM. These
    # read KeyInfo back off a key the platform really generated, which is the
    # only thing that can catch an OEM build that ignored a flag.
    f"{LDK_PACKAGE}.KeystoreKeyInfoTest#neitherAuthenticationFlagSurvivesKeyGeneration",
    f"{LDK_PACKAGE}.KeystoreKeyInfoTest#theBlobRoundTripsThroughTheRealKeystore",
    f"{LDK_PACKAGE}.KeystoreKeyInfoTest#twoWrapsOfTheSamePlaintextDiffer",
    f"{LDK_PACKAGE}.KeystoreKeyInfoTest#deletingTheKeyMakesTheBlobUnreadableAndThatIsRecoverable",
    # Records the observed security level per device rather than asserting one:
    # API 26-27 legitimately falls back to software. Required anyway, because the
    # BIT-18 device matrix is fed from its output and a silently dropped test
    # stops feeding it without anything going red.
    f"{LDK_PACKAGE}.KeystoreKeyInfoTest#recordTheObservedSecurityLevel",
    # --- :app — the installed application (BIT-8 rule 4 / BIT-20 rule 5) -------
    #
    # theBackupTransportIsActuallyAvailable is the canary: it is the reason the
    # other backup results mean anything, because on an image with no transport
    # "the backup set excluded our files" and "no backup set was ever produced"
    # are the same tick.
    f"{APP_PACKAGE}.BackupExclusionTest#theBackupTransportIsActuallyAvailable",
    f"{APP_PACKAGE}.BackupExclusionTest#theInstalledPackageHasBackupDisabled",
    # These two read the INSTALLED APK — its merged binary manifest and its
    # compiled resources — rather than the source tree BackupExclusionRulesTest
    # reads on the JVM. That is the difference between "we wrote the rule" and
    # "the rule survived the manifest merge and aapt", and a library dependency
    # re-adding allowBackup is exactly the kind of thing only the former sees.
    f"{APP_PACKAGE}.BackupExclusionTest#theInstalledManifestPointsAtOurDataExtractionRules",
    f"{APP_PACKAGE}.BackupExclusionTest#theInstalledRulesExcludeTheWalletDirectoryFromBothPaths",
    f"{APP_PACKAGE}.BackupExclusionTest#everyWalletFileLandedUnderNoBackup",
    f"{APP_PACKAGE}.BackupExclusionTest#aCloudBackupRunProducesNoBackupSetForThisPackage",
    # Asserts what is observable about the D2D path and prints the residual gap.
    # Required so that the gap keeps being REPORTED: deleting this test would
    # remove the only line in a green run that says D2D is not proven, which is
    # how "not yet proven" quietly becomes "proven".
    f"{APP_PACKAGE}.BackupExclusionTest#theDeviceTransferPathIsRecordedBecauseItCannotBeDriven",
}

CANARY = f"{APP_PACKAGE}.BackupExclusionTest#theBackupTransportIsActuallyAvailable"

MODULES = ("core/wallet-ldk", "app")

# AGP has moved this directory between major versions — `androidTest-results/`
# gained a `connected/` level, then a variant level under it — and the failure
# mode of hard-coding the wrong one is a FALSE RED after an emulator boot, which
# is the most expensive kind of wrong this file could be. So the default is the
# first of these that exists, per module, and `--results-dir` overrides.
#
# Only `outputs/` is searched, never `build/` wholesale: unit-test XML lands in
# `build/test-results/` and is written by a task that needs no device. Reading it
# here would let `./gradlew test` satisfy a gate whose entire claim is "these ran
# on a real Android image".
RESULTS_CANDIDATES = (
    "build/outputs/androidTest-results/connected",
    "build/outputs/androidTest-results",
    "build/outputs/connected_android_test_additional_output",
)


def module_results_dir(module):
    """The first AGP results layout that exists for `module`, else None."""
    for candidate in RESULTS_CANDIDATES:
        path = ANDROID_DIR / module / candidate
        if path.is_dir():
            return path
    return None


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
        action="append",
        default=None,
        help="An androidTest-results directory. Repeatable. Defaults to the "
             "first known AGP layout that exists under each of "
             f"{', '.join(MODULES)}.",
    )
    args = parser.parse_args(argv)

    problems = []

    if args.results_dir:
        results_dirs = list(args.results_dir)
        missing_dirs = [d for d in results_dirs if not d.is_dir()]
        if missing_dirs:
            for path in missing_dirs:
                print(f"::error::No such results directory: {path}")
            return 1
    else:
        results_dirs = []
        for module in MODULES:
            found = module_results_dir(module)
            if found is None:
                # Not a skip. A module whose results are absent ran no tests, and
                # the :app half going missing is exactly how the backup claim
                # would end up unchecked behind a green job.
                problems.append(
                    f"No instrumented-test results under android/{module}. Gradle "
                    "wrote none, which means no test in that module ran. Looked "
                    "for:\n"
                    + "".join(f"    {module}/{c}\n" for c in RESULTS_CANDIDATES)
                )
            else:
                results_dirs.append(found)

    files = []
    cases = []
    for results_dir in results_dirs:
        found_files, found_cases = collect(results_dir)
        if not found_files:
            problems.append(
                f"No TEST-*.xml under {results_dir}. connectedDebugAndroidTest goes "
                "green when it matches no tests, so this is the vacuous-green case "
                "this gate exists to catch, not an empty-directory quirk."
            )
        files.extend(found_files)
        cases.extend(found_cases)

    by_id = {}
    for case in cases:
        # A test that appears more than once — a second device, or a re-run — has
        # to pass every time it appears, so the worse outcome is the one kept. The
        # alternative silently lets one green attempt paper over a red one, which
        # is the retry-as-a-pass habit shared/flows/README.md rules out.
        existing = by_id.get(case.id)
        if existing is None or (existing.passed and not case.passed):
            by_id[case.id] = case

    print(f"{len(files)} result file(s), {len(by_id)} test(s), from "
          f"{len(results_dirs)} module(s)")
    for test_id in sorted(by_id):
        marker = "required" if test_id in REQUIRED else "extra"
        print(f"  [{by_id[test_id].state:>7}] {test_id}  ({marker})")

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

    if CANARY in by_id and not by_id[CANARY].passed:
        problems.append(
            "theBackupTransportIsActuallyAvailable did not pass, so read every other "
            "backup result in this run as unproven rather than as evidence. It "
            "asserts the Backup Manager is enabled and a transport is selected; "
            "without that, no backup set is produced for ANY package and "
            '"the wallet files were excluded" and "nothing was backed up at all" '
            "are the same tick. Check the transport setup in "
            "android/scripts/ci-wallet-instrumented.sh, and that the emulator image "
            "ships com.android.localtransport."
        )

    # Said on every run, green or red. The point of BIT-59 is to replace a claim
    # made from memory with a measured result, and a run that proves the cloud
    # path while saying nothing about device-to-device would be read as proving
    # both. wallet-security-properties.md §4 is where that gap is tracked.
    print("\nNOTE: the API 31+ device-to-device transfer path is NOT proven by this "
          "suite — `bmgr` has no D2D mode to drive. BackupExclusionTest asserts what "
          "is observable about it and prints BACKUP_EXCLUSION_D2D; the residual gap "
          "and its halt condition are wallet-security-properties.md §4.")

    if problems:
        print()
        for problem in problems:
            print(f"::error::{problem.splitlines()[0]}")
            print(problem)
        print("check-wallet-instrumented-results: FAILED.")
        return 1

    print(f"check-wallet-instrumented-results: all {len(REQUIRED)} required tests ran "
          "and passed on a real Android image.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
