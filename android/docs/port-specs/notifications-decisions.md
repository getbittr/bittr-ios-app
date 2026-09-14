# In-app push handling — port decisions

Branch `port/notifications`, ported from `ios/bittr/Notifications/*`, `Core/AlertManager.swift` (`showLoading`),
`Core/ShowPin.swift` (`lowerPinView`) and `Home/LoadWalletData.swift` (`finalizeSync`), 2026-09-14/15.
Spec: `notifications-removal-settings-pin.md` §A.

## Decided

1. **One coordinator, fed directly.** `BittrPushDelivery.onPush` hands every decoded push to the singleton
   `PushCoordinator`. It no longer relies on collectors of the `replay = 1` `envelopes` flow, because a late
   collector would get the last push a second time.
2. **Dedup on the main thread, by time, since Android has no id.** This is iOS's rule: the push is accepted when
   the last accepted one had a different id (or none) *and* is more than 10 s old. The 1 s handler delay is kept.
   The record lives in memory only; iOS persists it in `CacheManager`. After a process restart a push can be
   handled again, which is harmless because iOS handles the same push once per launch anyway. FCM's message id is
   not passed through yet (the decoder takes only the data map), so on Android the rule is the 10-second window
   alone.
3. **"Signed in" is `WalletState.Ready` and "synced" is `WalletOverview.hasSynced`.**
   - Unlocking with a push pending shows `loading.syncingWallet`.
   - The first transition to signed-in and synced replays pending payout, HTLC, swap and LNURL pushes, as
     `finalizeSync` does.
   - Information, expired and unknown pushes open their card at once, even on the PIN screen.
4. **`wasNotified` is reset when a payout or HTLC is triggered.** iOS never resets it, so after one push arrives
   while locked, every later push skips the "you're receiving a payment" alert until relaunch. That looks
   unintended.
5. **Overlays are drawn in the activity window, not as dialogs.** The Question card, loading card and alert sit
   above `BittrNavHost` in `MainActivity`'s root box, so the root `testTagsAsResourceId` exposes their ids.
   - `BittrInlineAlert` gained an optional `cardTestTag`, which puts `alert.incomingPayment` on the card.
   - Alert buttons keep the `alert.button.N` order.
   - One alert at a time: a new alert replaces the old one, whereas iOS stacks them.
6. **Loading is hidden before the "no node id" payout alert.** iOS leaves the spinner up under it.
7. **A successful payout clears the pending push.** iOS keeps it until LDK's `paymentReceived` reconciles it with
   `checkPaymentWithBittr`, and that handler is not ported (see Gap 1). Keeping it would do nothing on Android.
8. **Transport failures reuse iOS's copy.** An `HttpTransportException` on `/payout/lightning` shows
   `COULD_NOT_CONNECT`, the copy iOS uses for a non-2xx response; it contains "try again", so a retry is offered.
   On `/htlc-interceptor/ready` a transport failure maps to `bittrpayoutfail2`, like iOS's catch.
9. **Hooks for other ports are optional bindings** (`@BindsOptionalOf` in `PushHooksModule`): `DepositCodeSource`,
   `SwapPushHandler`, `LnurlPushHandler` and `PayoutSwapLauncher`. The Buy, swaps and LNURL ports each add a
   `@Binds` in their own module, and neither `PushHandlingModule.kt` nor `PushModule.kt` needs editing.
   - With no deposit code bound, an HTLC push ends on `alert.incomingPayment` / `bittrpayoutfail`, which is the
     no-account path `notification_htlcincoming.yaml` accepts.
   - With no swap or LNURL handler bound, those pushes are logged and dropped. They are still held while locked or
     syncing.
10. **Test injection has a debug-only receiver** (`app/src/debug`, `com.bittr.android.DEBUG_PUSH`, exported). It
    feeds the same decoder and `PushHost.pushDelivery` as FCM. It is not in the release manifest.
    - `push_server.js` gained an Android mode (`BITTR_PUSH_PLATFORM=android` or `?platform=android`). It maps each
      bittr key of the flow's APNS JSON to `--es <key> '<json>'` and drops `aps`, so an aps-only payload is an
      unknown push.
    - The flows themselves are unchanged.

## Question

1. **Invented copy.** "Swap & Instant Receive" on the channel-full alert has no swap screen to open, so without a
   `PayoutSwapLauncher` the app shows new text: "Swapping isn't available in the Android app yet. Tap Receive
   on-chain…". It needs approving, or should the button be hidden until swaps land?
2. Should `wasNotified` really reset after each trigger (Decided 4), or should Android keep iOS's sticky
   behaviour?

## Gap

1. **Node events are not wired to the UI.** `LdkEventPumpRunner` only logs, so these iOS behaviours are missing:
   - Transaction screen after `paymentReceived` / `checkPaymentWithBittr`.
   - The "closed lightning connection" card.
   - Payment-failed alerts.
2. **`Log.i` has no Sentry equivalent** for the iOS `SentryManager.capture` calls on these paths.
3. **The deposit code store is the Buy port's.** The `htlc_ready` success path cannot be exercised end to end until
   that store is bound.
4. **Not run on the emulator yet.** Only JVM tests have run. The flows below are expected to pass on Android, but
   that is unverified.
