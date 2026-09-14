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
