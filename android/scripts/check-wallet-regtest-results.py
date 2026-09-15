#!/usr/bin/env python3
"""Every test the nightly regtest job exists to run, required by name (BIT-132).

The twin of check-wallet-instrumented-results.py, for the other wallet emulator
job, and it exists for the reason that file gives for keeping two lists apart:

    this suite and the S-36 suite fail for unrelated reasons, run in different
    jobs, and must be renameable independently. Sharing a file would mean every
    wallet edit touching the list that guards the WebView tests.

All three of those hold here with more force. This job runs nightly rather than
per-push, it runs against a private Bitcoin and Lightning network that the other
job does not have, and its red means something the other job cannot say: **a fund
handling claim went unmeasured.**

WHAT IS SHARED, AND WHAT IS NOT

The LIST is this file's. The XML PARSING is not: `Case`, `collect`,
`evidence_lines` and `annotate` are imported from check-wallet-instrumented-
results.py rather than copied. Those functions encode findings that cost real
runs to learn — that AGP files an empty `<failure/>` for the test that was in
flight when the instrumentation process died, that the assertion text is the
element's body and not its `message` attribute, that `%` has to be escaped before
`%0A` is introduced — and a second copy of them would drift away from those
findings one careless edit at a time. A bug fixed in one and not the other is
worse than either.

WHY A SKIP IS A FAILURE HERE TOO

Same rule, and it matters more. This job's suite is gated by a SOURCE SET rather
than by an assumption (see app/build.gradle.kts), precisely so that an
unconfigured build compiles these classes out instead of skipping them. So a
`<skipped/>` in THIS job's results cannot mean "no environment" — it means
something skipped a test that had an environment to measure, which is the one
outcome that would let the nightly job stay green while proving nothing.

NO DEPENDENCIES, DELIBERATELY

stdlib only, matching every other check in android/scripts.

Locally, after a run:
  python3 android/scripts/check-wallet-regtest-results.py
"""

import argparse
import importlib.util
import pathlib
import sys

ANDROID_DIR = pathlib.Path(__file__).resolve().parents[1]

APP_PACKAGE = "com.bittr.android"

# Only :app, where check-wallet-instrumented-results.py reads two modules.
#
# Not an omission. Every test in this suite is a property of the INSTALLED
# APPLICATION — its BuildConfig, the network it was compiled to reach, its
# foreground service, its process dying and coming back. A library module's
# instrumented tests run in a self-instrumenting test APK built from the
# library's own manifest, and :core:wallet-ldk has no AndroidManifest.xml: no
# foreground service declaration, no applicationId to `am kill`, and a
# BuildConfig that is not the one LdkEnvironmentConfig reads.
MODULES = ("app",)

