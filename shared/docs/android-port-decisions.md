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

5a. **Decided — pull-to-refresh on Home** (iOS `ReloadWallet.swift`): once the wallet has synced, pulling Home's
    list down hides the balance and history, spins `home.headerSpinner`, marks the wallet as not synced (Send and
    Receive show their syncing guard), then resyncs the node and the on-chain wallet and takes a fresh reading.
    If nothing can be read, the previous balance and history come back. Two differences: the pull triggers at
    120 dp (iOS 200 pt of overscroll; tune after trying it), and there is no internet check before refreshing.
    Home's header and history are now one scrolling list so the pull works from the header too, as
    `remove_wallet.yaml`'s swipe needs.

5b. **Decided — a swap's transaction screen shows what was swapped** (iOS `setTransactionData`): a completed swap
    shows the amount that arrived, unsigned, with the type "Onchain to Lightning" / "Lightning to Onchain" and fees =
    sent − received + fee. A pending swap shows the swap file's amount; a refunded on-chain → Lightning swap shows
    0 sats; a Swap & Pay leg shows "- <amount paid>". Home's history row keeps the signed net amount, as on iOS.

5c. **Decided — the transaction screen opens when a payment or swap completes**, as iOS does: a received or sent
    Lightning payment (found by payment hash, retrying while the wallet catches up; Receive closes first) and a
    completed swap (once both legs are in history). Nothing opens while locked or during the 10-wrong-PIN removal.
    This also fixes Send falling back to a plain "success" alert after a Lightning payment (it looked the row up
    by payment id instead of payment hash).

5d. **Decided — bittr payouts and purchases open the celebration version of the transaction screen** (iOS
    `checkPaymentWithBittr` → `showConfetti`): a Lightning payment that arrives while a payout is expected, or a new
    channel's funding transaction, is checked with bittr's `/transaction_info`; if bittr confirms it, the screen
    opens with the piggy header, "Good job", the reminder card and hearts, plus the purchase breakdown (surcharge,
    bittr fee, transfer fee, purchase value, rate, current value, profit). Also ported: the "Payment failed" alert
    (Send no longer shows a second one) and the internet check before pull-to-refresh. Differences from iOS:
    - A payment only counts as the expected payout within 10 minutes of the payout request (iOS has no limit).
    - A funding purchase's screen is built from bittr's record, since that transaction isn't in the wallet history.
    - After a failed Lightning payment Send keeps the form filled in (iOS clears it).
    - The hearts are a hand-made animation (iOS uses SPConfetti) and need a visual check.

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

18. **Decided — "Swap & Instant Receive" on the "channel full" payout alert opens a Lightning → on-chain swap of
    the suggested amount**, as iOS's `handleNotificationSwap`. The "Swapping isn't available…" copy is only left
    as a fallback for tests.

19. **Decided (Ruben, 2026-09-15) — "arrived while locked": pay out silently, as on iOS.** Once a payout,
    incoming-payment or Lightning-address push has arrived while the app was locked, later payment pushes in the
    same session also go ahead without the "You're receiving a payment, tap Okay" alert. The flag is never
    cleared (Android used to clear it after each payout).

20. **Decided — pushes are tested on Android through a debug-only broadcast receiver.** Start
    `BITTR_PUSH_PLATFORM=android node shared/flows/scripts/push_server.js` and the flows run unchanged.

## Buy, bittr signup and profits (merged from `port/buy`)

Full log: `android/docs/port-specs/buy-decisions.md`. What needs you:

21. **Question — `buy_signup_no_notifications.yaml` on Android.** Maestro denies the notification permission
    before the app has ever asked, so the app still shows its own "receive notifications" prompt, and Okay then
    opens the system dialog, which the flow doesn't expect. Add an Android-only "Don't allow" step to the flow,
    or change the app?

22. **Decided — onboarding continues into the bittr signup** as on iOS: Continue on "Your wallet is ready" opens
    the Buy signup pages (IBAN, email, code, success, transfer); Skip still goes to the wallet. The navigation
    graph's start destination is now read once at launch, so unlocking during onboarding no longer resets it.

23. **Decided (Ruben, 2026-09-15) — no push token halts the signup**, and the user is asked whether they want
    on-chain-only payouts, as iOS does: with notifications allowed the code is sent once a token arrives (up to
    15 s); without one the signup stops on `tokenregistrationfail` [Try again, Continue], and Continue registers
    for on-chain payouts. A registration that carried a token is recorded, so the next launch doesn't re-send it.

24. **Decided — two iOS quirks not copied:**
    - A payout-mode change is applied even when the IBAN and other details didn't change. iOS only checks it
      inside the "details changed" branch, which contradicts its own comment.
    - A missing `lightning_address_username` doesn't count as a change, so "Update details" doesn't fire every
      time Buy opens.

25. **Decided — profits count the channel-funding purchase** (its txid goes to `/transaction_info`, as iOS's
    `getTxoID()`). Still not ported: the article cards on the signup pages, the connectivity check between pages,
    and the Sentry signup metric.

26. **Decided — the push handlers read the deposit code from the Buy customer store**
    (`BuyPushHooksModule`), so `htlc-interceptor/ready` and payouts work once a customer has signed up.

