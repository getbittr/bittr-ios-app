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

The third check is the same requirement for the lines nobody executes: the
copy-pasteable `# Run:` headers on the flows themselves and the command blocks
in the READMEs. Those are exempt from the literal-id rules above, because
explaining why the two platforms differ is the point of several of them — which
also made them invisible when BIT-102 moved the id into the environment, and
left 79 commands that die on contact. Documentation is copy-pasted, so it is
run, so it is checked.

A note on what counts as supplying the id, because it is not what it looks
like: it has to be a `--env`/`-e` flag. Maestro forwards a *shell* variable into
a flow's scope only when its name starts with `MAESTRO_` — and it does not strip
the prefix (`Env.withInjectedShellEnvVars`, read out of 2.10.0's bytecode), so
no shell variable can ever set `${APP_ID}`. `APP_ID=… maestro test …` and
`export APP_ID=…` look right, read right in review, and resolve to nothing. Two
Android READMEs documented exactly that form until BIT-143. Matching on the flag
rather than on the name is what makes this check see them.

Exit status: 0 if every appId is parameterised, every runner supplies one, AND
every documented invocation passes one, 1 otherwise.

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

# ── Documentation-side check ─────────────────────────────────────────────────

# `maestro test` anywhere on the line, not just in command position: in a header
# comment or a fenced block it never IS in command position, and that is the
# whole population this check exists for.
MENTIONS_MAESTRO_TEST = re.compile(r"maestro\s+test\b")

# Only a path into the shared suite counts. A bare `some_flow.yaml` in a
# docstring is an illustration, and `maestro test shared/flows/` (no file) is a
# folder run that several comments correctly tell you NOT to do.
NAMES_SHARED_FLOW = re.compile(r"shared/flows/\S*\.yaml\b")

# Where prose lives. Markdown is checked line for line; in every other suffix
# only comments are, which is also what keeps this from double-reporting the
# runner invocations that `check_runner` above already owns.
COMMENT_PREFIX = {
    ".sh": ("#",),
    ".py": ("#",),
    ".yaml": ("#",),
    ".yml": ("#",),
    ".js": ("//", "*"),
    ".kt": ("//", "*"),
    ".swift": ("//", "*"),
}
PROSE_SUFFIX = ".md"
DOC_SUFFIXES = {PROSE_SUFFIX, *COMMENT_PREFIX}

# Build output and vendored trees, none of which are ours to fix.
SKIP_DIRS = {
    ".git", ".gradle", ".idea", ".build", "__pycache__", "build",
    "node_modules", "DerivedData", "Pods", "venv",
}

# `test_check_app_ids.py` needs no exemption, and deliberately does not have
# one: its broken fixtures live in string literals, and a string literal is not
# a comment. If you add a case there, keep it that way — an exemption would be a
# hole in the one file whose failures are supposed to be observable.


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


def is_checkable_prose(path: Path, line: str) -> bool:
    """Is this joined line documentation, as opposed to code?

    Markdown is documentation throughout. Everywhere else only comments are —
    a `maestro test` in command position belongs to `check_runner`.
    """
    if path.suffix == PROSE_SUFFIX:
        return True
    prefixes = COMMENT_PREFIX.get(path.suffix, ())
    return line.lstrip().startswith(prefixes) if prefixes else False


def check_doc(path: Path) -> list[str]:
    problems = []
    rel = path.relative_to(ROOT)

    # Continuations joined for the same reason as in `check_runner`: the headers
    # wrap too, and `#   maestro test \` on its own line names no flow while the
    # line holding the path names no command. Split, each half looks innocent.
    try:
        text = path.read_text()
    except (UnicodeDecodeError, OSError):
        # A .md/.yaml that is not text is not documentation. Skipping beats
        # failing the build on someone's fixture.
        return problems

    for lineno, line in join_continuations(text):
        if not MENTIONS_MAESTRO_TEST.search(line):
            continue
        if not NAMES_SHARED_FLOW.search(line):
            continue
        if SUPPLIES_APP_ID.search(line):
            continue
        if not is_checkable_prose(path, line):
            continue
        problems.append(
            f"{rel}:{lineno}: documented `maestro test` on a shared flow with no "
            f"`--env APP_ID=…`. Copy-pasting this line fails: every flow "
            f"declares `appId: ${{APP_ID}}` and names no id itself, so Maestro "
            f"dies on an undefined variable before the app launches. Note a "
            f"shell `APP_ID=…` does NOT count — only `--env`/`-e` reaches the "
            f"flow. Use com.bittr.bittr-regtest (iOS) or "
            f"com.bittr.android.regtest (Android)."
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


def walk_docs() -> list[Path]:
    """Every file in the repo that could document a Maestro invocation.

    Repo-wide on purpose: the stale headers this check was written for were
    spread over flows, two platform READMEs, a setup guide and a helper script,
    and the next one will be somewhere none of those lists predicted.
    """
    found = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = Path(dirpath) / name
            if path.suffix in DOC_SUFFIXES:
                found.append(path)
    return found


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

    docs = sorted(walk_docs())
    if not docs:
        print(f"No documentation files found under {ROOT} — nothing to check.")
        return 1
    problems += [p for doc in docs for p in check_doc(doc)]

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
            f"file(s), {len(runners)} runner script(s) and {len(docs)} "
            f"documentation file(s)."
        )
        return 1

    print(
        f"All {len(flows)} flow files take their app id from the environment, "
        f"all {len(runners)} runner scripts supply one, and every documented "
        f"invocation across {len(docs)} files passes one."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
