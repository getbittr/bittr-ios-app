#!/usr/bin/env python3
"""Tests for k1-result.py — the only way a K1 result reaches a reader without admin.

    android/scripts/test_k1_result.py

WHY THIS EXISTS

k1-result.py carries the K1 table out of GitHub Actions. Every other channel the
workflow writes to needs credentials (job log 403, artefact 401, job summary not
in the API at all), so if this script reports wrongly there is nothing to check it
against — which is the opposite of the situation every other part of K1 is built
for.

Two of its behaviours had already gone wrong in use and are pinned here:

  * It spent the budget it needed. Polling every 30s over a 13-minute wait is 26
    of the 60 requests an unauthenticated IP gets per hour; run #2 of the workflow
    took the budget to 8 with the run still going, leaving too little to read the
    result. A tool built to stop K1 results going unread had made one unreadable.
  * `--run <id> --wait <n>` silently ignored the wait and reported the run as
    unfinished — indistinguishable, to the caller, from a run that had finished
    with no annotations.

And one that would be worse if it went wrong quietly: a run whose only annotation
is the runner's own "The process '/usr/bin/sh' failed with exit code 1" must still
print *something*, because that sentence is all run #1 ever produced.

No network: `get` is replaced with a fixture table, the same seam test_ci_runs.py
uses. Sleeps are stubbed so the budget tests take no time.
"""

import contextlib
import importlib.util
import io
import pathlib
import sys

MODULE = pathlib.Path(__file__).with_name("k1-result.py")
spec = importlib.util.spec_from_file_location("k1_result", MODULE)
k1 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(k1)

FAILURES = []
SLEPT = []


def run(argv, responses, now=1_000_000):
    """Invoke main() with `get`, time and sleep stubbed.

    `responses` maps a path substring to a value, or to a callable taking the call
    index so a test can make the same path answer differently over time — which is
    how "in progress, then completed" is expressed.

    Note which path a test has to vary: with `--run` the loop fetches
    `/actions/runs/<id>`, and without it `/actions/workflows/<wf>/runs`. Stubbing
    the wrong one leaves the loop seeing a run that never completes, which exits 2
    with the table printed — a confusing shape to debug, hence this note.
    """
    calls = {"n": 0, "paths": []}

    def fake_get(path):
        calls["n"] += 1
        calls["paths"].append(path)
        for key, value in responses.items():
            if key in path:
                return value(calls["n"]) if callable(value) else value
        return {"workflow_runs": [], "jobs": []} if "runs" in path else []

    SLEPT.clear()
    real = (k1.get, sys.argv, k1.time.sleep, k1.time.monotonic, k1.time.time)
    k1.get = fake_get
    sys.argv = ["k1-result.py"] + argv
    # A stubbed clock that advances only when the code sleeps, so a deadline is
    # reached by sleeping rather than by the test taking real time.
    clock = {"t": 0.0}
    k1.time.sleep = lambda s: (SLEPT.append(s), clock.__setitem__("t", clock["t"] + s))
    k1.time.monotonic = lambda: clock["t"]
    k1.time.time = lambda: now + clock["t"]
    out, err = io.StringIO(), io.StringIO()
    code = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            k1.main()
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
    finally:
        k1.get, sys.argv, k1.time.sleep, k1.time.monotonic, k1.time.time = real
    return code, out.getvalue(), err.getvalue(), calls


def make_run(number=2, conclusion="failure", status="completed"):
    return {
        "id": 34588466744,
        "run_number": number,
        "head_sha": "22cc4da0000",
        "head_branch": "k1-run/pilot",
        "status": status,
        "conclusion": conclusion,
        "created_at": "2026-09-11T10:10:00Z",
        "updated_at": "2026-09-11T10:22:00Z",
        "html_url": "https://github.com/getbittr/bittr-ios-app/actions/runs/34588466744",
    }


