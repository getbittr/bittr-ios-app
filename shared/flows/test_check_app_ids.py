#!/usr/bin/env python3
"""Prove check_app_ids.py fails on the things it exists to catch.

The documentation half of that check (BIT-143) is the reason this file exists.
The other two halves had gone two months without anyone watching them fail, and
the doc half is the one most likely to be "fixed" by loosening a regex the next
time it inconveniences someone — so each case below builds a throwaway tree,
breaks exactly one thing, and asserts the check goes red AND says which line.

The cases that must stay GREEN matter as much as the red ones. This check reads
every .md/.yaml/.sh/.js/.py/.kt/.swift file in the repo, so a careless widening
turns "don't run `maestro test shared/flows/`" — advice several comments
correctly give — into a build failure, and the fix for that is to delete the
advice. Cases 4-6 pin the three shapes that have to keep passing.

Keep every fixture line inside a string literal. The check reads this file like
any other, and for a .py it reads comments — so a broken example written as a
`#` comment would fail the build from inside its own test. There is deliberately
no exemption for this file; a string literal is not a comment, and that is the
whole trick.

Case 2 is the one worth reading. `APP_ID=… maestro test …` is not a typo, it is
the form two Android READMEs actually shipped: it looks correct, reviews as
correct, and resolves to nothing, because Maestro forwards shell variables into
a flow only when the name starts with `MAESTRO_` and does not strip the prefix.
Matching on the `--env` flag rather than on the name is the only reason the
check sees it, and that is a property a future regex tidy-up could quietly drop.

    ./shared/flows/test_check_app_ids.py
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
CHECK = "shared/flows/check_app_ids.py"

IOS = "com.bittr.bittr-regtest"

# A flow that passes the two pre-existing checks, so anything red in a case
# below is the thing that case broke.
GOOD_FLOW = "appId: ${APP_ID}\n---\n- launchApp\n"

# main() refuses to run with no runner scripts, so every tree needs one.
GOOD_RUNNER = f'#!/usr/bin/env bash\nmaestro test --env APP_ID={IOS} shared/flows/onboarding/smoke.yaml\n'


def build() -> Path:
    """A temp tree holding just the files the check reads."""
    tmp = Path(tempfile.mkdtemp(prefix="appids-"))
    (tmp / CHECK).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / CHECK, tmp / CHECK)
    (tmp / "shared/flows/onboarding").mkdir(parents=True, exist_ok=True)
    (tmp / "shared/flows/onboarding/smoke.yaml").write_text(GOOD_FLOW)
    (tmp / "android/scripts").mkdir(parents=True, exist_ok=True)
    (tmp / "android/scripts/ci-smoke.sh").write_text(GOOD_RUNNER)
    return tmp


def run(tmp: Path) -> tuple[int, str]:
    proc = subprocess.run(
        [sys.executable, str(tmp / CHECK)],
        capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


FAILURES: list[str] = []


def expect_red(name: str, tmp: Path, needle: str) -> None:
    code, out = run(tmp)
    if code == 0:
        FAILURES.append(f"{name}: check PASSED but should have failed.\n{out}")
    elif needle not in out:
        FAILURES.append(f"{name}: failed, but no mention of {needle!r}.\n{out}")
    else:
        print(f"  ok  {name}")
    shutil.rmtree(tmp, ignore_errors=True)


def expect_green(name: str, tmp: Path) -> None:
    code, out = run(tmp)
    if code != 0:
        FAILURES.append(f"{name}: check FAILED but should have passed.\n{out}")
    else:
        print(f"  ok  {name}")
    shutil.rmtree(tmp, ignore_errors=True)


def case_1_stale_run_header() -> None:
    """The BIT-143 defect itself: a copy-pasteable header that no longer runs."""
    tmp = build()
    flow = tmp / "shared/flows/features/receive.yaml"
    flow.parent.mkdir(parents=True, exist_ok=True)
    flow.write_text(
        "# Run: maestro test shared/flows/features/receive.yaml\n" + GOOD_FLOW
    )
    expect_red("stale `# Run:` header in a flow", tmp,
               "shared/flows/features/receive.yaml:1")


def case_2_shell_var_is_not_supplying_it() -> None:
    """The form that looks right and does nothing. See the module docstring."""
    tmp = build()
    (tmp / "android/README.md").write_text(
        "## Maestro\n\n```sh\n"
        "APP_ID=com.bittr.android.regtest maestro test "
        "shared/flows/onboarding/smoke.yaml\n```\n"
    )
    expect_red("shell `APP_ID=` prefix instead of `--env`", tmp,
               "android/README.md:4")


def case_3_wrapped_invocation() -> None:
    """Split over a `\\` continuation, each half looks innocent on its own."""
    tmp = build()
    (tmp / "shared/flows/suite.yaml").write_text(
        "# Run it with:\n"
        "#   maestro test \\\n"
        '#     --env MNEMONIC="a b c" \\\n'
        "#     shared/flows/suite.yaml\n" + GOOD_FLOW
    )
    expect_red("wrapped invocation missing the id", tmp,
               "shared/flows/suite.yaml:2")


def case_4_correct_line_passes() -> None:
    """The fix for case 1 must actually satisfy the check."""
    tmp = build()
    flow = tmp / "shared/flows/features/receive.yaml"
    flow.parent.mkdir(parents=True, exist_ok=True)
    flow.write_text(
        f"# Run: maestro test --env APP_ID={IOS} "
        "shared/flows/features/receive.yaml\n" + GOOD_FLOW
    )
    expect_green("a header carrying --env APP_ID", tmp)


def case_5_folder_run_prose_passes() -> None:
    """`maestro test shared/flows/` names no file — and is usually a warning."""
    tmp = build()
    (tmp / "ANDROID_PORT_PLAN.md").write_text(
        "- CI runs `maestro test shared/flows/` against both platforms.\n"
        "\nDon't run `maestro test shared/flows/` to get the whole suite.\n"
    )
    expect_green("prose about a folder run", tmp)


def case_6_foreign_flow_path_passes() -> None:
    """A flow outside the shared suite is not this check's business."""
    tmp = build()
    (tmp / "shared/flows/check_notes.md").write_text(
        "A bare `maestro test some_flow.yaml` leaves the id unresolved.\n"
    )
    expect_green("an illustrative non-shared flow path", tmp)


