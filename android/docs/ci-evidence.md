# CI evidence for BIT-5

BIT-5 closes on **three consecutive green CI runs** of
`.github/workflows/android-maestro.yml` plus a **wall-clock number**. This file is the
record of those runs. It exists as a file, rather than as a comment on the issue,
because the claim "the Android suite passes in CI" outlives the issue that asked for it
and the next person to doubt it will be reading the repo.

## Why this file is also the trigger

`workflow_dispatch` is unavailable until the workflow reaches the default branch, so
pushing is the only way to produce a run — and the workflow has a `paths:` filter, which
means **an empty commit does not trigger it**. Something under `android/**`,
`shared/flows/**`, `shared/test-ids/**` or the workflow file itself has to change.

Rather than bump a meaningless marker file, each evidence run is triggered by the commit
that adds its own row here. The commit that asks for the run is the commit that records
it. `android/docs/**` is inside the `android/**` filter, so this works.

## Runs

Each row is one push to `feature/bit-5-android-scaffold`. Runs cannot cancel each other
— non-dispatch runs are keyed on `github.sha` (see `self-hosted-runner.md`, *Why three
runs in a row is safe to do*) — so all three survive to be read.

| # | commit | trigger | result | flow | emulator job total |
|---|---|---|---|---|---|
| 0 | `a93f1fe` | push | **green** | not recorded | not recorded |
| 1 | `d2f1ba9` | push | *pending* | | |
| 2 | *this commit* | push | *pending* | | |

Run 0 is numbered zero deliberately: it is the first green run in this workflow's
history and it is what established that the job works end to end, but it predates the
concurrency fix and the `::notice`, so it produced no number anyone read. It is evidence
that CI *can* be green. It is not one of the three.

**Reading a result takes one click and no scrolling.** Open the run from
<https://github.com/getbittr/bittr-ios-app/actions/workflows/android-maestro.yml>; the
annotation box at the top of the page carries the whole line:

```
Maestro smoke — green in 512s
flow 14s · emulator boot 402s · APK install 9s · emulator job total 512s
```

The same figures are in the step summary at the bottom of the run page, as a table, with
the Maestro version and runner type alongside.

## What counts as green

The **whole job**, not the flow alone. A green flow inside a red job still fails the
run, and that is deliberate — the POSIX-`sh` failure that killed the first run happened
after the emulator booted and before the flow ran, and a rule that looked only at the
flow would have called it "no result" rather than "red".

There are **no retries anywhere in the workflow**, per BIT-5's brief. If a run needs to
be repeated to go green, that is a failing run and it gets a row here saying so — the
count restarts rather than the red row being dropped. Three consecutive means
consecutive.