TABLE = (
    "K1 — API 34 — matrix exit 1\n\n"
    "| case | result | mutation witness | key security level |\n"
    "|---|---|---|---|\n"
    "| M1 | ERROR | seal | - |\n\n"
    "**M1** — seal phase failed; no verdict on rule 2"
)

JOBS = {"jobs": [{"id": 99, "name": "K1 on API 34"}]}
TABLE_ANNOTATION = [
    {"annotation_level": "failure", "title": "K1 API 34", "message": TABLE},
    {
        "annotation_level": "warning",
        "title": "",
        "message": "Node.js 20 is deprecated. The following actions target Node.js 20...",
    },
]
ONLY_NOISE = [
    {
        "annotation_level": "failure",
        "title": "",
        "message": "The process '/usr/bin/sh' failed with exit code 1",
    }
]


def budget_of(remaining, reset_at):
    return {"resources": {"core": {"remaining": remaining, "reset": reset_at}}}


def check(name, condition, detail=""):
    print(f"{'ok  ' if condition else 'FAIL'}  {name}")
    if not condition:
        FAILURES.append(f"{name}{': ' + detail if detail else ''}")


PLENTY = budget_of(59, 1_003_600)


def test_table_is_printed_and_red_is_exit_1():
    code, out, err, _ = run(
        ["--run", "34588466744"],
        {"rate_limit": PLENTY, "/jobs": JOBS, "annotations": TABLE_ANNOTATION, "runs/": make_run()},
    )
    check("a red run exits 1", code == k1.NOT_GREEN, f"exit {code}")
    check("the table reaches stdout", "| M1 | ERROR | seal | - |" in out, out)
    check("the fingerprint line count is preserved", out.count("\n") > 6, out)
    check(
        "the rule-2 instruction is on stderr, not invented on stdout",
        "do not switch designs" in err.lower(),
        err,
    )


def test_runner_deprecation_noise_is_dropped():
    _, out, _, _ = run(
        ["--run", "1"],
        {"rate_limit": PLENTY, "/jobs": JOBS, "annotations": TABLE_ANNOTATION, "runs/": make_run()},
    )
    check("Node.js deprecation warning is not printed", "Node.js 20 is deprecated" not in out, out)


def test_uninformative_annotation_is_kept_when_it_is_all_there_is():
    # Run #1 produced exactly this and nothing else. Filtering it as noise would
    # leave the reader with a blank report for a run that did fail.
    _, out, _, _ = run(
        ["--run", "1"],
        {"rate_limit": PLENTY, "/jobs": JOBS, "annotations": ONLY_NOISE, "runs/": make_run()},
    )
    check(
        "the bare 'failed with exit code 1' still prints when alone",
        "failed with exit code 1" in out,
        out,
    )


def test_green_run_is_exit_0():
    code, out, _, _ = run(
        ["--run", "1"],
        {
            "rate_limit": PLENTY,
            "/jobs": JOBS,
            "annotations": [{"annotation_level": "notice", "title": "K1", "message": "| M1 | PASS |"}],
            "runs/": make_run(conclusion="success"),
        },
    )
    check("a green run exits 0", code == 0, f"exit {code}")
    check(
        "and says the evidence is image-specific",
        "and no others" in out,
        out,
    )


def test_unfinished_run_is_undetermined_not_red():
    # A run still going is not evidence in either direction. Reporting it as red
    # would make this disagree with ci-runs.py on the same question.
    code, _, err, _ = run(
        ["--run", "1"],
        {
            "rate_limit": PLENTY,
            "/jobs": JOBS,
            "annotations": [],
            "runs/": make_run(conclusion=None, status="in_progress"),
        },
    )
    check("in-flight is undetermined (2), not NOT_GREEN (1)", code == k1.UNDETERMINED, f"exit {code}")
    check("and says so", "has not finished" in err, err)


