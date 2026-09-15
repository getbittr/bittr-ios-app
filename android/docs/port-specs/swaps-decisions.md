# Swaps port — decisions, questions and gaps

The calls made while porting `ios/bittr/Swaps` to `:core:swaps` / `:feature:swap` (branch `port/swaps`,
2026-09-14). Read with `swaps.md`.

## Decided

1. **Crypto on bitcoin-kmp, no new dependency.** MuSig2 (`KeyAggCache`, `SecretNonce`, `Session`), the
   Taproot tweak and BIP341 sighash come from bitcoin-kmp 0.31 / secp256k1-kmp 0.23. Keys aggregate
   **unsorted, Boltz first**, as iOS does; a test proves the order changes the address. Tap tree, tweak
   and output key are cross-checked against bitcoin-kmp's own `ScriptTree` and `XonlyPublicKey.outputKey`.
2. **Verify before broadcast (addition).** Boltz's partial signature is verified, and the aggregate
   signature is checked against the lockup output key, before a claim or refund is broadcast. iOS
   broadcasts unchecked. No behaviour change on the happy path; a bad signature becomes a named failure.
3. **Claim/refund shape kept:** version 1, one input (claim `0xfffffffd`, refund `0xfffffffe`), one output,
   64-zero-byte witness placeholder in the transaction shown to Boltz, fee = fastest × 99 vB (last known
   rate, then 50 sat/vB). The underfunded-lockup refusal (`amount + claimFee − max(amount/100, 1000)`) is ported.
4. **Every validation check ported unchanged** (`BoltzSwapValidation`), with the evil-Boltz cases
   (substituted address, foreign key in the leaf, wrong preimage hash, wrong invoice hash, quote bounds) as
   JVM tests instead of a DEBUG harness build. The `-evilBoltz` launch-argument harness is **not** ported.
5. **Swap file:** iOS's JSON keys, `sha256(boltzID).json` with the legacy plaintext name as a fallback,
   in `filesDir/swaps` (app-private, backup is off app-wide). The refund key stays plaintext in it, as on
   iOS (rescue artifact). The latest-swap cache sits in the same directory; there is no Keychain-stripped
   second copy because both locations are app-private.
6. **The coordinator runs in the process scope**, not the screen's: the websocket subscription, claim and
   refund continue if the user leaves the swap screen. iOS ties them to the view controller.
7. **Swap index:** `nextSwapIndex()` increments before every attempt and returns the new value (first is 1),
   as `CacheManager.incrementSwapIndex()`. Not environment-scoped separately: debug and release are
   different application ids, so their stores are already separate.
8. **Notification gate:** a swap needs an FCM token and a minted webhook URL (`BoltzWebhookMinter` over the
   existing `BoltzWebhook` request, cached per token in `PrefsBoltzWebhookCache`). Okay on
   `alert.notificationsRequired` opens the app's notification settings (iOS asks for the permission).
9. **Suggested swaps skip the screen's amount checks**, matching iOS, which calls `SwapManager` directly for
   Swap & Pay (so an onchain→lightning swap works with no channel).
10. **"Download details"** shares the swap JSON as text (`ACTION_SEND`), not as a file, so no FileProvider
    is needed.
11. **Swipe down closes Move and Swap** (`Modifier.dismissOnPullDown`, pulling past the top of the scroll):
    the flows leave iOS sheets with `swipe: DOWN`.
12. **Status "?" and "why a limit" open alerts**, not the Question card iOS presents.
13. **Send's Swap & Pay for an invoice** compares against the on-chain *spendable* balance (Send's source has
    no total on-chain figure); iOS compares against `satoshisOnchain`.
14. `ChannelView` gains `inboundHtlcMaximumMsat` (the per-swap ceiling iOS checks); defaulted so existing
    fixtures compile.