## Swaps (merged from `port/swaps`)

Full log: `android/docs/port-specs/swaps-decisions.md`. Crypto (Taproot lockup, MuSig2 claim/refund) is on
bitcoin-kmp, with every iOS check on Boltz's answers and the evil-Boltz cases as JVM tests.

27. **Decided — Android checks Boltz's partial signature and the final signature before broadcasting** a claim
    or refund. iOS broadcasts unchecked; this doesn't change the happy path.

28. **Decided — claims and refunds keep running after the swap screen closes** (process scope). iOS ties them
    to the view controller.

29. **Decided (Ruben, 2026-09-15) — test on an emulator with Google Play services.** The local AVD moves from the
    plain `default` image (no Play services, so no Firebase token) to `google_apis`, which can mint real FCM tokens
    like a phone. `google_apis` rather than `google_apis_playstore`: same Play services, but it keeps `adb root`
    and a writable system, which is why the `fcm-delivery.yml` CI job already uses it. The CI Maestro job still
    boots `aosp_atd` (lightest, fastest); flows that need a real token (swaps, the signup's token step) need a
    `google_apis` leg there too.

30. **Decided (Ruben, 2026-09-15) — swap pushes behave as on iOS:** ignored while a swap screen is open;
    locked → "Your swap status has been updated / please sign in" and the push is kept; syncing → loading card;
    synced → open the latest swap's status, only while the app is on screen. A push never claims or refunds.

31. **Decided — swap history is ported** (`performSwapMatching`): a swap's two legs are one row, a lone leg is a
    pending swap row (`history.swapComplete<N>` / `history.swapPending<N>`), and the transaction screen shows the
    swap id and status with `transaction.swapStatusButton` / `transaction.copyBottomIdButton`. Received Lightning
    payments show their invoice description, and "Swap & Instant Receive" on a channel-full payout opens a
    Lightning → on-chain swap of the suggested amount. **Gaps left:** a Swap & Pay leg doesn't show iOS's second
    id or the amount from the swap file, a pending swap's amount isn't read from the swap file, payout
    notification ids aren't stored as descriptions, no Live Activity equivalent, and the `-evilBoltz` harness
    isn't ported (JVM tests cover it).

## LNURL, Lightning address, channel chart, sync overlay, notes (merged from `port/lnurl`)

Full log: `android/docs/port-specs/lnurl-decisions.md`.

32. **Decided (Ruben, 2026-09-15) — the new copy is fine:** "The invoice we received doesn't match the requested
    amount." Android refuses an LNURL-pay invoice for a different amount than was asked; iOS pays it.

33. **Decided — LNURL service URLs, callbacks and the Lightning-address push endpoint must be public https.**
    iOS fetches or posts to any URL. `notification_lnurl.yaml` still ends on `alert.paymentRequestFailed`.

34. **Decided — LNURL-auth uses iOS's own key derivation** (HMAC of the mnemonic, not LUD-05), so an account on a
    site carries over from iOS. Not tested against a live site.

35. **Gap — still missing here:**
    - An Android clipboard bridge for the invoice-paste steps in `send_lightning.yaml` / `receive_invoice.yaml`.
    - iOS's injected script that finds Lightning links on a web page: it needs a JavaScript bridge, which the
      app's WebView guard tests forbid. Tapping a link works.

35a. **Decided — LNURL links in the in-app browser** (`lightning:`, `lnurl:`, bare `lnurl1…`, https with
    `tag=login`) are handed to Send, only from the main frame of a `getbittr.com` page, as iOS does. From a web
    page only LNURL-auth is allowed, not pay or withdraw. The link travels in memory only, never in a route.
    Two differences from iOS: only exactly `getbittr.com` counts (iOS also accepts subdomains), and the login
    prompt appears on Send rather than over the page.

35b. **Decided — Send's "why a limit" card shows the channel chart** and balance/reserve/limit text when a
    channel is active. **Question:** without a channel iOS's header reads "why can't I *receive* instant
    payments?" on a Send screen — ported as-is; is that the intended copy?

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

## Porting status (2026-09-15)

Every iOS feature area is ported: everyday wallet, Receive/Send, Lightning address and LNURL, swaps, Buy and the
bittr signup, profits, notifications, wallet removal and the PIN flows, Device details, pull-to-refresh, and the
transaction confirmations. All of it passes JVM unit tests. What remains:

- **Verification:** only `restore_wallet`, `receive`, `receive_onchain`, `send_onchain`, `send_onchain_all`,
  `bitcoin_value` and `academy` have passed Maestro on the emulator (2026-09-14). Everything since has been
  tried by hand on Ruben's phone only (item 10b). Next: run the suite on `bittr-gapi` or CI.
- **Open questions:** 21 (`buy_signup_no_notifications.yaml` on Android), 35b (Send limit card copy).
- **Known gaps:** signup article cards, the connectivity check between signup pages and the Sentry signup
  metric (25); Swap & Pay's second id (31); no Live Activity equivalent and no `-evilBoltz` harness (31); the
  clipboard bridge for paste steps in flows and the injected link-finder script (35).
