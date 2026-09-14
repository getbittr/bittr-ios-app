# Porting spec — Lightning extras (LNURL, Lightning address, channel chart, sync overlay, notes)

Research notes for the Android port, written from the iOS sources on 2026-09-14. iOS paths are under `ios/bittr/`.

## A. LNURL / Lightning addresses on Send

Files: `Move, Send, Receive/SendVC/SendLNURL.swift`, `Send/AddressParsing.swift` (15–81, `extractLNURL` 104–110),
`Send/SendVCTextFields.swift` (12–48), `Send/SendViewController.swift` (92–109, 302–329), `SendLightning.swift`
(31–138, 293–298), `Confirm/ConfirmSendViewController.swift` (82, 108–119).

Detection: `extractLNURL` splits on `&:?=` and returns the first component that `isValidEmail()` or starts with
`lnurl` (scan/paste lower-case first). Typed input: return in `send.toTextField` or Next → `handleLNURL`. Any edit
to the field clears pending LNURL state.

`handleLNURL(code:)`: show `loading.handlingLnurl` ("Handling lightning request", `handlinglnurl`). URL:
`name@domain` → `https://{domain}/.well-known/lnurlp/{name}`; text containing `tag=login&k1` used as-is; otherwise
bech32 decode (fail → 1 s → "LNURL status" / `lnurlfail3`). `GET url`, after 1 s dispatch on `tag`:
- `payRequest`: `callback`, `minSendable`, `maxSendable` (msat), optional `metadata` string.
- `withdrawRequest`: `callback`, `k1`, `minWithdrawable`, `maxWithdrawable`.
- `login`: `callback`, `k1`, optional `action`.
- unknown tag → `lnurlfail4` "We currently only support lightning pay and withdraw requests."; HTTP error →
  `lnurlfail3`.

Pay: description = last `["text/plain", x]` of `metadata` parsed as `[[String]]`. `min == max` → alert `payrequest`
"Pay request" / `payrequest1` "Are you sure you'd like to pay <payable> satoshis?" [Cancel, Confirm] →
`sendPayRequest`. `min != max` → store callback/description/min/max; if an amount is entered handle immediately,
else clear and focus the amount field (no popup). Next/Done with pending LNURL → `handleLNURLAmountCompletion`:
empty/zero → `alert.amountMissing` ("Invoice" / `amountmissing`); out of range → "Oops!" / `lnurlbetween` "Amount
must be between <min> and <max> satoshis." `sendPayRequest`: `GET {callback}?amount={msat}` (raw `?`); needs `pr`,
else "Pay request" / `lnurlfail2` "We could not complete your pay request. Error:" + `detail`/"Unexpected error".
With `pr`: `pendingLnurlInvoice = pr`, `pendingLnurlNote = description`, `checkSendLightning()` → Confirm.
Confirm shows the typed address (`send.confirm.addressLabel` = `e2ebittr@staging.getbittr.com`). After payment the
LNURL description is stored as a transaction note (`storeTransactionNote(txid: kind.transactionID ?? id, note:)`).
iOS does not verify the invoice against metadata hash or amount.

Withdraw: `min == max` → `withdrawrequest` "Withdraw request" / `withdrawrequest3` "Are you sure you'd like to
withdraw <withdrawable> satoshis?" [Cancel, Confirm]; else text-field alert `alert.withdrawRequest` (field
`alert.textField`, placeholder `amountinsatoshis` "Amount") with `withdrawrequest1` "You can withdraw between
<minwithdrawable> and <maxwithdrawable> satoshis. How many satoshis would you like to withdraw?"; invalid →
re-prompt with `withdrawoutofrange` "Please enter an amount within the range shown." `sendWithdrawRequest`: invoice
(amountMsat, description "", 3600 s; fail → `unexpectederror`/`invoicecreatefail`), `GET
{callback}?k1={k1}&pr={invoice}`, needs `status == "OK"` else `lnurlfail1` "We could not complete this withdraw
request. Error:" + `reason`. Success: no alert.