def test_wait_applies_to_an_explicit_run_id():
    # The bug: --run made --wait a no-op, so this reported "has not finished"
    # immediately instead of waiting for the run it was pointed at.
    states = {"n": 0}

    def run_states(_call):
        states["n"] += 1
        return make_run(conclusion=None, status="in_progress") if states["n"] < 3 else make_run()

    code, out, _, _ = run(
        ["--run", "34588466744", "--wait", "600", "--interval", "90"],
        {"rate_limit": PLENTY, "/jobs": JOBS, "annotations": TABLE_ANNOTATION, "runs/": run_states},
    )
    check("--wait polls an explicit --run until it completes", code == k1.NOT_GREEN, f"exit {code}")
    check("and then prints the table", "| M1 | ERROR | seal | - |" in out, out)
    check("having slept between polls", SLEPT.count(90) == 2, str(SLEPT))


def test_wait_holds_rather_than_spending_the_read_budget():
    # The failure this pins: polling down to zero and then being unable to read
    # the result. With READ_COST or fewer requests left, the loop must wait for
    # the window instead of polling.
    budgets = {"n": 0}

    def shrinking(_call):
        budgets["n"] += 1
        # Plenty, then at the floor, then replenished after the "reset".
        if budgets["n"] == 1:
            return budget_of(20, 1_000_600)
        if budgets["n"] == 2:
            return budget_of(k1.READ_COST, 1_000_600)
        return budget_of(59, 1_004_200)

    states = {"n": 0}

    def run_states(_call):
        states["n"] += 1
        return make_run(conclusion=None, status="in_progress") if states["n"] < 2 else make_run()

    code, out, err, _ = run(
        ["--wait", "3000", "--interval", "90"],
        {
            "rate_limit": shrinking,
            "/jobs": JOBS,
            "annotations": TABLE_ANNOTATION,
            "workflows/": lambda call: {"workflow_runs": [run_states(call)]},
        },
    )
    check("it says it is holding for the window", "holding" in err, err)
    check(
        "and the hold is the time to reset, not the poll interval",
        any(s > 500 for s in SLEPT),
        str(SLEPT),
    )
    check("and still reads the result afterwards", "| M1 | ERROR | seal | - |" in out, out)
    check("exit reflects the run, not the wait", code == k1.NOT_GREEN, f"exit {code}")


def test_reset_past_the_deadline_is_undetermined():
    # Waiting for a reset that falls outside --wait must be reported as "could not
    # find out", never as a result.
    code, _, err, _ = run(
        ["--wait", "120"],
        {
            "rate_limit": budget_of(1, 1_003_600),
            "workflows/": {"workflow_runs": [make_run(conclusion=None, status="in_progress")]},
        },
    )
    check("exhausted budget past the deadline is undetermined", code == k1.UNDETERMINED, f"exit {code}")
    check("and names the token as the way out", "GITHUB_TOKEN" in err, err)


def test_rate_limit_read_failure_does_not_stop_the_wait():
    # budget() returning (None, None) must mean "assume there is budget", not
    # "refuse to work" — a flaky /rate_limit must not block reading a result.
    states = {"n": 0}

    def run_states(_call):
        states["n"] += 1
        return make_run(conclusion=None, status="in_progress") if states["n"] < 2 else make_run()

    def boom(_call):
        raise SystemExit(k1.UNDETERMINED)

    code, out, _, _ = run(
        ["--wait", "600", "--interval", "30"],
        {
            "rate_limit": boom,
            "/jobs": JOBS,
            "annotations": TABLE_ANNOTATION,
            "workflows/": lambda call: {"workflow_runs": [run_states(call)]},
        },
    )
    check("an unreadable rate limit still polls", code == k1.NOT_GREEN, f"exit {code}")
    check("and still prints the table", "| M1 | ERROR | seal | - |" in out, out)


def test_no_runs_is_undetermined():
    code, _, err, _ = run(["--branch", "k1-run/never"], {"rate_limit": PLENTY, "workflows/": {"workflow_runs": []}})
    check("no runs is undetermined", code == k1.UNDETERMINED, f"exit {code}")
    check("and says how to request one", "k1-run/**" in err, err)


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("all green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
