# Porting spec — push handling, wallet removal, Settings/Device gaps, PIN flows

Research notes for the Android port, written from the iOS sources on 2026-09-14.

## A. Push notifications

**Receive and route** (`ios/bittr/Notifications/NotificationManager.swift`): `willPresent` shows `[.banner, .list]`
(not for swaps); `didReceive`/`didReceiveRemoteNotification` share the path. Parse (`:297-388`), first key wins:
`bittr_specific_data` → `.lightningPayout` (`notification_id`, `bitcoin_amount` BTC decimal → sats×1000);
`bittr_notification` → `.information` (`header_text` default `"oops"`, `body_text` default `bittrnotificationfail`);
`swap_notification` (`swap_id`, `status`); `htlc_notification` → `.htlcExpired` if `expired == true` (`header_text`,
`body_text`, `time_sent`) else `.htlcIncoming` (also when not a dictionary); `lightning_address_notification` →
`.lnUrl` (`amount_msats` Int, `metadata`, `time_sent`, `username`, `endpoint`); else `.unknown`. Dedup (`:18-37`):
cached `latestNotification`; ignore same id or within 10 s; handler runs 1 s later. Dispatch: payout →
`handlePayoutNotification`; information/unknown → `handleBittrNotification`; lnUrl →
`handleLightningAddressNotification`; htlcIncoming → `handleHTLCNotification`; htlcExpired →
`handleHTLCExpiredNotification`. While `!userHasSignedIn` handlers store `lightningNotification`, set `wasNotified`;
after unlock `lowerPinView` shows `loading.syncingWallet` if pending; `finalizeSync` re-dispatches swap, payout,
htlcIncoming, lnUrl (not information/htlcExpired).

**Loading overlay** (`AlertManager.swift:616-676`): non-dismissable card with spinner + bold text, id on the card;
a new message replaces the old one and moves the id. `loading.syncingWallet` `syncingwallet3` "syncing wallet";
`loading.receivingPayment` `receivingpayment` "receiving payment"; (no id) `generatinginvoice` "Generating invoice".
Alerts put their `id` on the card; buttons `alert.button.N` in `buttons:` order.

**HTLC incoming** (`HandlePaymentNotification.swift:39-141`): locked → stored; not synced → `loading.syncingWallet`;
synced → single-flight guard; if the push arrived while open → `alert.incomingPayment` "Incoming payment" /
`newbittrpayment` "You're receiving a new payment! Tap Okay to receive it now and continue what you're doing after."
[Okay] → `triggerHTLCReady`: `loading.receivingPayment`, 0.5 s → deposit code = first non-empty
`ibanEntities[].yourUniqueCode` (none → `bittrpayoutfail`); `nodeId()` nil → `bittrpayoutfail2`; sign
`"htlc_ready:<deposit_code>:<timestamp>"`; `POST {base}/htlc-interceptor/ready` JSON `{deposit_code, timestamp,
pubkey, signature}` → `{success, action, error}`: `action == "resumed"` no alert; `"failed_timeout"` →
`bittrpayoutfail`; error `"no_held_htlc"` → `htlcnoheld`; else `bittrpayoutfail2`. Terminal alerts id
`alert.incomingPayment`, [Close]. Copy `bittrpayoutfail` "The notification did not contain the data needed to
complete your payout."; `bittrpayoutfail2` "Something went wrong processing the notification we sent to
you.\n\nPlease wait for your wallet to sync, and try again. Or go to Settings > Device details, and try again from
there." Flow `notification_htlcincoming.yaml`: on `unlock.topLabel` push `{aps, htlc_notification:{}}`, 2.5 s,
unlock, optional loading ids, `alert.incomingPayment` (60 s) → `alert.button.0` → `home.headerLabel`.

