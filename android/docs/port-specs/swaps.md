# Porting spec — swaps between on-chain and Lightning (Boltz)

Research notes for the Android port, written from the iOS sources on 2026-09-14. Paths are under `ios/bittr/`
unless stated. See `shared/docs/android-port-decisions.md` for the calls made while implementing.

## 1. iOS sources

| File | Role / key lines |
|---|---|
| `Swaps/SwapVC/SwapViewController.swift` | Swap screen. `nextTapped` 117-174, `showStatusView` 176-200, `confirmExpectedFees` 218-252, `proceedWithSwap` 260-293, `didVerifyBoltzInvoice` 295-298, pending entry points 88-104 / 334-411, `cancelSwap(alertID:)` 421 |
| `Swaps/SwapVC/SwapDirection.swift` | direction picker alert |
| `Swaps/SwapVC/SendableAmount.swift` | `calculateSendableAmount` 51-195 (max per direction), `startSuggestedOnchainToLightningSwap` 199+ |
| `Swaps/SwapVC/SwapVCLanguage.swift` | copy, test ids, keyboard "Done" accessory |
| `Swaps/SwapStatusVC/SwapStatusViewController.swift` | status card; `setSwap` 90-132, `receivedStatusUpdate` 183-220, `handleTransactionMempool` (claim) 230-283, refresh 285-352, `didCompleteOnchainTransaction` 354-368, download 376-401, status "?" answers 403-469, `userFriendlyStatus` 509-534 |
| `Swaps/Swap Manager/SwapManager.swift` | webhook mint 38-84, fee quote 121-152, `onchainToLightning` 154-322, `checkOnchainFees` 324-434, `sendOnchainPayment` 436-499, `checkSwapStatus` 519-545, `lightningToOnchain` 547-713, file persistence 736-816, `openCompletedSwapTransaction` 828-880, `checkReverseSwapFees` 913-967, `didReceivePaymentHash` 969-1000 |
| `Swaps/Swap Manager/BoltzRefund.swift` | claim 56-221, cooperative refund 236-394, `BoltzSwapValidation` 478-733, RIPEMD160 747+ |
| `Swaps/Swap Manager/BoltzSwiftSDK.swift` | bech32(m), tx parser, `detectSwap`, `BoltzClaimTransaction` (serialise + BIP341 sighash 853-928), `computeTapLeafHash` 1108-1146, `constructClaimTransaction` 1065-1106 |
| `Swaps/Swap Manager/BoltzAPI.swift` | claim/refund/broadcast HTTP |
| `Swaps/Swap Manager/WebSocketManager.swift` | Boltz websocket |
| `Swaps/Swap.swift` | model, fee maths, dictionary round-trip |
| `Helpers/EvilBoltz.swift` | DEBUG harness tampering with Boltz responses |
| `Home/SwapMatching.swift` | merges the two legs into one history row |

Where swaps are offered: Move (`MoveViewController.swift:163-171`; no channels → `instantpayments`/`questionvc13`
alert, else segue `MoveToSwap`); Send Lightning invoice short on outbound but on-chain covers it
(`SendLightning.swift:145-157`, "Swap & Pay" → `CoreToSwap` with `isFromLightningPayment`/`pendingLightningInvoice`);
Send on-chain short but Lightning covers it (`SendOnchain.swift:50-72`, `SendToSwap` with
`pendingOnchainAddress`/`pendingOnchainAmount`); bittr payout push `pendingSuggestedSwapAmount`; history swap rows
(`HistoryTable.swift:118-134`: `iconswapblue` + `history.swapComplete<row>` when succeeded, else `iconswapgrey` +
`history.swapPending<row>`); Transaction screen swap stack (`TransactionViewController.swift:38-47, 258-331`,
`transaction.swapStatusButton` → SwapStatus standalone); `.swap` push (`HandlePaymentNotification.swift:602-668`).

