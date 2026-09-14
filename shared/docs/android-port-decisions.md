# Android port — decisions and open questions

Calls made while porting the iOS app to Android on `android-parity` without someone to ask.
Each entry says what was decided, why, and what would change it. **Review these together.**

Status key: **Decided** (done, reversible) · **Question** (needs your answer) · **Gap** (not ported yet, shown honestly in the app)

---

## Everyday wallet (Home, Receive, Send, Transaction, Move)

1. **Decided — `send_onchain.yaml` is a self-send on the Android emulator.**
   The flow's fixed address `bcrt1qz2d3feqzlr3ggslt3ugs768utz8kmweah95qgv` belongs to the e2e wallet that
   `restore_wallet.yaml` restores (iOS sends to it from a different wallet). The new transaction therefore
   reads "+ 0 sats" with only "Fees paid". The mapping is identical to iOS (`amountMsat`, `feePaidMsat`), so
   nothing was changed.

2. **Decided — the confirm page's fee quote can differ from the fee actually paid.**
   The quote uses BDK's transaction-size preview (as iOS does); ldk-node picks the coins when it broadcasts.
   Seen: quoted 624 sats at the fast tier, paid 422. Same design as iOS, left as is.

3. **Decided — Lightning routing-fee estimate uses LDK's default cap** (1 % of the amount + 50 sats).
   iOS reads the cap off LDK's route parameters for the invoice; ldk-node does not expose that call, so
   Android computes LDK's default formula directly.

4. **Gap — "Add a note" on the transaction screen** is not ported yet (used by buy/swap flows).

5. **Decided — Home shows the balance in fiat under the balance** ("CHF 190", iOS `conversionLabel`),
   and refetches the price when the currency changes in Settings.

## Scanner and alerts

6. **Decided — every Compose dialog exposes its test ids** (`Modifier.exposeTestTags()`), and
   `DialogTestTagGuardTest` fails any new dialog that doesn't. Without it no `alert.button.N` was tappable
   by Maestro on Android.

7. **Decided — the scanner's alerts are drawn in-window** (`BittrInlineAlert`), not as dialogs, because
   `send_onchain.yaml` asserts `scanner.scannerView` and `alert.button.0` together and a dialog window hides
   the screen behind it from Maestro. Other alerts stay dialogs.

8. **Decided — "no camera" means no camera device**, not just no camera feature flag. A device can declare
   camera features and list no camera (the CI emulator with `-camera-back none`); the scanner now shows the
   "Scanning not supported" alert there, like iOS.

## Wallet removal (Device details, Forgot PIN, 10 wrong PINs)

11. **Decided — one removal coordinator, ported from `ResetApp.swift`, for all three entry points.**
    The wallet is only erased when `WipeSafety.channelsFullyClosedAndSwept` is true: no open channel, no
    Lightning balance, nothing still sweeping. If the node isn't running or can't be read, nothing is erased
    and the user gets `removalfailed` (with "Try again" when locked out). Before this, the Android 10-wrong-PIN
    wipe erased the seed with no channel check at all, which could have lost channel funds.

12. **Question — when the bittr node can't be reached for a cooperative close, iOS force-closes straight away**
    (`closeChannelConfirmed` → `forceCloseChannel()`), even though its own comment says "let the user explicitly
    choose force close". Android shows the `closechannel6`/`closechannel7` alert with [Cancel, Force Close]
    instead, the same alert iOS shows when the close call itself fails. A force close locks the funds for
    about a day and costs more in fees, so I didn't want to start one without asking. Should iOS change to match?

13. **Decided — the lockout shows `pinlock` first and works behind it (iOS order),** and never force-closes:
    locked out, an open channel is closed cooperatively and the only button is "Try again" until the funds
    have settled. A failed erase on the lockout path also offers "Try again" (iOS shows Okay and relies on a
    relaunch).

