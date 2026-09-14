# Porting spec — Buy, bittr signup and Profits

Research notes for the Android port, written from the iOS sources on 2026-09-14. iOS paths are under `ios/bittr/`.

## 1. Screens

Entry: `Home/HomeViewController.swift` `buyButtonTapped` (:183) → modal `BuyViewController`; `profitButtonTapped`
(:179) → `ProfitViewController` with `calculatedProfit`, `calculatedCurrentValue`, `calculatedInvestments`
(:287-292); ids `home.profitButton`, `home.profitLabel` (:112-113).

**Buy** (`Buy/BuyViewController.swift`): down arrow `buy.downButton`, piggy, "buy bitcoin" `buy.headerLabel`,
`updateDataSpinner`. No entity with non-empty `yourUniqueCode` → `emptyView` (`buyempty`, `buysubtitle`,
`buy.continueButton` → `RegisterIbanViewController`). Else a horizontal pager of 340pt cards
(`Buy/IbanCollectionViewCell.swift`): Your email `buy.yourEmail`, Your IBAN `buy.yourIban`, Partner IBAN (copy),
Partner `ourName` (copy), Your code `buy.yourCode` (copy), Lightning row (`?` `buy.paymentModeButton`, switch
`buy.paymentModeSwitch` ON when `paymentMode != "onchain"`, spinner). Copy → `alert.copied` ("Copied", value,
[Okay]). `?` → `alert.lightningExplanation` (`buyvclightning` / `buyvclightningexplanation`, [Okay]). Open → if codes
exist `getDepositCodeData` (return if node not running; spinner 1 s; GET `/deposit_code`; `parseNewData` matches by
`deposit_code`; if `iban`/`swift`/`lightning_address_username` changed → update + `buyvcupdatedetails` /
`buyvcupdatedetails2`). Switch: disable + spinner → `setPaymentMode`: turning ON without notification permission →
revert + `receivenotifications` / `lightningneedsnotifications` [Okay]; else no node/pubkey → revert +
`lightningnotready` / `syncingwallet2`; else sign + PATCH `/customer/payment-mode`; success reads
`data.payment_mode`; error text (`error`/`message`) containing "expired timestamp" retries once, else
`paymentmodeupdateerror` + server text, revert.

**Signup container** (`Buy/RegisterIbanViewController.swift`): five pages slid horizontally, each move checks
connectivity; header piggy + "buy bitcoin". Pages: 0 `Signup7ViewController`, 1 `Transfer1ViewController`, 2
`Transfer2ViewController` (OTP), 3 `Transfer3ViewController` (success), 4 `Transfer4ViewController` (info). Onboarding
reuses them as pages 9–13.

- Page 0 "wallet ready": check badge, "Your wallet is ready!" `signup.create.ready.topLabelOne`, `firstbitcoin`,
  Next `signup.create.ready.continueButton`, Skip `…skipButton`, article card. From Buy: badge, topLabelOne and Skip
  hidden. Next → page 1; Skip closes.
- Page 1 IBAN/email: `bittrinstructions4` `signup.bittr.start.topLabelOne`, `whatsyouriban` `…topLabelTwo`, IBAN
  field "Enter IBAN" `…ibanTextField` (+`…ibanButton`, autofocus), `whatsyouremail` `…topLabelThree`, email
  `…emailTextField`/`…emailButton`, Verify `…nextButton`, "I don't have an IBAN" `…skipButton`, article card.
  Enabled when IBAN non-blank and email valid; Return in email submits. Disabled tap → `oops` / `transfer1vc`.
  Enabled: if no `initiativeConfirmedAt` → sheet `alert.exclusiveInitiative` (`initiativetitle`/`initiativemessage`,
  `initiativeconfirm` `signup.bittr.initiative.confirmButton`, Cancel `…cancelButton`); Confirm stores ISO-8601 UTC
  (seconds). `gatherIbanDetails`: trim email; trim IBAN and strip spaces; update/create entity (UUID id, `order =
  count`); POST `/verify/email` → success page 2; `success:false` + `message` → `oops` + message; transport →
  `bittrsignupfail4`. Skip → `alert.onlyIban` (`weresorry`/`onlyiban`, [0 "Go to wallet", 1 "Cancel"]).