Swap screen: header "swap funds"; card: subtitle, "Move", amount field ("Enter amount of satoshis"), direction pill
(`fromLabel`/`fromButton`), "Move up to <amount> sats." + "?", Next (spinner), "Powered by" + Boltz logo (alert).
SwapStatus slides in inside the same controller: Direction / Amount / Fees / Status rows, refresh, status "?",
"Download details".

State machine: Next → guards (BDK scanned for on-chain→LN; amount > 0; amount ≤ `inboundHtlcMaximumMsat/1000`;
per-direction max: on-chain→LN ≥ max → drain mode, LN→on-chain > max → "exceeded" alert) → spinner → create swap
(key derivation, push-token gate `alert.notificationsRequired`, webhook mint, Boltz POST, validation — failure →
`alert.swapValidationFailed`) → fees alert [Cancel, Proceed] → Proceed: save latest swap, show status;
on-chain→LN: BDK broadcast to lockup address, fetch raw hex, websocket after 2 s; LN→on-chain: re-verify invoice
hash, pay via LDK, check payment after 3 s, websocket → status updates → `openCompletedSwapTransaction` (waits up
to 4×5 s for both legs in `listPayments`, one sync) → Transaction screen.

## 2. Boltz protocol

Base URLs (`Helpers/EnvironmentConfig.swift:79-96`; Debug = regtest):

| | Regtest/dev | Mainnet |
|---|---|---|
| REST | `https://boltz-api.bittr.io/v2` | `https://api.boltz.exchange/v2` |
| WS | `wss://boltz-api.bittr.io/v2/ws` | `wss://api.boltz.exchange/v2/ws` |
| Esplora | `https://esplora-regtest.bittr.io/api` | `https://esplora.getbittr.com/api` |

| Method + path | Request | Response fields used |
|---|---|---|
| `GET /swap/submarine` | – | `BTC.BTC.fees.percentage`, `BTC.BTC.fees.minerFees` (int) |
| `GET /swap/reverse` | – | `BTC.BTC.fees.percentage`, `BTC.BTC.fees.minerFees.lockup` (fallback `.claim`) |
| `POST /swap/submarine` | `{from:"BTC", to:"BTC", invoice, refundPublicKey, webhook:{url, hashSwapId:true}}` | `id, address, expectedAmount, claimPublicKey, swapTree.claimLeaf.output, swapTree.refundLeaf.output` |
| `POST /swap/reverse` | `{from, to, claimPublicKey, preimageHash, onchainAmount, webhook:{url, hashSwapId:true, status:["transaction.mempool","transaction.confirmed","invoice.settled","swap.expired","transaction.failed"]}}` | `id, invoice, lockupAddress, refundPublicKey, swapTree.claimLeaf.output, swapTree.refundLeaf.output` |
| `GET /swap/{id}` | – | `status`, `transaction.hex` |
| `POST /swap/reverse/{id}/claim` | `{index:0, transaction:<unsigned hex>, preimage, pubNonce}` | `pubNonce, partialSignature, error` |
| `POST /swap/submarine/{id}/refund` | `{pubNonce, transaction, index:0}` | `pubNonce, partialSignature, error` |
| `POST /chain/BTC/transaction` | `{hex}` | `transactionId`/`txid`/`id` (or bare string); 200/201 |
| Esplora `GET /tx/{txid}/hex` | – | raw hex (6 retries, 1.5 s) |

bittr backend (already ported on Android): `GET {bittrAPI}/boltz/webhook-token?pubkey&timestamp&signature`
(signature = LN node key over `boltz_webhook:<pubkey>:<ts>`) → `{success, url, device_token}`; cached per device
token, re-minted if the URL contains `?`. `POST /boltz/live-activity-token` (live activities only).

