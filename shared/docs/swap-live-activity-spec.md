# Swap Live Activity spec — `SwapLiveActivity` (iOS) → Live Update (Android)

**Status:** decided · **Decided by:** Head of App (Android), BIT-75 · **Source of truth:**
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

iOS values on the left; the Android port on the right. **The copy column is a transliteration, not
a decision** — see §6.

| Phase | iOS title | iOS subtitle | SF Symbol | iOS tint | Android icon | Android tint token |
| --- | --- | --- | --- | --- | --- | --- |
| `preparing` | Getting ready | Setting up your transfer | `hourglass` | `bittrYellow` | hourglass | `Yellow` `#FFC502` |
| `waitingConfirmation` | Confirming your transfer | This usually takes 10–30 minutes | `clock.fill` | `bittrYellow` | filled clock | `Yellow` `#FFC502` |
| `completing` | Almost there | Adding it to your instant balance | `bolt.horizontal.fill` | `bittrYellow` | horizontal bolt | `Yellow` `#FFC502` |
| `complete` | Swap complete | Your bitcoin is ready for instant payments ⚡️ | `checkmark.circle.fill` | `.green` (system) | filled check circle | `Green2` `#319A3D` |
| `failed` | Swap didn't go through | Tap to sort it out | `xmark.circle.fill` | `.red` (system) | filled x circle | `Red2` `#FF3B30` |

Three notes on the colours, because a straight transliteration gets all three wrong:

1. **`bittrYellow` in this file is a third yellow.** `SwapLiveActivity.swift` hardcodes
   `Color(red: 0.98, green: 0.79, blue: 0.14)` ≈ `#FAC924`. That matches neither the iOS design
   token (`#F6C744`) nor the Android one (`#FFC502`). It is a one-off local constant in a widget
   extension. **Use the Android `Yellow` token**, not `#FAC924`.
2. **`.green` and `.red` are SwiftUI system colours**, not brand tokens. Use `Green2` / `Red2`.
3. `Red2` is `#FF3B30`, which happens to be exactly iOS's system red. That one is a coincidence,
   not a reason to trust the other two.

Icons: these are SF Symbols and have no Android equivalents by name. They need real drawables.
Material Symbols has close matches for all five (`hourglass_empty`, `schedule`, `bolt`,
`check_circle`, `cancel`) but which glyph is a design call, not a porting call — §6.

### 4.3 The progress bar per phase

iOS: `preparing` → a static 0.12 bar; `waitingConfirmation`/`completing` → the time-based fill;
`complete` → 1.0 green; `failed` → 1.0 red.

Android, as three segments over the three non-terminal phases:

| Phase | Segments | `setProgress` | Chip (`setShortCriticalText`) | Chronometer |
| --- | --- | --- | --- | --- |
| `preparing` | 25 / 50 / 25 | 0 | — | no |
| `waitingConfirmation` | 25 / 50 / 25 | 25 | elapsed, e.g. `10m` | **yes** |
| `completing` | 25 / 50 / 25 | 75 | elapsed | **yes** |
| `complete` | one segment, 100, `Green2` | 100 | — | no |
| `failed` | one segment, 100, `Red2` | 100 | — | no |

The chronometer and chip follow iOS's `showsTimer`, which is true for exactly
`waitingConfirmation` and `completing`. On the other three phases iOS shows the phase icon where
the timer would be; on Android the icon is the notification's small icon and needs no switch.

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

## 6. What a designer owns, not a porter

Everything above is derivable from source. These are not, and the BIT-75 ticket was right that
they need a designer's pass rather than a transliteration:

1. **The five titles and subtitles.** The iOS strings are written for a wide lock-screen banner
   and an island. An Android notification's collapsed line is much shorter and truncates, and the
   status-bar chip is a handful of characters. "This usually takes 10–30 minutes" (32 chars) is
   fine expanded and will truncate collapsed. Decide per phase what the collapsed line says.
2. **The chip text.** §4.3 proposes the elapsed time. It could as well be a phase abbreviation.
   This is a genuinely new piece of copy with no iOS counterpart — the island shows a live timer
   because it can; a 6-character chip may want something else.
3. **The five icons.** Real drawables, from Material Symbols or drawn. §4.2 lists the closest
   matches; picking is a design call.
4. **What the expanded notification drops.** The expanded island has three regions and shows the
   "bittr swap" label, the timer, the phase title, the bar *and* "*N* sats → instant". Android's
   expanded notification is one region. Something goes. The app name is already in the notification
   header, which makes "bittr swap" the obvious cut, but that is a call.
5. **`setColorized(true)` is mandatory (§3.2) and it tints the notification.** Which brand colour
   it tints *to*, and whether that reads acceptably on the lock screen over a user's wallpaper and
   in both themes, is a design judgement that wants a real device.

These five are **copy and visual**, and they are the whole reason this can't just be implemented
from the iOS source. None of them blocks the mechanism in §3–§5.

**Strings:** twelve new entries (5 titles, 5 subtitles, 2 alert bodies) in `shared/strings/en.json`.
They have no iOS `*Language.swift` counterparts — the iOS copy is hardcoded in SwiftUI — so these
are new keys, not a migration.

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

The lock-screen and status-bar-chip visual treatment: how the colorized tint reads over a
wallpaper, on always-on display, in light and dark. Same class of check as `widget-spec.md` §6,
and same status — a few minutes, not a blocker.

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
