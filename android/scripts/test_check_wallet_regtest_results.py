#!/usr/bin/env python3
"""Cases for check-wallet-regtest-results.py.

WHY THIS SUITE EXISTS

Same argument as test_check_wallet_instrumented_results.py, with one addition
specific to this gate. It runs in a NIGHTLY job, so it is checked by a human at
most once a day and quite possibly once a week — which means a bug in it survives
longer than a bug in any per-push check, and the state it is protecting is a
fund-safety claim rather than a build.

The cases below are the ways it can go green wrongly:

  * a required test absent from the results entirely (the BdkAccountXpubParityTest
    shape: the run proved every required test ran and said nothing about that one);
  * a required test present and `<skipped/>`;
  * a required test present and failed;
  * no result files at all, which is what `connectedDebugAndroidTest` produces
    when its class filter matches nothing — and it exits 0.

Run: python3 android/scripts/test_check_wallet_regtest_results.py
"""

import contextlib
import importlib.util
import io
import pathlib
import sys
import tempfile

SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent


def load_module():
    path = SCRIPTS_DIR / "check-wallet-regtest-results.py"
    spec = importlib.util.spec_from_file_location("check_wallet_regtest", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gate = load_module()

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print(f"  ok    {name}")
    else:
        print(f"  FAIL  {name}{(': ' + detail) if detail else ''}")
        FAILURES.append(name)


def write_results(directory, cases, evidence=()):
    """One TEST-*.xml holding `cases`, in AGP's connected-test shape.

    `cases` is a list of (classname, name, outcome) where outcome is "pass",
    "skip" or a failure message. `evidence` lines go into <system-out>, which is
    where AGP files instrumentation stdout when it files it at all.
    """
    body = []
    for classname, name, outcome in cases:
        if outcome == "pass":
            body.append(f'<testcase classname="{classname}" name="{name}"/>')
        elif outcome == "skip":
            body.append(
                f'<testcase classname="{classname}" name="{name}"><skipped/></testcase>'
            )
        else:
            body.append(
                f'<testcase classname="{classname}" name="{name}">'
                f"<failure>{outcome}</failure></testcase>"
            )
    out = ""
    if evidence:
        out = "<system-out>" + "\n".join(evidence) + "</system-out>"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "TEST-regtest.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>'
        f'<testsuite name="regtest" tests="{len(cases)}">'
        + "".join(body)
        + out
        + "</testsuite>"
    )