Submarine (on-chain → LN): id `createDateId()` (`yyyyMMddHHmmss`), `dateID = "Swap onchain to lightning <id>"`;
LDK invoice (`amountMsat`, description = dateID, expiry 3600; suggested swap uses recipient invoice); key
`m/503'/0'/0'/0/<CacheManager.incrementSwapIndex()>` → `refundPublicKey`; POST; validate
(`validateSubmarineLockup`, `validateQuotedAmount(requested: invoiceSats, quoted: expectedAmount)`); fees: normal =
BDK `getSize` × fastest rate, `lightningFees = expectedAmount − amount`; drain = `maximumSendableOnchainDrain`;
proceed: BDK send `expectedAmount` (or send-all), fetch lockup hex, store; websocket; on `invoice.failedToPay` /
`transaction.lockupFailed` → cooperative refund.

Reverse (LN → on-chain): claim fee `fastest sat/vB × 99` (fallback last rate, then 50); `onchainAmount = amount +
claimFee`; 32-byte random preimage, `preimageHash = SHA256`; key same path → `claimPublicKey`; destination = next
unused address (or payout address); POST; validate (`validateReverseInvoice`, `validateReverseLockup`); fees
`onchainFees = invoiceSats − amount`, routing fee from invoice route hints; proceed re-checks invoice payment hash
== sha256(preimage), pays via LDK; on WS `transaction.mempool` with `transaction.hex` (or refresh on
`transaction.confirmed`/`invoice.settled`) → claim.

Keys/tree/MuSig: `agg = MuSig.aggregate([boltzKey, ourKey], sortKeys:false)` (Boltz first); `leafHash =
taggedHash("TapLeaf", 0xC0 || compactSize(script))`; branch `taggedHash("TapBranch", sorted(l,r))`; `tweak =
taggedHash("TapTweak", xonly(agg) || root)`; `outputKey = xonlyTweakAdd(agg, tweak)`; lockup = P2TR `51 20
<outputKey>`. Claim and refund spend the **key path only**: tx version 1, one input (sequence `0xfffffffd`; refund
`0xfffffffe`, locktime 0), one output `value − fee`; BIP341 `SIGHASH_DEFAULT`; our MuSig nonce → Boltz → aggregate
partial sigs → 64-byte witness. `detectSwap` finds the output matching `outputKey`. Claim refused when underfunded:
lockup must be ≥ `amount + claimFee − max(amount/100, 1000)`.

Validation (`BoltzRefund.swift:478-733`) — any throw → `cancelSwap(alertID: "alert.swapValidationFailed", title
"Error", message swapvalidationfailed, [Okay])`, before any funds move:
- wrong address (submarine): rebuilt P2TR script must equal the decoded `address` (`lockupAddressMismatch`); refund
  leaf must start `20<our x-only key>` (`ourKeyMissingFromLeaf`).
- wrong invoice (reverse): invoice parses with an amount; `paymentHash` == submitted `preimageHash`
  (`paymentHashMismatch`).
- reverse lockup: address matches; claim leaf ends `20<our x-only>ac`; claim leaf is exactly
  `82 01 20 88 a9 14 <h160> 88 20 <32> ac` with `h160 == RIPEMD160(SHA256(preimage))`.
- amounts: `requested ≤ quoted ≤ requested + ceil(requested×pct/100) + minerFee + max(requested/100, 1000)`; with
  no quote the ceiling is `2×requested`.

Status: WS `{"op":"subscribe","channel":"swap.update","args":[id]}`, status at `args[0].status`; reconnect 3 s
after close while active; initial `GET /swap/{id}` 2 s after the status view; refresh = same GET. iOS does **not**
implement script-path (timeout) refunds, retries of failed cooperative refunds, or background claims.

## 3. Persistence