# Every test that must have run and passed for the nightly regtest job to have
# done its job.
#
# Per method, by name, in the commit that writes the method — BIT-132's
# definition of done says so, and the reason is on the record in this repo:
# BdkAccountXpubParityTest spent its first two runs absent from the other gate's
# list, so the run that finally went green proved every required test ran and
# said nothing whatever about that one.
REQUIRED = {
    # --- The precondition, measured on the device (BIT-132 scope items 1-2) ----
    #
    # RegtestEnvironmentTest is the vacuity guard for everything else in this
    # job. wallet-node-device-tests.md's own summary is that K7 and K8 are not
    # blocked on hardware but on the `wallet-instrumented` job building a wallet
    # with NO NODE IN IT — so before any payment claim can be read, this job has
    # to have shown that its APK is on the other side of that branch and that the
    # network it names is actually answering.
    #
    # Each method is required separately because each one fails for a different
    # reason and only one of them is about our build:
    f"{APP_PACKAGE}.RegtestEnvironmentTest#theBuildCarriesAConfiguredRegtestEnvironment",
    f"{APP_PACKAGE}.RegtestEnvironmentTest#everyEndpointNamesTheEmulatorsOwnHost",
    # Esplora and Electrum are ONE electrs process listening twice, and they are
    # required as two tests anyway. A run where Esplora answers and Electrum does
    # not is a specific, quiet failure: the Lightning half works and the on-chain
    # balance is permanently zero, which is the exact case
    # LdkEnvironmentConfig.missingFields() calls out for the Electrum URL.
    f"{APP_PACKAGE}.RegtestEnvironmentTest#esploraAnswersASpendableTipHeight",
    f"{APP_PACKAGE}.RegtestEnvironmentTest#electrumAnswersServerVersion",
    f"{APP_PACKAGE}.RegtestEnvironmentTest#theLightningPeerAcceptsAConnection",
    # Records what this run saw rather than asserting it. Required by name for the
    # reason SeedReadableWhileLockedTest#recordTheLockStateTheseReadsHappenedIn is:
    # LND's node id is generated per bring-up, so this line is the only thing that
    # ties a payment result to the instance that held its HTLC. A rename that
    # dropped it would leave every future K7 verdict unattributable.
    f"{APP_PACKAGE}.RegtestEnvironmentTest#recordTheEnvironmentThisRunSaw",
    # --- K7 — an interrupted payment resolves to exactly one terminal outcome ---
    #
    # Four methods, four separate `am instrument` runs against one emulator boot,
    # sequenced by android/scripts/k7-interrupted-payment.sh. They are REQUIRED
    # individually and not as a class, because each phase failing means something
    # different and only the last one is a claim about the wallet:
    #
    #   1  the node came up and revealed an address to fund   — infrastructure
    #   2  it saw its coins and opened a channel              — infrastructure
    #   3  it paid a HELD invoice and the HTLC stuck at LND   — the window opened
    #   4  after the kill and the settle: one outcome, stable — THE CLAIM
    #
    # THEY DO NOT RUN IN THE UNDIRECTED SUITE, AND THAT IS WHY THEY ARE HERE.
    #
    # ci-wallet-regtest.sh runs `connectedDebugAndroidTest` with no class filter
    # and with `notAnnotation=com.bittr.android.HostDriven`, so these four are
    # filtered out of it — a filtered test is absent from the results rather than
    # `<skipped/>`, which this gate would fail. The host script then runs each by
    # name and preserves its XML under
    # android/app/build/outputs/androidTest-results/k7/phaseN, and ci-wallet-
    # regtest.sh passes every one of those directories to this file with
    # --results-dir.
    #
    # So the thing that catches a phase silently not running is exactly this list.
    # A method renamed in the test and not in the host script executes nowhere,
    # produces no XML, and is reported below as "did not run at all" — where
    # without these five lines it would be an empty space that reads, a year
    # later, exactly like a K7 that passed.
    f"{APP_PACKAGE}.K7InterruptedPaymentTest#phase1RevealTheAddressTheHostMustFund",
    f"{APP_PACKAGE}.K7InterruptedPaymentTest#phase2OpenAChannelToTheRegtestPeer",
    f"{APP_PACKAGE}.K7InterruptedPaymentTest#phase3PayTheHoldInvoiceAndLeaveItInFlight",
    # The one that is a fund-safety finding when it is red. The process was killed
    # with the HTLC accepted at the counterparty and the invoice was then settled,
    # so the money has left: a wallet reporting anything but exactly one
    # `Succeeded` record has either lost the claim or double-counted it. A rerun
    # that goes green does not withdraw that.
    f"{APP_PACKAGE}.K7InterruptedPaymentTest#phase4TheInterruptedPaymentResolvedToExactlyOneOutcome",
    # --- K8 — node lifecycle across Doze and App Standby ------------------------
    #
    # TWO CLASSES, AND THE SPLIT IS THE DESIGN RATHER THAN AN ACCIDENT OF SIZE.
    # android/docs/wallet-node-device-tests.md §4 settled it before either was
    # written: the two halves need different set-ups, and only one of them needs
    # a channel.
    #
    # The MACHINERY half runs in the undirected suite, beside
    # RegtestEnvironmentTest — a node, no channel, a forced deep-idle window.
    #
    #   theDeviceCanBeForcedIntoDeepIdleAtAll        — the emulator IMAGE
    #   theNodeAndItsForegroundServiceSurvive…       — THE CLAIM
    #   recordTheIdleMachineryThisRunSaw             — which machinery this was
    #
    # Required separately because the first one is not a claim about the wallet
    # at all. `dumpsys deviceidle force-idle` refuses on an image without the
    # idle machinery — one of the components ATD images are stripped of — and a
    # red there is a verdict about the AVD, where a red on the second is a
    # verdict about the foreground service. Those call for opposite
    # investigations, and a nightly job at 03:20 UTC should not make a reader
    # guess which one they have.
    f"{APP_PACKAGE}.K8DozeMachineryTest#theDeviceCanBeForcedIntoDeepIdleAtAll",
    f"{APP_PACKAGE}.K8DozeMachineryTest#theNodeAndItsForegroundServiceSurviveAForcedIdleWindow",
    # Records rather than asserts, and required by name for the reason
    # RegtestEnvironmentTest#recordTheEnvironmentThisRunSaw is: a green K8 row is
    # worth what the run's machinery was worth. The API level, the two idle-state
    # readings and the observed App Standby bucket are what separate "the node
    # survived Doze" from "this image has no Doze" — and the bucket in
    # particular is K8's own narrowing, because an app with a live foreground
    # service is one the platform re-derives as ACTIVE. See Doze.setStandbyBucket
    # for why that is recorded and never asserted.
    f"{APP_PACKAGE}.K8DozeMachineryTest#recordTheIdleMachineryThisRunSaw",
    #
    # The FRESHNESS half is @HostDriven and runs AFTER K7, over the channel K7
    # phase 2 opened and never closed. android/scripts/k8-doze-soak.sh sends to
    # the node's on-chain wallet and mines WHILE the device is inside its idle
    # window, and preserves the XML under androidTest-results/k8/freshness, which
    # ci-wallet-regtest.sh passes to this file with --results-dir.
    #
    # ONE METHOD, AND THAT IS A PLATFORM FACT. K7 is four instrumented runs
    # because it has to observe its own restart; this is the opposite constraint
    # — the node has to be ALIVE for the whole window, and the framework tears
    # the instrumented process down when a method returns. Split into phases
    # there would be no node in the window at all.
    #
    # ITS CLAIM IS NARROWED, and the narrowing is in the test, in the evidence
    # line and in wallet-node-device-tests.md §4's table. ChannelView carries no
    # monitor update id and ldk-node offers none, so "channel-monitor freshness"
    # as `wallet-core-spec` §6 words it is not observable through
    # LightningNodePort. What this measures is three proxies: the same channel
    # still ready and usable, the peer connected again, and the node's chain view
    # advanced past blocks mined while it was idle. A row that kept the spec's
    # wording over a test measuring proxies would be the dishonest one.
    #
    # A red K7 phase 2 makes this unrunnable rather than merely unreadable, and
    # this line is what turns that into "did not run at all" instead of silence.
    f"{APP_PACKAGE}.K8ChannelFreshnessTest#theChannelSurvivesAForcedIdleWindowAndTheNodeCatchesUp",
}