- Page 2 OTP: `youvegotmail` `signup.bittr.otp.topLabel`, code "Enter code" `…codeTextField`/`…codeButton`, Confirm
  `…nextButton`, "Resend code" `…resendButton`. Enabled > 5 chars; auto-submit once at ≥ 6. Disabled tap → `oops` /
  `transfer15vc`. `checkPushNotificationStatus`: not determined → `alert.receiveNotificationsPrompt`
  (`receivenotifications`/`receivenotifications2`, [0 Okay]) → system prompt → granted: register, 15 s timeout,
  token → send code; denied → denied branch. Denied → `alert.receiveNotificationsDenied`
  (`receivenotifications3`, [0 Cancel, 1 Continue]) → Continue sets `notificationsDenied` and sends. Token
  failure/timeout → `receivenotifications` / `tokenregistrationfail` [0 "Try again", 1 "Continue"]. `sendCodeToBittr`:
  POST `/verify/email/check2fa`; `token` → store `emailToken`, `gatherParameters` (pass `deposit_code`/`message` on
  recovery); `message == "Invalid 2FA verification token provided"` → `verificationfail`; other message →
  `transfer15vc2` with `<error>`; none → "unavailable."; transport → `verificationfail`. `gatherParameters`: message
  `I confirm I'm the sole owner of the bitcoin address I provided and I will be sending my own funds to bittr.
  Order: <first 32 chars of emailToken>. IBAN: <yourIbanNumber>` (or server `message` on recovery);
  `bitcoin_signature` = BIP137-style p2wpkh message signature with key `m/84'/{1 dev, 0 prod}'/0'/0/0`;
  `lightning_signature` = LDK `node.signMessage(utf8)`; wait for BDK up to 4×3 s (fail → `syncingwallet2`);
  address = external index 0; POST `/customer`. `createBittrAccount`: success needs `data.iban`,
  `data.deposit_code`, `data.swift` → `addBittrIban`, `setPaymentMode("onchain")` if notifications denied → page 3;
  `message == "Unable to create customer account (invalid iban)"` → `bittrsignupfail2` → page 1; other →
  `bittrsignupfail3` → page 1; transport → `bittrsignupfail`. Resend (30 s cooldown): at 0 → `/verify/email` again →
  `emailresent` / `emailresent2 <email>.` [0 Okay, 1 "Change email"]; during cooldown → `alert.resendCode` (empty
  title, `resendcode2`, [0 Okay, 1 Change email]); Change email → page 1.
- Page 3 success: check badge, "We're ready for your transfer!" `signup.bittr.success.topLabelOne`,
  `personaldetails` `…topLabelTwo`, Partner IBAN `…ourIbanLabel` (copy `…ibanButton`), Partner (copy
  `…nameButton`), Your code `…yourCodeLabel` (copy `…codeButton`), Screenshot `…screenshotButton` (`saved` /
  `screenshot2`, fail `oops` / `screenshot3`), Finish `…nextButton` → page 4.
- Page 4 info: cards `transfer3Amount`, `transfer3Lightning`, `transfer3Connection`, `transfer3DCA` with labels
  (ids `signup.bittr.transferInfo.{amount,lightning,connection,dca}{Title,Label}`), "Let's go" `…nextButton`, "Back"
  `…backButton` → page 3. Let's go → `bankingapp` / `bankingapp2` (HTML, placeholders `<ouribannumber>`,
  `<ourname>`, `<youruniquecode>`) [0 "Done"] → close.