Auth: prompt `lnurl` "LNURL status" / `lnauth1` "<domain> wants to <action> with your lightning wallet. No bitcoin
will be sent. Would you like to proceed?" (action → Log in/Register/Link account/Authenticate). https only, `k1`
32 bytes. Seed = HMAC-SHA256(key = lower-cased trimmed mnemonic, msg `"bittr-lnurl-auth-seed-v1"`); linking key =
HMAC-SHA256(seed, lower-case host); DER secp256k1 signature over `k1`. `GET callback` with `k1`, `sig`, `key`
(compressed pubkey hex). `{status, reason}` → `lnauth2` "You've been successfully signed in." / `reason` or
`lnauth3` "We could not sign you in. Please try again."

## B. Receiving via Lightning address / LNURL

Receive `.lnurl` (`ReceiveViewController.swift` 157–166, 247–300, 449, 628–630, 644–651): default type no channel →
`.onchain`; channel + address → `.lnurl`; else `.bitcoinqr`. Address = first non-empty
`IbanEntity.lightningAddressUsername` (backend `lightning_address_username`, full `user@host`, cache key
`lightningaddressusername`). `receive.addressTitle` `url` "Address"; `receive.addressLabel` address or `unavailable`
"Unavailable"; QR hidden when absent; Copy copies it; cards Copy + More only. Picker [Cancel, Address, Bitcoin QR,
Create invoice, `showlnurl` "Lightning address"] (`alert.button.4`). Info `alertlnurl` "Lightning address" /
`alertmessagelnurl`.

`receive_lnurl.yaml`: unlock, Receive, `helpers/show_onchain_address.yaml`, `helpers/show_lnurl.yaml`,
`receive.addressLabel` visible, no edit/refresh; branch: text "Unavailable" + no `receive.qrImageView`, or QR +
`receive.addressLabel` ".+@.+[.].+"; question → `alert.button.0`; copy → Okay; `header.downButton`.

Incoming LNURL push (`Notifications/NotificationManager.swift:354–380`, `HandleLightningAddressNotification.swift`
13–131): payload `lightning_address_notification` with `amount_msats`, `metadata`, `time_sent`, `username`,
`endpoint`; dedupe repeats within 10 s. Missing field → drop. Locked → `wasNotified = true` + `alert.paymentRequest`
`paymentrequest` "Payment Request" / `paymentrequest2` "Someone wants to pay you <b><amount> satoshis</b>! Please
sign in to accept the payment." [Okay]. Signed in, not synced → `loading.syncingWallet` (`syncingwallet3` "syncing
wallet"); `finalizeSync` re-invokes. Synced, `!wasNotified` → `paymentrequest3` "Someone wants to pay you <b><amount>
satoshis</b>! Accept now or try again later in Device Details." [Cancel, `handlenow` "Handle now"]. Synced,
`wasNotified` → immediately: loading `generatinginvoice` "Generating invoice"; `descriptionHash =
hex(SHA256(utf8(metadata)))`; `receivePaymentWithHash(amountMsat, descriptionHash, 3600)`; `POST endpoint` JSON
`{invoice, amount_msats, description_hash, time_sent, username}`; success no alert; failure →
`alert.paymentRequestFailed` `paymentrequestfailed` "Payment Request Failed" / `paymentrequestfailed2` "We couldn't
process this payment request. If this keeps happening, please contact support@getbittr.com." [Okay].

`notification_lnurl.yaml`: launch (notifications allowed), `unlock.topLabel`, `resolve_lnurl.js` (GET
`/.well-known/lnurlp/{user}`), payload `amount_msats: 1500000`, `endpoint: "http://127.0.0.1:59999/e2e/lnurl-invoice"`,
repeat `push_notification.js` until `alert.paymentRequest` → `alert.button.0`; unlock; optional
`loading.syncingWallet`; `alert.paymentRequestFailed` (60 s) → `alert.button.0`; `home.headerLabel`.

## C. Channel statistics chart

`Question/QuestionViewController.swift` (1–140), from `move.channelButton` → `launchQuestion(question:
"lightningchannel", answer: "lightningexplanation1", type: "lightningexplanation")`. With an active channel
(`isChannelReady`): "Your balance" = `outboundCapacityMsat/1000 + (unspendablePunishmentReserve ?? 0)`; "Receive
limit" = `channelValueSats − outbound/1000 − reserve`; `totalLabel` "<channelValueSats> total, <reserve> reserve";
bar width = balance ÷ `channelValueSats`; text `questionvc7`. Without a channel: text card only. Ids
`question.yellowCard`, `question.answerLabel`, `question.channelView`.

## D. Sync status overlay

