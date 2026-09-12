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

`.github/workflows/android-maestro.yml`, job **`S-36 isolation tests (emulator)`**. Runs
25 to 98 are on `feature/bit-62-instrumented-ci`, which is now merged; anything after that
is on `android-parity`.

| # | commit | result | verdict line |
|---|---|---|---|
| 25 | `7abd725` | **RED** | 212s · 9 required · vacuity check FAILED |
| 27 | `518cdd7` | **RED** | 179s · 9 required · vacuity check FAILED |
| 68 | `3bb6e52` | **RED** | 202s · 9 required · 0 missing · 0 skipped · **2 failed** · canary passed |
| 95 | `5956c29` | **green** | 203s · 9 required · 0 missing · 0 skipped · 0 failed · canary passed |
| 97 | `52b0ffe` | **RED** | 233s · 11 required · 0 missing · 0 skipped · **1 failed** · canary passed |
| 98 | `3b2392a` | **RED** | job never ran — `build` failed first, on `:app`'s unit tests |

Run 95 is the first execution of `CrossOriginIframeIsolationTest` in the test's life. It
is also, as of this writing, the last verdict this suite has given: runs 97 and 98 are
both about the two positive controls added *after* it, and neither has yet been answered
on a device.

**Run 97** is the positive controls' own false red, diagnosed under
*The positive controls* below and fixed in `3b2392a`. Note `11 required`, not 9 — the two
controls are in the `REQUIRED` set, so neither can be quietly dropped.

**Run 98** carries no signal about this suite at all. `build` went red on `:app`'s unit
tests — the BIT-106 test-gate breakage, unrelated to anything here and fixed three hours
later on `android-parity` by `8ae197d`, which the branch tip predates. Every emulator job
`needs: build`, so `instrumented` was *skipped*, not failed. Worth stating plainly,
because a red run with this suite's job showing grey is the one shape that looks like
evidence and is not.

The verdict on `3b2392a` therefore has to come from `android-parity`, which carries both
that commit and `8ae197d`. Four attempts to get it produced nothing, for a reason that had
nothing to do with the tests — see *The gate that would not start* below.

Reproduce the table without credentials — the repository is public and the Actions REST
API on a public repo is readable anonymously:

```sh
android/scripts/ci-runs.py --branch feature/bit-62-instrumented-ci
android/scripts/ci-runs.py --branch android-parity
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

`ci-instrumented.sh` does not take that on trust. It reads `dumpsys webviewupdate` before
running anything, prints the provider on every run, and **fails the job outright** if the
image ships none — because the alternative is every test in the suite failing at `WebView`
construction with `MissingWebViewPackageException`, and not one of those failures
mentioning the system image. So the assumption cannot rot silently in either direction.

## The gate that would not start

Runs **121, 122, 125 and 126** on `android-parity` are red having started **zero jobs** —
not this job, *all four*, `build` and `maestro` included. Recorded here because it is the
reason this suite went most of a day without a verdict, and because the failure is unusually
hard to read.

Two consolidation merges stacked two authors' work into non-overlapping regions of the same
files. Git merged cleanly and produced text nobody wrote: `jobs.instrumented` defined twice
— BIT-33 and BIT-62 had each written a job to run `ci-instrumented.sh` — plus two `run:`
keys in one `build` step, and `ci-instrumented.sh` itself left as two scripts concatenated,
the older copy appended after the newer one's `exit`.

A duplicate key is well-formed YAML. Most parsers accept it and silently resolve
last-one-wins, so loading the file locally reported four healthy jobs and told nobody
anything was wrong. GitHub's parser rejects it, and rejects it *before scheduling
anything* — so there is no step log to read, no check run, and no failing step to open.
With no `name:` ever parsed, the run list shows the file path where the workflow name goes,
which scans as a different workflow rather than a broken one. The tell:

```sh
# a healthy run lists its jobs; a startup failure returns total_count 0
curl -s https://api.github.com/repos/getbittr/bittr-ios-app/actions/runs/<id>/jobs
```

Fixed under BIT-110 in `e202344`, which kept the BIT-62 copy of the job. That is not a
preference between two designs: the BIT-33 copy booted `aosp_atd`, which is the one image
the section above explains this suite must not run on. `.github/workflows/workflow-lint.yml`
now runs actionlint from a file of its own, because the lint that names this defect was
inside the file that could not start.

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

## The positive controls (runs 97 and 98)

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

### Run 97: the control's own false red

The iframe control failed on its first run, and — exactly like run 68 — the failure was
the test's, not the wallet's. The assertion that fired says the iframe "never reported in
at all", and the report it printed alongside itself was:

```
{"ran":true,"bridges":["bittrLnurl","postMessage:bittrLnurl"],"errors":[],
 "topNavigated":false,"planted":["lightning:lnurl1dp68gurn8ghj7..."]}
```

`ran` is true and both halves of the probe found the planted bridge. The control had
worked perfectly and then failed to notice.

The check was a substring test for `{"ran":true}` against
`JSON.stringify(window.__bittrIframe)`. `evaluateJavascript` hands back a JSON *encoding*
of its result, so a stringified object arrives with every quote escaped: the haystack held
`\"ran\":true` and the needle was `"ran":true`. It could not have matched its own subject
on any run, green or red.

`3b2392a` asks it the way `theCrossOriginIframeActuallyRan` asks it — reduce to a bare
boolean in JS, compare the whole encoded value exactly. The three other checks in that
test were unaffected: `bittrLnurl`, `postMessage:bittrLnurl` and `lightning:` contain no
quote characters, so they survive the escaping intact, which is why the same bug did not
take the whole test down and made the failure look like the probe's.

Two false reds now, out of two substantive findings, and both found by a run rather than
by review. That is the argument for this job stated better than the issue stated it: a
test nobody has executed can be asserting something false as easily as asserting nothing.

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
