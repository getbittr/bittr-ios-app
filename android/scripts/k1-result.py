#!/usr/bin/env python3
"""Read K1's result tables back out of GitHub Actions, with no credentials.

    android/scripts/k1-result.py                  # the latest K1 run
    android/scripts/k1-result.py --last 3         # the last 3 runs
    android/scripts/k1-result.py --branch k1-run/pilot
    android/scripts/k1-result.py --run 34586609943
    android/scripts/k1-result.py --wait 900       # poll until the latest run ends

Exit codes: 0 every row PASS · 1 looked and it is not green · 2 could not find out.

Unauthenticated, GitHub allows 60 requests/hour per IP, and reading one run costs
about six of them. `--wait` polls every 90s and stops polling rather than spend
below what reading the result needs — see the loop in main(). Set GITHUB_TOKEN to
make all of that irrelevant (5000/hour).

WHY THIS EXISTS

K1's output is a table — device x mutation x pass/fail — and BIT-18's definition
of done is that table plus a one-line verdict. The workflow writes it to three
places, and on `getbittr/bittr-ios-app` every one of them is behind credentials:

    GET /actions/jobs/:id/logs        403  Must have admin rights to Repository.
    GET /actions/artifacts/:id/zip    401  Requires authentication
    the job summary                   not exposed by the REST API at all

So the first K1 run (#1, k1-run/pilot, 393d229) could be observed to fail and
could not be observed to say why. The only detail any unauthenticated reader
could get was the annotation "The process '/usr/bin/sh' failed with exit code 1",
which is true of every possible cause.

Annotations are the exception: /repos/:owner/:repo/check-runs/:id/annotations is
readable anonymously on a public repo. That is the same fact ci-runs.py is built
on — see its own "WHY THIS EXISTS", where BIT-5 lost three rounds to results that
existed and never reached whoever needed them. k1-ci.sh now sends the table out
that way, and this reads it back.

WHY NOT JUST EXTEND ci-runs.py

Different question and different shape. ci-runs.py answers "is the Android gate
green and how long does it take", with build/emulator duration columns and a
`--require-green N` gate for BIT-5's definition of done. This answers "what did
the matrix measure", where the payload is a markdown table and the durations are
not the point. Sharing a 15-line urllib helper is not worth coupling them;
stdlib-only and independent matches shared/test-ids/*.py for the same reason.

WHAT "GREEN" MEANS HERE

The run conclusion, which k1-ci.sh sets from the matrix exit code: every row
PASS, or not. An ERROR row is not a pass — the harness could not establish what
happened — so it goes red, and this reports red. A FAIL row is a BIT-8 rule-2
contradiction on that device and must be reported on BIT-18 and BIT-8 before
anything is redesigned; it is never a reason to switch designs here.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

REPO = "getbittr/bittr-ios-app"
WORKFLOW = "k1-keystore-lockscreen.yml"
API = "https://api.github.com"

# A gate has to distinguish "I looked, and it is not green" from "I could not
# find out" — rate limit, network, no runs yet. Same split as ci-runs.py.
NOT_GREEN = 1
UNDETERMINED = 2


def undetermined(message):
    print(message, file=sys.stderr)
    sys.exit(UNDETERMINED)


def get(path):
    """GET a JSON path, with the rate limit reported as itself rather than as a crash."""
    req = urllib.request.Request(
        f"{API}{path}",
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "bittr-k1-result",
        },
    )
    # Anonymous is 60 requests/hour per IP. A token raises it to 5000 and is also
    # what keeps this working if the repo is ever made private — at which point
    # the annotation channel stops being special and the artefact is readable too.
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        if exc.code == 403 and "rate limit" in exc.read().decode("utf-8", "replace").lower():
            undetermined(
                "GitHub API rate limit reached (60/hour unauthenticated). "
                "Set GITHUB_TOKEN for 5000/hour, or wait."
            )
        undetermined(f"GitHub API {exc.code} for {path}: {exc.reason}")
    except urllib.error.URLError as exc:
        undetermined(f"Could not reach the GitHub API: {exc.reason}")


# Reading one run costs about this many requests: the run, its jobs, and the
# annotations of each job. Kept as a floor the poll loop will not spend, because
# the one thing worse than waiting is waiting successfully and then having no
# budget left to read what you waited for.
READ_COST = 6


def budget():
    """Requests left this hour, and when the window resets.

    /rate_limit does not itself count against the limit, so this is free to call.
    Returns (remaining, reset_epoch), or (None, None) if it cannot be read —
    callers treat that as "assume there is budget" rather than refusing to work.
    """
    try:
        data = get("/rate_limit")["resources"]["core"]
        return data["remaining"], data["reset"]
    except SystemExit:
        # get() exits on error. A missing rate-limit reading must not be fatal to
        # a command whose whole job is to tolerate a flaky network.
        return None, None


def annotations_for(run):
    """Every annotation on every job of a run, most useful level first.

    The table arrives as one annotation because GitHub caps a job at 10 per
    level; k1-ci.sh sends it as `error` when any row is not PASS and `notice`
    when the run is clean.
    """
    out = []
    for job in get(f"/repos/{REPO}/actions/runs/{run['id']}/jobs").get("jobs", []):
        for ann in get(f"/repos/{REPO}/check-runs/{job['id']}/annotations"):
            level = ann.get("annotation_level")
            message = ann.get("message") or ""
            # The runner's own deprecation warnings are noise here, and there are
            # three of them per job. Filtered by content rather than by level, so
            # a real warning from the matrix still prints.
            if level == "warning" and "deprecat" in message.lower():
                continue
            # "The process '/usr/bin/sh' failed with exit code 1" is the action
            # reporting that our script exited non-zero. True, and it is what
            # this script exists because of — it carries no information. Kept
            # only when nothing else is present, which is handled below.
            out.append(
                {
                    "job": job["name"],
                    "level": level,
                    "title": ann.get("title") or "",
                    "message": message,
                    "uninformative": "failed with exit code" in message
                    and "process" in message.lower(),
                }
            )
    informative = [a for a in out if not a["uninformative"]]
    return informative if informative else out


def show(run):
    conclusion = run["conclusion"] or run["status"]
    mark = {"success": "every row PASS", "failure": "NOT every row PASS"}.get(conclusion, conclusion)
    print(f"run #{run['run_number']}  {run['head_sha'][:7]}  {run['head_branch']}  [{mark}]")
    print(f"  {run['html_url']}")
    anns = annotations_for(run)
    if not anns:
        print(
            "  No annotations. If the run is still going this is expected; if it is\n"
            "  finished, it ran a commit from before k1-ci.sh emitted the table this\n"
            "  way, and the table is only in the artefact (which needs a token)."
        )
        return
    for ann in anns:
        print()
        print(f"  --- {ann['job']} [{ann['level']}] {ann['title']}")
        for line in ann["message"].splitlines():
            print(f"  {line}")


def latest(branch):
    query = "?per_page=10"
    if branch:
        query += f"&branch={branch}"
    runs = get(f"/repos/{REPO}/actions/workflows/{WORKFLOW}/runs{query}").get("workflow_runs", [])
    if not runs:
        undetermined(
            f"No runs of {WORKFLOW}"
            + (f" on branch {branch}" if branch else "")
            + ". Request one by pushing a k1-run/** branch, or with workflow_dispatch "
            "once the workflow is on the default branch."
        )
    return runs


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--last", type=int, default=1, help="how many recent runs to report (default 1)")
    ap.add_argument("--branch", help="only runs for this branch")
    ap.add_argument("--run", type=int, help="a specific run id")
    ap.add_argument(
        "--wait",
        type=int,
        metavar="SECONDS",
        help="poll until the newest matching run completes, then report it",
    )
    ap.add_argument(
        "--interval",
        type=int,
        default=90,
        metavar="SECONDS",
        help="seconds between polls while --wait is set (default 90)",
    )
    args = ap.parse_args()

    if args.run:
        runs = [get(f"/repos/{REPO}/actions/runs/{args.run}")]
    elif args.wait:
        # An emulator boot plus six mutations is minutes, not seconds, so a long
        # interval costs nothing in latency. What it buys is the budget.
        #
        # The first version of this polled every 30s, which over a 13-minute wait
        # is 26 of the 60 requests an unauthenticated IP gets per hour — and it
        # then hit the limit and could not read the result it had waited for. The
        # failure mode of a tool built to stop results going unread was to make
        # one unreadable. So the loop now refuses to spend below READ_COST and
        # waits out the window instead, saying so rather than failing quietly.
        deadline = time.monotonic() + args.wait
        while True:
            remaining, reset = budget()
            if remaining is not None and remaining <= READ_COST:
                pause = max(0, reset - int(time.time())) + 5
                print(
                    f"  {remaining} API requests left this hour; holding {pause}s for the "
                    f"window to reset rather than spending what reading the result needs.",
                    file=sys.stderr,
                )
                if time.monotonic() + pause > deadline:
                    undetermined(
                        f"Rate limit resets in {pause}s, past the --wait deadline. Re-run "
                        "then, or set GITHUB_TOKEN for 5000 requests/hour."
                    )
                time.sleep(pause)
                continue

            runs = latest(args.branch)[:1]
            if runs[0]["status"] == "completed":
                break
            if time.monotonic() >= deadline:
                print(
                    f"run #{runs[0]['run_number']} is still {runs[0]['status']} after "
                    f"{args.wait}s — reporting what exists.",
                    file=sys.stderr,
                )
                break
            print(
                f"  run #{runs[0]['run_number']} is {runs[0]['status']}"
                + (f" ({remaining} API requests left)" if remaining is not None else "")
                + "...",
                file=sys.stderr,
            )
            time.sleep(args.interval)
    else:
        runs = latest(args.branch)[: args.last]

    for i, run in enumerate(runs):
        if i:
            print()
        show(run)

    newest = runs[0]
    if newest["status"] != "completed":
        undetermined(f"\nrun #{newest['run_number']} has not finished; no verdict either way.")
    if newest["conclusion"] != "success":
        print(
            f"\nrun #{newest['run_number']}: not every row is PASS. A FAIL row is a BIT-8 "
            "rule-2 contradiction on that device — report it on BIT-18 and BIT-8, do not "
            "switch designs. An ERROR row means the run has no verdict.",
            file=sys.stderr,
        )
        sys.exit(NOT_GREEN)
    print(
        f"\nrun #{newest['run_number']}: every row PASS. Evidence for BIT-8 rule 2 on the "
        "images in the table above and no others."
    )


if __name__ == "__main__":
    main()
