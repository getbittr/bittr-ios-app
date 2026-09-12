#!/usr/bin/env python3
"""Tests for ci-runs.py — the gate that decides whether BIT-5's definition of done holds.

    android/scripts/test_ci_runs.py

WHY THIS EXISTS

ci-runs.py is the instrument that answers "are the last N runs green". It shipped
with no tests, and the first time it was run against a repository that had a run
in flight it reported NOT GREEN — because `conclusion` is null until a run
finishes, and null is not "success". Three genuinely green runs, gate says red.

That failure mode is invisible in the happy case and fires exactly when someone
is pushing repeatedly, which is what the definition of done consists of. So the
interesting cases here are the ones with a run still going.

No network: `get` is replaced with a fixture table. That is the whole seam, and
it is why the tests can assert on rate-limit and 404 behaviour too.
"""

import contextlib
import importlib.util
import io
import pathlib
import sys
import urllib.error

MODULE = pathlib.Path(__file__).with_name("ci-runs.py")
spec = importlib.util.spec_from_file_location("ci_runs", MODULE)
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)

FAILURES = []


def run(argv, responses):
    """Invoke main() with `get` stubbed; return (exit_code, stdout, stderr)."""

    def fake_get(path):
        for key, value in responses.items():
            if key in path:
                if isinstance(value, Exception):
                    raise value
                return value
        return {"workflow_runs": [], "jobs": []} if "runs" in path else []

    real_get, real_argv = ci.get, sys.argv
    ci.get = fake_get
    sys.argv = ["ci-runs.py"] + argv
    out, err = io.StringIO(), io.StringIO()
    code = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            ci.main()
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
    finally:
        ci.get, sys.argv = real_get, real_argv
    return code, out.getvalue(), err.getvalue()


def make_run(number, conclusion, status="completed", minutes=6):
    return {
        "id": 1000 + number,
        "run_number": number,
        "head_sha": f"{number:07d}abc",
        "head_branch": "feature/bit-5-android-scaffold",
        "status": status,
        "conclusion": conclusion,
        "created_at": "2026-09-10T11:00:00Z",
        "updated_at": f"2026-09-10T11:{minutes:02d}:00Z",
    }


NO_JOBS = {"jobs": []}


def check(name, condition, detail=""):
    print(f"{'ok  ' if condition else 'FAIL'}  {name}")
    if not condition:
        FAILURES.append(f"{name}{': ' + detail if detail else ''}")


def test_in_flight_run_is_not_a_failure():
    """The bug this file was written for: 3 green behind 1 in-flight is still green."""
    runs = [
        make_run(11, None, status="in_progress"),
        make_run(10, "success"),
        make_run(9, "success"),
        make_run(8, "success"),
    ]
    code, out, err = run(["--require-green", "3"], {"/runs?": {"workflow_runs": runs}, "/jobs": NO_JOBS})
    check("in-flight run does not make the gate red", code == 0, f"exit {code}, stderr={err.strip()!r}")
    check("in-flight run is called out in the output", "#11 is in_progress" in out, out)
    check("the three counted runs are named", "#10, #9, #8" in out, out)


def test_red_run_is_a_failure():
    runs = [make_run(10, "failure"), make_run(9, "success"), make_run(8, "success")]
    code, _, err = run(["--require-green", "3"], {"/runs?": {"workflow_runs": runs}, "/jobs": NO_JOBS})
    check("a red run exits 1", code == ci.NOT_GREEN, f"exit {code}")
    check("the red run is named on stderr", "#10 failure" in err, err)


def test_red_behind_in_flight_still_fails():
    """Skipping in-flight runs must not skip past a red one to find greens."""
    runs = [
        make_run(11, None, status="in_progress"),
        make_run(10, "failure"),
        make_run(9, "success"),
        make_run(8, "success"),
        make_run(7, "success"),
    ]
    code, _, err = run(["--require-green", "3"], {"/runs?": {"workflow_runs": runs}, "/jobs": NO_JOBS})
    check("a red run behind an in-flight one still fails", code == ci.NOT_GREEN, f"exit {code}")
    check("and it is the red one that is named", "#10 failure" in err, err)


