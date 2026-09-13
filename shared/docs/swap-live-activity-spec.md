# Swap Live Activity spec — `SwapLiveActivity` (iOS) → Live Update (Android)

**Status:** decided · **Decided by:** Head of App (Android), BIT-75 (§1–§5, §7 — the mechanism)
and Mobile Product Designer, BIT-115 (§4.2, §4.3, §6 — the copy, icons and tint) ·
**Source of truth:**
`ios/BittrWidget/SwapLiveActivity.swift`, `ios/BittrWidget/SwapActivityAttributes.swift`,
`ios/bittr/Swaps/SwapLiveActivityController.swift` at `2867c35`

The companion to [`widget-spec.md`](widget-spec.md), which covers the *other* widget in the same
iOS extension. `widget-spec.md` §8 deliberately left this surface out and said it needed its own
scoping decision and its own spec. This is it.

Like the price widget, this surface is absent from the BIT-3 screenshot catalog and cannot be
added to it — Maestro cannot drive the iOS Dynamic Island or Lock Screen. So this document
replaces the screenshot as the design input and behavioural spec.

---

## 1. Decision

**In scope for the port — out of scope for the v1 done-gate.** Same shape as BIT-11, for the
same reason: the port's v1 definition of done is "the iOS Maestro suite passes on Android", and a
surface no Maestro flow can reach cannot be part of that gate.

**It is cheaper than BIT-75's ticket assumed, and that is why it stays in scope.** The ticket
said "there is no direct Android equivalent" and "the closest construct is an ongoing/foreground-service
notification with a progress indicator — a different thing, not a 1:1 port". That was true before
Android 16. It is no longer true, and three specific claims in it are wrong:

| Ticket claim | Actual |
| --- | --- |
| "No direct Android equivalent" | Android 16 (API 36) ships **Live Updates**: `Notification.ProgressStyle` + promoted-ongoing. That *is* the counterpart — lock screen presence, a status-bar chip, a segmented progress bar. |
| "Dynamic Island has no counterpart at all" | The status-bar chip is the counterpart to the island's compact presentation. `setShortCriticalText("10m")` is literally the compact-trailing text. Only the *expanded* island's three-region layout has no counterpart (§6). |
| "ongoing/**foreground-service** notification" | No foreground service is needed. A promoted ongoing notification is an ordinary `notify()` call. A foreground service is only needed to keep the LDK node alive to claim the HTLC — a separate concern that belongs to Phase 4 item 9, not to this surface. |

Everything the surface needs is **already in the build**: `androidx.core` is pinned at `1.19.0`,
which ships `NotificationCompat.ProgressStyle` (with `Api36Impl`/`Api37Impl`) and
`NotificationCompat.Builder.setRequestPromotedOngoing`. `targetSdk` is 36, `compileSdk` 37, and
`POST_NOTIFICATIONS` is already declared in the manifest. No new dependency, no new module, no
new extension or process. It is roughly one Kotlin file plus a notification channel.

It is also **not "checked by hand"**, which is the other thing that made it look expensive. Most
of this surface is a JVM unit test — see §7, which reports a probe that already ran offline.

**Placement: Phase 4, after item 7 (swaps) and item 9 (notifications + payout).** It cannot be
built before the thing it reports on exists. `ANDROID_PORT_PLAN.md` Phase 4 item 11 covers only
the Glance price widget and should not absorb this; this is its own item.

This call is reversible. If the founder would rather drop the surface from the port entirely, the
sunk cost is this document.

---

## 2. What the surface actually is

A **live progress display for one onchain→lightning (submarine) swap**, rendered by the system
outside the app: on the Lock Screen, and in the Dynamic Island on devices that have one.

It is the opposite of the price widget in every way that matters. The price widget is autonomous,
stateless and touches no user data. This one is **app-driven, stateful, and about the user's own
money in flight**:

- **Five phases**, each with its own title, subtitle, icon and tint.
- **State lives in two fields.** `ContentState` is deliberately just `boltzStatus: String` and
  `startedAt: Double`. The phase and every label are *derived* from the raw Boltz status via
  `SwapPhase.from(boltzStatus:)`, so the backend never replicates the mapping. Keep this
  property on Android — it is the reason a push payload is two fields wide.
- **`startedAt` is Unix epoch seconds as a `Double`**, not a `Date`, with a comment explaining
  why (ActivityKit decodes dates in content-state as seconds-since-2001). On Android the
  equivalent footgun does not exist, but the wire format should stay epoch-seconds anyway so one
  backend payload serves both platforms.

Static attributes, fixed for the life of the activity: `swapID` (the Boltz swap id, and the
activity key), `directionIsOnchainToLightning`, `targetSats` (what the user receives),
`expectedOnchainSats`.

> Only `targetSats` is actually rendered ("*N* sats → instant"). `directionIsOnchainToLightning`
> and `expectedOnchainSats` are carried but never displayed on any of the three iOS
> presentations. Do not go looking for where they show up; port them only if Android's copy
> decides to use them.

