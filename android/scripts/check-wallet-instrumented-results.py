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
    anyone needed: the annotation for a red wallet run read "These tests failed:"
    with an empty list under it, which looks exactly like "no tests ran" and is
    not. `%` is escaped BEFORE `%0A` is introduced, or a percent sign in a test's
    own failure message would corrupt the escapes added after it.
    """
    text = text.rstrip()
    if len(text) > MAX_ANNOTATION:
        text = text[:MAX_ANNOTATION] + "\n… truncated; full text is above this line."
    return text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
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
    # BackupExclusionTest (BIT-101) is the behavioural half: plant a
    # wallet-bearing install, drive `bmgr`, and leave a real set on the local
    # transport. Three methods, @FixMethodOrder NAME_ASCENDING.
    #
    # It does NOT assert the set's contents, and since BIT-108 it deliberately
    # does not try. It used to delete what it planted, restore, and assert
    # nothing came back; `bmgr restore` kills the target process and the
    # instrumentation runs inside it, so that assertion died exactly when there
    # was a set worth checking and passed exactly when there was not. These three
    # methods passing therefore means THE CONDITIONS WERE CREATED, not that rule
    # 5 holds. The verdict comes from android/scripts/check-backup-set.sh, which
    # greps the transport's tree from the host in the same job — so a green here
    # with no backup-set notice in the run's annotations is not a result yet.
    #
    # backupManagerAndTheLocalTransportAreLiveOnThisDevice is the canary in the
    # sense CANARY below means it — not to be confused with the canary FILE the
    # suite plants, which is what check-backup-set.sh requires before calling a
    # clean grep evidence. This one is the reason the other two mean anything,
    # because on an image with no local transport "the backup set excluded our
    # files" and "no backup set was ever produced" are the same tick. It also
    # names com.android.localtransport specifically, which is what makes a
    # Play-image runner a legible red rather than a vacuous green.
    f"{APP_PACKAGE}.BackupExclusionTest#backupManagerAndTheLocalTransportAreLiveOnThisDevice",
    f"{APP_PACKAGE}.BackupExclusionTest#cloudBackupOfAWalletBearingInstallCarriesNoWalletMaterial",
    # The half `allowBackup="false"` may not cover, and the one BIT-20 §5.3
    # turns on. Required by name so that a `is_device_transfer` hook that stops
    # existing cannot quietly reduce this suite to one cloud test run twice.
    f"{APP_PACKAGE}.BackupExclusionTest#deviceTransferOfAWalletBearingInstallCarriesNoWalletMaterial",
    # InstalledBackupConfigurationTest is the configuration half, on the device.
    # These read the INSTALLED APK — its merged binary manifest and its compiled
    # resources — rather than the source tree BackupExclusionRulesTest reads on
    # the JVM. That is the difference between "we wrote the rule" and "the rule
    # survived the manifest merge and aapt", and a library dependency re-adding
    # allowBackup is exactly the kind of thing only the former sees.
    #
    # They are required alongside the three above because they are what makes a
    # red BackupExclusionTest readable: green here plus red there rules out "we
    # misconfigured it" and leaves the halt.
    f"{APP_PACKAGE}.InstalledBackupConfigurationTest#theInstalledPackageHasBackupDisabled",
    f"{APP_PACKAGE}.InstalledBackupConfigurationTest#theInstalledManifestPointsAtOurDataExtractionRules",
    f"{APP_PACKAGE}.InstalledBackupConfigurationTest#theInstalledRulesExcludeTheWalletDirectoryFromBothPaths",
    f"{APP_PACKAGE}.InstalledBackupConfigurationTest#everyWalletFileLandedUnderNoBackup",
}

CANARY = (
    f"{APP_PACKAGE}.BackupExclusionTest#backupManagerAndTheLocalTransportAreLiveOnThisDevice"
)

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
        #
        # The ATTRIBUTE is not where AGP puts the interesting part. For connected
        # tests the `message` attribute is routinely absent and the assertion text
        # and stack trace are the element's TEXT — so reading only the attribute
        # reported both of run 34692523156's real failures as "(no message)",
        # which named the tests and then said nothing about them. Attribute
        # first (it is the one-line summary when present), element text second,
        # and the literal only when there is genuinely neither.
        self.problem = None
        # An EMPTY <failure> — no attribute and no text — is not just an
        # unhelpful message, it is a different event. Every assertion in this
        # suite is written with a message attached, so a failure carrying none
        # did not come from an assertion: it is what the runner synthesises for
        # the test that was in flight when the instrumentation process died.
        # Kept as a separate flag because the distinction decides whether a red
        # run is read as a product finding or as a harness one.
        self.problem_empty = False
        if problems:
            text = (
                (problems[0].get("message") or "").strip()
                or (problems[0].text or "").strip()
            )
            self.problem_empty = not text
            self.problem = text or "(no message)"

    @property
    def passed(self):
        return not self.skipped and self.problem is None

    @property
    def state(self):
        if self.skipped:
            return "SKIPPED"
        return "FAILED" if self.problem else "passed"


# Prefixes the suite prints its per-run observations under. These are the lines
# that say WHICH of the two green outcomes a run got — a real backup set that
# excluded our material, or a package the framework declined outright — and
# which of the two Keystore flags the device was able to report on.
#
# They go to instrumentation stdout, which AGP puts in <system-out> in the XML
# and in the HTML report. Both are artefacts, and downloading a workflow
# artefact needs a token that reading a public run's annotations does not. A
# result nobody can read without credentials is most of the way back to no
# result, so the gate lifts these into the job log itself.
EVIDENCE_PREFIXES = ("BACKUP_EXCLUSION", "KEYSTORE_KEY_INFO")


def evidence_lines(root):
    """Lines under EVIDENCE_PREFIXES from every <system-out> in one result file."""
    found = []
    for out in root.iter("system-out"):
        for line in (out.text or "").splitlines():
            stripped = line.strip()
            if stripped.startswith(EVIDENCE_PREFIXES):
                found.append(stripped)
    return found


def collect(results_dir):
    """Every <testcase> under results_dir, the files, and the evidence lines."""
    files = sorted(results_dir.rglob("TEST-*.xml"))
    cases = []
    evidence = []
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
        evidence.extend(evidence_lines(root))
    return files, cases, evidence


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
    evidence = []
    for results_dir in results_dirs:
        found_files, found_cases, found_evidence = collect(results_dir)
        if not found_files:
            problems.append(
                f"No TEST-*.xml under {results_dir}. connectedDebugAndroidTest goes "
                "green when it matches no tests, so this is the vacuous-green case "
                "this gate exists to catch, not an empty-directory quirk."
            )
        files.extend(found_files)
        cases.extend(found_cases)
        evidence.extend(found_evidence)

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

    # Before the verdict, because on a red run this is the context the verdict
    # has to be read against — and on a green one it is the difference between
    # "the rules were exercised and held" and "the package was never offered to
    # a transport". Absence is itself reported: these lines are printed
    # unconditionally by the tests that own them, so none arriving means those
    # tests did not reach the print, whatever their recorded outcome says.
    print("\nWhat the device reported:")
    if evidence:
        for line in evidence:
            print(f"  {line}")
    else:
        print("  (none — no BACKUP_EXCLUSION or KEYSTORE_KEY_INFO line in any "
              "<system-out>. Those are printed unconditionally by the tests that "
              "own them, so this means the tests did not get that far, or the "
              "runner did not capture instrumentation stdout.)")

    # ...and again as an annotation, which is the part that matters.
    #
    # The previous commit put these lines in the job log and called the problem
    # solved. It was not: on this public repo the job log answers 403 and
    # artifacts answer 401, so "in the log" means "readable by a signed-in
    # maintainer and by nobody else" — the same inaccessibility that made the
    # result unreadable in the first place, moved one step. Annotations are the
    # only channel that answers 200 without a token, which is why every other
    # verdict in this file goes through one. Emitted on green runs too: on a
    # green run this IS the result, because it says which of the two green
    # outcomes the run got.
    # Built outside the f-string on purpose: a backslash inside an f-string
    # expression is a syntax error before Python 3.12, and this script's own
    # rule is stdlib-only on whatever the runner ships.
    # The absence wording is deliberately agnostic about the cause, because the
    # first version was not and was wrong within one run. It said absence meant
    # "the tests did not reach the print"; run 110 had KeystoreKeyInfoTest pass
    # all five cases — it plainly reached the print — and still reported no
    # lines. So the lines are printed and do not land in <system-out>: AGP does
    # not file instrumentation stdout there, which is a wrong assumption in THIS
    # script about where to look, not an observation about the device. Known
    # cause as of run 110; tracked on BIT-108, since the fix (get the
    # observation to the host) is the same one the assertion needs.
    reported = "\n".join(evidence) if evidence else (
        "No BACKUP_EXCLUSION or KEYSTORE_KEY_INFO line reached <system-out>. Read "
        "any pass in this run as UNPROVEN either way: these lines are what say "
        "which of the two green outcomes a run got. Two causes, and they are not "
        "distinguishable from here — the tests did not reach the print, or the "
        "lines were printed and the runner did not file instrumentation stdout "
        "into the result XML. The latter is the known cause as of run 110 and is "
        "tracked on BIT-108; do not read this as a device finding without "
        "checking which one it was."
    )
    print(f"::notice title=What the device reported::{annotate(reported)}")

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

    # An empty <failure> alongside required tests that never ran is the
    # signature of the instrumentation process dying mid-test, not of an
    # assertion. Named here so the next reader does not have to re-derive it:
    # run 107 produced exactly this shape and the obvious reading — "the
    # device-transfer path leaked wallet material" — would have been the §5.3
    # halt, declared on evidence that says nothing of the kind.
    #
    # It stays a FAILURE. This block explains a red run; it never excuses one.
    # The distinction it draws is about which issue the red belongs to, and the
    # host-side check-backup-set.sh verdict is what settles it, because that one
    # reads the transport's own tree and needs no surviving process.
    empty_failures = sorted(t for t in failed if by_id[t].problem_empty)
    if empty_failures and missing:
        problems.append(
            "Read the two blocks above together before acting on either. These "
            "failed with a COMPLETELY empty <failure> — no message, no stack "
            "trace:\n"
            + "".join(f"    {t}\n" for t in empty_failures)
            + "  Every assertion in this suite is written with a message attached, "
            "so a failure carrying none did not come from an assertion. Together "
            "with required tests that did not run at all, this is what the runner "
            "records when the instrumentation process DIES mid-test — and this "
            "suite restores data into the very process it is running in.\n"
            "  So this is most likely a finding about the test harness, NOT about "
            "the product, and it is NOT on its own the BIT-20 §5.3 halt. What "
            "settles it is the `Backup set inspection` annotation: that check "
            "greps the transport's own on-disk tree from the HOST, so it survives "
            "a process that does not. A marker found there is the halt. This "
            "signature alone is not."
        )

    if CANARY in by_id and not by_id[CANARY].passed:
        problems.append(
            "backupManagerAndTheLocalTransportAreLiveOnThisDevice did not pass, so "
            "read every other backup result in this run as unproven rather than as "
            "evidence. It asserts the Backup Manager is enabled and that "
            "com.android.localtransport/.LocalTransport is offered; without that, no "
            "backup set is produced for ANY package and "
            '"the wallet files were excluded" and "nothing was backed up at all" '
            "are the same tick. Check the transport setup in "
            "android/scripts/ci-wallet-instrumented.sh, and that the emulator image "
            "is an AOSP one — Play images offer the GMS transports instead, which "
            "cannot be restored from on demand."
        )

    # Said on every run, green or red. A reader who sees two green backup tests
    # should be told, in the run, which layer each of them exercised — because
    # `allowBackup="false"` makes the package ineligible outright, and an
    # ineligible package produces an empty set that satisfies "nothing of ours
    # came back" without the <device-transfer> rules having been consulted at
    # all. That is a pass for BIT-20 rule 5 and it is NOT a proof that the rules
    # work; the BACKUP_EXCLUSION lines in the instrumentation output say which
    # of the two happened, per path.
    print("\nNOTE: read the 'What the device reported' annotation on this run "
          "before quoting this suite. Each path prints the framework's own result "
          "for the package and whether the canary came back: canaryReturned=true "
          "means the set was real and excluded our material, canaryReturned=false "
          "with a declining result means the package was ineligible and exclusion "
          "was never exercised on that path. Both are passes; only the first is "
          "evidence about the rules. wallet-security-properties.md §4 is where "
          "that distinction is tracked.")

    if problems:
        print()
        for problem in problems:
            print(f"::error::{annotate(problem)}")
            print(problem)
        print("check-wallet-instrumented-results: FAILED.")
        return 1

    print(f"check-wallet-instrumented-results: all {len(REQUIRED)} required tests ran "
          "and passed on a real Android image.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