`Home/HomeViewController.swift:366–377` (`home.syncStatusButton`), `Core/SyncingStatus.swift`. Not synced → slide up
`sync.statusView` over 0.2-alpha dim with three rows, spinner → checkmark: `fetchconversionrates` "Fetch conversion
rates", `startlightningnode` "Start lightning node", `finalcalculations` "Final calculations"; auto-dismiss 0.5 s
after the final step, or `sync.closeButton`. Synced → Move (or `conversionfail`). `receive_onchain.yaml` taps
`"45%,20%"` and branches on `sync.statusView` / `move.subtitleLabel`.

## E. Transaction notes and descriptions

`Transaction/TransactionViewController.swift` 164–172, 391–405, 611–678, 686–698; `Cache/CacheManager.swift`
255–352. Cache keys: `hashes` (invoice timestamps), `descriptions`, `lightningfees`, `transactionnotes` (txid →
note). Lookups by `cacheIDs`: stable id, preimage/txid, payment id. Description row (`transaction.descriptionLabel`)
shows `lnDescription` (channel closure → `channelclosuretransaction`); hidden for swaps and payout confetti;
`transaction.descriptionButton` copies → `alert.copied`. Note: existing note → `transaction.labelNote`; else
`transaction.addNoteButton` "Add a note"; either opens `alert.addNote` (title/placeholder "Add a note", field
`alert.textField` prefilled, [Cancel, `save` "Save"]); trimmed non-empty stored, empty deleted. Card titles `note`
"Note", `description` "Description".

## F. `receive_invoice.yaml`, `send_lightning.yaml`

Both need an active channel. `receive_invoice`: Receive → More `alert.button.3` → `receive.invoiceLabel` `.*lnbcrt.*`;
copy; Send paste → "Invoice and amount", no amount; edit 2000 → paste → amount "2000"; 1000-sat invoice →
`submit_invoice.js` → `transaction.yellowCard`. `send_lightning`: Move → `move.channelButton` →
`question.channelView`; normal invoice via `request_invoice.js` + clipboard bridge (`clipboard_server.js` uses
`xcrun simctl pbcopy`; iOS "Allow Paste" prompt) → confirm → `transaction.yellowCard`; zero-amount invoice →
`alert.amountMissing` → currency Bitcoin → "0.00001" → Done → confirm; Lightning address
`e2ebittr@staging.getbittr.com` → Enter → wait `loading.handlingLnurl` gone → "1500" → Done → Confirm shows the
address → confirm.

## Already on Android

`:core:lnurl` (policy only: `LnurlDetector`, `LnurlEndpoint.validate` (https, no private hosts), `LnurlPay.next`,
`LnurlPayGate`, `LnurlSource` (QrScan/Deeplink/FirstPartyWeb), `LnurlAuth.parse/prompt` without signing);
`core/common/.../destination/Lnurl.kt`; `SendController` routes LNURL to `LNURL_NOT_ON_ANDROID`; WebView drops
lightning/lnurl schemes; `ReceiveSource.lightningAddress()` returns null (bittr account not ported);
`PushEnvelope.LightningAddress` decoded but unused; `LightningNodePort.receiveBolt11(… Hash …)`; `QuestionScreen`
text only; `TransactionScreen` without note/description; Home sync tap → alert.

## Decisions (recommended defaults)

1. Detect with `Destination`, then `LnurlDetector` + `LnurlEndpoint.validate` before any HTTP; add `:core:lnurl` to
   `:feature:send`.
2. Add `LnurlSource.ManualEntry` (pay/withdraw allowed).
3. Fixed amount → `payrequest1` alert; ranges → amount entry + Confirm page is the consent; fetch `pr` at Done, pay
   on confirm.
4. Check `pr` amount == requested and network; description-hash check logged, not blocking.
5. Build callback URLs properly (`&` when a query exists, URL-encode `pr`).
6. Store the LNURL description as a note (same cache keys and `cacheIDs` order).
7. LNURL-auth out of scope; never invent a new derivation.
8. Port withdraw with `alert.withdrawRequest` and re-prompt.
9. Port the Lightning-address push state machine; validate the pushed `endpoint` before POSTing.
10. Receive Lightning address blocked on the bittr account (`lightning_address_username`).
11. Build `sync.statusView` with three rows driven by engine events.
12. Channel chart with iOS formulas; extend `ChannelView` (outbound, reserve).
13. Android clipboard/push bridges for flows via adb.