**Information / expired / unknown** (`HandleBittrNotification.swift:12-16`): `launchQuestion(question:answer:)`
modal. `oops` "Oops!"; `bittrnotificationfail` "Something went wrong processing the notification we sent to you.
Please contact support@getbittr.com if you have any questions."; `htlc_expired_title` "Payment expired". Flow
`notification_information.yaml`: re-push until `question.yellowCard`; `header.titleLabel` "bittr update"
(**lowercased** by `addHeader`); `question.answerLabel` text; `header.downButton`; repeat for expired ("payment
expired") and unknown (aps only, "oops!").

**Lightning payout** (`HandlePaymentNotification.swift:13-37, 143-292`): locked → stored; not synced → loading;
synced + open → alert "Bittr payout" / `newbittrpayment` [Okay] → `triggerPayout`: `loading.receivingPayment`, 1 s;
needs `notificationID` and `amountMsat` (else `bittrpayoutfail`), `nodeId` (else `bittrpayoutfail2` [Close, Try
again]); not connected → `couldntconnect` [Close, Try again → reconnect]; invoice `getInvoice(amountMsat,
description: notificationId, 3600)` (cache timestamp + description); sign `notificationId`; `POST
{base}/payout/lightning?notification_id=&invoice=&signature=&pubkey=` (empty body) → `success, error, pre_image,
bitcoin_amount, fiat_amount, fiat_currency, error_code, suggested_swap_amount`; non-2xx → "Couldn't connect to Bittr
to complete payout. Please try again or check your connection."; error containing "try again" → [Tryagain];
`error_code == "CHANNEL_FULL"` → `insufficientfunds` [Receive onchain → `POST
{base}/payout/onchain?notification_id=&signature=&pubkey=`, Swap and receive instantly → swap]; completion on LDK
`.paymentReceived` → `checkPaymentWithBittr` → Transaction screen. `build_payout_push.js` sends
`bittr_specific_data:{notification_id, bitcoin_amount}` or `htlc_notification:{}` for the first deposit.

**LNURL push** (`HandleLightningAddressNotification.swift:13-130`): see `lightning-extras.md` §B.

**Simulator injection**: `push_notification.js` → `localhost:8888/push?bundleId=` → `push_server.js` → `xcrun simctl
push booted <bundleId> <file>`.

**Android today**: `PushEnvelopeDecoder` expects FCM `data` with one discriminator whose value is a JSON string
(same key order; non-object `htlc_notification` → `Unknown(NOT_AN_OBJECT)`, a divergence). `BittrMessagingService`
→ `dataMessageWake` (acts only on `bittr_wake`) → decode → `BittrPushDelivery.onPush` →
`MutableSharedFlow(replay = 1)` that **nothing collects**. No alert, overlay, dedup, replay or signing;
`PushModule.provideRequestSigner` returns null. `BittrAlertDialog` can't tag the card id. `TestID.Loading.*` unused.
`android/scripts/send-fcm-wake.sh` sends only `bittr_wake`.

**Android test injection**: FCM data values must be strings, e.g. `{"htlc_notification":"{}"}`,
`{"bittr_notification":"{\"header_text\":\"Bittr update\",\"body_text\":\"…\"}"}`. Bridge: `push_server.js` Android
mode → `adb shell am broadcast -a com.bittr.android.DEBUG_PUSH --es <discriminator> '<json>'` → debug-only receiver →
`PushEnvelopeDecoder.decode` → `pushDelivery.onPush`. Emulator host is `10.0.2.2`.

## B. Wallet removal

`Core/ResetApp.swift:41-119` `restoreWalletTapped`, from `device.row.restore`, `signup.restore.removeWalletButton`,
the 10th wrong PIN, and after `finalizeSync`:
1. Not synced: `resettingPin` → "Remove wallet" / `removewallet1` "Are you sure you want to remove this wallet from
   your device?\n\nYou can restore the wallet using your recovery phrase." [Cancel, Remove wallet →
   `startWalletInBackground`]; incorrect-PIN wipe → `startWalletInBackground`; else `alert.syncingWallet`.
2. Synced and `!channelsFullyClosedAndSwept()`: active channel, manual → `restorewallet4` "Please close your
   lightning connection(s) before removing your wallet from this device.\n\nOtherwise, you may lose access to the
   funds in your lightning connection." [Cancel, Close connection(s)] → `closechannel2` "If you close your lightning
   connection(s), its funds will be deposited back into your wallet.\n\nPlease wait for this transaction to show up,
   before definitively removing this wallet from your device." [Cancel, Close connection(s)] →
   `closeChannelConfirmed`; lockout → `closeChannelConfirmed` immediately; closed but not swept → lockout
   `stillclosing` [Try again] / manual `walletRemovalInProgress = true` + `stillclosing` [Okay].
3. Synced and swept: `resettingPin` or lockout → `performWalletReset`; else `restorewallet2` "Are you sure you'd like
   to remove this wallet from your device?\n\nOnly remove your wallet if you're sure you've properly backed up your
   wallet." [Cancel, Remove] → `restorewallet3` "Are you sure you want to remove your wallet from this device?"
   [Cancel, Remove] → `performWalletReset`.

