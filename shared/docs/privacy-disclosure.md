# Privacy disclosure inventory

What the app sends off the device, where it goes, and how that maps to the two
places we have to declare it: the iOS privacy manifest
(`ios/bittr/PrivacyInfo.xcprivacy`) and the App Store Connect App Privacy label.

Everything below is read from the code at the line references given. Where a
call is user-initiated navigation rather than collection, it is listed under
[Not declared](#not-declared-and-why) with the reason.

The Android Play Data safety form will need the same inventory. It is the same
app and the same backend, so the left-hand columns carry over; only the store's
category names differ.

Refs BIT-91. The map is settled separately by BIT-71 and is not reopened here.

## What leaves the device

### To bittr's backend (`getbittr.com/api`)

| Field | Sent by | Endpoint |
| --- | --- | --- |
| Email address | `Transfer1ViewController.swift:332`, `Transfer2ViewController.swift:232`, `Transfer2ViewController.swift:349` | `POST /verify/email`, `POST /verify/email/check2fa`, `POST /customer` |
| IBAN (the customer's own bank account) | `Transfer1ViewController.swift:333`, `Transfer2ViewController.swift:356` | `POST /verify/email`, `POST /customer` |
| Bitcoin address | `Transfer2ViewController.swift:351` | `POST /customer` |
| Extended public key (`xpub`) | `Transfer2ViewController.swift:359` | `POST /customer` |
| Lightning node pubkey | `Transfer2ViewController.swift:357`, `BittrService.swift:106`, `BuyViewController.swift:213` | `POST /customer`, `GET /transaction_info`, `GET /deposit_code` |
| Message signatures over the above | `Transfer2ViewController.swift:355`, `BittrService.swift:105` | several |
| APNs device token | `Transfer2ViewController.swift:363` | `POST /customer` |
| Live Activity push token | `SwapManager.swift:107`, posted at `:110` | `POST /boltz/live-activity-token` |
| Deposit code | `BuyViewController.swift:357`, `BittrService.swift:104` | `PATCH /customer/payment-mode`, `GET /transaction_info` |
| Transaction ids | `BittrService.swift:103` | `GET /transaction_info` |
| Lightning invoices and amounts | `HandleLightningAddressNotification.swift:104`, `BittrService.swift:21` | `POST` to the lightning-address endpoint, `POST /payout/lightning` |
| Lightning address username | `HandleLightningAddressNotification.swift:108` | as above |
| Payout mode (`lightning` / `onchain`) | `Transfer2ViewController.swift:368`, `BuyViewController.swift:358` | `POST /customer`, `PATCH /customer/payment-mode` |

On-chain wallet sync goes to `esplora.getbittr.com` in production
(`EnvironmentConfig.swift:96`), so bittr also sees the wallet's addresses and
balances as a matter of course. That is first-party and already covered by the
financial-info entry.

### To Sentry (`ingest.us.sentry.io`)

Configured in `SentryManager.swift:15`. `sendDefaultPii` is off
(`SentryManager.swift:23`), the IP address and geo fields are overwritten
(`:74`-`:80`), and `RedactionManager.swift` strips invoices, LNURLs, xpubs,
on-chain addresses, long hex runs, IBANs, email addresses, amounts and BIP39
phrases from messages, exceptions, extras, breadcrumbs and URLs before send.

What still goes:

- Crash and error events — `SentryManager.capture(_:context:)` at `:163`.
- Performance traces at a 10 % sample rate — `:22`.
- Counters for feature use: `app.launch.open`, `swap.*.initiated`,
  `lightning.payment.success`, `onchain.transaction.success` and others —
  `SentryManager.countMetric(_:)` at `:180`, ~30 call sites.
- **The APNs device token, attached to every event** — `:97`-`:99`.

That last one decides the `Linked` answer for everything Sentry sends. The same
token is on the customer record at `POST /customer`, so a Sentry event can be
joined to a named customer by anyone holding both. The diagnostic data is
therefore linked to identity, and the manifest says so.

### To third parties

- **Boltz** (`api.boltz.exchange`, `EnvironmentConfig.swift:76`) — swap amounts,
  invoices, on-chain addresses, refund pubkeys. `SwapManager.swift:239`, `:625`.
  Swap ids are hashed before they reach *bittr's* endpoint
  (`SwapManager.swift:106`), but Boltz itself sees the swap in full.
- **BTCMap** (`api.btcmap.org`) — the places list is fetched with no user
  coordinates in the query (`BitcoinPlace.swift:37`-`:55`). Nothing about the
  user is sent. This is what BIT-71 concluded; nothing here changes it.
- **LDK rapid gossip sync** (`rapidsync.lightningdevkit.org`) — a static network
  snapshot download. No user data.
- **mempool.space** — block tip height (`BitcoinManager.swift:281`) and a fee
  estimate (`:527`). No user data on either call.

## Proposed manifest and label

Both should carry the same ten entries. None is used for tracking: the app has
no ATT prompt, no IDFA access and no advertising SDK.

| Data type | Manifest key | Linked | Tracking | Purpose | Because |
| --- | --- | --- | --- | --- | --- |
| Email Address | `EmailAddress` | Yes | No | App Functionality | Registration and 2FA |
| Payment Info | `PaymentInfo` | Yes | No | App Functionality | The customer's IBAN |
| Other Financial Info | `OtherFinancialInfo` | Yes | No | App Functionality | Bitcoin address, xpub, balances, amounts |
| Purchase History | `PurchaseHistory` | Yes | No | App Functionality | `GET /transaction_info` returns the customer's purchases |
| User ID | `UserID` | Yes | No | App Functionality | Deposit code, email token, node pubkey, lightning address username |
| Device ID | `DeviceID` | Yes | No | App Functionality, Analytics | APNs and Live Activity push tokens |
| Crash Data | `CrashData` | Yes | No | App Functionality | Sentry |
| Performance Data | `PerformanceData` | Yes | No | App Functionality, Analytics | Sentry traces |
| Other Diagnostic Data | `OtherDiagnosticData` | Yes | No | App Functionality | Sentry breadcrumbs and context |
| Product Interaction | `ProductInteraction` | Yes | No | Analytics | `countMetric` feature counters |

`NSPrivacyTracking` is `false` and `NSPrivacyTrackingDomains` is empty, for the
same reason the Tracking column is No throughout.

### Judgement calls worth a second opinion

- **Purchase History.** The purchase itself starts as a bank transfer, outside
  the app; the app sends deposit codes and transaction ids and receives the
  history back. Declaring it is the conservative reading and costs nothing,
  since the same customer record is already declared under financial info.
- **Product Interaction linked.** The `countMetric` counters carry no identifier
  of their own. They are declared linked because they travel on the same Sentry
  project as events that do carry the device token. Dropping the device token
  from `beforeSend` would let both this and the three diagnostic rows move to
  unlinked — the single highest-value privacy change available here.
- **No Name, no Phone Number.** Neither is collected anywhere in the iOS code.
  Grepping the app for name and phone fields returns only UI copy. If the label
  currently declares either, it over-declares.
- **KYC documents are not app-collected.** The privacy policy lists passport /
  ID card / driving licence, proof of residence and proof of source of funds,
  but no upload path exists in the app — no document picker, no KYC screen, and
  the only camera use is the QR scanner (`NSCameraUsageDescription`,
  `project.pbxproj:1622`). Those documents reach bittr out of band, so they are
  not declared on the label. The privacy policy covering them is a separate
  question from what this app transmits.

## Not declared, and why

- **Location.** The map asks for `NSLocationWhenInUseUsageDescription` to centre
  the view, and the coordinate never leaves the device. Settled in BIT-71.
- **Opening a transaction on mempool.space.** `TransactionViewController.swift:716`
  builds `mempool.space/tx/<txid>` and hands it to the in-app web view when the
  user taps through. mempool.space sees that txid and the device's IP. It is
  user-initiated navigation to a website rather than collection by the app, so
  it is not a label entry — but it is worth knowing the path exists.
- **Academy images** from bittr's S3 bucket, and the privacy policy / terms /
  support pages in `SettingsViewController.swift:75`-`:81`. Content fetches; no
  user data attached.

## The gap this leaves open

The current App Store Connect App Privacy label has never been written down.
Until someone with access records it verbatim, the comparison in this document
is one-sided: it says what the label *should* say, not what it *does* say.

Fill this in when that is known:

| Data type | On the label today | In the manifest | Action |
| --- | --- | --- | --- |
| _(to be recorded)_ | | | |

Changing the label is a customer-facing disclosure and goes through the Tier 1
route before anything is edited in App Store Connect.
