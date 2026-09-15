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

4. **Decided — "Add a note" on the transaction screen** is ported (`transaction.addNoteButton`, `alert.addNote`),
   with the LNURL work.

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

## Device details

8a. **Decided — Public key, Bittr peer and Pending payout are ported** (they showed "syncing wallet" whatever
    the wallet's state). Public key shows the node id with [Copy, Close]. Bittr peer shows connected, or not
    connected with [Close, Connect]. Pending payout makes the signed `GET /notifications` call and hands a
    payout to the push handler. Lightning connections shows the channel count once the wallet has synced. Two
    notes:
    - iOS crashes on Pending payout when there's no node (it force-unwraps `nodeId()`); Android shows
      "syncing wallet" instead.
    - Like iOS, the pending-payout list stops reading at the first notification missing a field such as
      `sent_at`, so a half-filled notification hides the ones after it. Ported as-is so both platforms agree.
      **Answered 2026-09-15:** a bug — tracked in https://github.com/getbittr/bittr-ios-app/issues/96; Android changes
      with the iOS fix.

## Wallet removal (Device details, Forgot PIN, 10 wrong PINs)

11. **Decided — one removal coordinator, ported from `ResetApp.swift`, for all three entry points.**
    The wallet is only erased when `WipeSafety.channelsFullyClosedAndSwept` is true: no open channel, no
    Lightning balance, nothing still sweeping. If the node isn't running or can't be read, nothing is erased
    and the user gets `removalfailed` (with "Try again" when locked out). Before this, the Android 10-wrong-PIN
    wipe erased the seed with no channel check at all, which could have lost channel funds.

12. **Decided (Ruben, 2026-09-15) — when the bittr node can't be reached for a cooperative close, the manual
    removal force-closes straight away, as iOS does** ("if the peer is not reachable something must be wrong").
    A close call that fails with the peer connected still asks via `closechannel6`/`closechannel7`, also as iOS.
    The 10-wrong-PIN lockout never force-closes.

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

17. **Decided — the "lightning connection closed" Question card** (`question.yellowCard` after a close, which the
    channel branch of `remove_wallet.yaml` / `forgot_pin_remove_wallet.yaml` dismisses) opens from LDK's
    `ChannelClosed` event (LNURL port), and is not shown during the 10-wrong-PIN removal, as on iOS.

## Notifications (merged from `port/notifications`)

Full log: `android/docs/port-specs/notifications-decisions.md`. The two that need you:

18. **Decided — "Swap & Instant Receive" on the "channel full" payout alert opens the swap screen** now that swaps
    are merged. It opens the plain swap screen; iOS pre-fills the suggested amount, which the Android swap route
    can't take yet (small gap). The "Swapping isn't available…" copy is only left as a fallback for tests.

19. **Question — "arrived while locked" flag.** Ruben needs context first (given 2026-09-15): when a payout or
    incoming-payment push arrives while the app is locked, the app remembers it and, after unlock and sync, pays
    out straight away without the "You're receiving a payment, tap Okay" alert — signing in counts as consent.
    iOS never clears that flag, so every *later* push in the same session also skips the alert; Android clears it
    after each payout. Still open.

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

23. **Decided (Ruben, 2026-09-15) — no push token halts the signup**, and the user is asked whether they want
    on-chain-only payouts, as iOS does. (Being implemented; replaces the "register without a token" behaviour.)

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

30. **Decided (Ruben, 2026-09-15) — swap pushes behave as on iOS:** locked → "please sign in" alert, syncing →
    loading card, synced → open the swap status only when the app is in front. No claim or refund straight from
    a push in the background. (Being implemented; Android claimed from the push before.)

31. **Gap — swap history rows.** Android's history has no description cache yet, so the two legs of a swap show
    as separate, unlabelled rows. The transaction screen has no swap status button, there's no swap from a payout
    push, and there's no Live Activity equivalent. The `-evilBoltz` test harness isn't ported (JVM tests cover it).

## LNURL, Lightning address, channel chart, sync overlay, notes (merged from `port/lnurl`)

Full log: `android/docs/port-specs/lnurl-decisions.md`.

32. **Decided (Ruben, 2026-09-15) — the new copy is fine:** "The invoice we received doesn't match the requested
    amount." Android refuses an LNURL-pay invoice for a different amount than was asked; iOS pays it.

33. **Decided — LNURL service URLs, callbacks and the Lightning-address push endpoint must be public https.**
    iOS fetches or posts to any URL. `notification_lnurl.yaml` still ends on `alert.paymentRequestFailed`.

34. **Decided — LNURL-auth uses iOS's own key derivation** (HMAC of the mnemonic, not LUD-05), so an account on a
    site carries over from iOS. Not tested against a live site.

35. **Gap — still missing here:**
    - Lightning invoice descriptions on received payments, since Receive doesn't store them.
    - LNURL links inside the in-app browser.
    - The chart on Send's "why a limit" card.
    - An Android clipboard bridge for the invoice-paste steps in `send_lightning.yaml` / `receive_invoice.yaml`.
    - ~~The Lightning-address push handler~~ — now bound: locked → `alert.paymentRequest` "please sign in", then
      answered after the first sync; open → [Cancel, Handle now]; a failure → `alert.paymentRequestFailed`.

36. **Decided — the channel-closed card** (`question.yellowCard`, "closed lightning connection") now opens from
    LDK's `ChannelClosed` event, as `remove_wallet.yaml` expects, and like iOS it stays hidden during the
    10-wrong-PIN wipe.

## Test environment

9. **Decided — local emulator runs with `-memory 4096 -cores 6 -camera-back none`.** With the AVD's 4 cores /
   2 GB, cold starts took 8–36 s and the flows' 15 s launch wait failed; with 6 cores / 4 GB, 0.4–0.5 s.
   CI already uses `-camera-back none`.

10b. **Gap — none of tonight's new screens have passed a Maestro flow on the emulator yet.** Everything merged
    tonight passes its JVM unit tests (app, send, home, settings, buy, swaps, LNURL, network, wallet-ldk), but
    three emulator runs (23:30, 01:05 and a health-gated rerun until 03:45) failed on the emulator, not the app:
    - The emulator's Android system repeatedly hung and restarted, even right after fresh cold boots. Its watchdog
      logged `StorageManagerService`, `ActivityManagerService` and `PowerManagerService` blocked for 60–151 s,
      from 22:38 on (before the merges). Once system_server crashed writing a battery-stats system property. After
      each hang the apps died with `DeadSystemException`, and twice the package service broke.
    - The app itself was not stuck: its only ANR (02:30) shows the main thread idle, waiting for a focus event
      from the system. In the one run that got past unlocking, Home was on screen with the new fiat line, profit pill
      and Buy button, but Maestro's driver could not read it (`DEADLINE_EXCEEDED`).
    - The Mac had 18 of 19 GB swap in use and was busy (Spotlight, Wi-Fi daemon, browser). Disk had 199 GB free.
    **Next step:** run the flows on a quiet Mac (reboot first) or the CI emulator, starting with `settings`,
    `pin_warning`, `forgot_pin`, `notification_information`, `buy_signup`, `payment_mode`, then the destructive
    `forgot_pin_remove_wallet`, `remove_wallet`, `wrong_pin`. The helper scripts are described in the summary.

10a. **Decided — `notification_information.yaml` not run to a result yet.** It needs pushes delivered to the
    app, which the iOS runs inject through the simulator; on Android that path belongs to the notifications
    port. The overnight batch stuck in its timeouts was stopped so the emulator could be reused.

## Branches

10. **Decided — kept on GitHub:** `k1-run/*` and `regtest-run/bit-147-first` (they are how the K1/K7/K8 CI runs
    are requested, and `k1-result.py` looks runs up by branch name), the four unmerged `snapshot/*` branches,
    Tom's `fix/home-header-refactor` (open PR #94), and `ios-parity`. Deleted: 49 merged `feature/bit-*` and
    `merge/bit-63-tokens-into-android`. **Answered 2026-09-15:** the `k1-run/*`, `regtest-run/*` and `snapshot/*`
    branches were deleted from GitHub too (11 branches).

## Not ported yet (to be worked through overnight)

- Lightning address / LNURL pay, withdraw and auth (Send shows "not available on Android yet").
- Swaps (Boltz) — Move's swap button and Send's swap suggestions say "not available on Android yet".
- Buy and bittr signup, profits.
- Notifications (incoming payment, payment requests, information).
- Sync status overlay (`sync.statusView`), channel statistics chart (`question.channelView`), transaction notes.
- Wallet removal from Device details / Forgot PIN.
