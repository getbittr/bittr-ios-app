# The S-36 isolation tests, on a real emulator (BIT-62)

BIT-58 asked for an instrumented test that loads a first-party page containing a
cross-origin iframe which tries to reach the LNURL bridge, and asserts the wallet does
not react. That test was written and committed months before anything ever executed it.
BIT-62 is the issue that ran it.

This file records the runs, because "the isolation suite passes on a device" is a claim
that outlives the issue that asked for it, and the next person to doubt it will be
reading the repo rather than the issue tracker. It is the companion to
[`ci-evidence.md`](ci-evidence.md), which does the same job for the Maestro smoke flow.

## The runs

`.github/workflows/android-maestro.yml`, job **`S-36 isolation tests (emulator)`**, on
branch `feature/bit-62-instrumented-ci`.

| # | commit | result | verdict line |
|---|---|---|---|
| 25 | `7abd725` | **RED** | 212s · 9 required · vacuity check FAILED |
| 27 | `518cdd7` | **RED** | 179s · 9 required · vacuity check FAILED |
| 68 | `3bb6e52` | **RED** | 202s · 9 required · 0 missing · 0 skipped · **2 failed** · canary passed |
| 95 | `5956c29` | **green** | 203s · 9 required · 0 missing · 0 skipped · 0 failed · canary passed |
| 97 | `52b0ffe` | **RED** | 233s · 11 required · 0 missing · 0 skipped · **1 failed** · canary passed |
| 98 | `3b2392a` | *not reached* | build job red at `./gradlew test`; the emulator job was skipped |
| 131 | `48c529d` | **green** | 186s · 11 required · 0 missing · 0 skipped · 0 failed · canary passed |

Run 95 is the first execution of `CrossOriginIframeIsolationTest` in the test's life.
**Run 131 is the one to cite**: the full eleven, including both positive controls, green on
a real WebView. Run 95 proved the suite runs; run 131 proves the probe inside it still
recognises a bridge while doing so.