`closeChannelConfirmed` (`:153-239`): manual sets `walletRemovalInProgress`; connect if needed (fail: lockout
`closeretrylater` [Try again], manual → `forceCloseChannel`); cooperative close; throws manual → `closechannel6`
"Connection Closure Issue" / `closechannel7` [Cancel, Force Close]; success → `didCloseChannel()` → `stillclosing`
[Okay] (manual) / [Try again] (lockout), title `restorewallet`. LDK `.channelClosed` → Question "closed lightning
connection" / `closedlightningchannel2` (not on the incorrect-PIN wipe). `forceCloseChannel` (`:241-292`): fail
`forceclose3`, success `forceclose4`, never wipes. `performWalletReset` (`:294-400`): stop sync, stop node, delete
documents, reset node state (fail → restore flags + `removalfailed`), delete client info, clear
`walletRemovalInProgress`, after 1 s `launchSignup(onPage: 3)` (`signup.create.start.createWalletButton`). Launch
resume (`CoreViewController.checkWalletRemoval`): ≥ 10 failures → `pinlock` + start; `walletRemovalInProgress` →
`removalinprogress` [Cancel, Remove wallet → `resettingPin = true`].

Flows: `remove_wallet.yaml` (reads `move.satsInstant`; `nav.settingsButton` → `settings.row.device` →
`device.row.restore`; channel arc `alert.button.1`×2, `question.yellowCard` → down, `alert.button.0`, mine 6, pull,
`move.satsInstant` "0 sats", `history.transactionButton0` → `transaction.descriptionLabel` `.*closed lightning
connection.*`, restore again; tail `alert.button.1`×2 → `signup.create.start.createWalletButton` 30 s).
`forgot_pin_remove_wallet.yaml` (`pin.restoreButton` → `alert.button.1` → `signup.restore.topLabel` →
`signup.restore.removeWalletButton` → `alert.button.1` → channel branch → `signup.create.start.createWalletButton`
120 s).

Android today: `WalletService.removeWallet()` erases key material; `NodeBackedWalletService.removeWallet` = node down
→ wipe node state → seed removal, **no channel gate**; `WipeSafety.channelsFullyClosedAndSwept` unused outside
tests; `device.row.restore` → one-button "Syncing wallet" (`nodeIsUp` hard-coded false); `RestoreScreen` has no
`removeWalletButton`; missing strings; no resume flag.

## C. Settings / Device status

iOS row order: darkmode, language, currency, devicetoken, publickey, bittrpeer, pendingpayouts, lightningchannels,
restore. Token alert "Device token" [Copy 0, Close 1]. `pendingpayouts`: `GET
{base}/notifications?timestamp=&signature=&pubkey=` signing `"notifications:<pubkey>:<timestamp>"`, keep `data[]`
with `notification_type=="payout"` and `status=="sent"`, `bittrpendingpayout2` or `bittrpendingpayout3` [Cancel,
Confirm → `handlePayoutNotification`]. `bittrpeer`: `bittrpeer2` "You're connected to bittr." [Okay] or `bittrpeer3`
[Close, Connect]. Android: publickey/bittrpeer/pendingpayouts show the one-button syncing alert (fake passes /
fails); devicetoken launches only `POST_NOTIFICATIONS`.

## D. PIN flows

iOS `Pin/PinViewController.swift:119-214`: < 4 digits `alert.pinRequired`; ≥ 10 failures → remove; correct → reset
counter, start; wrong → increment; 10 → `pinlock` + `restoreWalletTapped`; exactly 3 → `pinwarning` "Warning" /
`pinwarning2` + attempts [Okay 0, Forgot PIN 1]; else `incorrectpin` [Okay]. Forgot PIN `forgotpin`/`forgotpin2`
[Cancel 0, Reset 1]. Android `UnlockViewModel` matches order, copy and indexes. `pin_warning.yaml`,
`forgot_pin.yaml`, `wrong_pin.yaml` covered; `wrong_pin_with_channel.yaml` not (Android wipes without closing).

## Decisions (recommended defaults)

1. One `WalletRemovalCoordinator` porting `restoreWalletTapped`/`closeChannelConfirmed`/`performWalletReset`, gated
   on `WipeSafety`; no UI calls `removeWallet()` directly; no node → refuse and retry.
2. Persisted last-notification cache (handled flag, 10 s/id dedup, pending dispatched after unlock and sync).
3. Tag alert cards; buttons in iOS array order.
4. App-level loading overlay host `(id, message)`.
5. Debug-only broadcast receiver + `push_server.js` Android mode; `send-fcm-wake.sh --data-file` smoke test.
6. Show the "Oops!" card for `Unknown` (not for `bittr_wake`-only messages).
7. Lowercase question header titles.
8. No system notification in the foreground.
9. Persist `walletRemovalInProgress` (no backup), prompt at unlock.
10. Port node-backed Device rows once the node is up.
11. Manual force close only; never on the lockout path.