Swap file `Documents/<sha256(boltzID)>.json` (legacy `<boltzID>.json`), pretty JSON of `Swap.toDictionary()`:
`dateID, onchainToLightning, satoshisAmount, isSuggested, createdInvoice, privateKey, boltzID, boltzExpectedAmount,
onchainFees, lightningFees, feeHigh, claimTransactionFee, sentOnchainTransactionID, boltzOnchainAddress,
refundPublicKey, claimLeafOutput, refundLeafOutput, claimPublicKey, preimage, destinationAddress, boltzInvoice,
lockupTx` (private key deliberately plaintext — Boltz rescue file). Cache keys: `swapids` (dateID→boltzID),
`suggestedswaps` (dateID→`pending|succeeded|failed`), `ongoingswap` (key stripped to Keychain `swapkey_<boltzID>`),
`swapindex` (env-scoped), plus `storeInvoiceDescription(preimage: txid|preimageHash, desc: dateID)`,
`storePaymentFees`, Boltz webhook URL/token. `SwapMatching.swift` groups transactions whose `lnDescription` contains
"Swap" by description into one combined row.

## 4. Crypto on Android

No new dependency needed: bitcoin-kmp-jvm 0.31.0 (`fr.acinq.bitcoin.crypto.musig2.{Musig2, KeyAggCache, SecretNonce,
IndividualNonce, AggregatedNonce, Session}`, `ScriptTree`, `Crypto.TaprootTweak`, `Transaction` BIP341 sighash,
`Bech32`, `Ripemd160`, `Script`) and secp256k1-kmp 0.23.0 (`musigPubkeyAgg`, `musigPubkeyXonlyTweakAdd`,
`musigNonceGen`, `musigNonceAgg`, `musigPartialSign`, `musigPartialSigAgg`); bdk-android 1.2.0 and
ldk-node-android 0.7.0 for send/invoice/pay.

## 5. Copy and test ids

Copy (`Language.swift` 340-427, 581-584): `swapfunds` "swap funds"; `swapsubtitle` "Move satoshis between your
bitcoin wallet and your bitcoin lightning connection."; `move` "Move"; `onchaintolightning` "Onchain to Lightning";
`lightningtoonchain` "Lightning to Onchain"; `swapdirection` "I'd like to move my funds from..."; `satsatatime`
"Move up to <amount> sats."; `enteramountofsatoshis` "Enter amount of satoshis"; `swapamountexceeded` "You can only
move up to <amount> satoshis at a time. Please enter an amount within this limit."; `swapfunds3` "The expected fee
to move <b><amount> satoshis</b> (<convertedamount>) is <b><feesamount> satoshis</b> (<convertedfees>).";
`swapfunds3range` "…is between <b><feesamountmin> and <feesamount> satoshis</b> (<convertedfees>).";
`onchaintolightningexplanation` "\n\nIt may take around <b>10 minutes</b> to complete this swap. You may close the
app in the meantime.\n\nIf the swap fails, some of the paid fees may not be refundable."; `wishtoproceed` "Do you
wish to proceed?"; `proceed` "Proceed"; `swaperror2` "We encountered some issue while processing your swap. No
funds have been swapped. Please try again."; `swapvalidationfailed` "We could not verify the swap details we
received. No funds have been sent. Please try again."; `notificationsrequired` "Notifications Required"; statuses
`swapstatuspreparing` "Preparing", `swapstatusawaitingconfirmation` "Waiting to be mined",
`swapstatusawaitingpayment` "Awaiting payment", `swapstatusinvoicepending` "Awaiting swap payout",
`swapstatusswapcomplete` "Swap complete", `swapstatusclaiming` "Claiming your bitcoin", `swapstatusfailedtopay`
"Swap failed (couldn't pay invoice)", `swapstatusexpired` "Swap expired", `swapstatusincorrectamount` "Swap failed
(incorrect amount)", `swapstatusawaitingtransaction` "Awaiting transaction", `swapstatusinvoicexpired` "Swap failed
(invoice expired)", `swapstatusfailed` "Swap failed"; `swapandpay` "Swap & Pay"; `swapinsufficientfunds`,
`swapinsufficientfundslightning`; `swapid` "Swap ID"; `swapstatus` "Swap status"; `swapsucceeded` "Complete";
`swappending` "Pending"; `swapfailed` "Failed and refunded"; `downloadswapfile` "Download details"; `poweredbyboltz`
"Powered by"; `boltzexplanation3` "Powered by Boltz"; `boltzexplanation` "<b>Boltz.exchange</b> is a non-custodial
bitcoin bridge. It enables you to swap funds between bitcoin layers, while staying in full control of your money."

