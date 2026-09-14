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
