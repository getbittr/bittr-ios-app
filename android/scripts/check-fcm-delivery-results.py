#!/usr/bin/env python3
"""Fail a green `fcm-delivery` run whose device-side preconditions did not run.

    android/scripts/check-fcm-delivery-results.py
    android/scripts/check-fcm-delivery-results.py --results-dir <dir>

Exit codes: 0 the required tests ran and passed · 1 they did not.

WHY THIS EXISTS

BIT-135. `connectedDebugAndroidTest` exits 0 when it matched no tests, and this
job matches tests by ANNOTATION — `-Pandroid.testInstrumentationRunnerArguments.
annotation=com.bittr.android.RequiresPlayServices`. A filter that matches nothing
is one typo away and produces a task that is green, fast, and empty.

That matters more here than it would for an ordinary suite, because this job's
real claim is not in the test results at all. `FcmDeliveryTest` only leaves the
device in the state a wake needs — Play services present, this APK registered
against `bittr-regtest`, a wallet on disk, a registration token handed off. The
delivery itself is driven from the host afterwards by `ci-fcm-delivery.sh`. So an
empty instrumented run does not merely prove less; it means the host phase is
about to send a message to a device that has no wallet and no hand-off, report no
wake, and be RIGHT — about a device nothing prepared.

WHY A SECOND FILE RATHER THAN A FLAG ON check-wallet-instrumented-results.py

That file's header gives the argument and it applies here verbatim: REQUIRED is a
hard-coded literal on purpose, the two suites fail for unrelated reasons, they run
in different JOBS ON DIFFERENT IMAGES, and they must be renameable
independently. Sharing a file would mean every FCM edit touching the list that
guards the backup claim — and, worse, would put both jobs' REQUIRED sets in one
place while each job can only ever satisfy half of them.

It is deliberately the *smaller* of the two files. This one reads one module.

WHAT IT DOES NOT DECIDE

Whether a message was delivered. That verdict is `ci-fcm-delivery.sh`'s, from
logcat on the host, for the same reason `check-backup-set.sh` owns the backup
verdict: the evidence outlives the process that produced it and the instrumented
run cannot see it. A green here plus no `FCM delivery` notice in the run's
annotations is not a result yet.

NO DEPENDENCIES, DELIBERATELY

stdlib only, matching every other check in this directory: these run on a runner,
on a Mac and in a container, with no pip step in front of them.
"""

import argparse
import pathlib
import re
import sys
import xml.etree.ElementTree as ElementTree

ANDROID_DIR = pathlib.Path(__file__).resolve().parents[1]

APP_PACKAGE = "com.bittr.android"

MAX_ANNOTATION = 4000

# Every test that must have run and passed for this job's host phase to mean
# anything. Named per method rather than per class, for the reason
# check-wallet-instrumented-results.py's list gives: naming the class would let
# two of three disappear without a word.
REQUIRED = {
    # The image. ASSERTED here, unlike FcmWakeTest's recorded twin, because in
    # this job "no Play services" is not an observation about the image — it is
    # the job having booted the wrong one, which makes every other result vacuous
    # and makes the send below address a device that was never addressable.
    #
    # It is also the guard on the annotation filter. If `notAnnotation` is ever
    # dropped from ci-wallet-instrumented.sh, this method fails there naming the
    # image rather than failing somewhere that reads like an FCM problem.
    f"{APP_PACKAGE}.FcmDeliveryTest#playServicesAreOnThisImage",
    # BIT-123's standing note, on the device. GoogleServicesConfigTest pins the
    # committed configs on the JVM; this reads what FirebaseApp actually
    # initialised with in the installed APK, after the google-services plugin and
    # aapt have both had it. Required by name because the host phase is about to
    # point a real credential at this device, and the only other Bittr project is
    # bittr-prod — whose registration tokens are real user devices.
    f"{APP_PACKAGE}.FcmDeliveryTest#thisApkSendsAndReceivesThroughTheRegtestProject",
    # The hand-off. Without it the host has no address, and without the wallet
    # BackgroundWake answers NoWallet — which is the same silence as an
    # undelivered message, i.e. the one distinction this whole job exists to draw.
    f"{APP_PACKAGE}.FcmDeliveryTest#aWalletAndARegistrationTokenAreLeftForTheHostToWake",
}

