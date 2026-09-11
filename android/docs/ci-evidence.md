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

| # | commit | run | result | end-to-end | build job | emulator job | flow |
|---|---|---|---|---|---|---|---|
| 0 | `a93f1fe` | 5 | **green** | 6m48s | not recorded | not recorded | not recorded |
| 1 | `d2f1ba9` | 8 | **green** | 6m36s | 4m33s | 1m55s | 18s |
| 2 | `6a9bc95` | 9 | **green** | 6m37s | 4m13s | 2m17s | 20s |
| 3 | `4855ed2` | 10 | **green** | 6m42s | 4m34s | 2m00s | 19s |
| — | `e1f042b` | 11 | **green** | 6m48s | 4m17s | 2m23s | 16s |
| — | `000d240` | 12 | **green** | 6m08s | 4m10s | 1m50s | 18s |

**3/3 green. Median end-to-end 6m37s, spread 6s.** BIT-5's definition of done is met.

Runs 6 and 7 were green in between, on other commits. **Runs 7 through 12 are six
consecutive greens**, spanning 6m08s to 6m48s — a 40s spread across six runs, no retries
anywhere. Three was what was asked for; the extra three are what make "reliably, not
once" more than a phrase.

Rows 11 and 12 have no `#` because they were not evidence runs — they are ordinary
pushes that happened to be green, which is the more interesting kind. Run 12 is the one
that carries `test_ci_runs.py`, so the streak includes a run of the tests that guard the
tool that reports the streak.

### Reproducing this table

```sh
android/scripts/ci-runs.py --require-green 3
```

Output at the time of writing:

```
 run  commit   result    end-to-end    build  emulator  branch
  12  000d240  green          6m08s    4m10s     1m50s  feature/bit-5-android-scaffold
        flow 18s · emulator boot 64s · setup 20s · APK install 0s · emulator job total 102s
  11  e1f042b  green          6m48s    4m17s     2m23s  feature/bit-5-android-scaffold
        flow 16s · emulator boot 86s · setup 27s · APK install 1s · emulator job total 130s
  10  4855ed2  green          6m42s    4m34s     2m00s  feature/bit-5-android-scaffold

3/3 green (#12, #11, #10) · median end-to-end 6m42s
```

No token, no `gh`, no clicking. The repository is public and the Actions REST API on a
public repo is readable anonymously — worth stating plainly, because this issue spent
three rounds asking a human to read these numbers off the Actions tab on the assumption
that the agent could not. Nobody checked the assumption. `--require-green N` exits
non-zero unless the most recent N runs all succeeded, so the claim in this file is
re-verifiable rather than merely recorded.

Exit codes are **0 green · 1 looked and it is not green · 2 could not find out**. The
split matters: without it a rate limit and a broken build are the same exit code, and an
outage reads as a regression. Unauthenticated is 60 requests/hour per IP and each run
costs two, so about eight invocations an hour before it starts answering 2. Set
`GITHUB_TOKEN` to raise that to 5000.

**A run still in flight is skipped, not counted as a failure.** This was a real bug, not
a hypothetical one — `conclusion` is `null` until a run completes, `null != "success"`,
so the first invocation of this tool against a repo with a run in progress reported *NOT
GREEN* over three genuinely green runs. It would have fired for the ~7 minutes after
every push, which is to say on exactly the pushes this file exists to measure.
`android/scripts/test_ci_runs.py` covers that case and runs in the `build` job; a gate
that misreports is worse than no gate.

**End-to-end is the number BIT-5 asks for** — commit pushed to run finished. It is not
the figure in a run's own `::notice`, which covers the emulator job only (~2 minutes)
and understates the wait by more than four. Both are printed, total first.

### Where the time actually goes

The emulator was expected to be the expensive, unreliable half. It is neither: ~2
minutes, stable to within 22s across the three runs. The `build` job is the long pole at
~4m30s, and **unit tests are 3m-3m26s of it** — about half of all CI time, for eleven
tests on a scaffold. If 6m37s ever becomes too long to wait for, that is the row to
attack, and Gradle configuration and daemon warm-up are the first suspects rather than
the tests themselves.

Run 0 is numbered zero deliberately: it is the first green run in this workflow's
history and it is what established that the job works end to end, but it predates the
concurrency fix and the `::notice`, so it produced no number anyone read. It is evidence
that CI *can* be green. It is not one of the three.

**Reading a result takes one click and no scrolling.** Open the run from
<https://github.com/getbittr/bittr-ios-app/actions/workflows/android-maestro.yml>; the
annotation box at the top of the page carries the whole line. This is what run 10
emitted:

```
Maestro smoke — green in 109s
flow 19s · emulator boot 89s · APK install 1s · emulator job total 109s
```

Runs from this commit onward carry the corrected labels described below, which split
that 89s into `emulator boot ~65s · setup ~24s`. Those two figures are derived here from
run 10's per-step durations rather than quoted from any run — no run has printed them
yet; the first to do so is the one triggered by this commit.

The same figures are in the step summary at the bottom of the run page, as a table, with
the Maestro version and runner type alongside.

Two corrections are baked into that line, both found by checking the annotation against
the API's per-step durations rather than by reading it:

- **It is the emulator job, not the run.** 109s against a 6m42s run. The `build` job
  runs first and is longer. Anyone quoting the annotation as "how long CI takes" is off
  by a factor of four, which is why the line now says so and why `ci-runs.py` leads with
  end-to-end.
- **"emulator boot" used to include things that were not the boot.** It was measured
  from the top of the job, so it also contained the JDK setup, Maestro's installer and
  the AVD cache restore — 20-34s of the 88-107s originally reported. Boot and setup are
  measured separately now, and boot means boot. The number that got that wrong was one
  I had promoted to the top of the page the round before, having dropped the qualifier
  the step-summary table still carried.

## What counts as green

The **whole job**, not the flow alone. A green flow inside a red job still fails the
run, and that is deliberate — the POSIX-`sh` failure that killed the first run happened
after the emulator booted and before the flow ran, and a rule that looked only at the
flow would have called it "no result" rather than "red".

There are **no retries anywhere in the workflow**, per BIT-5's brief. If a run needs to
be repeated to go green, that is a failing run and it gets a row here saying so — the
count restarts rather than the red row being dropped. Three consecutive means
consecutive.
