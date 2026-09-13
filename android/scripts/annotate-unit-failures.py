#!/usr/bin/env python3
"""Say out loud which unit test failed, in the one channel a reader can reach.

    android/scripts/annotate-unit-failures.py
    android/scripts/annotate-unit-failures.py --android-dir <dir>

Always exits 0. It is a reporter, not a gate: `./gradlew test` has already
decided the step's fate by the time this runs, and a reporter that can fail the
build would be able to turn a green run red by mis-parsing XML.

WHY THIS EXISTS

Run 98 (`3b2392a`) went red in the build job, at `./gradlew test`. Everything a
reader without repository credentials could learn about it was this:

    [failure] Process completed with exit code 1.

Job logs on this repository answer 403 without admin rights and artifacts answer
401, so check-run annotations are the only part of a run that is readable at all
from outside. That annotation is GitHub's own, it is emitted for every non-zero
step, and it does not distinguish the two cases that matter:

  * a unit test genuinely failed — there is a bug, and its name and assertion
    message are sitting in XML on the runner; or
  * nothing failed a test — Gradle died fetching a dependency, ran out of memory,
    or the daemon was killed — and the right response is to re-run, not to go
    looking for a bug that is not there.

Those two demand opposite responses and looked identical, which cost a full
re-run to tell apart. `check-instrumented-results.py` already learned this lesson
for the emulator job (see run 27 in its header); this is the same lesson applied
to the unit-test step, which had no reporter at all.

It deliberately does NOT read `outputs/androidTest-results/` — that is the
emulator job's evidence, and `check-instrumented-results.py` is careful that
`./gradlew test` can never satisfy a gate whose claim is "these ran on a real
Android image". The reverse care is taken here: this reads only
`build/test-results/`, which is written by tasks that need no device.

NO DEPENDENCIES, DELIBERATELY

stdlib only, matching check-instrumented-results.py and ci-runs.py: these run on
a runner, on a Mac and in a container, with no pip step in front of them.
"""

import argparse
import importlib.util
import pathlib
import sys
import xml.etree.ElementTree as ElementTree

SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent


def _sibling(name, path):
    """Import a sibling script whose filename is not an identifier."""
    spec = importlib.util.spec_from_file_location(name, SCRIPTS_DIR / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# Reused rather than reimplemented: failure_message knows that AGP and Gradle
# record a failure in two different places, detail knows the per-test budget, and
# annotate knows GitHub's escaping. A second, subtly different copy of any of
# those is how an annotation goes quiet again.
_checker = _sibling("check_instrumented_results", "check-instrumented-results.py")
annotate = _checker.annotate
detail = _checker.detail
failure_message = _checker.failure_message

TITLE = "Unit tests"


def result_files(android_dir):
    """Every JUnit XML any module's unit-test task wrote, in a stable order.

    `*/build/test-results/` is the Gradle convention and the glob is deliberately
    deep: modules nest (`feature/website`), and each module writes one directory
    per variant (`testDebugUnitTest`, `testReleaseUnitTest`).
    """
    return sorted(android_dir.glob("**/build/test-results/**/TEST-*.xml"))


def failures(paths):
    """(test id, message) for every failed or errored <testcase> in `paths`.

    A file that will not parse is reported as a failure of its own rather than
    skipped. Gradle truncates its XML when the JVM running the tests is killed —
    an OOM leaves exactly that — and "the file is unreadable" is a finding, not a
    reason to report nothing.
    """
    found = []
    for path in paths:
        try:
            root = ElementTree.parse(path).getroot()
        except ElementTree.ParseError as exc:
            found.append((str(path), f"unparseable XML ({exc}); the JVM writing "
                                     "it probably died mid-run"))
            continue
        for case in root.iter("testcase"):
            problems = list(case.findall("failure")) + list(case.findall("error"))
            if not problems:
                continue
            test_id = f"{case.get('classname', '?')}#{case.get('name', '?')}"
            found.append((test_id, failure_message(problems[0]) or "(no message)"))
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--android-dir",
        type=pathlib.Path,
        default=SCRIPTS_DIR.parent,
        help="the android/ directory to search (default: this script's parent)",
    )
    args = parser.parse_args(argv)

    paths = result_files(args.android_dir)
    found = failures(paths)

    if found:
        message = "These unit tests failed:\n"
        for test_id, text in found:
            message += f"  {test_id}\n{detail(text)}"
        annotate(message, TITLE)
        return 0

    # No failure in the XML. Said as a notice rather than left silent, because
    # silence here is indistinguishable from "this reporter never ran" — and the
    # absence of a finding IS the finding: it points at the toolchain rather than
    # at the tests. See run 98.
    scanned = f"{len(paths)} result file(s)"
    if not paths:
        scanned = ("no result files at all, so the failure happened before any "
                   "test task got to write one")
    print(
        f"::notice title={TITLE}::The unit-test step failed but no test did: "
        f"{scanned} searched under android/**/build/test-results/, none "
        "recording a failure or error. Read this as a toolchain failure — a "
        "dependency fetch, an OOM-killed JVM, a compile error in the test "
        "sources — and not as a wallet bug. Re-running is a reasonable first "
        "response, which it never is for a real test failure."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
