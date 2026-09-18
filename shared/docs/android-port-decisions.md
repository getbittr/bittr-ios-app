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
    list down spins `home.headerSpinner`, marks the wallet as not synced (Send and Receive show their syncing
    guard), resyncs the node and the on-chain wallet and takes a fresh reading. **Ruben, 2026-09-17:** the balance
    and history stay on screen during the refresh instead of blanking as iOS's `resetWallet()` does. The pull
    triggers at 120 dp (iOS 200 pt) and first checks the connection. Home's header and history are one scrolling
    list so the pull works from the header too, as `remove_wallet.yaml`'s swipe needs.

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

5e. **Decided — Home shows the last known data on launch** (iOS `WalletCache` + `showCachedData()`): the last
    synced balance, fiat line, profit pill and history appear immediately while the header spinner runs, and the
    live sync replaces them. As on iOS the wallet still counts as not synced, so Send, Receive, the balance card
    and pull-to-refresh keep their guards; cached history rows can be opened. Saved per backend under `no_backup`
    and cleared when the wallet is removed. Differences: rates are saved per currency (iOS saves EUR and CHF
    only), and the profit summary is saved as numbers rather than recalculated from the cached history.

5f. **Decided — removing a wallet clears the old wallet's figures from memory too**, so a new or restored wallet
    never briefly shows them: the overview (and its refresh snapshot), profits, the saved bittr accounts and
    purchases, the expected payout and the confirmations' opened ids. The sent-to-bittr ids and swap files are kept,
    as on iOS (`deleteClientInfo`).

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

8b. **Decided — the pending-payout check skips payouts that are already finished.** bittr's `GET /notifications`
    kept listing a payout that `POST /payout/lightning` then answered "This payment has already been processed.",
    so the same payout was offered forever. Android now remembers payouts that paid out or got that answer
    (`processedPayouts` in the customer store), skips notifications bittr marks `acknowledged` (paid), and offers the
    newest remaining one; each listed notification's id and status is logged (`DeviceNode` tag). Reported with the
    observed statuses on issue #96. iOS has the same problem; **Question:** should the backend
    drop processed notifications from the list, and keep `status` in sync (one processed payout stayed `sent`)?

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

