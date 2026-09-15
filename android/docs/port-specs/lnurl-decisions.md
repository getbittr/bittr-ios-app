# Lightning extras — decisions and open questions

Branch `port/lnurl`. Calls made while porting LNURL, Lightning addresses, the channel chart, the sync
overlay and transaction notes without someone to ask. Status: **Decided** · **Question** · **Gap**.

## LNURL on Send

1. **Decided — every LNURL service URL and callback goes through `LnurlEndpoint.validate` first**
   (https only, no private/loopback hosts). A rejected URL shows iOS's `lnurlfail3`, not the validator's
   own reason, to keep iOS's copy. iOS fetches any URL.
2. **Decided — new `LnurlSource.ManualEntry`** for typed and pasted input, allowed for pay, withdraw and
   auth like a QR scan. Web pages stay blocked from pay and withdraw.
3. **Decided — callback parameters are appended properly** (`&` when the callback already has a
   query, values URL-encoded, a same-named parameter replaced). iOS appends `?amount=` as a raw
   string, which breaks callbacks that already carry a query.
4. **Decided — the pay callback's invoice must be for the requested amount on this network** before the
   Confirm page opens. Otherwise: "Pay request" / `lnurlfail2` + "The invoice we received doesn't match
   the requested amount." **Question:** is that new sentence OK? iOS pays whatever invoice comes back.
   The description hash is not checked, same as iOS.
5. **Decided — the Confirm page is the consent for a range pay request.** Same as iOS: the amount is typed,
   then Done fetches the invoice and opens Confirm showing the typed address.
6. **Decided — a service's non-2xx answer counts as a failure** (`lnurlfail3`), like iOS's
   `CallsManager`. A 200 with `{"status":"ERROR"}` shows the service's `reason`.
7. **Decided — LNURL-auth is ported with iOS's own derivation.** The seed is HMAC-SHA256 of the lower-cased
   mnemonic with `bittr-lnurl-auth-seed-v1`; the linking key is HMAC-SHA256 of the seed and the host; the
   signature is DER over k1. This isn't LUD-05, but it is what iOS does, so an iOS user keeps their
   identity on a site after moving to Android. Not tested against a live LNURL-auth site.
8. **Decided — a pay request with min > max or min ≤ 0 is refused** (`lnurlfail3`). iOS would show an
   impossible range.
9. **Gap — the in-app browser (`WebsiteScreen`) still drops `lightning:`/`lnurl` links.** iOS's
   `WebsiteViewController` handles LNURL-auth from pages. Not ported.

## Lightning-address push (`lightning_address_notification`)

10. **Decided — the logic is in `app/.../lnurl/LightningAddressPush.kt`, and the alerts are the
    notifications port's job.** Merge binding: implement the notifications port's `LnurlPushHandler` by
    calling `LightningAddressPush.request(push)`, then `step(signedIn, synced, wasNotified)`:
    - `AskToSignIn`: `alert.paymentRequest`, `paymentrequest2`.
    - `WaitForSync`: `loading.syncingWallet`, replayed after the first sync.
    - `AskHandleNow`: `paymentrequest3` [Cancel, Handle now].
    - `HandleNow`: `generatinginvoice`, then `handle(request)`. On failure, `alert.paymentRequestFailed`.

    The copy is in `LightningAddressPushCopy`. Construct it with `composition.lightning` and the app's
    `HttpClient`.
11. **Decided — the pushed `endpoint` must be public https** before the invoice is posted to it. iOS posts
    to any URL. `notification_lnurl.yaml` pushes `http://127.0.0.1:59999/...` and expects
    `alert.paymentRequestFailed`, which this still produces.

## Receive

12. **Gap — Receive's Lightning address** (`receive_lnurl.yaml`'s address branch) needs the bittr account's
    `lightning_address_username`, which comes with the Buy/signup port. `AppReceiveSource.lightningAddress()`
    still returns null, which is the flow's "Unavailable" branch.

## Transaction screen

13. **Decided — notes are a JSON file in the app's files directory** (`transaction_notes.json`), keyed by
    the history row id (txid, or preimage, else payment id), like iOS's `transactionnotes`. They're in the
    normal backup set, like iOS's UserDefaults; they hold no key material.