---

## 3. The Android construct

### 3.1 The one builder, verified

This is the whole surface. Every line below is load-bearing, and §7 reports the test that proves it:

```kotlin
val style = NotificationCompat.ProgressStyle()
    .setProgressSegments(listOf(/* see §4.3 */))
    .setProgress(phase.progress)

NotificationCompat.Builder(context, CHANNEL_SWAP_PROGRESS)
    .setSmallIcon(R.drawable.ic_stat_swap)
    .setContentTitle(phase.title)            // §4.1
    .setContentText(phase.subtitle)          // §4.1
    .setShortCriticalText(phase.chipText)    // the status-bar chip — the island's compact text
    .setStyle(style)
    .setOngoing(true)                        // REQUIRED for promotion
    .setColorized(true)                      // REQUIRED for promotion — see §3.2
    .setRequestPromotedOngoing(true)
    .setWhen(startedAtMillis)                // the timer origin
    .setUsesChronometer(true)                // reproduces Text(startDate, style: .timer)
    .setOnlyAlertOnce(true)                  // except on the terminal post — §5.4
    .setContentIntent(deepLink(phase))       // §5.6
    .build()
```

Posted with `NotificationManager.notify(idFor(swapID), notification)`. A re-post with the same id
*replaces* the notification, which is how updates work — and it is also the dedup mechanism, so
iOS's `isLive(boltzID:)` guard has no Android counterpart. Derive the id stably from the Boltz
swap id (e.g. `swapID.hashCode()`) so two concurrent swaps get two notifications and the same
swap never stacks.

### 3.2 `setRequestPromotedOngoing(true)` is not sufficient — and this is the trap

Requesting promotion does not grant it. Android 16's `Notification.hasPromotableCharacteristics()`
computes eligibility locally, and a notification that fails it is posted as an *ordinary*
notification — silently, with no error. Read off the API 36 framework bytecode, it requires:

- `isOngoingEvent()` — so `setOngoing(true)`, **and**
- `!isGroupSummary()`, **and**
- `!containsCustomViews()` — so no `setCustomContentView`, **and**
- `hasTitle()` — so `setContentTitle` is mandatory, **and then either**
  - `isOngoingCallStyle()`, **or**
  - `isColorizedRequested()` **and** `hasPromotableStyle()` (style is null, `BigTextStyle`,
    `CallStyle` or `ProgressStyle`).

So for this surface — `ProgressStyle`, not a call — **`setColorized(true)` is mandatory**. Omitting
it is the difference between a Live Update and a plain progress notification, and nothing in the
API tells you. The probe in §7 got `promotable=false` on the first attempt for exactly this reason.

### 3.3 Below API 36 it degrades, it does not break

`minSdk` is 26, so API 26–35 has no Live Updates. The **same builder** is safe there — no version
branching, no `Build.VERSION` checks. Verified at API 26: the notification posts, the title and
text render, the progress bar renders as an ordinary determinate bar, and the `ProgressStyle`
data is carried in the extras (`android.progressSegments`, `android.progress`, …) as inert
compat extras. What is lost is the promotion: no status-bar chip, and lock-screen presence is
whatever an ongoing notification normally gets.

That is an acceptable, self-documenting degradation. Do not build a second code path for it.

### 3.4 The progress bar should not be time-based

iOS fills the bar over a **15-minute wall-clock window** (`estimatedConfirmationWindow`) using
`ProgressView(timerInterval:)`. `ProgressStyle` has no time-interval mode, so this cannot be
ported literally.

Do not try to emulate it. The iOS source already concedes the bar is decorative — *"it's
decorative (the real signal is the phase), so we keep it long enough that it rarely tops out
before confirmation"*. A time-based bar that is explicitly not a real signal is a worse fit for
Android than what `ProgressStyle` is actually designed for: **segments representing the stages of
a journey**. Use a phase-derived bar (§4.3). It is more honest and it is less code.

The *elapsed timer* is a different thing and does port exactly: `setWhen(startedAt)` +
`setUsesChronometer(true)` is the native equivalent of `Text(startDate, style: .timer)`.

---

## 4. States — the complete enumeration

### 4.1 The five phases

`SwapPhase` and its Boltz mapping port **verbatim** — it is pure logic, it is the contract with
the backend, and it is the one part that must not be redesigned:

| Phase | Boltz statuses that map to it |
| --- | --- |
| `preparing` | `swap.created`, `invoice.set`, **and any unrecognised status** (the `default:` arm) |
| `waitingConfirmation` | `transaction.mempool` |
| `completing` | `transaction.confirmed`, `invoice.pending` |
| `complete` | `invoice.paid`, `transaction.claim.pending`, `transaction.claimed`, `invoice.settled` |
| `failed` | `invoice.failedToPay`, `swap.expired`, `transaction.lockupFailed`, `invoice.expired`, `transaction.failed`, `transaction.refunded` |