def test_cancelled_is_skipped():
    runs = [
        make_run(11, "cancelled"),
        make_run(10, "success"),
        make_run(9, "success"),
        make_run(8, "success"),
    ]
    code, _, err = run(["--require-green", "3"], {"/runs?": {"workflow_runs": runs}, "/jobs": NO_JOBS})
    check("a cancelled run is not counted as red", code == 0, f"exit {code}, stderr={err.strip()!r}")


def test_too_few_completed_is_undetermined():
    """Not enough evidence is not the same claim as 'it is red'."""
    runs = [make_run(11, None, status="in_progress"), make_run(10, "success")]
    code, _, err = run(["--require-green", "3"], {"/runs?": {"workflow_runs": runs}, "/jobs": NO_JOBS})
    check("too few completed runs exits 2, not 1", code == ci.UNDETERMINED, f"exit {code}")
    check("and says how many it had", "1 completed run" in err, err)


def run_against_transport(argv, error):
    """Invoke main() with urlopen raising, so get()'s own error handling is what runs.

    Stubbing `get` here would test the stub: the rate-limit and 404 branches live
    *inside* get, and a fixture that raises before reaching them proves nothing.
    """
    real_urlopen, real_argv = ci.urllib.request.urlopen, sys.argv

    def fake_urlopen(*_args, **_kwargs):
        raise error

    ci.urllib.request.urlopen = fake_urlopen
    sys.argv = ["ci-runs.py"] + argv
    out, err = io.StringIO(), io.StringIO()
    code = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            ci.main()
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
    finally:
        ci.urllib.request.urlopen, sys.argv = real_urlopen, real_argv
    return code, out.getvalue(), err.getvalue()


def test_rate_limit_is_undetermined():
    """An outage must not be reportable as a regression."""
    limit = urllib.error.HTTPError(
        "https://api.github.com", 403, "rate limit exceeded", {}, io.BytesIO(b"API rate limit exceeded")
    )
    code, _, err = run_against_transport(["--require-green", "3"], limit)
    check("rate limit exits 2, not 1", code == ci.UNDETERMINED, f"exit {code}")
    check("rate limit explains the fix", "GITHUB_TOKEN" in err, err)


def test_private_repo_404_is_undetermined():
    gone = urllib.error.HTTPError("https://api.github.com", 404, "Not Found", {}, io.BytesIO(b"{}"))
    code, _, err = run_against_transport(["--require-green", "3"], gone)
    check("404 exits 2, not 1", code == ci.UNDETERMINED, f"exit {code}")
    check("404 suggests the token", "GITHUB_TOKEN" in err, err)


def test_network_failure_is_undetermined():
    code, _, err = run_against_transport(["--require-green", "3"], urllib.error.URLError("no route to host"))
    check("an unreachable API exits 2, not 1", code == ci.UNDETERMINED, f"exit {code}")


def test_no_runs_is_undetermined():
    code, _, err = run(["--require-green", "3"], {"/runs?": {"workflow_runs": []}})
    check("no runs at all exits 2", code == ci.UNDETERMINED, f"exit {code}")


def test_median_is_reported():
    runs = [make_run(10, "success", minutes=8), make_run(9, "success", minutes=6), make_run(8, "success", minutes=7)]
    code, out, _ = run(["--require-green", "3"], {"/runs?": {"workflow_runs": runs}, "/jobs": NO_JOBS})
    check("median of 6/7/8 minutes is 7m00s", code == 0 and "7m00s" in out, out)


def test_human():
    cases = {0: "0s", 19: "19s", 59: "59s", 60: "1m00s", 402: "6m42s", None: "?"}
    for seconds, want in cases.items():
        check(f"human({seconds}) == {want}", ci.human(seconds) == want, ci.human(seconds))


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