Run 97 is the first run carrying the two positive controls, and its single failure is one
of them — `theIframeBridgeProbeReportsABridgeThatIsActuallyThere`, on its own `ran`
check. It is a false red of exactly the kind [run 68](#run-68-the-red-was-the-tests-not-the-wallet) was, and the
report it printed is the proof, because the probe it was doubting had in fact worked
perfectly:

```
Report: "{\"ran\":true,\"bridges\":[\"bittrLnurl\",\"postMessage:bittrLnurl\"],
          \"errors\":[],\"topNavigated\":false,
          \"planted\":[\"lightning:lnurl1dp68…\"]}"
```

The frame ran, both halves of the probe found the planted bridge, and the catch-all
posted to it. The assertion looked for the substring `{"ran":true}` in that text and
could never have found it: `evaluateJavascript` hands back a JSON *encoding*, so the
haystack holds `\"ran\":true` while the needle held `"ran":true`. `3b2392a` had already
fixed it — by predicting it from re-reading the diff, before run 97 reported — and asks
the question the way `theCrossOriginIframeActuallyRan` asks it, reducing to a bare
boolean in JS and comparing the whole encoded value.

So run 97 is evidence *for* the positive controls rather than against them: every
substantive claim they make passed on the emulator, and the one assertion that failed
was testing its own phrasing. Run 131 confirms it — the same eleven tests, the fixed
assertion, nothing failed.

Run 98 carried that fix and never got to the emulator: the build job went red at
`./gradlew test` and the `instrumented` job was skipped behind it. No unit test had
failed. `./gradlew test --rerun-tasks` on the same commit executed all 226 tasks green
locally, and run 131 — the same tree plus a reporter script — was green on the runner, so
the failure was transient in the toolchain. Establishing *that* is what the run itself
could not say, and it is why `annotate-unit-failures.py` now exists; see
[Reading a red build job](#reading-a-red-build-job).

Reproduce the table without credentials — the repository is public and the Actions REST
API on a public repo is readable anonymously:

```sh
android/scripts/ci-runs.py --branch feature/bit-62-instrumented-ci
```

## What the green actually establishes

The suite is nine tests, now eleven. Counting them is not the same as reading them, and
three of the four watch-fors on BIT-62 were about exactly that gap.

**The iframe genuinely ran.** `theCrossOriginIframeActuallyRan` passed. This is a
separate test on purpose: if the iframe never loads, "no bridge was found" and "the
iframe never got to look" produce the same tick, and the second is worthless. Runs 25
and 27 are what that looks like when it fails — the vacuity check caught them.

**Both loopback servers were reachable from inside the emulator.** Implied by the canary:
the iframe document is served by the *second* `LocalTestServer`, on a different port, and
it reported back.

**The hardening baseline holds on the real object.**
`theHardeningBaselineIsAppliedToTheRealWebView` reads the live `WebSettings` off a real
`WebView`, which is the half the source-scanning guards in `:app` cannot cover — they
read the source that sets a value and cannot see it being overwritten afterwards.

**Nothing was skipped or renamed away.** 0 missing, 0 skipped. `REQUIRED` in
`android/scripts/check-instrumented-results.py` is a hard-coded list of test IDs; a
rename fails the build and points at itself as the place to review.

## Why its own job, on a `default` image

The Maestro job boots `aosp_atd` — an Automated Test Device, stripped for boot speed —
and caches its AVD snapshot under a key naming that image. What ATD strips varies by API
level, and a WebView provider is a plausible casualty. The Maestro flow drives Compose UI
and would not notice; **every** test in this suite constructs a real
`android.webkit.WebView` and would fail at construction. Sharing the AVD would make this
suite's correctness depend on a choice made for a different test's speed, so this job
uses a full AOSP `default` image and pays the slower boot.

`ci-instrumented.sh` does not take that on trust. It reads
`dumpsys webviewupdate` before running anything, prints the provider on every run, and
**fails the job outright** if the image ships none — because the alternative is nine
tests failing at `WebView` construction with `MissingWebViewPackageException` and not one
of the failures mentioning the system image. So the assumption cannot rot silently in
either direction.

## Run 68: the red was the test's, not the wallet's

Worth keeping, because it is the most useful thing that happened here and it is the
answer to "what if the test had been asserting something false all along".

Two of nine failed, both of them the assertions on `window.__bittrProbe.bridges`. The
hostile page ends with a catch-all — walk `for…in` over `window`, report anything
carrying a `postMessage` — so that a bridge injected under an unanticipated name is still
caught. `for…in` walks `Window.prototype`, where the frame-tree aliases live and are
enumerable, so the window came back under its own aliases: `self`, `frames`, `parent`,
`top`. The page excluded four names and `frames` went straight through.
`window.frames === window`, every `Window` has `postMessage`, so the probe filed the
page's own DOM API as a wallet bridge.

S-36 ships no bridge. The finding was the test's.

The interesting part is that `CrossOriginIframeIsolationTest` already had `frames` in its
skip list and passed. The two copies of the probe had diverged, and only one of them had
ever been run — **a test nobody has executed can be asserting something false as easily
as asserting nothing at all**, which is BIT-62's premise arriving from the other
direction. Both now exclude by object identity rather than by name: a name list cannot
exclude an alias it has not heard of, while the entire job of the catch-all is to admit a
bridge under a name it has not heard of.

## The positive controls (runs 97–)

After run 95 there was still one hole. Every bridge assertion in both classes is
`assertEquals("[]", bridges)` — and an empty list is also exactly what a probe that has
stopped working returns. The canary closes half of it by proving the frame loaded. It
does not prove the probe inside that frame can still *recognise* a bridge, so it moves
the vacuity down one level rather than closing it: from "did the frame load" to "did the
probe look".

That is not a hypothetical, because the alias exclusion had just been rewritten. Identity
is the right shape and it is also one `!` away from excluding everything, at which point
all four bridge assertions pass forever and nothing in the suite notices.

So each class now carries a positive control — the same page with a bridge-shaped object
planted in it, asserting the probe reports it:

- `ThirdPartyIsolationTest#theBridgeProbeReportsABridgeThatIsActuallyThere`
- `CrossOriginIframeIsolationTest#theIframeBridgeProbeReportsABridgeThatIsActuallyThere`

Both halves of the probe are checked separately, because they fail independently: the
name list (`bittrLnurl`) and the `for…in` catch-all (`postMessage:bittrLnurl`). The
catch-all is the one that matters — it is the only half that can catch a bridge added
under a name nobody predicted, and it is the half the identity change rewrote. Each also
asserts the catch-all *posted* to what it found, which is the claim that a discovered
bridge is never merely noted.

**The iframe copy is the load-bearing one.** In the main frame `parent`, `top` and `self`
are all the window itself, so `v === window` alone would have covered them. Inside a
frame cross-origin to its parent they are genuinely *different* objects — cross-origin
`Window` proxies, each with a real `postMessage` — and the probe has to reject those
while still reporting the planted object sitting beside them. An exclusion written
slightly too wide passes every other test in the file and fails only there.

### Why the bridge is planted from JavaScript

**Not** `addJavascriptInterface`. That API is banned repo-wide by
`JavascriptInterfaceGuardTest`, which scans every Kotlin file under `android/` —
including the instrumented tests — and has deliberately no allowlist. A test that had to
be exempted from the ban in order to exist would be the wrong trade: the ban is the
stronger guarantee and it should not acquire its first exception on behalf of a test.

Planting the object in the page is also the more honest shape. Nothing native is exposed,
the wallet is not modified, and what is under test is the probe rather than the app. A
real `addJavascriptInterface` bridge would reach the probe's rule
(`typeof v.postMessage === 'function' && !isSelfAlias(v)`) the same way the planted one
does: as an enumerable own property of `window` that is not the window.

The guard's scan strips comments *and* string literals before searching, which is why
both test files are free to name the banned API in prose and in assertion messages — and
they have to, because the reason it is banned is the whole point.

## Reading a red build job

The emulator job sits behind `build`, so a red build job means the isolation suite did not
run at all — and run 98 is the case where nobody could tell why. Job logs on this
repository answer **403** without admin rights and artifacts answer **401**, so check-run
annotations are the only part of a run readable from outside, and all run 98 offered was
GitHub's own:

```
[failure] Process completed with exit code 1.
```

That single line cannot distinguish a unit test that genuinely failed — whose name and
assertion message are sitting in XML on the runner — from a Gradle that died fetching a
dependency or was OOM-killed. The two want opposite responses: read the assertion, or
re-run. Telling them apart cost a full local `./gradlew test --rerun-tasks`.

`android/scripts/annotate-unit-failures.py` closes that. It runs only on the red path
(`if: failure()`), **always exits 0** — a reporter that could fail a build would be able to
turn a green run red by mis-parsing XML — and emits one of two things:

- `::error::` naming each failing test with its message, read from either the `message=`
  attribute or the element body, because not every writer uses the attribute; or
- `::notice::` saying no test failed, and how many result files it searched.

The second is the one run 98 needed. The absence of a finding *is* the finding: it points
at the toolchain rather than at the wallet, and saying so is a conclusion where silence was
not. It reuses `check-instrumented-results.py`'s `failure_message`, `detail` and `annotate`
rather than copying them — a second, subtly different copy of the escaping is how an
annotation goes quiet again — and reads only `build/test-results/`, never
`outputs/androidTest-results/`. That is the mirror of the care that file already takes in
the other direction, so neither job can ever be satisfied by the other's evidence.

## What these tests are for

S-36 ships **no** LNURL bridge on any origin — no `addJavascriptInterface`, no
`addWebMessageListener`; `androidx.webkit` is not a dependency of `:feature:website` at
all. So the suite is expected to pass today and does.

Its value is as a regression gate on the day someone adds a bridge. The iframe probe
would find it — and an iframe is exactly the case a `webView.url` origin check waves
through, because that check sees the main frame's first-party URL and never looks at the
frame the script is actually running in. `addJavascriptInterface` has no frame scoping at
all. That is the iOS gap BIT-58 was named after, and this is the test that would have
caught it.