**Profits** (`Profits/ProfitViewController.swift`): header piggy + "your profits" (`header.downButton`),
`profitsubtitle` `profits.subtitleLabel`, card rows "Total investment" `profits.totalInvestmentLabel`, "Current
value" `profits.totalValueLabel`, "Total profit" `profits.totalProfitLabel`; values `"<chosenCurrency> <Int>"`.
Calculation (`Home/LoadWalletData.swift:412-479`) over `isBittr` transactions: `btc` = received BTC; `conv` =
current price (if tx `currency` differs — "EUR"→€, else CHF — use that currency's price); `profit = btc*conv −
fiatNetAmount`, `investment = fiatNetAmount`; if currencies differ rescale both by `/conv*currentValue`; sum rounded;
current value = `btc*currentValue` rounded. Home pill: `"0 %"` if investment 0, else `"<round(profit/investment*100)>
%"` without minus; loss colours + `arrow.down` else profit + `arrow.up`; visible with the balance. `isBittr` from
GET `/transaction_info` (`LoadWalletData.swift:155-229`, `Helpers/BittrService.swift:79-137`).

## 2. API (base includes `/api`; JSON; 30 s)

| # | Method, path | Request | Response used |
|---|---|---|---|
| A | `POST /verify/email` | `email`, `iban`, `category:"ios"` | `success==false` + `message` rejects |
| B | `POST /verify/email/check2fa` | `email_address`, `token_2fa`, `lightning_pubkey` (if node up) | `token`; recovery `deposit_code`, `message`; error `message` |
| C | `POST /customer` | `email`, `email_token`, `bitcoin_address`, `initial_address_type:"extended"`, `category:"ios"`, `bitcoin_message`, `bitcoin_signature`, `iban`, `lightning_pubkey`, `lightning_signature`, `xpub_key`, `xpub_addr_type:"bech32"`, `xpub_path:"m/0/x"`, `skip_xpub_usage_check:"true"`, `ios_device_token` (Android: `android_device_token`), optional `payment_mode:"onchain"`, `exclusive_initiative_confirmed_at`, `deposit_code` | `data.iban`, `data.deposit_code`, `data.swift`, `data.lightning_address_username`; error `message` |
| D | `GET /deposit_code?timestamp=&signature=&pubkey=` | signature over `deposit_codes:<pubkey>:<timestamp>` | `data.deposit_code`, `data.iban`, `data.swift`, `data.lightning_address_username`, `data.payment_mode` |
| E | `PATCH /customer/payment-mode` | `deposit_code`, `payment_mode` (`"lightning"`/`"onchain"`), `pubkey`, `signature`, `timestamp` (Int) | `data.payment_mode`; error `error`/`message` |
| F | `GET /transaction_info?tx_ids=&deposit_codes=&signature=&pubkey=` | comma lists; signature over `depositCodesString + txIdsString` | `success`, `data[]`: `tx_id`, `transfer_type`, `historical_exchange_rate`, `datetime`, `currency`, `bitcoin_amount`, `transfer_fee`, `bittr_fee`, `surcharge`, `fiat_amount_net`, `fiat_amount_gross` |

Signatures/pubkey = LDK node id and `node.signMessage`. C also needs the xpub.

## 3. Persistence

`device` (env-scoped) `[IbanEntity]` sorted by `order`: `yourIbanNumber`, `yourEmail`, `ourIbanNumber`, `ourName`
(default `"BITTR AG"`), `yourUniqueCode`, `order`, `id`, `emailToken`, `ourSwift`, `lightningAddressUsername`,
`paymentMode` (`""`/`"lightning"`/`"onchain"`), `initiativeConfirmedAt`. Also `notificationstoken`; profit inputs
`senttobittr`, `txoid`, `walletcache`, `currency`.

## 4. Copy (English)

`buybitcoin` "buy bitcoin"; `buysubtitle` "To buy bitcoin, make a bank transfer to a partner and put your unique code
in the transfer description field."; `buyempty` "No order has been set up. Tap below to create your first one.";
`youremail` "Your email"; `youriban` "Your IBAN"; `ouriban` "Partner IBAN"; `ourname` "Partner"; `yourcode` "Your
code"; `buyvclightning` "Lightning"; `buyvclightningexplanation` "Purchases up to 100 EUR/CHF go into your Lightning
connection. Spend and receive instantly, with very low fees.\n\nTurn this off to receive your bittr purchases
on-chain instead, in the regular part of your wallet."; `buyvcupdatedetails` "Update details";
`buyvcupdatedetails2` "Your partner details have changed. The above details have been updated.";
`lightningnotready` "Lightning not ready"; `syncingwallet2` "Please wait a moment while we're syncing your wallet.";
`paymentmodeupdateerror` "Couldn't update payout mode"; `lightningneedsnotifications` "Lightning payouts are
delivered via push notifications, so you must allow notifications to switch to lightning.\n\nOn your device, go to
Settings > Notifications > bittr to authorize our notifications, then try again."; `walletisready` "Your wallet is
ready!"; `firstbitcoin` "Get your first bitcoin, hassle-free, here with one of our partners."; `bittrinstructions4`
"Buy bitcoin whenever you want, simply by making a bank transfer."; `whatsyouriban` "What's your IBAN (International
Bank Account Number)?"; `whatsyouremail` "What's your email address?"; `enteriban` "Enter IBAN"; `enteremail` "Enter
email"; `verify` "Verify"; `noiban` "I don't have an IBAN"; `transfer1vc` "Please enter your IBAN and email in order
to proceed."; `bittrsignupfail4` "Something went wrong verifying your email address. Please try again.";
`initiativetitle` "Your own exclusive initiative"; `initiativemessage` (three paragraphs, `Language.swift:176`,
verbatim); `initiativeconfirm` "I confirm my request is made solely on my own exclusive initiative, without any
encouragement or solicitation from Bittr"; `weresorry` "We're sorry!"; `onlyiban` "Buying bitcoin with bittr is only
available to IBAN holders.\n\nYou can still use your wallet to send and receive bitcoin."; `gotowallet` "Go to
wallet"; `youvegotmail` "You've got mail! Please enter your verification code below."; `entercode` "Enter code";
`resendcode` "Resend code"; `transfer15vc` "Please enter the verification code in order to proceed.";
`receivenotifications` "Receive notifications"; `receivenotifications2` "To receive instant bitcoin payments, you
must allow notifications.\n\nWithout them, your purchases are paid into the regular (on-chain) part of your wallet
instead."; `receivenotifications3` "To receive instant bitcoin payments, you must allow notifications.\n\nOn your
device, go to Settings > Notifications > bittr to authorize our notifications.\n\nYou're free to continue without
notifications, but then all your purchases will be paid into the regular (on-chain) part of your wallet.";
`tokenregistrationfail` "We couldn't register this device for notifications. Please check your internet connection
and try again, or continue with regular payouts."; `tryagain` "Try again"; `verificationfail` "Please enter the
correct verification code."; `transfer15vc2` "Something went wrong verifying your code. Please restart the app and
try again. (Error: <error>)"; `bittrsignupfail` "Something went wrong creating your account. Please try again.";
`bittrsignupfail2` "The IBAN you've entered appears to be invalid. Please enter a valid IBAN.";
`bittrsignupfail3` "Something went wrong. Please try again later."; `emailresent` "We've resent our email!";
`emailresent2` "Check your Spam and Promotion folders to see if the code is there.\n\nPlease also check whether your
address is correct:"; `changeemail` "Change email"; `resendcode2` "Please wait 30 seconds before requesting another
verification code."; `readyfortransfer` "We're ready for your transfer!"; `personaldetails` "These are your personal
details. To buy bitcoin, make a bank transfer at any time and include your unique code in the transfer
description/memo field."; `screenshot` "Screenshot"; `saved` "Saved"; `screenshot2` "We've added the screenshot to
your Photo Library."; `screenshot3` "We couldn't save your screenshot. Try taking a screenshot manually.";
`finaldetails` "Finish"; `transfer3Amount` "Amount"; `transfer3AmountLabel` "You can buy up to 999 € worth of
bitcoin per 30 days from bittr."; `transfer3Lightning` "Instant payments"; `transfer3LightningLabel`
(`Language.swift:483`, verbatim); `transfer3Connection` "Lightning connection"; `transfer3ConnectionLabel` "Lightning
funds exist only on this device. Don't delete this app before closing your lightning connection.";
`transfer3DCA` "Dollar-cost-averaging"; `transfer3DCALabel` "Easily stack up on bitcoin by setting up a recurring
bank transfer, e.g. 50 € every Monday."; `letsgo` "Let's go"; `back` "Back"; `bankingapp` "Open your banking app";
`bankingapp2` "Create your (recurring) transfer to<br><br><b><ouribannumber></b>\n<b><ourname></b>\n<b><youruniquecode></b>";
`done` "Done"; `yourprofits` "your profits"; `profitsubtitle` "Here's to financial independence! These are the
results of your savings so far."; `totalinvestment` "Total investment"; `currentvalue` "Current value";
`totalprofit` "Total profit".