`isTerminal` is `complete || failed`.

> The `default:` arm mapping to `preparing` is deliberate and load-bearing: a Boltz status this
> app has never seen must not blank the surface. Port the `else -> PREPARING`, do not throw.

### 4.2 Presentation per phase

**Decided in BIT-115** — the copy, icons and tint below are the Android values to build, not a
transliteration. §6 is the reasoning and the evidence; this is the table to implement from.

What iOS renders:

| Phase | iOS title | iOS subtitle | SF Symbol | iOS tint |
| --- | --- | --- | --- | --- |
| `preparing` | Getting ready | Setting up your transfer | `hourglass` | `bittrYellow` |
| `waitingConfirmation` | Confirming your transfer | This usually takes 10–30 minutes | `clock.fill` | `bittrYellow` |
| `completing` | Almost there | Adding it to your instant balance | `bolt.horizontal.fill` | `bittrYellow` |
| `complete` | Swap complete | Your bitcoin is ready for instant payments ⚡️ | `checkmark.circle.fill` | `.green` (system) |
| `failed` | Swap didn't go through | Tap to sort it out | `xmark.circle.fill` | `.red` (system) |

What Android renders. Copy is keyed, not literal — the keys are in `shared/strings/en.json`
under `swapliveupdate.*`, and the rendered text is repeated here only so the table is readable:

| Phase | Title (`…title`) | Subtitle (`…subtitle`) | Small icon | Tint |
| --- | --- | --- | --- | --- |
| `preparing` | Getting ready | Setting up your transfer | `ic_stat_swap_preparing` | `Yellow` `#FFC502` |
| `waitingConfirmation` | Confirming your transfer | Usually 10–30 minutes | `ic_stat_swap_confirming` | `Yellow` `#FFC502` |
| `completing` | Almost there | Adding to instant balance | `ic_stat_swap_completing` | `Yellow` `#FFC502` |
| `complete` | Swap complete | Ready for instant payments ⚡️ | `ic_stat_swap_complete` | `Yellow` `#FFC502` |
| `failed` | Swap didn't go through | Tap to sort it out | `ic_stat_swap_failed` | `Yellow` `#FFC502` |

Three of the five subtitles are iOS's, unchanged, because they already fit. Two shrank: the
collapsed line truncates at roughly 30 characters and iOS's were 32 and 33. `complete`'s dropped
from 45 — it was never going to survive, and "Your bitcoin is" is the part the header already
implies. **One tint, on all five phases** — see §6.5, which is also why the `Green2` / `Red2` that
used to be in this column are gone. They moved to the progress bar (§4.3), which is where colour
can do its job without the card changing colour underneath the user mid-swap.

Three notes on the colours, because a straight transliteration gets all three wrong:

1. **`bittrYellow` in this file is a third yellow.** `SwapLiveActivity.swift` hardcodes
   `Color(red: 0.98, green: 0.79, blue: 0.14)` ≈ `#FAC924`. That matches neither the iOS design
   token (`#F6C744`) nor the Android one (`#FFC502`). It is a one-off local constant in a widget
   extension. **Use the Android `Yellow` token**, not `#FAC924`.
2. **`.green` and `.red` are SwiftUI system colours**, not brand tokens. Use `Green2` / `Red2`.
3. `Red2` is `#FF3B30`, which happens to be exactly iOS's system red. That one is a coincidence,
   not a reason to trust the other two.

Icons: these are SF Symbols and have no Android equivalents by name. The five drawables exist —
`android/app/src/main/res/drawable/ic_stat_swap_*.xml`, Material Symbols at **FILL 1**. §6.3 is
why filled rather than outlined, and what constrains anyone re-syncing them from upstream.

### 4.3 The progress bar per phase

iOS: `preparing` → a static 0.12 bar; `waitingConfirmation`/`completing` → the time-based fill;
`complete` → 1.0 green; `failed` → 1.0 red.

Android, as three segments over the three non-terminal phases:

| Phase | Segments | Segment colour | `setProgress` | Chip (`setShortCriticalText`) | Chronometer |
| --- | --- | --- | --- | --- | --- |
| `preparing` | 25 / 50 / 25 | `Ink` `#0D0D0D` | 0 | unset — §6.2 | no |
| `waitingConfirmation` | 25 / 50 / 25 | `Ink` `#0D0D0D` | 25 | unset — §6.2 | **yes** |
| `completing` | 25 / 50 / 25 | `Ink` `#0D0D0D` | 75 | unset — §6.2 | **yes** |
| `complete` | one segment, 100 | `Green2` `#319A3D` | 100 | unset | no |
| `failed` | one segment, 100 | `Red2` `#FF3B30` | 100 | unset | no |

