#!/usr/bin/env python3
"""Check that no shared Maestro flow names a platform's app id literally.

The shared flows in `onboarding/`, `features/` and `helpers/` are meant to drive
both platforms off one file, and the app id is the only thing that legitimately
differs between the two runs:

    iOS debug      com.bittr.bittr-regtest
    Android debug  com.bittr.android.regtest   (applicationIds cannot contain hyphens)

So the id comes in as an env var — `appId: ${APP_ID}`, passed per platform by
`shared/flows/test_suite.sh` (iOS) and `android/scripts/ci-smoke.sh` (Android).
A literal id reintroduced into a shared flow does not fail at parse time; it
fails on whichever platform it does NOT name, as `launchApp` against a package
that is not installed, several minutes into a CI run that had to boot an
emulator first. This check turns that into a build-time error.

What counts as acceptable in an `appId:` position:

  ${APP_ID}         the app under test on this platform
  ${EVIL_APP_ID}    the iOS-only EvilBoltz build (SEC-01/02 swap-tamper flows);
                    a second *app*, not a second platform, hence its own var
  ${output.APP_ID}  a caller-injected override, resolved by an evalScript that
                    itself defaults to one of the two above

The mirror-image failure is a runner that does not SUPPLY the variable. A bare
`maestro test some_flow.yaml` leaves `appId: ${APP_ID}` unresolved and dies at
`launchApp` — the same "package not installed" symptom, reached from the other
end, and just as expensive when it lands twenty minutes into an unattended
capture pass. `bit14_topup.sh` shipped with exactly that on two of its five
invocations. So the second check below reads the shell scripts that drive
Maestro and requires every `maestro test` naming a flow to pass `--env APP_ID`.

Exit status: 0 if every appId is parameterised AND every runner supplies one,
1 otherwise.

    ./shared/flows/check_app_ids.py
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
FLOW_DIR = ROOT / "shared/flows"

# Every `appId:` position, whether it is the config header's own key or the
# per-command override inside `launchApp:` / `clearState:` / `stopApp:`.
#
# `[ \t]*`, not `\s*`: `\s` matches newlines, so with `re.MULTILINE` the leading
# `^\s*` happily starts on a blank line above and swallows the newline, putting
# match.start() on the wrong line — which is how this reported an appId on line
# 18 and the literal id on the same line as 19.
APP_ID_LINE = re.compile(r"^[ \t]*(?:-[ \t]*)?appId:[ \t]*(\S+)[ \t]*$", re.MULTILINE)

ALLOWED = {"${APP_ID}", "${EVIL_APP_ID}", "${output.APP_ID}"}

# A literal id is the failure this check exists for, but it is not the only way
# to smuggle one in — a JS default inside an evalScript is the other, and that
# is exactly where two of them used to live (`output.APP_ID == null ? '...'`).
LITERAL_ID = re.compile(r"com\.bittr\.[A-Za-z0-9._-]+")

# Comments and prose may name the ids freely: explaining WHY the two platforms
# differ is the point of several of these headers. Only code is checked.
COMMENT = re.compile(r"^\s*#")

# ── Runner-side check ────────────────────────────────────────────────────────

# `maestro test` in *command* position. The leading group is what may precede a
# command in shell — nothing, a pipeline/list operator, or `if`/`then`/`else`.
# It is there to reject `maestro test` appearing inside a string, which is how
# test_suite.sh echoes the line it is about to run:
#     info "${BOLD}maestro test ${FLOW_PATH}${RESET}"
# That is prose, not an invocation, and flagging it would be a false positive.
MAESTRO_TEST = re.compile(
    r"(?:^|[;&|(]|\b(?:if|then|else|do)\s+)\s*(maestro\s+test\b)"
)

# A `--env APP_ID=…` / `-e APP_ID=…` anywhere in the joined command line.
SUPPLIES_APP_ID = re.compile(r"(?:--env|-e)[= ]\s*APP_ID=")

# Only invocations that actually name a flow are checked: `maestro test --help`
# and friends have no appId to resolve.
NAMES_A_FLOW = re.compile(r"\S+\.yaml\b")

# Shell scripts that drive Maestro. Kept to the two directories that hold
# runners so a vendored or sample script elsewhere cannot fail the build.
RUNNER_DIRS = ("shared/flows", "android/scripts")


def join_continuations(text: str) -> list[tuple[int, str]]:
    """Fold `\\`-continued shell lines into one, keeping the starting line no.

    Every runner in this repo writes its Maestro call across several lines, so
    checking line-at-a-time would see `maestro test \\` with no `--env` on it
    and report every single one of them.
    """
    joined: list[tuple[int, str]] = []
    buf, start = "", 0
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not buf:
            start = lineno
        stripped = line.rstrip()
        if stripped.endswith("\\"):
            buf += stripped[:-1] + " "
            continue
        joined.append((start, buf + stripped))
        buf = ""
    if buf:
        joined.append((start, buf))
    return joined


def check_runner(path: Path) -> list[str]:
    problems = []
    rel = path.relative_to(ROOT)

    for lineno, line in join_continuations(path.read_text()):
        if COMMENT.match(line):
            continue
        if not MAESTRO_TEST.search(line):
            continue
        if not NAMES_A_FLOW.search(line):
            continue
        if SUPPLIES_APP_ID.search(line):
            continue
        problems.append(
            f"{rel}:{lineno}: `maestro test` runs a flow without "
            f"`--env APP_ID=…`. Every flow declares `appId: ${{APP_ID}}` and "
            f"the runner supplies it — a bare call dies at launchApp. See the "
            f'"App id" section of shared/flows/README.md.'
        )

    return problems


def check(path: Path) -> list[str]:
    problems = []
    text = path.read_text()
    rel = path.relative_to(ROOT)

    for match in APP_ID_LINE.finditer(text):
        value = match.group(1)
        if value not in ALLOWED:
            line = text[: match.start()].count("\n") + 1
            problems.append(
                f"{rel}:{line}: appId is {value!r}, not one of "
                f"{', '.join(sorted(ALLOWED))}. A literal app id runs on one "
                f"platform only — see the module docstring."
            )

    for lineno, line in enumerate(text.splitlines(), start=1):
        if COMMENT.match(line):
            continue
        found = LITERAL_ID.search(line)
        if found:
            problems.append(
                f"{rel}:{lineno}: literal app id {found.group(0)!r} in flow code. "
                f"Use ${{APP_ID}} / ${{EVIL_APP_ID}} so the flow runs on both "
                f"platforms."
            )

    return problems


def main() -> int:
    flows = sorted(FLOW_DIR.rglob("*.yaml"))
    if not flows:
        print(f"No flows found under {FLOW_DIR} — this check is checking nothing.")
        return 1

    problems = [p for flow in flows for p in check(flow)]

    runners = sorted(
        {p for d in RUNNER_DIRS for p in (ROOT / d).rglob("*.sh")}
    )
    if not runners:
        print(f"No runner scripts found under {', '.join(RUNNER_DIRS)}.")
        return 1
    problems += [p for runner in runners for p in check_runner(runner)]

    if problems:
        # `::error::` renders in the run's annotation box on GitHub; locally it is
        # noise, so it is keyed off the CI variable rather than off isatty() —
        # piping the output through `tee` or `less` is not the same thing as
        # running under Actions.
        prefix = "::error::" if os.environ.get("GITHUB_ACTIONS") else ""
        for problem in problems:
            print(f"{prefix}{problem}")
        print(
            f"\n{len(problems)} app-id problem(s) across {len(flows)} flow "
            f"file(s) and {len(runners)} runner script(s)."
        )
        return 1

    print(
        f"All {len(flows)} flow files take their app id from the environment, "
        f"and all {len(runners)} runner scripts supply one."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