21. **Decided (Ruben, 2026-09-17) — the app explains notifications first, then Android asks**, as on iOS. The flow
    `buy_signup_no_notifications.yaml` gets an Android-only step that taps the system dialog's "Don't allow" after
    the in-app prompt, because Maestro's `notifications: deny` doesn't answer that dialog on Android.

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
    channel is active. Without a channel the header reads "why can't I *receive* instant payments?", as on iOS
    (Ruben, 2026-09-17: keep it).

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
- **Open questions:** 8b (backend: processed payouts in `/notifications`, issue #96).
- **Known gaps (2026-09-17):** fixed — signup article cards (Buy signup pages; the create-wallet pages' cards
  aren't ported yet), the connection check between signup pages, Swap & Pay's second id, a clipboard helper for
  the paste steps in flows (`BITTR_CLIPBOARD_PLATFORM=android node shared/flows/scripts/clipboard_server.js`),
  and Lightning links on `getbittr.com` pages (checked once a second with `evaluateJavascript`, no JS bridge;
  iOS observes the DOM). Not done: the Sentry signup metric (Android has no Sentry SDK — adding one is a
  separate decision), the `-evilBoltz` harness (JVM tests cover it), and no Live Activity (not needed).
## 37. Resolved — a second wallet on the same install cannot start its node

**Found 2026-09-18, running the suite.** Create a wallet, remove it, create another one on the same
install, and the node refuses to come up:

```
BittrNode: Node start failed
org.lightningdevkit.ldknode.BuildException$WalletSetupFailed: Failed to setup onchain wallet.
```

Nothing then works that needs the node — `forgot_pin_remove_wallet.yaml` fails because the removal
cannot read the channel it has to close ("Something went wrong removing your wallet"), and a signup
in that state cannot sign `POST /customer` either. Wiping the app's data makes the same flow pass, which
is why it only shows up mid-suite, after `wrong_pin_with_channel` has removed a wallet.

**Why.** `WalletService.removeWallet` erases the seed and deliberately leaves ldk-node's state directory
where it is (`NodeBackedWalletService`'s comment: force-close sweep material is not ours to delete). The
piece that was supposed to deal with the leftovers on the way in — `SeedImportGuard`, which quarantines
state whose discriminator does not match the new seed, and `SeedImporter` around it — **is not wired into
the app**: nothing outside its own tests calls `prepareForImport`. So the next wallet builds a node over
the previous wallet's on-chain store.

**The decision to take, Ruben:** what should happen to the old node state when a new wallet appears on a
device that already had one — quarantine it (what the guard was written for, keeping the old channel's
sweep material), or delete it? And should removal itself quarantine on the way out, rather than leaving it
for the next seed? Both touch material that a force-close needs, so this is not a call to make in passing.

**Decided 2026-09-18 (Ruben): quarantine, don't delete.** `NodeBackedWalletService.createWallet` and
`restoreWallet` now take the node down, write the seed, and run `SeedImportGuard.prepareStateFor` on the new
phrase: state that is this seed's is kept, anything else (a mismatched or missing discriminator) is moved to
`no_backup/wallet/foreign_ldk_state/<n>-<random>/`, and the new seed's discriminator is recorded. Nothing is
deleted, and removal itself still leaves the state where it is. The guard runs after the seed write rather
than before (the reverse of `SeedImporter`) because a seed with no PIN is not a wallet and starts no node,
so a crash between the two only means doing the signup again. A quarantine is logged (`WalletModule` tag) and not
yet shown to the user; iOS's `didQuarantineForeignState` isn't read by any screen either.

## 38. Design review, pass 1 — where the build departs from the review

**2026-09-18.** Claude Design compared the Android build with its Android proposal (`Bittr Android
Onboarding.html`), screen by screen, from Maestro screenshots. Nearly all of it went in as written
(`70251eac` shared components, `5ec98a52` screens). These are the places it did not, and why:

- **The canvas stays `#FFC502`**, not the review's `#FFC107`. The mock's value is Material amber in a
  tweak panel; `#FFC502` is the iOS brand colour, signed off as DEV-01.
- **Gold labels and word numerals use `rowLabel` (`#8A6A00`)**, not `#EFA900`. On a white row `#EFA900`
  is about 2 : 1; `rowLabel` is the darkened gold signed off for exactly this (DEV-40, 5.07 : 1).
- **The disabled button's label is ink @ 50 %**, not Material's 38 %. 38 % is 2.26 : 1 on the disabled
  fill, under the 3 : 1 floor `TokenContrastTest` holds a disabled label to; 50 % is 3.05 : 1. The fill is
  the review's ink @ 12 %.
- **S7 (fields "drawn fully rounded") was not reproduced.** The recovery-phrase rows, send fields and Buy
  fields already use the 16 dp field shape; the ones on 8 or 12 dp were moved to 16 dp as they were
  touched. The grey word numerals the same finding mentions are gold now.
- **The article card's title is `onTonalFill` (ink)** rather than `#2A2118`, so it also reads in dark mode,
  where the card is blue.
- **Settings in the bottom bar is a labelled tab** (S9), which changes Home's bottom bar from the mock's
  unlabelled gear square.

Pass 2 of the review (academy, map, value, settings, swap, send on-chain, receive on-chain, payment mode,
removal and PIN flows) has not happened yet.

## 39. Design review, pass 2 — where the build departs from the review

**2026-09-18.** Pass 2 went in as `7d8b08c4` (shared components and screens) and the Academy and
Bitcoin-value branches merged after it. Not taken, or taken differently:

- **S3 was already as specified.** The disabled pill is ink @ 12 % over `#FFC502` under an ink @ 50 %
  label; the review measured `#C9A21A` off a JPEG. No change.
- **S14 ("previous screen left painted") is the navigation crossfade caught mid-way by the screenshot**,
  not a screen left behind: every destination paints its own canvas.
- **The payout confetti already falls behind the rows** (`5ec98a52`); it shows through the card's
  translucent 9 % wash, and the Reminder card is below the fold of a scrolling screen, not clipped.
- **The switch's off state stays see-through with a 70 % ink border and thumb.** The review asked for a
  cream track with a white thumb and a 20 % ink outline, which is well under the 3 : 1 edge WCAG 1.4.11
  needs; `CanvasComponentColorsTest` (BIT-95) holds the current tokens for that reason.
- **A copied value is one line with a middle ellipsis**, not two: Compose middle-ellipsizes single
  lines only. Start and end of the hash stay visible; TalkBack and the flows read all of it.
- **"How to recover my wallet?" sits under the Restore card** on the forgot-PIN restore screen, where the
  restore arc already has it, rather than between Cancel and "Remove wallet from device".
- **"Academy (beta)" is unchanged** — a product-copy question for Ruben (drop "(beta)", or show it as a
  chip beside the title).
- **Bitcoin value keeps the shared type scale** (title 26/32, price 36) rather than one-off 28/34 and
  34 sp; if headings should be 28 sp, that belongs in `BittrTypography`, for every screen.
- **Chart axis labels are 13 sp at 70 % ink**, not 12 sp at 55 %: 55 % on white is 4.3 : 1, under AA.
- **The chart line is ink, and the selected range segment is cream with a check**: the card is white,
  so the review's white line and white selected segment would not show on it.
- **Semibold (600) renders bold** throughout: the app bundles Gilroy Regular and Bold only.
- **Not done yet:** numbering the three removal dialogs ("Step 2 of 3") is a copy change for iOS and
  Android together; the receive on-chain address wrap (`send_swap_suggestion_onchain/01b`).

## 40. The map's tiles come from OpenFreeMap, not bittr's own host

**2026-09-18, Ruben.** The self-hosted tile plan (map-sdk-decision.md, 2026-09-11; `tiles.getbittr.com`,
BIT-139) never got its hosting, so the Android map drew only a blank background. Asked what Google Maps
would imply instead, Ruben chose the middle option: **keep MapLibre and point it at a hosted tile
service**, OpenFreeMap's Liberty style.

- **Why not Google's map SDK:** on top of viewport and IP, it sends Google a pseudonymous install id and
  pan/zoom interaction data (all declarable in the Play data-safety form), needs Play services, and
  would have been a rewrite of the map screen.
- **Why OpenFreeMap:** no API key, no account, no cookies; commercial use allowed; its privacy policy
  keeps no IP addresses by default (30 days at most, for incidents). **Costs:** no SLA, it can stop
  without notice; it may be behind Cloudflare, which would then see the IP too.
- **What still leaves the device:** the viewport and the client IP, to OpenFreeMap, on every pan — as
  with any tile host. The shipped copy already says this without naming anyone, so no copy change.
- **In the code:** `MapBasemap.STYLE_URI`, the credit `MapCopy.BASEMAP_ATTRIBUTION` rendered under the
  BTCMap line, and `TileHostGuardTest.APPROVED_VENDOR_HOSTS` naming `tiles.getbittr.com`'s stand-in by
  exact hostname. Going back to self-hosted tiles is that constant again.