The chronometer follows iOS's `showsTimer`, which is true for exactly `waitingConfirmation` and
`completing`. On the other three phases iOS shows the phase icon where the timer would be; on
Android the icon is the notification's small icon and needs no switch.

**The segment colours are not what renders, and that is deliberate.** `ProgressStyle` runs every
segment colour through `sanitizeProgressColor(segment, background, default)`, which rewrites
anything below 3 : 1 against the background. Measured against our `#FFC502` tint:

| Declared | Renders as | Ratio |
| --- | --- | --- |
| `Ink` `#0D0D0D` | `#0D0D0D` — unmodified | 12.25 : 1 |
| `Green2` `#319A3D` | `#11852A` | 3.00 : 1 |
| `Red2` `#FF3B30` | `#E3171D` | 3.00 : 1 |
| `Yellow` `#FFC502` | `#966B00` | 3.01 : 1 |

Two consequences. First, **the in-flight segments are ink because ink is the only one of the four
that survives** — a bar declared in the brand colour over the brand background renders as a dark
olive that appears in no token, silently. The probe test written under BIT-75 declares its three
segments `YELLOW`; that is this defect, and it is why the numbers above are now pinned in
`SwapLiveUpdatePresentationTest`. Second, the two terminal colours *are* worth declaring as the
tokens even though neither renders as itself: the rewrite is deterministic and hue-preserving, so
what lands is recognisably the brand's green and red. Do not "correct" the tokens to the rendered
values — that would double-apply the rewrite on the next platform release that adjusts its floor.

### 4.4 Presentations

iOS has **three** (Lock Screen / expanded island / compact island) plus a `minimal` variant for
when several activities compete. Android has **two**: the collapsed+expanded notification, and
the status-bar chip. Mapping:

| iOS presentation | Android |
| --- | --- |
| Lock Screen banner | the notification, on the lock screen |
| Dynamic Island — expanded (leading/trailing/bottom) | the expanded notification (one region — content collapses, §6) |
| Dynamic Island — compact leading/trailing | the status-bar chip (`setShortCriticalText`) |
| Dynamic Island — `minimal` | **no counterpart.** Concurrent swaps become separate notifications; group them if that ever happens in practice. |

---

## 5. Lifecycle

iOS's controller is `SwapLiveActivityController`. Its five entry points, and what each becomes:

### 5.1 Start

iOS: `SwapLiveActivityController.start(swap:)` from `SwapViewController.swift:285` when the swap
begins. Guarded by `ActivityAuthorizationInfo().areActivitiesEnabled`; dedups on `swapID`; opens
with `boltzStatus: "swap.created"` and `startedAt: now`; requests `pushType: .token`.

Android: post the notification. The `areActivitiesEnabled` guard becomes the **`POST_NOTIFICATIONS`
permission check** — same shape, same early return, same "log and carry on, never fail the swap".
Dedup is free (§3.1). There is no push-token request (§5.3).

### 5.2 Update

iOS: `update(boltzID:boltzStatus:)` / `applyUpdate` from three places — the foreground WebSocket
(`SwapStatusViewController.swift:179`) and pushes (`NotificationManager.swift:165`, `:177`, `:200`).
Each rebuilds the content-state and **preserves `startedAt`** so the timer origin does not reset.

Android: re-`notify()` with the same id. **Preserving the timer origin is the one easy thing to
get wrong** — `setWhen` must carry the original `startedAt`, not `now`, or the elapsed timer jumps
back to zero on every update. Persist `startedAt` with the swap; do not read it back off the posted
notification.

### 5.3 The push model is the one real architectural difference

This is the part that is genuinely not a port, and it is worth being precise about because it is
*simpler* on Android, not harder.

**iOS:** each activity gets its own APNs push token, streamed to the backend via
`observePushToken` → `SwapManager.registerLiveActivityToken(swapID:token:startedAt:)`. The backend
sends `apns-push-type: liveactivity` and **the system updates the rendered activity without waking
the app**. The app also has to send `startedAt` along with the token, because every liveactivity
push must carry the full content-state and only the app knows the start time.

**Android:** there is no per-surface push channel and no way to mutate a posted notification from
outside the process. The only mechanism is: backend sends an FCM **data** message → the app's
`FirebaseMessagingService` wakes → app code re-posts the notification.

Consequences:

- **`registerLiveActivityToken` has no Android analogue.** The device already registers one FCM
  token (Phase 4 item 9); the swap id travels in the data payload. One fewer endpoint, one fewer
  token lifecycle, and no `startedAt` round-trip — the app owns `startedAt` locally, so the
  payload only needs `swapID` + `boltzStatus`.
- **`resumeTokenObservation()` has no Android analogue** either. It exists on iOS only to re-attach
  per-activity token observers after a relaunch.
