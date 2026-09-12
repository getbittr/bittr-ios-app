# Capturing the sync status overlay (`receive_onchain/00_sync_status.png`)

Design-system screen **S-27**. One screenshot. Not blocking anything — this is the
only screen of the 38 in batch 4 with no captured shot to check the source
numbers against.

## Why it is missing

`receive_onchain.yaml:69–86` taps the header spinner by coordinate, then branches:

| guard | what opened | shot |
| --- | --- | --- |
| `visible: sync.statusView` | sync overlay (still syncing) | `00_sync_status.png` |
| `visible: move.subtitleLabel` | balance/Move screen (already synced) | `00_move_balance.png` |

`HomeViewController.swift:366` `syncingStatusTapped` picks the branch on
`coreVC.walletHasSynced`. On the 2026-09-09 run the sync had already finished, so
the second branch fired. `00_move_balance.png` is on disk; `00_sync_status.png` is
not. **The flow is correct** — it is written to survive both outcomes and it did.

Re-running the suite is the same coin flip. It needs a forced slow sync.

## The lever is `finalizeSync()`, not `walletHasSynced`

Stubbing `walletHasSynced` to stay false is the obvious idea and it produces the
**wrong screenshot**. `LoadWalletData.swift:520` `finalizeSync()` does two separate
things:

```swift
self.coreVC!.walletHasSynced = true      // gates which branch the tap takes
self.coreVC!.completeSync(.final)        // drives what the overlay *shows*
```

Pin only the first and the second still runs: `completeSync(.final)`
(`SyncingStatus.swift:76`) lights the third checkmark and schedules
`hideSyncView()` 0.5 s later. The tap would then open an overlay with all three
rows checkmarked and nothing spinning — and, because nothing calls `hideSyncView`
a second time, it would never auto-dismiss, hanging the flow's
`extendedWaitUntil notVisible` for its full 60 s timeout.

Delay **`finalizeSync()` as a whole** instead. It has exactly one call site
(`LoadWalletData.swift:147`), already guarded by `!walletHasSynced`.

## Sync state timeline

| # | call | site | overlay after |
| --- | --- | --- | --- |
| 1 | `startSync(.conversion)` | `ShowCachedData.swift:59` | conversion spinning |
| 2 | `completeSync(.conversion)` | `ShowCachedData.swift:64` | conversion ✓ |
| 3 | `startSync(.ldk)` | `StartLightning.swift:66`/`71` | LDK spinning |
| 4 | `completeSync(.ldk)` | `StartLightning.swift:98` | LDK ✓ |
| 5 | `startSync(.final)` | `StartLightning.swift:109` | final spinning |
| 6 | `completeSync(.final)` | `LoadWalletData.swift:530` | final ✓, auto-hide in 0.5 s |

The capture window is **between 5 and 6**: conversion ✓, LDK ✓, final spinning.
That is the richest state for a spec — it shows a completed row and a pending row
in the same frame.

## Proposed patch

Follows the `EvilBoltz` precedent (`EvilBoltz.swift:203–223`): a `CommandLine`
flag with an env-var fallback, hard-gated on `EnvironmentConfig.isDevelopment`.

> **Not applied — this Swift patch is the one manual step.** This repo has no Mac
> in the loop, so the change is unbuilt and uncompiled; committing it would put an
> unverified Swift edit on the branch. Apply it during the BIT-14 Mac pass, where
> it can actually be compiled. The Maestro/harness plumbing that feeds it
> (`test_suite.sh`, `receive_onchain.yaml`) **is** committed — see *Running it*.

```diff
--- a/ios/bittr/Home/LoadWalletData.swift
+++ b/ios/bittr/Home/LoadWalletData.swift
@@
         if (self.coreVC != nil && !self.coreVC!.walletHasSynced) {
-            // Finalize sync.
-            self.finalizeSync()
+            // Finalize sync. Under -slowSync the whole call is deferred so the
+            // sync overlay stays open long enough to screenshot: walletHasSynced
+            // stays false (so the header tap opens the overlay rather than the
+            // Move screen) *and* the `.final` row keeps spinning. Deferring only
+            // the flag would show a fully-checkmarked overlay that never
+            // auto-dismisses. Debug/regtest only.
+            if let delay = Self.slowSyncDelay, !Self.slowSyncArmed {
+                Self.slowSyncArmed = true
+                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
+                    self?.finalizeSync()
+                }
+            } else {
+                self.finalizeSync()
+            }
         } else if ...
```