# The method whose failure makes every other result in this run unreadable, in
# the sense check-wallet-instrumented-results.py's CANARY means it.
CANARY = f"{APP_PACKAGE}.FcmDeliveryTest#playServicesAreOnThisImage"

MODULE = "app"

# Same three layouts and the same reasoning as the wallet gate: AGP has moved
# this directory between major versions and the failure mode of hard-coding the
# wrong one is a FALSE RED after an emulator boot. Only `outputs/` is searched,
# never `build/` wholesale — unit-test XML lands in `build/test-results/` and is
# written by a task that needs no device, so reading it here would let
# `./gradlew test` satisfy a gate whose entire claim is "this ran on a real
# Play-services image".
RESULTS_CANDIDATES = (
    "build/outputs/androidTest-results/connected",
    "build/outputs/androidTest-results",
    "build/outputs/connected_android_test_additional_output",
)

# What the suite prints per run. FCM_DELIVERY_IMAGE says which image was booted;
# FCM_DELIVERY_TOKEN says a token was minted and how long it was.
EVIDENCE_PREFIXES = ("FCM_DELIVERY_IMAGE", "FCM_DELIVERY_TOKEN")

# A registration token is a long run of these and nothing else. Used only to
# assert that one never reaches the XML — see check_no_token_leaked.
TOKEN_SHAPED = re.compile(r"[A-Za-z0-9_:.-]{100,}")


def annotate(text):
    """Encode a multi-line problem so all of it survives into an annotation.

    Identical in intent to check-wallet-instrumented-results.py's, and identical
    for a reason: a workflow command is ONE line, everything after the first
    newline is ordinary log output, and on this PUBLIC repo the job log answers
    403 while annotations answer 200. `%` is escaped BEFORE `%0A` is introduced,
    or a percent sign in a test's own failure message would corrupt the escapes
    added after it.
    """
    text = text.rstrip()
    if len(text) > MAX_ANNOTATION:
        text = text[:MAX_ANNOTATION] + "\n… truncated; full text is above this line."
    return text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def results_dir():
    """The first AGP results layout that exists for :app, else None."""
    for candidate in RESULTS_CANDIDATES:
        path = ANDROID_DIR / MODULE / candidate
        if path.is_dir():
            return path
    return None


class Case:
    """One <testcase>, reduced to what this gate has an opinion about."""

    def __init__(self, element):
        self.id = f"{element.get('classname', '?')}#{element.get('name', '?')}"
        # AGP writes <skipped/> for @Ignore and for a failed assumption alike;
        # both mean "this did not run". There should be none in this job at all:
        # the image precondition is ASSERTED rather than assumed precisely so
        # that a wrong image is a red and not a skip.
        self.skipped = element.find("skipped") is not None
        problems = list(element.findall("failure")) + list(element.findall("error"))
        self.problem = None
        if problems:
            # Attribute first (it is the one-line summary when present), element
            # text second. For connected tests the `message` attribute is
            # routinely absent and the assertion text is the element's TEXT, so
            # reading only the attribute reports every real failure as
            # "(no message)". `or "(no message)"` last, because a <failure/> with
            # neither would otherwise store "" — which is falsy, and would make a
            # failed test read as passed.
            self.problem = (
                (problems[0].get("message") or "").strip()
                or (problems[0].text or "").strip()
                or "(no message)"
            )

    @property
    def passed(self):
        return not self.skipped and self.problem is None

    @property
    def state(self):
        if self.skipped:
            return "SKIPPED"
        return "FAILED" if self.problem else "passed"