- **Delivery is best-effort.** Send the data message at high priority; in Doze or app-standby it
  may still be deferred. The failure mode is benign and better than iOS's: a posted notification
  does not expire, so a missed intermediate update leaves the bar at the previous phase rather than
  making the surface vanish. Reconcile on next app resume from persisted swap state.
- Use **`data` messages, not `notification` messages** — consistent with the plan's existing FCM
  notes. A `notification` message is rendered by the system when the app is backgrounded and the
  app never gets to build the Live Update.

### 5.4 Terminal

iOS: on a terminal phase, `applyUpdate` fires an `AlertConfiguration` (the island "pop" plus a
haptic), then sleeps **8 seconds** and calls `end(dismissalPolicy: .after(.now + 60))`. The
`finishingSwapIDs` set makes sure this happens once per swap, because several distinct Boltz
statuses collapse to `complete` and the socket and a push can both deliver one.

Android:

- **Drop the 8-second sleep.** It exists because an ended Live Activity leaves the Dynamic Island
  almost immediately, so the final state needs to be held artificially. An Android notification
  persists until cancelled. Post the terminal state with `setOngoing(false)` +
  `setAutoCancel(true)` and leave it; there is nothing to linger for. Do not port
  `Task.sleep(nanoseconds: 8_000_000_000)`.
- **Keep the once-per-swap guard.** The duplicate-terminal-status problem is identical on Android
  and the reason is the Boltz mapping, not ActivityKit. `finishingSwapIDs` ports as-is.
- The `AlertConfiguration` becomes: drop `setOnlyAlertOnce` on the terminal post so it makes a
  sound, on a channel at `IMPORTANCE_DEFAULT`. Alert copy on iOS is "Swap complete / Your bitcoin
  is ready for instant payments ⚡️" and "Swap didn't go through / Tap to sort it out." — the same
  strings as the phase title/subtitle, so one source per phase covers both.

### 5.5 Stale sweep and cancel

iOS: `endStaleActivities()` on launch and foreground (`AppDelegate.swift:41`, `SceneDelegate.swift:78`)
cancels anything terminal or older than **3 hours**, because a swap can complete via a push while
the app is closed and strand the activity. `endAll()` force-ends on manual cancel.

Android: the same sweep, over persisted swap rows rather than over live `Activity` handles — on
Android the app cannot enumerate its posted notifications below API 23-era limits reliably from
cold, so the swap table is the source of truth. Cancel by the same derived id. Keep the 3-hour cap.

### 5.6 Taps

iOS routes taps by phase via `widgetURL`: `bittr://resumeswap` on `completing` (the wallet must
come online to receive the incoming payment — the same destination as the HTLC-resume
notification), `bittr://swapstatus` otherwise. That asymmetry is deliberate; port it.

Android: `setContentIntent(PendingIntent)`. **Prerequisite:** the Android manifest currently
declares no `bittr://` scheme at all, so the deep-link host has to exist before this surface can
route anywhere.

---

## 6. The design decisions — **decided, BIT-115**

§3–§5 are derivable from source. These five were not, and BIT-75 was right that they needed a
designer rather than a transliteration. This section used to enumerate them as open; it now
records what was decided and what the decision rests on.

The headline is that **four of the five did not need a device**, which is not what §7.3 assumed.
Three framework entry points are public and decide the rendered appearance off-device —
`Notification.Colors#resolvePalette`, `ProgressStyle#sanitizeProgressColor`, and the drawables
themselves under Robolectric's native graphics mode. Every number below is measured, and the
measurements are pinned in `android/app/src/test/kotlin/com/bittr/android/SwapLiveUpdatePresentationTest.kt`
so they fail rather than rot.

### 6.1 The five titles and subtitles — **iOS copy survives, two subtitles shrink**

The decided strings are in §4.2. The collapsed line is one row at body size and truncates at
roughly 30 characters, so the budget applied was **≤ 24 for a title** and **≤ 30 for a subtitle**,
the tighter title budget because a title renders larger and is the first thing to be squeezed at
a large font scale.

Against that budget iOS's copy mostly already fits, and the honest outcome is that most of it is
kept verbatim rather than rewritten for the sake of it. The three changes:

| Phase | iOS | Android | Why |
| --- | --- | --- | --- |
| `waitingConfirmation` | This usually takes 10–30 minutes (32) | Usually 10–30 minutes (21) | Same information, inside budget. "This usually takes" is throat-clearing a notification cannot afford. |
| `completing` | Adding it to your instant balance (33) | Adding to instant balance (25) | Same. |
| `complete` | Your bitcoin is ready for instant payments ⚡️ (45) | Ready for instant payments ⚡️ (29) | "Your bitcoin is" is what the notification is already about. The ⚡️ stays — it is the instant-balance mark elsewhere in the app and it is one glyph. |

Two things deliberately *not* done:

- **The titles are not prefixed with "Swap".** The notification header already renders the app
  name, and §6.4 puts the amount beside it, so "bittr · 21 000 sats · Getting ready" is the line
  the user actually reads. A title that repeats the header wastes the shortest row on the surface.