def case_7_runner_without_env_still_caught() -> None:
    """The pre-existing runner check, which had no test of its own."""
    tmp = build()
    (tmp / "android/scripts/ci-smoke.sh").write_text(
        "#!/usr/bin/env bash\nmaestro test shared/flows/onboarding/smoke.yaml\n"
    )
    expect_red("runner invocation with no --env APP_ID", tmp,
               "android/scripts/ci-smoke.sh:2")


def case_8_literal_app_id_still_caught() -> None:
    """The pre-existing flow check, likewise."""
    tmp = build()
    (tmp / "shared/flows/onboarding/smoke.yaml").write_text(
        f"appId: {IOS}\n---\n- launchApp\n"
    )
    expect_red("literal app id in a shared flow", tmp,
               "shared/flows/onboarding/smoke.yaml:1")


def main() -> int:
    print("check_app_ids.py self-test")
    for case in (
        case_1_stale_run_header,
        case_2_shell_var_is_not_supplying_it,
        case_3_wrapped_invocation,
        case_4_correct_line_passes,
        case_5_folder_run_prose_passes,
        case_6_foreign_flow_path_passes,
        case_7_runner_without_env_still_caught,
        case_8_literal_app_id_still_caught,
    ):
        case()

    if FAILURES:
        for failure in FAILURES:
            print(f"\nFAIL {failure}")
        print(f"\n{len(FAILURES)} self-test case(s) failed.")
        return 1

    print("\nAll 8 cases behave as documented.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