14. **Decided — Forgot PIN → "Remove wallet from device" always asks `removewallet1` first**, then starts the
    node in the background (without unlocking), syncs, and applies the same channel rules.

15. **Decided — the "removal in progress" flag is a marker file under `no_backup`,** so a phone restored from
    backup doesn't offer to remove a wallet it never started removing. The launch prompt (`removalinprogress`)
    matches iOS.

16. **Decided — removing a wallet still leaves the LDK state directory on the device** (as before). It is only
    ever reached once channels are closed and swept, and a later wallet with a different seed quarantines it
    (`SeedImportGuard`) rather than deleting it. iOS deletes its documents directory.

17. **Gap — the "lightning connection closed" Question card** (`question.yellowCard` after a close, which the
    channel branch of `remove_wallet.yaml` / `forgot_pin_remove_wallet.yaml` dismisses) needs LDK's
    `ChannelClosed` event to reach the UI. It comes with the notifications/events work.

## Notifications (merged from `port/notifications`)

Full log: `android/docs/port-specs/notifications-decisions.md`. The two that need you:

18. **Question — new copy.** On the "channel full" payout alert, "Swap & Instant Receive" shows "Swapping isn't
    available in the Android app yet…" until the swaps port provides a swap screen. This goes away once swaps
    are merged. Until then, approve the copy or hide the button?

19. **Question — "arrived while locked" flag.** iOS never resets `wasNotified`, so after one push arrives while
    the app is locked, every later push skips the "you're receiving a payment" alert until the app is relaunched.
    Android resets it after each payout or HTLC. Keep that, or copy iOS?

20. **Decided — pushes are tested on Android through a debug-only broadcast receiver.** Start
    `BITTR_PUSH_PLATFORM=android node shared/flows/scripts/push_server.js` and the flows run unchanged.

## Buy, bittr signup and profits (merged from `port/buy`)

Full log: `android/docs/port-specs/buy-decisions.md`. What needs you:

21. **Question — `buy_signup_no_notifications.yaml` on Android.** Maestro denies the notification permission
    before the app has ever asked, so the app still shows its own "receive notifications" prompt, and Okay then
    opens the system dialog, which the flow doesn't expect. Add an Android-only "Don't allow" step to the flow,
    or change the app?

22. **Question — onboarding's "Your wallet is ready" → bittr signup isn't wired yet.** Continue still ends
    onboarding, so `happy_path_signup.yaml` and `fresh_install_unhappy.yaml` don't reach the signup pages. The
    Buy signup pages can be reused there as iOS does (pages 9–13). I can do that next if you want it.

23. **Question — a signup with no push token.** Emulators often have no FCM token, so Android registers after
    15 s without `android_device_token` and sends the token later with `PATCH /customer/device-token`.
    iOS shows `tokenregistrationfail` [Try again, Continue] instead. OK?

24. **Decided — two iOS quirks not copied:**
    - A payout-mode change is applied even when the IBAN and other details didn't change. iOS only checks it
      inside the "details changed" branch, which contradicts its own comment.
    - A missing `lightning_address_username` doesn't count as a change, so "Update details" doesn't fire every
      time Buy opens.

25. **Gap — profits don't count the channel-funding transaction yet** (iOS sends `getTxoID()` to
    `/transaction_info` too). Also not ported: the article cards on the signup pages, the connectivity check
    between pages, and the Sentry signup metric.

26. **Decided — the push handlers read the deposit code from the Buy customer store**
    (`BuyPushHooksModule`), so `htlc-interceptor/ready` and payouts work once a customer has signed up.

## Swaps (merged from `port/swaps`)

Full log: `android/docs/port-specs/swaps-decisions.md`. Crypto (Taproot lockup, MuSig2 claim/refund) is on
bitcoin-kmp, with every iOS check on Boltz's answers and the evil-Boltz cases as JVM tests.