- **`complete`'s title is not pointed at `swapstatusswapcomplete`.** It is the same sentence, and
  `shared/strings/README.md` is right that "Swap complete" living in three places is a problem —
  but this is a fourth *legitimate* home, not a fourth copy to collapse. The status screen's key
  labels one Boltz status; this key labels a phase that collapses **four** of them
  (`invoice.paid`, `transaction.claim.pending`, `transaction.claimed`, `invoice.settled`). They
  agree today by good luck of the copywriting, not by contract, and coupling them would make a
  reword of a per-status screen label silently change a notification. Whoever does that
  consolidation should leave `swapliveupdate.complete.title` alone.

### 6.2 The chip text — **unset, on all five phases**

The spec proposed elapsed time (`10m`). **That is the one option that can be wrong**, and it
should not be built.

`setShortCriticalText(String)` takes a static string. There is no chronometer variant of it — the
elapsed count in the notification body ticks because `setWhen` + `setUsesChronometer` hands the
system an origin and lets it render the clock, and the chip has no equivalent. So a chip reading
`10m` is a snapshot taken at post time, and this surface re-posts only when the Boltz status
changes. Between `transaction.mempool` and `transaction.confirmed` that is a **10–30 minute gap
with no re-post**, so the chip would freeze at `0m` or `1m` for the whole wait it exists to
describe. Re-posting on a timer to keep it honest is not available either: that is a wakeup a
minute for half an hour, and in Doze — the lock-screen case, which is the entire use case — it
would not fire anyway.

Leaving it unset strictly dominates. The chip still appears; it renders the app icon, and
`Notification` exposes `hasAppProvidedWhen()` and `showsChronometer()` as public accessors
alongside `getShortCriticalText()`, which is the API shape of a renderer that falls back to a
live time when no override is given. **That fallback is the one claim here that is not measured**
— SystemUI is not something Robolectric runs — so it is written as the reason the downside is
bounded, not as a fact.

If the device check (§7.3) shows a bare chip with no timer, the replacement is **`1/3`, `2/3`,
`3/3`**: it mirrors the segmented bar, it fits, and it changes exactly when the notification
re-posts, so it is the only candidate that is never stale. Do not reach back for elapsed time.

### 6.3 The five icons — **Material Symbols, FILL 1, authored**

They exist: `ic_stat_swap_{preparing,confirming,completing,complete,failed}.xml`, mapped in §4.2.
`hourglass_top` / `schedule` / `bolt` / `check_circle` / `cancel`.

Three rules govern them, and each one is a way to get this wrong quietly:

1. **Filled, not outlined.** `setSmallIcon` renders at status-bar size, where an outlined glyph's
   2 dp strokes break up. This is why iOS's outlined `hourglass` does *not* port as
   `hourglass_empty`, which §4.2 used to suggest. `hourglass_top` also happens to say "just
   started" — a full upper chamber — which `hourglass_empty` does not say at all.
2. **Alpha silhouettes.** On a colorized notification the framework paints the small icon in the
   palette's primary text colour (measured: `#1A1B20`), so any colour in the drawable is
   discarded. All detail is a transparent cut-out. Three of the five — the clock hands, the check,
   the cross — are *only* cut-outs, so a wrong fill rule turns them into three identical discs.
3. **The y-up grid.** Material Symbols are authored on a 960×960 grid with a `0 -960 960 960`
   viewBox, which `VectorDrawable` has no equivalent for. Each file carries a
   `<group android:translateY="960">` instead, and the path data underneath is byte-identical to
   upstream so a re-sync does not need coordinates re-derived. Delete that group — the obvious
   tidy-up — and the glyph renders entirely outside its own bounds: no crash, no warning, a blank
   space in the status bar.

Rules 2 and 3 are both silent failures, so both are asserted rather than documented: the guard
rasterises all five and checks coverage, centring, and that the three disc glyphs still have
enclosed transparent pixels.

### 6.4 What the expanded notification drops — **"bittr swap"; the amount moves to `setSubText`**

Android's expanded notification is one region against the island's three, so the island's five
elements have to fit into: header (app name, sub-text, time), title, text, bar.

| iOS element | Android |
| --- | --- |
| "bittr swap" label | **dropped** — the header already renders the app name |
| the elapsed timer | header, via `setWhen` + `setUsesChronometer` (§4.3) |
| the phase title | `setContentTitle` |
| the bar | `ProgressStyle` |
| "*N* sats → instant" | header, via **`setSubText`**, as the bare amount — `21 000 sats` |

`setSubText` rather than folding the amount into the subtitle, because sub-text is Android's
designated "which instance of this notification" slot and the amount is exactly that: §4.4 says
concurrent swaps become separate notifications with no counterpart to the island's `minimal`
variant, so the amount is the only thing distinguishing two of these in a shade. Folding it into
`setContentText` would instead cost the phase subtitle its line, which is the one row carrying
what is happening.