## 5. Test ids

All present in `TestIDs.kt`: `Buy.*` (`headerLabel, downButton, continueButton, yourCode, yourEmail, yourIban,
paymentModeSwitch, paymentModeButton`), `Profits.*`, `Home.buyButton/profitButton/profitLabel`,
`Signup.Create.Ready.*`, `Signup.Bittr.Initiative.*`, `Signup.Bittr.Start.*`, `Signup.Bittr.Otp.*`,
`Signup.Bittr.Success.*`, `Signup.Bittr.TransferInfo.*`, `Alert.{copied, exclusiveInitiative, lightningExplanation,
onlyIban, receiveNotificationsPrompt, receiveNotificationsDenied, resendCode}`.

## 6. Flows

- `buy_signup.yaml`: unlock, `home.buyButton`, `buy.headerLabel`, `buy.continueButton`,
  `signup.create.ready.continueButton`, IBAN `NL27ABNA0451135725` (field focused), `…emailButton`, email
  `e2ebittr@getbittr.com`, `pressKey: Enter`, `initiative.confirmButton`, code `123456` (auto-submit), optional
  `alert.button.0` + "Allow", `success.topLabelOne` (90 s), next, `transferInfo.amountTitle`, scroll to next, tap,
  `alert.button.0`, `buy.yourCode` (20 s), `buy.yourEmail`, `buy.yourIban`, `buy.downButton`, `home.headerLabel`.
