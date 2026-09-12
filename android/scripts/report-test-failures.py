#!/usr/bin/env python3
"""Turn a red Gradle test task into GitHub check-run annotations.

    android/scripts/report-test-failures.py                  # scan android/**/build/test-results
    android/scripts/report-test-failures.py --root <dir>     # scan somewhere else
    android/scripts/report-test-failures.py --max 5          # cap the annotations

Always exits 0. This runs when the job has ALREADY failed; its job is to say
what failed, and a non-zero exit here would only replace one uninformative
failure with another.

WHY THIS EXISTS, AND WHY IT IS NOT AN UPLOADED ARTIFACT

A red `Unit tests` step in the build job takes all three emulator jobs with it
(they `needs: build`), so BIT-59's own job never executes. That happened on run
42 and again on run 47, and run 47 cost an entire round of work to the fact that
NOTHING ABOUT THE FAILURE WAS READABLE FROM OUTSIDE. Specifically, on this repo
and for the agents working in it:

  - The job-log endpoint, /actions/jobs/{id}/logs, answers 403 "Must have admin
    rights to Repository" to every token available here — including none, which
    is the normal case, since getbittr/bittr-ios-app is public and the rest of
    the Actions API reads fine anonymously.
  - The run page is JS-rendered, so scraping it yields job names without step
    conclusions.
  - ARTIFACTS ARE NOT A WAY OUT. This was the fix attempted first, and it does
    not work: /actions/artifacts/{id}/zip answers 401 "Requires authentication"
    anonymously, and the web download URL 404s after its redirect. An uploaded
    JUnit report is readable by a signed-in human and by nothing else.

What IS readable anonymously is the check-run annotation list,
/repos/{owner}/{repo}/check-runs/{job_id}/annotations. Run 47's build job has
three entries there and they are the only thing recoverable about it: two Node
deprecation warnings, and 'Process completed with exit code 1.'

So the diagnosis has to be put where the annotations are, which means emitting
`::error::` workflow commands from inside the job. That is what this does: it
reads the JUnit XML Gradle has already written and re-states each failure as a
workflow command, so "which test, and what did it say" survives into a channel
that needs no credentials to read.

The artifact upload is kept alongside it. It carries the full HTML report and
costs nothing; it is simply not the channel this script exists to fill.

BOTH RESULT LAYOUTS

The pure-Kotlin modules (:core:common, :core:wallet, :core:wallet-stub,
:core:lnurl) write build/test-results/test/, the Android ones write
build/test-results/testDebugUnitTest/ and testReleaseUnitTest/. A glob over
test-results/ covers whichever module broke without naming the layouts.

NO XML AT ALL IS A FINDING

If the task died before any test ran — a Kotlin compile error in a test source
set, a Gradle configuration failure — there are no result files, and saying so
out loud is worth an annotation of its own. Otherwise this script would be
silent in exactly the case where the log is the only evidence and the log cannot
be read.

NO DEPENDENCIES, DELIBERATELY

stdlib only, matching check-wallet-instrumented-results.py, ci-runs.py and
shared/test-ids/*.py: these run on a runner with no pip step in front of them.
"""

import argparse
import pathlib
import sys
import xml.etree.ElementTree as ElementTree

ANDROID_DIR = pathlib.Path(__file__).resolve().parents[1]

# GitHub renders at most 10 annotations per step and keeps the rest only in the
# API response. Ten failures is already far past the point where the useful move
# is to read the report rather than the annotations, and a suite that broke
# wholesale (a bad shared fixture) would otherwise bury the first, most
# diagnostic failure under ninety identical ones.
DEFAULT_MAX = 10

# An assertion message in this repo can run to several paragraphs — the wallet
# and guard tests deliberately carry their whole diagnosis in the message. The
# annotation only needs enough to identify the failure; the artifact has the
# rest.
MESSAGE_CHARS = 1200


def escape(text):
    """Escape a string for a `::error::` workflow command's message body.

    Newlines are the load-bearing one: an un-escaped newline ends the command
    and the remaining lines are printed as ordinary log output, i.e. into the
    channel that cannot be read. %0A survives into the annotation intact.
    """
    return (
        text.replace("%", "%25")
        .replace("\r", "")
        .replace("\n", "%0A")
        .replace(":", "%3A")
        .replace(",", "%2C")
    )


def failures_in(path):
    """Yield (classname, name, kind, detail) for each failed/errored testcase.

    A malformed or truncated XML file is itself reported, rather than raising:
    Gradle writing half a result file is a symptom of the run dying mid-test,
    which is exactly the kind of failure this script is here to surface.
    """
    try:
        root = ElementTree.parse(path).getroot()
    except ElementTree.ParseError as error:
        yield (path.name, "(unparseable)", "error", f"{path}: {error}")
        return

    for case in root.iter("testcase"):
        for kind in ("failure", "error"):
            for node in case.findall(kind):
                detail = (node.get("message") or "") + "\n" + (node.text or "")
                yield (
                    case.get("classname") or path.stem,
                    case.get("name") or "(unnamed)",
                    kind,
                    detail.strip(),
                )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=pathlib.Path,
        default=ANDROID_DIR,
        help="Directory to scan for **/build/test-results/**/*.xml (default: android/).",
    )
    parser.add_argument(
        "--max",
        type=int,
        default=DEFAULT_MAX,
        help=f"Most annotations to emit (default: {DEFAULT_MAX}).",
    )
    args = parser.parse_args(argv)

    # sorted() so a run is reproducible and two runs of the same failure produce
    # the same annotation order — otherwise comparing runs means comparing sets.
    reports = sorted(args.root.glob("**/build/test-results/**/*.xml"))

    if not reports:
        print(
            "::error title=Unit tests failed with no test results::"
            + escape(
                "No JUnit XML was written under "
                f"{args.root}/**/build/test-results/, so the failure happened "
                "before any test ran — a compile error in a test source set, or "
                "a Gradle configuration failure. The step log has it; the log is "
                "not readable without repository admin. Reproduce with "
                "`./gradlew test --no-daemon` in android/."
            )
        )
        return 0

    found = []
    for report in reports:
        found.extend(failures_in(report))

    if not found:
        # Worth its own annotation. A red task whose every result file is green
        # is a real and specific situation — the task failed outside the tests
        # themselves (a Robolectric/JVM crash after the last result was flushed,
        # an OOM, a Gradle verification task) — and silence here would read as
        # "nothing to report" when the truth is "not where you are looking".
        print(
            "::error title=Unit tests failed but every test passed::"
            + escape(
                f"Scanned {len(reports)} JUnit XML file(s) and found no failing "
                "testcase. The task failed outside the tests themselves — a "
                "worker JVM crash, an OOM, or a non-test task in the same "
                "invocation. Reproduce with `./gradlew test --no-daemon` in "
                "android/."
            )
        )
        return 0

    print(f"Found {len(found)} failing test(s) across {len(reports)} report file(s).")

    for classname, name, kind, detail in found[: args.max]:
        detail = detail[:MESSAGE_CHARS] or "(no message in the report)"
        print(
            f"::error title={classname}.{name} ({kind})::"
            + escape(f"{classname}#{name}\n\n{detail}")
        )

    hidden = len(found) - args.max
    if hidden > 0:
        print(
            "::error title=More failures than annotations::"
            + escape(
                f"{hidden} further failing test(s) are not annotated. The full "
                "set is in the unit-test-report artifact, and `./gradlew test "
                "--no-daemon` in android/ reproduces it."
            )
        )

    # Deliberately 0: see the module docstring. The step that ran the tests has
    # already failed the job.
    return 0


if __name__ == "__main__":
    sys.exit(main())