15. **Esplora URLs are host + `/api`.** The production Esplora host is `esplora.getbittr.com`, and
    `ApiBaseUrlGuardTest` reserves `…getbittr.com/api` literals for `BittrEnvironment`. The explorer is not
    the bittr API, so `BoltzEndpoints` keeps the host and appends the path rather than widening the guard.

## Questions

1. **FCM token on the test emulator.** Without a Firebase token every swap stops at
   `alert.notificationsRequired`; `swap.yaml` then tries to reprovision the wallet. Is the emulator build
   expected to get a real FCM token (google-services + Play services image)?
2. Should Android refund/claim in the background after a push when the app is not open? iOS does not; the
   `SwapPushHandler` would allow it once the notifications port wires pushes through.

## Gaps (not ported yet)

1. **History labels and merged swap rows** (`SwapMatching.swift`, `history.swapPending<N>` /
   `history.swapComplete<N>`): Android's history has no description cache, so `recordDescription` is logged
   only and the two legs show as separate rows. `swap.yaml`'s `history.swapPending0` wait passes vacuously.
2. **Transaction screen swap stack** (`transaction.swapStatusButton`): needs the dateID → Boltz id link from
   the description cache. `SwapRoutes.status(boltzId)` and `SwapCoordinator.statusOf` are ready for it.
3. **Swap from a bittr payout push** (`pendingSuggestedSwapAmount`) — belongs with the payout notification port.
4. **Live Activity / Dynamic Island** — no Android counterpart built (an ongoing notification would be the analogue).
5. Script-path (timeout) refunds and retries of a failed cooperative refund — not on iOS either.

## Swap history and pushes (branch `port/swap-history`, 2026-09-15)

1. **Decided — one description store for the whole history** (`TransactionDescriptionStore`, `transaction_descriptions.json`
   in the app's files directory, like iOS's `invoicedescriptions` in `UserDefaults`). Keys are what iOS keys by: the
   payment hash for Lightning (Receive stores each invoice's description; `WalletActivity.paymentHash` is new so a paid
   row whose id is its preimage still finds it) and the txid on-chain. Swaps write their `dateID` through
   `SwapWallet.recordDescription`, which only logged before.
2. **Decided — `performSwapMatching()` runs in a decorated `WalletOverviewSource`** (`history/HistoryModule`): the node's
   overview gets its descriptions, then legs sharing a "Swap …" description become one row (id = the date part, iOS's),
   a lone leg a pending swap row, and a Swap & Pay leg keeps its row with the suggested swap's status. Everything that
   injects `WalletOverviewSource` sees matched rows; the swap wallet adapter and the event pump still read the raw
   overview through the composition. Not ported: iOS's cache of completed combined rows
   (`CacheManager.storeLightningTransaction`), which Android doesn't need because it recomputes from the legs.
3. **Decided — history rows show the swap icon** (`history.swapComplete<N>` / `history.swapPending<N>`), and the transaction
   screen shows Swap ID, Swap status (`transaction.swapStatusButton` → the status screen) and the second id row
   (`transaction.copyBottomIdButton`), per iOS's direction/status table. A swap's "Fees paid" is its total cost
   (sent − received + fees). **Gap:** a Swap & Pay leg doesn't yet show iOS's bottom id and the amount from the swap
   file (it shows its own amount and id plus the swap stack); a pending swap's amount isn't read from the swap file.
4. **Decided — "Swap & Instant Receive" opens a lightning-to-onchain swap of the suggested amount straight away**
   (`SwapRoutes.payoutSwap`, iOS `handleNotificationSwap`), not a suggested swap.
5. **Decided (decision 30) — a swap push matches iOS and never claims or refunds:** ignored while a swap screen is open;
   locked → `swapstatusupdate` / `pleasesignin` alert and the push is kept; syncing → `loading.syncingWallet`; synced →
   the latest swap's status screen opens, only while the app is on screen (`AppForeground`, set from `MainActivity`'s
   start/stop). `SwapCoordinator` is no longer bound as the push handler; claims and refunds stay with the swap screens
   and the coordinator's status tracking.
