# Buy, bittr signup and Profits — port decisions

Written during the overnight port (2026-09-14/15), branch `port/buy`. The format is **Decided** (a call I made and why), **Question** (needs a product or backend answer), **Gap** (not ported or known to differ).

## Decided

1. **Buy and its signup are one destination.** iOS presents `RegisterIbanViewController` modally over `BuyViewController` and dismisses back to it. On Android, `BuyRoute` holds the signup container as state, so after the final "Done" the Buy cards (`buy.yourCode`) are already on screen, as `buy_signup.yaml` expects. System Back closes the signup.
2. **Alerts are drawn inside the screen, not in a dialog window.** Maestro reads only the focused window, and these alerts need the card ids (`alert.copied`, `alert.lightningExplanation`, `alert.resendCode`, `alert.onlyIban`, `alert.receiveNotificationsPrompt/Denied`, `alert.exclusiveInitiative`). `BuyAlertCard` puts the id on the card and `alert.button.N` on the buttons, in iOS's order.
3. **Responses are read the way iOS's `CallsManager.makeApiCall` reads them.** Any JSON object body counts as an answer whatever the HTTP status, so server messages like "Invalid 2FA verification token provided" reach the screen. `GET /transaction_info` is the exception: iOS decodes it strictly, so it needs a 2xx and `success: true`.
4. **No push token halts the signup, as on iOS** (Ruben, 2026-09-15: "if we don't have a device token we should halt the signup and ask the user if they then only want onchain payouts"). With notifications authorised, the code is only sent once `DeviceTokenSource` has a token (bounded at 15 s, `startTokenRegistrationTimeout`). With none, the signup stops on `tokenregistrationfail` [Try again, Continue]; Continue registers with `payment_mode: onchain` and no token. A registration that did carry a token records it through `DeviceTokenLifecycle.onRegistered`, so the next app start does not post it again. Emulators without Play services therefore always reach this alert.
5. **The payout mode is updated independently of the partner details.** In `BuyViewController.parseNewData`, the `payment_mode` check sits inside the "IBAN/SWIFT/username changed" branch, which contradicts its own comment ("tracked independently"). Android applies a changed mode on its own and refreshes silently.
6. **An absent `lightning_address_username` does not count as a change.** iOS compares `String?` with `String`, so when the backend omits the field, "Update details" would fire every time Buy opens. Android compares only when the field is present.
7. **"Asked for notifications before" is a local flag.** Android has no equivalent of iOS's `.notDetermined`, so `NotificationAccess` records that the system prompt was shown. Below API 33 there is no runtime permission, so the flag counts as already asked and the check falls through to whether notifications are enabled.
8. **Screenshot saves the app window to `Pictures/bittr` through MediaStore** on API 29 and up. On older versions it shows the `screenshot3` failure alert rather than asking for storage permission.
9. **Customer records live in a JSON file under `no_backup`, one file per backend** (`customer-development.json` / `customer-production.json`). They use iOS's field names so the two platforms are easy to compare. `BittrCustomerStore.firstDepositCode()` is the single read for "which bittr customer is this device"; `PushModule` now uses it as the device-token lifecycle's deposit code.
10. **The `bitcoin_signature` key is derived from the seed** (`RegistrationSigner`, path `m/84'/{1 debug, 0 release}'/0'/0/0`). The `bitcoin_address` is BDK's external index 0, waiting 4 × 3 s for BDK to open as iOS does. The xpub is BDK's account xpub, falling back to bitcoin-kmp's (the two are checked equal by `BdkAccountXpubParityTest`).
11. **Profits look up received transactions not yet in `sentToBittr`, plus the channel-funding transaction** (`CacheManager.getTxoID()`, from the cached funding outpoint), unless it was already sent and is in the history, as `getBittrTransactions` does. The funding purchase counts at the `bitcoin_amount` bittr reports, since it is not a received transaction of this wallet.
12. **The Buy page shown from Home** has no check badge, no "Your wallet is ready!" and no Skip, matching `Signup7ViewController.viewWillAppear` when `ibanVC != nil`.

## Question

1. **`buy_signup_no_notifications.yaml` on Android.** Maestro's `launchApp: permissions: notifications: deny` revokes the permission, but the app has never shown the prompt, so it shows `alert.receiveNotificationsPrompt`. Tapping Okay then opens the *system* dialog, which the flow does not expect. Options: set the "already asked" flag when permission is revoked but was once granted (not detectable), or add an Android-specific step to the flow that taps "Don't allow".
2. ~~Onboarding's Ready → bittr signup~~ — done: Continue on "Your wallet is ready" opens the Buy signup on the IBAN page (`signup/bittr`, `BuyRoute(onboarding = true)`), and every way out of it (Done, "Go to wallet", Back, down) lands on Home. The navigation graph's start destination is now read once at launch, because following the wallet state rebuilt the graph when onboarding unlocked the wallet.
3. ~~Registration with no FCM token~~ — superseded by Decided 4: there is no longer a registration without a token unless the user chose on-chain payouts.

## Gap

1. **Signup article cards** (`supported-countries` and others) are not shown; they need the article fetch.
2. **Connectivity check on each page move** (`checkInternetConnection`) is not ported; failures surface as the per-call alerts instead.
3. ~~The funding transaction id~~ — now included; see Decided 11.
4. **`buy_incoming.yaml` / `buy_more.yaml`** need the push bridge (payout and HTLC notifications), which belongs to the notifications fork. Profits and the Home pill are in place for them.
5. **Signup completion is not reported to Sentry** (`SentryManager.countMetric("bittrsignup.success")`).