- `buy_signup_no_notifications.yaml` (notifications denied): skip → `alert.onlyIban` Go to wallet; short IBAN →
  initiative cancel/confirm → invalid IBAN alert; bad email alert; resend + cooldown `alert.resendCode` → Change
  email; wrong code `111111` → prompt/denied → Continue → wrong-code alert → `123456` → Continue; success copy alerts,
  screenshot; info back/next; Done; `buy.paymentModeSwitch checked:false`; tap switch → alert → still false.
- `payment_mode.yaml`: Buy (sign up if needed), `buy.paymentModeButton` → `alert.lightningExplanation`; toggle switch
  → `checked:false` (60 s) → toggle → `checked:true`.
- `buy_incoming.yaml` / `buy_more.yaml`: profits before; Buy copy `buy.yourCode`; swipe down; `trigger_bank_transaction.js`
  (POST `https://staging.getbittr.com/api/e2e/bank-transaction` `{deposit_code}`); mine; `build_payout_push.js`;
  `push_notification.js` (→ `localhost:8888/push` → `xcrun simctl push`); payout alerts; `home.profitLabel`; profits
  changed.

iOS-only mechanics: `simctl push`, swipe-down dismissal, "Allow" system dialogs, `permissions: notifications: deny`
(API 33+ on Android), tap label to dismiss keyboard, `pressKey: Enter`, `checked:` on a toggleable switch.

## 7. Already on Android

`core/network`: `HttpClient`, `BittrEnvironment`, `CustomerApi` (`EmailVerification` A with `category:"android"`,
`CustomerRegistration` C with `android_device_token`; `Registered` does not read `lightning_address_username`),
`DeviceTokenApi` (PATCH `customer/device-token`, Boltz webhook). Missing: B, D, E, F. `core/push`:
`SignedRequestMessage.paymentMode` (KDoc says `"instant"` — use `"lightning"`), `PushChannelPolicy`,
`DeviceTokenRetryBudget`. `app/di/PushModule.kt`: `provideRequestSigner` stub (pubkey/sign return null),
`DeviceTokenLifecycle` with `depositCode = { null }`. `core/wallet-ldk`: `accountXpub`, `Bip84Account`; no `nodeId`,
`signMessage`, BIP137 path signing. `feature/signup/ReadyScreen.kt`: continue and skip both finish onboarding. Home
`onBuy` → NotPortedDialog; no profit pill.

## 8. Decisions (recommended defaults)

1. `payment_mode` values `"lightning"`/`"onchain"`; fix the KDoc.
2. Add `nodeId()`, `signMessage()`, `signMessageForPath()` to the wallet seam; replace the `PushModule` signer stub;
   match iOS message bytes with unit tests.
3. FCM token with a bounded 15 s wait; register without `android_device_token` if none; `DeviceTokenLifecycle` PATCH
   later.
4. POST_NOTIFICATIONS on API 33+; in-app prompt when never requested, then system dialog; denied → Cancel/Continue
   alert; same button order.
5. Screenshot → bitmap → MediaStore Pictures.
6. Buy as a full-screen destination also dismissable by swipe down.
7. Tapping the background clears focus.
8. IBAN entities as an env-scoped JSON store with iOS field names; feed `depositCode` into `DeviceTokenLifecycle`.
9. One signup ViewModel with a step enum shared by onboarding and Buy.
10. Mirror iOS quirks (`ourName` "BITTR AG", server-side IBAN validation, `bankingapp2` HTML as bold text).
11. Profit strings exactly `"<symbol> <Int>"` / `"<n> %"`, pure tested function.
12. Android push bridge for flows (debug receiver via adb) behind `push_notification.js`.