Test ids (all in `android/core/common/.../TestIDs.kt`): `swap.subtitleLabel, amountTextField, nextButton,
fromLabel, fromButton`; `swapStatus.confirmCard, confirmStatusLabel, refreshButton`; `history.swapPending<N>,
swapComplete<N>`; `move.swapButton`; `transaction.swapStatusButton`; `alert.swapValidationFailed`,
`alert.notificationsRequired`.

## 6. Flows

- `features/swap.yaml` (needs a channel from `buy_incoming.yaml`): leg 1 via `helpers/swap_leg1.yaml` (balance card →
  `move.swapButton` → 75000 → "Done" → `swap.nextButton`); `alert.notificationsRequired` → reprovision; Proceed
  `alert.button.1`; "Swap complete" (mine 1); Home, `history.swapPending0` gone. Reverse leg 50000 via
  `swap.fromButton` → `alert.button.1`; wait "Move up to 0 sats." gone. Then transaction screen checks
  (`transaction.swapStatusButton` → `swapStatus.confirmCard`, copy id, url id, copy bottom id, add note).
- `send_swap_suggestion_onchain.yaml`: regular < 50000, instant > 75000; paste own address, amount, Swap & Pay
  `alert.button.1`, fees `alert.button.1`, "Swap complete".
- `send_swap_suggestion_lightning.yaml`: on-chain ≥ 50000, no channel; paste 50000-sat invoice, next, `alert.button.1`
  ×2, `swapStatus.confirmCard`, refresh, "Swap complete".
- `evil_boltz_wrong_invoice.yaml` / `evil_boltz_wrong_address.yaml` (`${EVIL_APP_ID}`): swap leg →
  `alert.swapValidationFailed` → Okay; `swapStatus.confirmCard` not visible, `swap.nextButton` visible. Evil
  harness: launch arg `-evilBoltz wrong-invoice|wrong-address|all`; attacker address
  `bcrt1pcz9mae53csyv8d0t4fansh446jdjey2pg2djn5utqver5e42gp5s507k3j`; fake invoice from `{bittrAPI}/e2e/invoice`.

## 7. Already on Android

`MoveScreen` swap button stub; `SendController` notes swap suggestions unported; `Bip84Account.swapRefundKey`
(`m/503'/0'/0'/0/<i>`, tested); `DeviceTokenApi` Boltz webhook mint + `DeviceTokenLifecycle`; `PushEnvelope.Swap`;
Swap Live Update contract tests; all test ids.

## 8. Decisions to make (recommended defaults)

1. Use bitcoin-kmp Musig2/Taproot + secp256k1-kmp; build golden vectors from iOS first (agg key, tweak, output key,
   sighash, final tx) as JVM tests.
2. Keep key order `[boltzKey, ourKey]` unsorted and the x-only tweak; a mismatch yields wrong addresses that
   validation rejects.
3. Keep iOS's claim tx shape (v1, one output, sequence `fffffffd`, fixed 99 vB fee).
4. Port every validation check unchanged into a pure JVM `BoltzSwapValidation` with tampered-response tests; raise
   `alert.swapValidationFailed` before fees or payment.
5. Cooperative refund only (parity); persist `timeoutBlockHeight`; follow-up for timeout refund and background claim.
6. Keep the swap JSON schema and `sha256(boltzID)` filename in app-private storage; export via share sheet.
7. Increment the swap index before every attempt, env-scoped.
8. Notification gate: require an FCM token + minted webhook URL, same `alert.notificationsRequired` copy.
9. OkHttp WebSocket while the status screen is foreground, reconnect after 3 s, refresh = GET.
10. Keep dateID strings for leg matching.
11. Port `SendableAmount` max-amount formulas verbatim.
12. Evil build: debug-only flavour/interceptor behind a flag, guarded out of release.