plus, on the same type:

```swift
#if DEBUG
/// Seconds to hold the sync overlay open before finalising, for capturing
/// S-27. `-slowSync` (bare, = 20 s) or `-slowSync 30`, or `BITTR_SLOW_SYNC=30`.
/// Regtest builds only. A delay of 0 — what every ordinary suite run passes —
/// means "off".
static var slowSyncDelay: TimeInterval? {
    guard EnvironmentConfig.isDevelopment else { return nil }
    // Accept -slowSync and --slowSync: Maestro renders an `arguments:` key as
    // `-key`, and hand-runs tend to type the double dash.
    if let i = CommandLine.arguments.firstIndex(where: {
        $0 == "-slowSync" || $0 == "--slowSync"
    }) {
        let next = i + 1
        if CommandLine.arguments.indices.contains(next),
           !CommandLine.arguments[next].hasPrefix("-"),
           let parsed = TimeInterval(CommandLine.arguments[next]) {
            return parsed > 0 ? parsed : nil
        }
        return 20   // bare flag, no value
    }
    if let raw = ProcessInfo.processInfo.environment["BITTR_SLOW_SYNC"],
       let parsed = TimeInterval(raw) { return parsed > 0 ? parsed : nil }
    return nil
}
/// `loadWalletData` can re-enter while the deferred call is pending — without
/// this each pass would schedule another `finalizeSync`.
static var slowSyncArmed = false
#else
static var slowSyncDelay: TimeInterval? { nil }
static var slowSyncArmed = false
#endif
```

## Running it

```sh
BITTR_SLOW_SYNC=20 shared/flows/test_suite.sh features/receive_onchain.yaml
```

**The plumbing for that command is already committed** — only the Swift patch
above is outstanding.

An earlier draft of this doc claimed `receive_onchain.yaml` needed no change and
that the env var alone would do it. That was wrong, and it would have failed
silently — the flow would have run green and simply not produced the shot.
`test_suite.sh` invokes `maestro test --env … <flow>`, and Maestro launches the
app **on the simulator**, so a variable exported in the Mac's shell is never in
`ProcessInfo.processInfo.environment` for the app. It has to travel as a launch
argument. Two small commits now carry it:

- `test_suite.sh` reads `$BITTR_SLOW_SYNC` (default `0`) and passes it to every
  flow as `--env SLOW_SYNC=…`;
- `receive_onchain.yaml` declares `env: SLOW_SYNC: "0"` as the default and
  launches with `arguments: { slowSync: ${SLOW_SYNC} }`, which Maestro renders as
  `-slowSync <n>`.

So an ordinary suite run passes `-slowSync 0`, which the patch reads as *off*.
That is why the Swift side must treat `0` as disabled rather than as a zero-second
delay — otherwise every normal `receive_onchain` run would defer `finalizeSync`
onto the next runloop turn for no reason.

The flow needs no *other* change: it already waits for the overlay's own
auto-dismiss, which still fires — just `delay` seconds later, well inside the
existing 60 s `extendedWaitUntil`.

If `slowSync` somehow arrives uninterpolated (a literal `${SLOW_SYNC}`, e.g. an
older Maestro that does not substitute inside `arguments`), `TimeInterval(…)`
returns nil and the flag reads as off — the flow still passes, it just captures
`00_move_balance.png` as before. Verify from the run log that the app launched
with `-slowSync 20` before concluding the patch is at fault.

Expect `00_sync_status.png` **and** `00_move_balance.png` to both be absent-or-present
per run: with the flag armed you get `00_sync_status.png` and the Move branch does
not fire, so `00_move_balance.png` from the 2026-09-09 run should be kept, not
overwritten. Both are legitimate captures of the two branches.

## Why not throttle the network

Network Link Conditioner / a slow `simctl` profile also widens the window, and
needs no app change. Two reasons to prefer the flag:

- it is still probabilistic — a slower fetch is not a *bounded* fetch, and the
  20 s window above is exact;
- LDK start (step 3→4) is not purely network-bound, so throttling stretches the
  conversion step much more than the rest, biasing which row is still spinning
  when the tap lands.

Throttling is the right fallback if the Mac pass would rather not touch app code
for one screenshot. It will just take a few attempts.

## Verifier

`screenshot_map.py` already classifies this correctly — `00_sync_status.png` is
one of the 6 **"Conditional branch not taken"** benign misses, not a failure. If
the shot is captured, the count drops to 5 and nothing else needs updating.