The "→ instant" phrasing is dropped with the label. It was doing work on iOS because the island
had no other room to say where the money is going; on Android `completing` and `complete` both
say "instant" in the subtitle, at the two moments it matters.

One accepted cost: sub-text and the chronometer share the header row, and sub-text truncates
first. That is the right thing to lose — of the three header elements the amount is the one the
user already knows.

### 6.5 The tint — **`Yellow` `#FFC502`, one tint, all five phases**

`setColorized(true)` is mandatory (§3.2), so the only questions were which colour and whether it
reads. Both are settled, and the "wants a real device" caveat this section used to carry does not
survive contact with `Notification.Colors#resolvePalette`, which is public and computes the exact
rendered palette for a requested colour:

| | Measured |
| --- | --- |
| Background | `#FFC502` — **the platform uses the requested colour verbatim**, it does not lighten or darken a colorized background |
| Primary and secondary text | `#1A1B20`, chosen by the platform |
| Contrast | **10.84 : 1** — AAA, against a 4.5 : 1 requirement |
| Light vs dark scheme | **byte-identical** |

That last row is the interesting one. BIT-94 and BIT-95 both turned on a token checked in one
scheme and broken in the other, and this issue inherited the rule to check both. Here the answer
is that **a colorized notification has only one scheme**: `resolvePalette` takes a `nightMode`
flag and, for the colorized path, ignores it. So there is no dark variant of this tint to design,
and no second set of numbers to maintain.

The wallpaper half of the old caveat dissolves the same way: a colorized background is **opaque**,
so a lock-screen render does not composite the user's wallpaper and legibility is not a function
of it. What the wallpaper does affect is whether the card is *noticed*, and a saturated yellow is
the best answer available to that.

**Why one tint and not iOS's three.** iOS tints an accent inside the activity; `setColor` on a
colorized notification paints the **entire card**. Transliterating the per-phase tints would
therefore give a card that is yellow, then green, then red during one swap — which reads as three
different notifications rather than one thing still happening, and that continuity is the whole
job of this surface. So the card stays the brand colour throughout and the phase is carried by the
icon, the copy, and the bar. Colour does work in exactly one place: the terminal bar (§4.3), where
the swap is over and there is no continuity left to protect.

**This is also self-documenting, by accident of the framework.** `Notification#isColorized()`
returns true only when colorized was requested **and** the notification is a foreground service,
or a media session, or *promoted ongoing*. Promotion is the system's call (§3.2). So the tint and
the promotion are the same event: below API 36, or whenever promotion is declined, the card is not
yellow — it is an ordinary notification. There is no state in which a yellow card is not a Live
Update, and no need to check for one.

### 6.6 Strings

**Twelve new keys in `shared/strings/en.json`**, namespaced `swapliveupdate.*`. They have no iOS
`*Language.swift` counterparts — the iOS copy is hardcoded in SwiftUI — so they are new keys, not
a migration, and `check_flow_copy.py` is green with them added.

The twelve are **not** the 5 titles / 5 subtitles / 2 alert bodies this section originally
specified. The alert bodies do not exist as separate strings, and should not:

- §5.4 makes the terminal post *itself* the alert — the same notification, same title, same text,
  re-posted without `setOnlyAlertOnce` on an `IMPORTANCE_DEFAULT` channel. There is no second
  surface with its own copy, so two alert-body keys would be two more copies of a sentence that
  already renders from `swapliveupdate.{complete,failed}.subtitle`. `shared/strings/README.md`
  spends a section on what duplicate copies of one sentence cost; minting two on purpose, on the
  same page that records the cost, is not defensible.
- The two keys that *are* needed and that nobody had written are the **notification channel's name
  and description** — `swapliveupdate.channel.{name,description}`. They are user-visible, in
  Settings › Notifications, and `NotificationChannel` cannot be constructed without the name.

So: 5 titles, 5 subtitles, 2 channel strings.

One note for the generator, which does not exist yet: `swapliveupdate.failed.title` contains an
apostrophe, and an unescaped `'` in `strings.xml` is a build error rather than a rendering bug.
`Swap complete` is now the fourth place that sentence lives in the repo — deliberately, see §6.1.

---

## 7. Verification — most of this is a unit test

This is where the surface differs most from the price widget, and from the assumption that an
un-Maestro-able surface must be "checked by hand".

### 7.1 Provable on the JVM, no emulator, no device

Robolectric (pinned at 4.16.1) runs at API 36 **and** at API 26, and `ShadowNotificationManager`
returns the actually-posted notification. That makes the following assertable in seconds:
title and text per phase, chip text, progress value and segments, the ongoing/colorized flags,
**promotion eligibility**, the chronometer flag and timer origin, the channel, the content-intent
URI, and the degradation at `minSdk`.

