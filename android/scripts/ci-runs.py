#!/usr/bin/env python3
"""Read Android Maestro CI results straight from the GitHub API.

    android/scripts/ci-runs.py                 # the last 5 runs, with timings
    android/scripts/ci-runs.py --last 3        # just the last 3
    android/scripts/ci-runs.py --require-green 3   # exit 1 unless the last 3 are green

WHY THIS EXISTS

BIT-5's definition of done is "three consecutive green CI runs, and report the
wall-clock number". For three rounds of this issue the results existed and the
number did not reach anyone: the agent that needed it had no way to read a run,
so each round ended by asking a human to open the Actions tab and copy a line
back. That produced "nothing to paste" twice and one pasted stack trace, and it
made a one-click chore the critical path of a definition of done.

The premise underneath it was wrong. `getbittr/bittr-ios-app` is a PUBLIC
repository, and the Actions REST API on a public repo needs no authentication
at all — runs, per-step durations and annotations are all readable anonymously.
Three rounds of asking were three rounds of not checking.

So the number is no longer something a person fetches. It is something anyone,
or anything, runs one command to get.

WHAT IT REPORTS, AND WHY THAT SHAPE

The end-to-end figure — run created to run finished — is the one that answers
"how long do I wait", and it is the one BIT-5 asks to be told. It is NOT the
emulator job's duration, which is the figure the workflow's own annotation
reports and is roughly a third of it. The build job runs first, takes longer,
and on the evidence runs was dominated by unit tests rather than by anything
Android-specific. Quoting the emulator number as "how long CI takes" understates
it by minutes, so both are printed, separately, with the total first.

NO DEPENDENCIES, DELIBERATELY

stdlib only — urllib, not requests — matching shared/test-ids/*.py, which parse
with `re` rather than PyYAML for the same reason: these checks have to run on
any python3 without a pip step, on a runner, on a Mac, or in a container.

AUTH

None needed while the repo is public. If GITHUB_TOKEN or GH_TOKEN is set it is
used, which raises the rate limit from 60 requests/hour per IP to 5000 and is
also what makes this keep working if the repo is ever made private.
"""

import argparse
import datetime
import json
import os
import sys
import urllib.error
import urllib.request

REPO = "getbittr/bittr-ios-app"
WORKFLOW = "android-maestro.yml"
API = "https://api.github.com"


def get(path):
    """GET a JSON path, with the rate limit reported as itself rather than as a crash."""
    req = urllib.request.Request(
        f"{API}{path}",
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "bittr-ci-runs",
        },
    )
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        if exc.code == 403 and "rate limit" in exc.read().decode("utf-8", "replace").lower():
            sys.exit(
                "GitHub API rate limit reached (60/hour per IP without a token).\n"
                "Set GITHUB_TOKEN or GH_TOKEN to raise it to 5000/hour, or wait."
            )
        if exc.code == 404:
            sys.exit(
                f"404 for {path}.\n"
                f"If {REPO} has been made private since this was written, this script "
                "needs GITHUB_TOKEN set to a token with `actions:read`."
            )
        raise


def parse(stamp):
    return datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00")) if stamp else None


def secs(start, end):
    start, end = parse(start), parse(end)
    return (end - start).total_seconds() if start and end else None


def human(seconds):
    """Seconds as `6m42s` — minutes matter for the run total and are unreadable as 402s."""
    if seconds is None:
        return "?"
    seconds = int(round(seconds))
    return f"{seconds // 60}m{seconds % 60:02d}s" if seconds >= 60 else f"{seconds}s"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--last", type=int, default=5, help="how many recent runs to report")
    ap.add_argument("--branch", help="only runs for this branch")
    ap.add_argument(
        "--require-green",
        type=int,
        metavar="N",
        help="exit non-zero unless the most recent N runs all succeeded",
    )
    ap.add_argument("--steps", action="store_true", help="also print per-step durations")
    args = ap.parse_args()

    # --require-green must look at exactly N, independently of --last, or asking for
    # "the last 3 green" while printing 5 would check the wrong set.
    want = max(args.last, args.require_green or 0)
    query = f"?per_page={want}"
    if args.branch:
        query += f"&branch={args.branch}"
    runs = get(f"/repos/{REPO}/actions/workflows/{WORKFLOW}/runs{query}").get("workflow_runs", [])

    if not runs:
        sys.exit("No runs found. If this workflow has never run on this branch, that is the answer.")

    print(f"{'run':>4}  {'commit':<8} {'result':<9} {'end-to-end':>10}  {'build':>7} {'emulator':>9}  branch")
    print("-" * 78)

    for run in runs[: args.last]:
        total = secs(run["created_at"], run["updated_at"])
        jobs = get(f"/repos/{REPO}/actions/runs/{run['id']}/jobs").get("jobs", [])
        durations = {}
        notice = None
        for job in jobs:
            durations[job["name"]] = secs(job["started_at"], job["completed_at"])
        build = next((v for k, v in durations.items() if "Build" in k), None)
        emu = next((v for k, v in durations.items() if "smoke" in k or "emulator" in k), None)

        result = run["conclusion"] or run["status"]
        mark = {"success": "green", "failure": "RED"}.get(result, result)
        print(
            f"{run['run_number']:>4}  {run['head_sha'][:7]:<8} {mark:<9} {human(total):>10}"
            f"  {human(build):>7} {human(emu):>9}  {run['head_branch']}"
        )

        # The workflow's own annotation, which is where the in-job decomposition
        # (setup / boot / install / flow) lives. Printed under its run so the two
        # numbers are never read as answers to the same question.
        for job in jobs:
            if "smoke" not in job["name"] and "emulator" not in job["name"]:
                continue
            for ann in get(f"/repos/{REPO}/check-runs/{job['id']}/annotations"):
                if ann.get("annotation_level") == "notice":
                    notice = ann.get("message")
        if notice:
            print(f"        {notice}")
        if args.steps:
            for job in jobs:
                print(f"        {job['name']} ({job['conclusion']})")
                for step in job.get("steps", []):
                    d = secs(step["started_at"], step["completed_at"])
                    if d is not None and d > 0:
                        print(f"          {human(d):>7}  {step['name']}")

    if args.require_green:
        checked = runs[: args.require_green]
        if len(checked) < args.require_green:
            sys.exit(
                f"\nAsked for {args.require_green} consecutive green runs; only "
                f"{len(checked)} runs exist."
            )
        bad = [r for r in checked if r["conclusion"] != "success"]
        if bad:
            sys.exit(
                f"\nNOT {args.require_green} consecutive green: "
                + ", ".join(f"#{r['run_number']} {r['conclusion']}" for r in bad)
            )
        median = sorted(secs(r["created_at"], r["updated_at"]) for r in checked)[len(checked) // 2]
        print(f"\n{args.require_green}/{args.require_green} green · median end-to-end {human(median)}")


if __name__ == "__main__":
    main()