def collect(directory):
    """Every <testcase> under `directory`, the files, and the evidence lines."""
    files = sorted(directory.rglob("TEST-*.xml"))
    cases = []
    evidence = []
    system_out = []
    for path in files:
        try:
            root = ElementTree.parse(path).getroot()
        except ElementTree.ParseError as exc:
            print(f"::error::{path} is not parseable XML ({exc}). The test run did "
                  "not finish writing its results; treat this as a failed run.")
            raise SystemExit(1)
        for case in root.iter("testcase"):
            cases.append(Case(case))
        for out in root.iter("system-out"):
            for line in (out.text or "").splitlines():
                system_out.append(line)
                stripped = line.strip()
                if stripped.startswith(EVIDENCE_PREFIXES):
                    evidence.append(stripped)
    return files, cases, evidence, system_out


def check_no_token_leaked(system_out):
    """A registration token must never reach the result XML.

    `shared/docs/privacy-disclosure.md` lists the FCM registration token as a
    per-install device identifier, and the whole reason the token route was
    chosen over a topic is that it costs NO code in any shipped artefact — a
    promise that is worth nothing if the test prints the token into a result file
    that is uploaded as an artefact and pasted into annotations.

    `FcmDeliveryTest` prints the token's LENGTH and not its value, which is what
    `BittrMessagingService.onNewToken` does. This is the check that the next
    person to add a diagnostic println does not quietly undo that. It looks for a
    token-SHAPED run of characters rather than for the token itself, because the
    token is not available here and must not be.
    """
    leaked = []
    for line in system_out:
        if not line.strip().startswith(EVIDENCE_PREFIXES):
            continue
        for candidate in TOKEN_SHAPED.findall(line):
            leaked.append(candidate[:20] + "…")
    return leaked


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--results-dir",
        type=pathlib.Path,
        default=None,
        help="An androidTest-results directory. Defaults to the first known AGP "
             f"layout that exists under {MODULE}.",
    )
    args = parser.parse_args(argv)

    problems = []

    directory = args.results_dir or results_dir()
    if directory is None:
        print("::error::" + annotate(
            f"No instrumented-test results under android/{MODULE}. Gradle wrote none, "
            "which means no test ran — so the device was never prepared, and any "
            "delivery result from the host phase is about an unprepared device. "
            "Looked for:\n"
            + "".join(f"    {MODULE}/{c}\n" for c in RESULTS_CANDIDATES)
        ))
        print("check-fcm-delivery-results: FAILED.")
        return 1
    if not directory.is_dir():
        print(f"::error::No such results directory: {directory}")
        return 1

    files, cases, evidence, system_out = collect(directory)

    if not files:
        problems.append(
            f"No TEST-*.xml under {directory}. connectedDebugAndroidTest goes green "
            "when it matches no tests, and this job selects tests by ANNOTATION — so "
            "this is most likely a mistyped "
            "-Pandroid.testInstrumentationRunnerArguments.annotation argument in "
            "ci-fcm-delivery.sh rather than an empty-directory quirk. It must name "
            "com.bittr.android.RequiresPlayServices exactly."
        )

    by_id = {}
    for case in cases:
        # A test that appears more than once has to pass every time, so the worse
        # outcome is the one kept — no retry-as-a-pass.
        existing = by_id.get(case.id)
        if existing is None or (existing.passed and not case.passed):
            by_id[case.id] = case

    print(f"{len(files)} result file(s), {len(by_id)} test(s), from android/{MODULE}")
    for test_id in sorted(by_id):
        marker = "required" if test_id in REQUIRED else "extra"
        print(f"  [{by_id[test_id].state:>7}] {test_id}  ({marker})")

    print("\nWhat the device reported:")
    if evidence:
        for line in evidence:
            print(f"  {line}")
    else:
        print("  (none — no FCM_DELIVERY_IMAGE or FCM_DELIVERY_TOKEN line in any "
              "<system-out>. Those are printed unconditionally by the tests that "
              "own them, so this means the tests did not get that far, or the "
              "runner did not file instrumentation stdout into the result XML — "
              "which is the known state of this repo's emulator jobs since run 110, "
              "tracked on BIT-114.)")

    reported = "\n".join(evidence) if evidence else (
        "No FCM_DELIVERY_IMAGE or FCM_DELIVERY_TOKEN line reached <system-out>. "
        "These are the per-run readings — which Play services version this image "
        "carries, and that a registration token of non-zero length was minted. "
        "Both facts are ALSO asserted, by playServicesAreOnThisImage and by "
        "aWalletAndARegistrationTokenAreLeftForTheHostToWake, so this is a "
        "diagnostics gap and not an unproven claim. Two causes, not "
        "distinguishable from here: the tests did not reach the print, or the "
        "runner did not file instrumentation stdout into the result XML. The "
        "latter has been the case on every emulator job in this repo since run "
        "110 and is tracked on BIT-114."
    )
    print(f"::notice title=FCM delivery — what the device reported::{annotate(reported)}")

    leaked = check_no_token_leaked(system_out)
    if leaked:
        problems.append(
            "A registration token appears to have been printed into the result XML:\n"
            + "".join(f"    {fragment}\n" for fragment in leaked)
            + "  shared/docs/privacy-disclosure.md lists the FCM registration token as a "
            "per-install device identifier, and these results are uploaded as an "
            "artefact and quoted into annotations. FcmDeliveryTest prints the token's "
            "LENGTH and never its value — the same rule BittrMessagingService.onNewToken "
            "follows. Whatever added a println of the value has to go."
        )

    missing = sorted(REQUIRED - set(by_id))
    if missing:
        # ALL of them missing and SOME of them missing call for opposite first
        # guesses, so the message says which shape this run has rather than
        # listing both causes every time. All missing is almost always the filter
        # — this job runs one class and selects it by annotation, so a mistyped
        # argument drops the whole suite at once and a rename drops one method.
        cause = (
            "Every required test is missing, which for this job is most often the "
            "annotation filter rather than a rename: ci-fcm-delivery.sh must pass "
            "-Pandroid.testInstrumentationRunnerArguments.annotation="
            "com.bittr.android.RequiresPlayServices, spelled exactly, and "
            "FcmDeliveryTest must still carry @RequiresPlayServices."
            if len(missing) == len(REQUIRED)
            else "Some but not all of them are missing, which is the shape of a "
            "rename rather than of a filter that matched nothing."
        )
        problems.append(
            "These tests did not run at all:\n"
            + "".join(f"    {test_id}\n" for test_id in missing)
            + f"  {cause}\n"
            + "  If a rename was intended, update REQUIRED in this file in the same "
            "commit — that edit is the review point for dropping a check."
        )

    skipped = sorted(t for t, c in by_id.items() if c.skipped)
    if skipped:
        problems.append(
            "These tests were skipped. A skipped test does not fail a build, which is "
            "how a green run comes to prove nothing — and nothing in this suite is "
            "written as an assumption, so a <skipped/> here means an @Ignore was added:\n"
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
            "playServicesAreOnThisImage did not pass, so read every other result in "
            "this run — including the host phase's delivery verdict — as 'did not "
            "look' rather than as evidence. Without Play services no registration "
            "token can be minted and no FCM message can reach this device at all, so "
            '"the wake did not fire" and "nothing could ever have been delivered" are '
            "the same silence. Check the emulator image in "
            ".github/workflows/fcm-delivery.yml: it must be google_apis, and the AVD "
            "cache key has to change whenever the image does or the old snapshot is "
            "restored under the new config."
        )

    print("\nNOTE: this gate does NOT decide whether a message was delivered. It "
          "decides whether the device was prepared for one. The delivery verdict is "
          "the 'FCM delivery' annotation, written by ci-fcm-delivery.sh from logcat "
          "on the HOST — because the wake happens after Gradle exits, in a process "
          "this suite is not running in. A green here with no 'FCM delivery' notice "
          "in the run is not a result yet. android/docs/wallet-node-device-tests.md "
          "§1 is where the row lives.")

    if problems:
        print()
        for problem in problems:
            print(f"::error::{annotate(problem)}")
            print(problem)
        print("check-fcm-delivery-results: FAILED.")
        return 1

    print(f"\ncheck-fcm-delivery-results: all {len(REQUIRED)} required tests ran and "
          "passed on a real Play-services image.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