CANARY = f"{APP_PACKAGE}.RegtestEnvironmentTest#recordTheEnvironmentThisRunSaw"

# The prefix this suite prints its per-run observations under, lifted out of
# <system-out> into the job log and into an annotation — the annotation being the
# only channel that answers 200 without a token on this public repository. See
# check-wallet-instrumented-results.py's EVIDENCE_PREFIXES for the full argument.
EVIDENCE_PREFIXES = ("REGTEST_ENVIRONMENT", "K7_INTERRUPTED_PAYMENT", "K8_DOZE_SOAK")


def _shared():
    """check-wallet-instrumented-results.py's parsing, imported not copied.

    Hyphenated, so there is no `import` that reaches it — same loader shape the
    test files in this directory use.
    """
    path = ANDROID_DIR / "scripts" / "check-wallet-instrumented-results.py"
    spec = importlib.util.spec_from_file_location("check_wallet_instrumented", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


shared = _shared()


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
        for path in [d for d in results_dirs if not d.is_dir()]:
            print(f"::error::No such results directory: {path}")
            return 1
    else:
        results_dirs = []
        for module in MODULES:
            found = shared.module_results_dir(module)
            if found is None:
                problems.append(
                    f"No instrumented-test results under android/{module}. Gradle "
                    "wrote none, which means no test in that module ran. Looked "
                    "for:\n"
                    + "".join(f"    {module}/{c}\n" for c in shared.RESULTS_CANDIDATES)
                )
            else:
                results_dirs.append(found)

    files, cases, evidence = [], [], []
    for results_dir in results_dirs:
        found_files, found_cases, _ = shared.collect(results_dir)
        files.extend(found_files)
        cases.extend(found_cases)
        if not found_files:
            problems.append(
                f"No TEST-*.xml under {results_dir}. connectedDebugAndroidTest goes "
                "green when it matches no tests, so this is the vacuous-green case "
                "this gate exists to catch, not an empty-directory quirk."
            )
    # This suite's own prefixes, not the other gate's, so `evidence_lines` is
    # re-run here rather than taken from `collect`.
    for path in files:
        import xml.etree.ElementTree as ElementTree

        root = ElementTree.parse(path).getroot()
        for out in root.iter("system-out"):
            for line in (out.text or "").splitlines():
                stripped = line.strip()
                if stripped.startswith(EVIDENCE_PREFIXES):
                    evidence.append(stripped)

    by_id = {}
    for case in cases:
        # A test that appears more than once has to pass every time, so the worse
        # outcome wins. Same rule as the other gate, same reason: a retry is not
        # a pass.
        existing = by_id.get(case.id)
        if existing is None or (existing.passed and not case.passed):
            by_id[case.id] = case

    print(f"{len(files)} result file(s), {len(by_id)} test(s), from "
          f"{len(results_dirs)} module(s)")
    for test_id in sorted(by_id):
        marker = "required" if test_id in REQUIRED else "extra"
        print(f"  [{by_id[test_id].state:>7}] {test_id}  ({marker})")

    print("\nWhat the device reported:")
    for line in evidence or ["  (none)"]:
        print(f"  {line}")

    missing = sorted(REQUIRED - set(by_id))
    if missing:
        problems.append(
            "These required tests did not run at all:\n"
            + "".join(f"    {test_id}\n" for test_id in missing)
            + "  A test that is absent from the results is not a test that passed. "
            "If a rename was intended, update REQUIRED in this file in the same "
            "commit."
        )

    skipped = sorted(t for t, c in by_id.items() if c.skipped)
    if skipped:
        problems.append(
            "These tests were skipped. A skipped test does not fail a build, which "
            "is why it is checked here — and in THIS job a skip cannot mean 'no "
            "environment', because an unconfigured build compiles these classes "
            "out rather than skipping them (app/build.gradle.kts). So a skip here "
            "is a test that had a network to measure and did not:\n"
            + "".join(f"    {test_id}\n" for test_id in skipped)
        )

    failed = sorted(
        (t, c) for t, c in by_id.items() if t in REQUIRED and c.problem is not None
    )
    if failed:
        problems.append(
            "These required tests failed:\n"
            + "".join(
                f"    {test_id}\n      {case.problem.splitlines()[0][:400]}\n"
                for test_id, case in failed
            )
        )

    if CANARY in by_id and not by_id[CANARY].passed:
        problems.append(
            f"The canary ({CANARY}) did not pass. It is the line that says WHICH "
            "regtest network this run measured, and LND's node id is generated per "
            "bring-up — so without it no result from this run is attributable to "
            "the peer that produced it."
        )

    if problems:
        print()
        for problem in problems:
            print(problem)
        print(f"::error::{shared.annotate(chr(10).join(problems))}")
        return 1

    print(
        f"\ncheck-wallet-regtest-results: all {len(REQUIRED)} required tests ran "
        "and passed."
    )
    # ONE ANNOTATION PER PREFIX, NOT ONE FOR ALL THREE.
    #
    # `annotate` truncates at 4000 characters, which is the measured cap, and this
    # suite's evidence does not fit in one. Counted on the classes as written: the
    # environment lines, K7's four phases, K8's two result lines and the soak's
    # `tick` line every 30s of two 120s windows come to roughly 4700 characters.
    #
    # The half that would be lost is the half this job exists to report. Evidence
    # is appended in results-file order and K8's directories are passed last, so a
    # single truncated notice cuts K8 — including the **freshness** line, whose
    # narrowed wording (same channel ready and usable, peer reconnected, chain view
    # advanced — and NOT channel-monitor freshness as wallet-core-spec §6 words it)
    # is the one result here that cannot be re-derived from anything else. The
    # truncation note would say "full text is above this line", pointing at a job
    # log that answers 403 on this public repository.
    #
    # There is no limit on the NUMBER of annotations, only on each one's length, so
    # grouping costs nothing and removes the cliff. Emitted in EVIDENCE_PREFIXES
    # order rather than sorted, so the environment — the vacuity guard — is read
    # first, which is the order android/docs/wallet-node-device-tests.md asks for.
    for prefix in EVIDENCE_PREFIXES:
        group = [line for line in evidence if line.startswith(prefix)]
        if group:
            print(f"::notice::{shared.annotate(chr(10).join(group))}")
    # Anything that matched a prefix at collection time is in exactly one group
    # above, so this is unreachable unless EVIDENCE_PREFIXES is edited in one place
    # and not the other. Reported rather than dropped, because a line that no
    # longer reaches an annotation is a line nobody can read at all.
    ungrouped = [
        line for line in evidence
        if not any(line.startswith(p) for p in EVIDENCE_PREFIXES)
    ]
    if ungrouped:
        print(f"::warning::{shared.annotate(chr(10).join(ungrouped))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