def run(results_dir):
    """main() with stdout captured, returning (exit code, output)."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = gate.main(["--results-dir", str(results_dir)])
    return code, out.getvalue()


ALL_REQUIRED = sorted(gate.REQUIRED)


def cases_for(required, outcome="pass"):
    return [(t.split("#")[0], t.split("#")[1], outcome) for t in required]


# --- The list itself -----------------------------------------------------------
#
# Asserted before any behaviour, because an empty or class-only REQUIRED set would
# make every case below pass while the gate checked nothing.

print("REQUIRED")
check("is not empty", len(gate.REQUIRED) > 0, str(len(gate.REQUIRED)))
check(
    "names every entry per method, not per class",
    # BIT-132's definition of done. A class-level entry would let four of five
    # methods disappear without a word, which is the mistake the other gate's
    # comments record having made.
    all("#" in test_id for test_id in gate.REQUIRED),
    sorted(t for t in gate.REQUIRED if "#" not in t),
)
check(
    "the canary is one of the required tests",
    gate.CANARY in gate.REQUIRED,
    gate.CANARY,
)
check(
    "every required test names a class that exists in the regtest source set",
    # The rename trap, caught here rather than after an emulator boot. A REQUIRED
    # entry for a class nobody wrote is indistinguishable, in the gate's own
    # output, from a class that failed to run.
    all(
        any(
            (
                SCRIPTS_DIR.parent
                / "app"
                / "src"
                / source_set
                / "kotlin"
                / (test_id.split("#")[0].replace(".", "/") + ".kt")
            ).exists()
            for source_set in ("androidTestRegtest", "androidTest")
        )
        for test_id in gate.REQUIRED
    ),
    str(sorted(gate.REQUIRED)),
)
check(
    "every required method name appears in its class's source",
    # The other half of the same trap: the file exists and the method was renamed.
    all(
        (
            "fun " + test_id.split("#")[1]
            in "".join(
                path.read_text()
                for source_set in ("androidTestRegtest", "androidTest")
                for path in [
                    SCRIPTS_DIR.parent
                    / "app"
                    / "src"
                    / source_set
                    / "kotlin"
                    / (test_id.split("#")[0].replace(".", "/") + ".kt")
                ]
                if path.exists()
            )
        )
        for test_id in gate.REQUIRED
    ),
)

# --- Behaviour ------------------------------------------------------------------

with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)

    print("a complete green run")
    green = root / "green"
    write_results(
        green,
        cases_for(ALL_REQUIRED),
        evidence=["REGTEST_ENVIRONMENT configured=true network=Regtest"],
    )
    code, output = run(green)
    check("exits 0", code == 0, output)
    check("says how many required tests it checked", str(len(gate.REQUIRED)) in output)
    check(
        "lifts the evidence line into the log and into a ::notice::",
        "REGTEST_ENVIRONMENT configured=true" in output and "::notice::" in output,
        output,
    )

    print("one required test absent")
    for omitted in ALL_REQUIRED:
        partial = root / ("absent-" + omitted.split("#")[1])
        write_results(partial, cases_for([t for t in ALL_REQUIRED if t != omitted]))
        code, output = run(partial)
        check(
            f"exits 1 when {omitted.split('#')[1]} never ran",
            code == 1 and omitted in output,
            output,
        )

    print("one required test skipped")
    skipped = root / "skipped"
    write_results(
        skipped,
        cases_for([ALL_REQUIRED[0]], "skip") + cases_for(ALL_REQUIRED[1:]),
    )
    code, output = run(skipped)
    check("exits 1", code == 1)
    check(
        "explains that a skip here cannot mean 'no environment'",
        # The whole point of gating by source set rather than by @Assume. If this
        # message ever softens, the gate has lost the distinction it was built on.
        "compiles these classes out" in output,
        output,
    )

    print("one required test failed")
    failed = root / "failed"
    write_results(
        failed,
        cases_for([ALL_REQUIRED[0]], "chainSourceUrl host was staging.example.com")
        + cases_for(ALL_REQUIRED[1:]),
    )
    code, output = run(failed)
    check("exits 1", code == 1)
    check(
        "quotes the failure message rather than only naming the test",
        "staging.example.com" in output,
        output,
    )

    print("the canary alone failing")
    canary_red = root / "canary"
    write_results(
        canary_red,
        cases_for([t for t in ALL_REQUIRED if t != gate.CANARY])
        + cases_for([gate.CANARY], "no evidence line"),
    )
    code, output = run(canary_red)
    check("exits 1", code == 1)
    check(
        "says why an unattributable run is not a result",
        "generated per" in output and "bring-up" in output,
        output,
    )

    print("no result files at all")
    empty = root / "empty"
    empty.mkdir(parents=True)
    code, output = run(empty)
    check(
        "exits 1 rather than treating an empty directory as a clean run",
        # connectedDebugAndroidTest exits 0 when its class filter matches nothing,
        # so this is the vacuous green the gate exists for — not a quirk.
        code == 1 and "vacuous-green" in output,
        output,
    )

    print("a directory that does not exist")
    code = gate.main(["--results-dir", str(root / "nope")])
    check("exits 1", code == 1)

    print("a test appearing twice, green then red")
    retried = root / "retried"
    write_results(
        retried,
        cases_for(ALL_REQUIRED)
        + cases_for([ALL_REQUIRED[0]], "failed on the second device"),
    )
    code, output = run(retried)
    check(
        "the worse outcome wins, so a retry is not a pass",
        code == 1 and "second device" in output,
        output,
    )

print()
if FAILURES:
    print(f"{len(FAILURES)} failed:")
    for name in FAILURES:
        print(f"  - {name}")
    sys.exit(1)
print("all check-wallet-regtest-results.py cases passed")