14. **Gap — Lightning invoice descriptions.** ldk-node's payment details carry no description, and Android's
    Receive doesn't cache one (iOS `storeInvoiceDescription`). So the Description card only shows for
    channel-closure payouts (`channelclosuretransaction`, from the closure txids the scan recorded) until
    Receive stores descriptions.

## Channel chart and events

15. **Decided — the chart's figures are iOS's formulas**: balance = outbound + reserve; receive limit =
    value − outbound − reserve; the bar is balance ÷ value, clamped to 0–1. `question.channelView` sits
    above `questionvc7` on the Lightning connections card (Device details and Move). Send's
    "why a limit" card doesn't show the chart yet.
16. **Decided — `NodeEvents` is a buffered SharedFlow on `WalletComposition`,** and `BittrNavHost` opens
    `question/channel-closed` on `ChannelClosed`. iOS suppresses this card during the incorrect-PIN wipe
    (`removingWalletForIncorrectPin`). At merge, the removal coordinator should gate it the same way.

## Sync overlay

17. **Decided — "Start lightning node" and "Final calculations" complete together**, on the first wallet
    reading. Android's overview only publishes once both have happened, and I didn't add a separate
    node-started signal. "Fetch conversion rates" completes when Home has a price, which Home now fetches
    at start as iOS does. The sheet closes 0.5 s after the last row, or on `sync.closeButton`.

## Flows and tooling

18. **Gap — `send_lightning.yaml` and `receive_invoice.yaml` need a funded channel** and, for pastes, the
    clipboard bridge (`clipboard_server.js` uses `xcrun simctl pbcopy`; on Android that's
    `adb shell cmd clipboard` or an `am broadcast`). No Android clipboard mode was added. The LNURL part of
    `send_lightning.yaml` (type address → Enter → wait for `loading.handlingLnurl` → type amount → Done →
    Confirm) doesn't need the clipboard.

## Follow-up: LNURL links in the in-app browser and the chart on Send's limit card (`port/ln-extras`)

19. **Decided — a first-party page's Lightning links are handed to the wallet** (`WebsiteNavigationPolicy`,
    the port of `decidePolicyFor`). A `lightning:` / `lnurl:` link, a bare `lnurl1…`, or an https link with a
    `tag=login` query item is handed on from the main frame of a first-party page. Anywhere else — a
    third-party page or any subframe — it is cancelled, as on iOS. `LnurlSourcePolicy` still decides what a page
    may do: LNURL-auth only, never pay or withdraw.
20. **Decided — first-party means exactly `https://getbittr.com`.** iOS also accepts subdomains
    (`host.hasSuffix(".getbittr.com")`). `FirstPartyOrigins` and `WebViewBridgeOriginGuardTest` already pin the
    exact host, and a subdomain failing to start LNURL-auth fails safe.
21. **Decided — the link is handled on Send**, not over the browser. The browser hands the LNURL to Send in
    memory (`WebLnurlHandoff`) and opens it, so the auth prompt (origin and page title, R-9) is Send's. iOS
    shows it over the browser. Back from Send returns to the page.
22. **Gap — iOS's injected anchor-scanning script is not ported.** It posts the first Lightning link on a
    first-party page to a JavaScript message handler, which is a bridge R-1 keeps out of the app. Tapping the
    link still works, because that is a navigation.
23. **Decided — iOS cancels an https `tag=login` link on a third-party page**, so Android now does too (it
    used to load it as an ordinary page). Only a parsed `tag` query item counts; the text `tag=login` elsewhere
    in a URL still loads.
24. **Decided — Send's "why a limit for instant payments?" card is iOS's `lightningsendable` card.** With an
    active channel: the chart (`question.channelView`) and `questionvc7`'s figures. With none, iOS replaces
    the header and text with `questionvc12` / `questionvc13`. The `limitlightninganswer` text iOS passes in is
    never shown on this path, so Android no longer shows it either. **Question:** `questionvc12` reads "why
    can't I receive instant payments?" on a card about *sending*. Ported as-is. Is that the intended copy?