A probe doing exactly this was written and run offline against `origin/android-parity`
(`:app:testReleaseUnitTest`, 3 tests, 0 failures) and reports:

```
api36 template=android.app.Notification$ProgressStyle     <- the real platform style applied
api36 shortCriticalText=10m                               <- chip text survives the post
api36 title=Confirming your transfer
api36 text=This usually takes 10-30 minutes
api36 progress=25
api36 chronometer=true   when=1000000                     <- timer origin preserved
api36 ongoing=2                                           <- FLAG_ONGOING_EVENT set

promote colorized=true                                    <- with setColorized(true)
promote notOngoing=false                                  <- guard is real
promote inboxStyle=false                                  <- guard is real

api26 template=null                                       <- degrades, does not throw
api26 title=Confirming your transfer
api26 progress=25  progressMax=100
api26 keys=[android.progressPoints, android.progress, android.progressMax,
            android.progressSegments, android.styledByProgress, android.progressIndeterminate]
```

So the phase table in §4 is machine-checkable against the real posted notification. Write that
test alongside the implementation; it is the guard that the copy, the tints and the promotion
requirements in §3.2 stay correct.

**One caveat, stated explicitly:** `FLAG_PROMOTED_ONGOING` is set by the system
(`NotificationManagerService`), which Robolectric does not run — the probe reads `flags=0` for it
and that is expected, not a defect. `hasPromotableCharacteristics()` is computed on the
notification itself and *is* meaningful off-device. So the JVM proves **eligibility**, not that
the system actually promoted it. That last step needs a device.

### 7.2 Possibly provable on the emulator — worth one experiment

Unlike iOS, Maestro on Android reads the UiAutomator hierarchy, which includes `com.android.systemui`.
So swiping the shade open and asserting on the notification's title may well work, where the iOS
suite can only work *around* the system banner. Compare the retry loops in
`shared/flows/features/notification_information.yaml`: the iOS banner is invisible to
`assertVisible` and cannot be targeted, so the flow taps blindly through it and loops until the
card underneath is gone. That is the best iOS allows; it is not evidence about Android.

**This is untested and should not be written down as fact.** It is one short flow to find out, on
the existing emulator CI lane, once there is something to post. If it works, this surface is
partially in the Maestro gate after all and §1's exclusion can be revisited for Android only.

### 7.3 Needs a human eye on a real device

**This shrank under BIT-115, and most of what it used to list is now measured.** It said the
colorized tint over a wallpaper, in light and dark, needed an eye. It does not: the palette is
computed by `Notification.Colors#resolvePalette`, which is public, so the rendered background and
text colours and their 10.84 : 1 ratio are asserted on the JVM; the background is opaque, so the
wallpaper is not composited; and the palette is byte-identical in both schemes, so there is no
second case. §6.5 has the numbers.

What genuinely still needs a device, and it is now **one question, not four**:

- **What the status-bar chip renders when `setShortCriticalText` is unset.** §6.2 leaves it unset
  on all five phases because a static string cannot tick, and expects the system to fall back to a
  live elapsed time. SystemUI is not something Robolectric runs, so that is the one unmeasured
  claim on this surface. If the chip comes up bare, §6.2 names the replacement (`1/3` … `3/3`) and
  it is a one-line change.
- Worth a glance while the device is in hand, but not blocking anything: the same card on
  always-on display, where the panel may render the tint at reduced luminance.

Same status as before — a few minutes, not a blocker, and now with a specific thing to look at
rather than an impression to form.

---

## 8. Dependencies

In order, all of them already on the roadmap:

1. **The wallet engine (BIT-6)** — no swap, nothing to report on.
2. **Phase 4 item 7, swaps via `boltz-android`** — the Boltz status stream this surface renders.
   The `SwapPhase` mapping in §4.1 is against Boltz submarine statuses and is independent of the
   SDK, so it can be written and tested before the SDK is wired.
3. **Phase 4 item 9, notifications + FCM** — no Firebase dependency, no `google-services.json` and
   no `FirebaseMessagingService` on `android-parity` yet, so there is currently nothing to deliver
   remote updates. `POST_NOTIFICATIONS` *is* already declared, and the manifest comment on it
   records why the two halves are split: asking for the permission works today, but **delivery
   needs Firebase provisioned (BIT-39), which only the founder can do**. That is a dependency of
   item 9, not of this surface — and note the degradation is mild: without any remote update the
   Live Update still starts, and still advances whenever the app is foregrounded and the socket
   reports a new status. It just stops being *live* while backgrounded.
4. **A `bittr://` deep-link host** — not declared in the Android manifest yet (§5.6).
5. **Backend: FCM data messages for swap status.** The plan already carries "handle both APNs and
   FCM tokens". Worth noting the Android side needs *less* than iOS: no per-activity token
   registration endpoint (§5.3).

Nothing here is a decision; it is an ordering.
