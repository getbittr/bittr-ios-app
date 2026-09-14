# Buy, bittr signup and Profits — port decisions

Written during the overnight port (2026-09-14/15), branch `port/buy`. The format is **Decided** (a call I made and why), **Question** (needs a product or backend answer), **Gap** (not ported or known to differ).

## Decided

1. **Buy and its signup are one destination.** iOS presents `RegisterIbanViewController` modally over `BuyViewController` and dismisses back to it. On Android, `BuyRoute` holds the signup container as state, so after the final "Done" the Buy cards (`buy.yourCode`) are already on screen, as `buy_signup.yaml` expects. System Back closes the signup.
2. **Alerts are drawn inside the screen, not in a dialog window.** Maestro reads only the focused window, and these alerts need the card ids (`alert.copied`, `alert.lightningExplanation`, `alert.resendCode`, `alert.onlyIban`, `alert.receiveNotificationsPrompt/Denied`, `alert.exclusiveInitiative`). `BuyAlertCard` puts the id on the card and `alert.button.N` on the buttons, in iOS's order.
3. **Responses are read the way iOS's `CallsManager.makeApiCall` reads them.** Any JSON object body counts as an answer whatever the HTTP status, so server messages like "Invalid 2FA verification token provided" reach the screen. `GET /transaction_info` is the exception: iOS decodes it strictly, so it needs a 2xx and `success: true`.
4. **The FCM token wait is bounded at 15 s, and a missing token does not block registration.** iOS shows `tokenregistrationfail` with [Try again, Continue] when no APNs token arrives. Android registers without `android_device_token` (contract §2.1 allows this), and `DeviceTokenLifecycle` sends it later with `PATCH /customer/device-token`. Emulators often have no FCM token, and the alert would stop `buy_signup.yaml` for no benefit to the customer.
5. **The payout mode is updated independently of the partner details.** In `BuyViewController.parseNewData`, the `payment_mode` check sits inside the "IBAN/SWIFT/username changed" branch, which contradicts its own comment ("tracked independently"). Android applies a changed mode on its own and refreshes silently.
6. **An absent `lightning_address_username` does not count as a change.** iOS compares `String?` with `String`, so when the backend omits the field, "Update details" would fire every time Buy opens. Android compares only when the field is present.
7. **"Asked for notifications before" is a local flag.** Android has no equivalent of iOS's `.notDetermined`, so `NotificationAccess` records that the system prompt was shown. Below API 33 there is no runtime permission, so the flag counts as already asked and the check falls through to whether notifications are enabled.
8. **Screenshot saves the app window to `Pictures/bittr` through MediaStore** on API 29 and up. On older versions it shows the `screenshot3` failure alert rather than asking for storage permission.
9. **Customer records live in a JSON file under `no_backup`, one file per backend** (`customer-development.json` / `customer-production.json`). They use iOS's field names so the two platforms are easy to compare. `BittrCustomerStore.firstDepositCode()` is the single read for "which bittr customer is this device"; `PushModule` now uses it as the device-token lifecycle's deposit code.
10. **The `bitcoin_signature` key is derived from the seed** (`RegistrationSigner`, path `m/84'/{1 debug, 0 release}'/0'/0/0`). The `bitcoin_address` is BDK's external index 0, waiting 4 × 3 s for BDK to open as iOS does. The xpub is BDK's account xpub, falling back to bitcoin-kmp's (the two are checked equal by `BdkAccountXpubParityTest`).
11. **Profits look up received transactions only** (`receivedSats > 0` and net positive) that are not yet in `sentToBittr`. The funding tx id iOS also sends (`CacheManager.getTxoID()`) is not sent yet; see Gap 3.
12. **The Buy page shown from Home** has no check badge, no "Your wallet is ready!" and no Skip, matching `Signup7ViewController.viewWillAppear` when `ibanVC != nil`.

## Question

1. **`buy_signup_no_notifications.yaml` on Android.** Maestro's `launchApp: permissions: notifications: deny` revokes the permission, but the app has never shown the prompt, so it shows `alert.receiveNotificationsPrompt`. Tapping Okay then opens the *system* dialog, which the flow does not expect. Options: set the "already asked" flag when permission is revoked but was once granted (not detectable), or add an Android-specific step to the flow that taps "Don't allow".
2. **Onboarding's Ready → bittr signup** (`happy_path_signup.yaml`, `fresh_install_unhappy.yaml`) still ends onboarding on Continue. The Buy signup pages could be reused there (iOS reuses them as pages 9–13). This was not wired, to keep `CreateWalletScreen` untouched while other forks edit the nav graph.
3. **Should a registration with no FCM token prompt `DeviceTokenLifecycle` straight away?** Right now the token is sent on the lifecycle's next trigger.

## Gap

1. **Signup article cards** (`supported-countries` and others) are not shown; they need the article fetch.
2. **Connectivity check on each page move** (`checkInternetConnection`) is not ported; failures surface as the per-call alerts instead.
3. **The funding transaction id** is not included in `/transaction_info`, so a channel-funding purchase does not yet count towards profits.
4. **`buy_incoming.yaml` / `buy_more.yaml`** need the push bridge (payout and HTLC notifications), which belongs to the notifications fork. Profits and the Home pill are in place for them.
5. **Signup completion is not reported to Sentry** (`SentryManager.countMetric("bittrsignup.success")`).