27. **Decided — Android checks Boltz's partial signature and the final signature before broadcasting** a claim
    or refund. iOS broadcasts unchecked; this doesn't change the happy path.

28. **Decided — claims and refunds keep running after the swap screen closes** (process scope). iOS ties them
    to the view controller.

29. **Question — FCM on the test emulator.** A swap needs a push token for Boltz's webhook, so without Firebase
    set up on the emulator every swap stops at `alert.notificationsRequired`. Should the Android test emulator
    get a Play-services image and `google-services.json`?

30. **Question — should Android claim or refund in the background after a swap push**, when the app isn't open?
    iOS doesn't.

31. **Gap — swap history rows.** Android's history has no description cache yet, so the two legs of a swap show
    as separate, unlabelled rows. The transaction screen has no swap status button, there's no swap from a payout
    push, and there's no Live Activity equivalent. The `-evilBoltz` test harness isn't ported (JVM tests cover it).

## LNURL, Lightning address, channel chart, sync overlay, notes (merged from `port/lnurl`)

Full log: `android/docs/port-specs/lnurl-decisions.md`.

32. **Question — new copy:** "The invoice we received doesn't match the requested amount." Android refuses an
    LNURL-pay invoice for a different amount than was asked; iOS pays whatever invoice comes back.

33. **Decided — LNURL service URLs, callbacks and the Lightning-address push endpoint must be public https.**
    iOS fetches or posts to any URL. `notification_lnurl.yaml` still ends on `alert.paymentRequestFailed`.

34. **Decided — LNURL-auth uses iOS's own key derivation** (HMAC of the mnemonic, not LUD-05), so an account on a
    site carries over from iOS. Not tested against a live site.

35. **Gap — still missing here:**
    - Lightning invoice descriptions on received payments, since Receive doesn't store them.
    - LNURL links inside the in-app browser.
    - The chart on Send's "why a limit" card.
    - An Android clipboard bridge for the invoice-paste steps in `send_lightning.yaml` / `receive_invoice.yaml`.
    - The Lightning-address push handler isn't bound to the notifications hook yet (see below).

36. **Decided — the channel-closed card** (`question.yellowCard`, "closed lightning connection") now opens from
    LDK's `ChannelClosed` event, as `remove_wallet.yaml` expects. iOS hides it during the 10-wrong-PIN wipe; Android
    doesn't yet.

## Test environment

9. **Decided — local emulator runs with `-memory 4096 -cores 6 -camera-back none`.** With the AVD's 4 cores /
   2 GB, cold starts took 8–36 s and the flows' 15 s launch wait failed; with 6 cores / 4 GB, 0.4–0.5 s.
   CI already uses `-camera-back none`.

10a. **Decided — `notification_information.yaml` not run to a result yet.** It needs pushes delivered to the
    app, which the iOS runs inject through the simulator; on Android that path belongs to the notifications
    port. The overnight batch stuck in its timeouts was stopped so the emulator could be reused.

## Branches

10. **Decided — kept on GitHub:** `k1-run/*` and `regtest-run/bit-147-first` (they are how the K1/K7/K8 CI runs
    are requested, and `k1-result.py` looks runs up by branch name), the four unmerged `snapshot/*` branches,
    Tom's `fix/home-header-refactor` (open PR #94), and `ios-parity`. Deleted: 49 merged `feature/bit-*` and
    `merge/bit-63-tokens-into-android`. **Question:** delete the CI-trigger and snapshot branches too?

## Not ported yet (to be worked through overnight)

- Lightning address / LNURL pay, withdraw and auth (Send shows "not available on Android yet").
- Swaps (Boltz) — Move's swap button and Send's swap suggestions say "not available on Android yet".
- Buy and bittr signup, profits.
- Notifications (incoming payment, payment requests, information).
- Sync status overlay (`sync.statusView`), channel statistics chart (`question.channelView`), transaction notes.
- Wallet removal from Device details / Forgot PIN.
