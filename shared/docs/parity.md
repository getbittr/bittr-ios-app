# Parity tracker

Per-feature status of iOS vs Android implementation. Updated as Maestro flows go green on each platform.

For the *order* the Android side should be built in — which flows need the
wallet engine, which don't, and what is holding each wave up — see
[`android-parity-roadmap.md`](android-parity-roadmap.md). This file stays the
per-flow status tracker.

Every flow under `shared/flows/` is listed below. iOS is the source of truth and is
implemented.

The Android column takes three values, and the middle one exists because the
Android Maestro runner is not stood up yet:

- **`not started`** — nothing built.
- **`screens built`** — every step of the flow is reachable in the app and is
  covered by a JVM test that walks the flow's ids in the flow's order. That is
  as far as a claim can honestly go without the runner: Robolectric reads the
  Compose semantics tree directly, so it cannot prove `testTagsAsResourceId`
  bridges those ids onto the accessibility tree Maestro queries.
- **`done`** — the flow passes under Maestro in CI on Android. **Only this
  counts** for BIT-7's definition of done. Nothing reads `done` yet.

**Assertion fragility — the alert surface is matched by copy.** `alert.button._index` and `alert.textField` are the only accessibility ids on the alert surface, so *which* alert is on screen is asserted by matching its wording: 220 alert interactions across 33 flow files, and 147 `text:` matchers of which 39 depend on app copy. Reword one of those strings and the flow fails silently, on both platforms at once once they share `shared/strings/`. The dependency is pinned in `shared/strings/copy-lock.json` and checked in CI — the measurement, the seven strings hardcoded outside the copy table, and the verbatim rule for the `*Language.swift` → `shared/strings/` move are in `shared/strings/README.md`.

## Onboarding & wallet setup

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Test-ID smoke | done | n/a | `onboarding/smoke.yaml` | Verifies the JSON → build.py → Swift → Maestro pipeline reaches a real ID on Signup1. |
| Create wallet (onboarding subflow) | done | not started | `onboarding/happy_path_wallet.yaml` | Drives Signup1 → Signup7 (create wallet, mnemonic, verify, set/confirm PIN). Also opens the "What is bittr?" article on Signup1 and closes it. Reusable subflow. |
| Bittr signup (onboarding subflow) | done | not started | `onboarding/happy_path_signup.yaml` | IBAN / email / OTP / info-cards from Signup7 through to Home. Reusable subflow. |
| Fresh install (full onboarding) | done | not started | `onboarding/fresh_install.yaml` | Top-level orchestrator: clearState + clearKeychain, then runs `happy_path_wallet` + `happy_path_signup`. |
| Fresh install, skip bittr signup | done | not started | `onboarding/fresh_install_skip_signup.yaml` | Creates a wallet from scratch then taps Skip on Signup7 → Home with no bittr account. |
| Fresh install, unhappy path | done | not started | `onboarding/fresh_install_unhappy.yaml` | Wallet creation through every validation gate: Cancel back to Signup1, the confirm-statements alert, the seed-phrase screenshot warning (fires a real Simulator screenshot via `scripts/screenshot_server.js` since Maestro's own capture doesn't post the iOS notification; best-effort), an invalid non-BIP39 word (`invalidwords`) then a valid-but-wrong recovery phrase (`incorrectphrase`), and the PIN too-short / too-long / mismatch alerts, before creating the wallet, then continuing into the bittr signup (Transfer1) and exiting via "I don't have an IBAN" → "Go to wallet" to reach Home. |
| Seed gate rejects wrong words | done | not started | `onboarding/seed_gate_rejects_wrong_words.yaml` | **Parity-critical (BIT-19).** Recovery is mnemonic-only (BIT-8), so Signup4 is the entire recovery guarantee: past it without the real 12 words and the wallet is unrecoverable. Asserts all three rejection branches of `Signup4ViewController.nextButtonTapped` — valid-but-wrong BIP39 words (`alert.incorrectPhrase`), a non-BIP39 string (`alert.invalidWords`), an empty field (`alert.missingWords`) — and that each leaves the flow **still on Signup4**, then that the right words do advance. Decoys are derived from the captured mnemonic so one can never coincidentally be the requested word. Android must pass this unchanged; an implementation that accepts any input, or auto-advances on blur, passes every other flow in the suite. |
| Restore wallet | done | not started | `onboarding/restore_wallet.yaml` | clearState + clearKeychain, restores from a fixed test mnemonic, sets PIN 1234 → Home. |

## Buy & bittr account

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Buy — first incoming bank transaction | done | not started | `features/buy_incoming.yaml` | Opens the lightning channel; needs `fresh_install` first. Also walks the TransactionViewController (copy ID, Bittr/Transfer fee alerts, add note). |
| Buy — subsequent top up | done | not started | `features/buy_more.yaml` | Preserves wallet state; needs a prior `buy_incoming` run for the channel. Requires `scripts/push_server.js`. Also walks the TransactionViewController (copy description + ID, fee alerts, add note). |
| Buy — bittr signup from Buy | done | not started | `features/buy_signup.yaml` | Completes the bittr signup from the empty Buy card via the RegisterIban modal. Needs a wallet *without* a bittr account (run `restore_wallet` first). |
| Buy — signup validation + no notifications | done | not started | `features/buy_signup_no_notifications.yaml` | Unhappy IBAN/email validation alerts + the OTP resend flow (resend → "email resent" alert; a second tap in cooldown → "wait 30 seconds" alert → "Change email" back to Transfer1, then re-verify) + the OTP notification-permission gate, finishing on the on-chain payout fallback. On the Transfer3 success screen also copies the IBAN / name / code (each a "Copied" alert) and taps Screenshot (saves to Photos → "Saved" alert), and on Transfer4 taps Back → Transfer3 → Finish (round-trip) before continuing. Needs `fresh_install_skip_signup` first; launchApp auto-denies the iOS notification dialog. |
| Payout mode toggle | done | not started | `features/payment_mode.yaml` | Toggles the Buy card's payout mode lightning ↔ onchain (PATCH /customer/payment-mode). Self-provisions a wallet + order if missing. |
| Notification — QuestionVC push types | done | not started | `features/notification_information.yaml` | Injects the three QuestionViewController-backed push types back-to-back — `.information` (`bittr_notification`), `.htlcExpired` (`htlc_notification` with `expired: true`) and `.unknown` (unrecognised payload → fallback "Oops!") — and asserts each opens with the expected header/body, then closes it. Re-pushes each until it clears the 10s notification dedup window. Requires `scripts/push_server.js`. Independent of wallet state — auto-provisions a wallet if needed. |
| Notification — LNURL (locked) | done | not started | `features/notification_lnurl.yaml` | Fires a `.lnUrl` (`lightning_address_notification`) push on the PIN screen → asserts the "Payment Request — please sign in" alert, unlocks, and asserts the deferred processing re-runs on sign-in (generate invoice → POST), which fails gracefully ("Payment Request Failed") since no e2e endpoint accepts the invoice. Metadata gathered live from `e2ebittr@staging.getbittr.com` via `scripts/resolve_lnurl.js`. Requires `scripts/push_server.js`; auto-provisions a wallet if needed. |
| Notification — HTLC incoming (locked) | done | not started | `features/notification_htlcincoming.yaml` | Fires a `.htlcIncoming` (`htlc_notification`) push on the PIN screen (silent while locked), pauses so it's handled before sign-in (`scripts/sleep.js`), unlocks, and follows the deferred path through the "syncing wallet" → "receiving payment" pending views to the terminal "Incoming payment" alert — the no-real-payment terminal state (`facilitateHTLCReady`'s htlc_ready call fails, or no deposit code short-circuits to the same alert). Requires `scripts/push_server.js`; auto-provisions a wallet if needed. |

## Receive

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Receive | done | not started | `features/receive.yaml` | Auto-recovers via `happy_path_wallet` + `happy_path_signup` if launched on a clean install. |
| Receive onchain → Send round-trip | done | not started | `features/receive_onchain.yaml` | Taps the header spinner right after unlock: while syncing this opens the sync status view (waits for it to auto-dismiss), or — if the sync already finished — the balance/Move screen, which it closes. Shows the onchain address, copies it via the QR long-press context menu (exercises Share + Copy), pastes into Send asserting Regular/onchain with and without a 5000 sat amount, then renews until the address pool is exhausted. Uses `helpers/show_onchain_address.yaml`. |
| Receive invoice → Send round-trip | done | not started | `features/receive_invoice.yaml` | Switches the type to a lightning invoice, copies it, pastes into Send asserting lightning with and without a 2000 sat amount. Requires an active channel. Uses `helpers/show_invoice.yaml`. |
| Receive LNURL / Lightning address | done | not started | `features/receive_lnurl.yaml` | The user's own lightning address — the fourth Receive type. Parks on the onchain address first so the More → "Show LNURL" switch is a real type change (with a channel *and* an address, Receive already opens on LNURL), then reads the info alert and copies the address. Branches on whether the bittr account carries an address: captures either the populated state (label + QR) or the "Unavailable" state (QR hidden). Identifies the mode structurally — the title renders as "Address" for both onchain and LNURL — via the card row: LNURL is the only type with no add-amount card, so there is no amount/description state to capture. Read-only; requires an active channel. Uses `helpers/show_onchain_address.yaml` + `helpers/show_lnurl.yaml`. |

## Send

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Send onchain | done | not started | `features/send_onchain.yaml` | Opens Send, opens the QR scanner (simulator shows the "scanning not supported" alert), reads the lightning-channel info via the "You can send…" question (QuestionViewController), switches to Regular, reads the Regular/Instant explanation alert and the onchain max-sendable info alert, enters an address + 5 EUR, confirms with the fast fee, sends, mines 6 blocks, then opens the new transaction. Requires an onchain balance. |
| Send onchain (max) | done | not started | `features/send_onchain_all.yaml` | Sends the full balance via "Send all", exercising the tight-fee path (fast fee exceeds balance → Update amount; failed broadcast → retry with the slowest fee past the low-fee warning), then mines 6 blocks and opens the new transaction. Requires an onchain balance. |
| Send lightning | done | not started | `features/send_lightning.yaml` | Pays a normal (amount-bearing) invoice, a zero-amount invoice (amount in BTC), and a Lightning Address (LNURL-pay), each confirmed via the TransactionViewController. Targets come from a separate live wallet via `LN_INVOICE`/`LN_ZERO_INVOICE`/`LN_ADDRESS`; the Paste steps need `scripts/clipboard_server.js`. Requires an active channel with outbound capacity. |
| Send → swap suggestion (no channel) | done | not started | `features/send_swap_suggestion_lightning.yaml` | Pay a lightning invoice with no usable channel → the "insufficient funds / Swap and pay" suggestion → SwapViewController auto-runs an onchain→lightning swap that pays the recipient (reuses swap.yaml's mine → "Swap complete" arc) → open the new transaction from Home. Requires a wallet with onchain funds and no channel; needs `scripts/clipboard_server.js`. |
| Send → swap suggestion (low onchain) | done | not started | `features/send_swap_suggestion_onchain.yaml` | The mirror image: pay an onchain address with too little onchain balance but a funded channel. Reads the Move-screen balances (asserts regular < 50000, instant > 75000), sizes the payment off the lightning balance (50000 + any lightning above 75000), and copies one of its own onchain receive addresses as the target → the "insufficient funds / Swap and pay" suggestion → SwapViewController auto-runs a lightning→onchain swap that pays the address (same arc as swap.yaml's first leg) → open the new transaction from Home. Requires < 50000 sats onchain and > 75000 sats of Lightning outbound. No clipboard helper (copies its own address in-app). |

## Swap & read-only screens

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Swap (lightning ↔ onchain, both directions) | done | not started | `features/swap.yaml` | Re-uses the existing channel + onchain balance from a prior buy flow. Also walks a swap TransactionViewController (Swap status screen, onchain/lightning ID copy, explorer WebsiteViewController, add note). |
| Bitcoin value chart | done | screens built (BIT-99) | `features/bitcoin_value.yaml` | Opens from Home's currency icon; waits for price data, scrubs the graph, switches span m/y/5y. Needs an existing wallet (unlocks with PIN). |
| Bitcoin map | done | screens built (BIT-99) | `features/bitcoin_map.yaml` | Opens from Home's map icon; waits for the btcmap sync, opens a place, optionally opens/closes its website in the in-app browser (WebsiteViewController), taps "Open in Maps" → Apple Maps and returns to Bittr via a coordinate tap on the "‹ bittr regtest" status-bar breadcrumb (fixed iPhone 15 geometry), closes the place, moves the map, recentres on user. Grants location via launchApp; needs an existing wallet (unlocks with PIN). **Two steps of this flow are iOS-only and need an Android rewrite before the runner sees it**: the "Open in Maps" hand-off returns to the app through a fixed-coordinate tap on the iOS status-bar breadcrumb, which has no Android counterpart (the back gesture does that job), and Android's `geo:` intent is answered by the system chooser rather than by Apple Maps. The Android map also draws no basemap until BIT-73 — every step the flow drives works; the streets under the markers do not. |
| Academy | done | screens built (BIT-99) | `features/academy.yaml` | Opens the Academy tab, plays the latest available lesson to completion (paging Next → Complete, waiting on image-download spinners; on page 2 it also taps Back to page 1 and forward again to exercise the Back button), then opens the next unlocked lesson. Needs an existing wallet (unlocks with PIN). |
| Profit screen | done | not started | _within_ `features/buy_incoming.yaml`, `features/buy_more.yaml` | No dedicated flow; the ProfitViewController is opened and asserted before and after each buy to prove the profit recalculated. |

## Settings & wallet management

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Settings (all items + device details) | done | not started | `features/settings.yaml` | Exercises every Settings item and Device-details row, the website pages, dark-mode toggle and currency switch. Needs a synced wallet (unlocks with PIN). |
| Remove wallet (from Settings) | done | not started | `features/remove_wallet.yaml` | Settings → Device details → Remove wallet; covers both the no-channel (direct reset) and active-channel (close on-chain, mine, then reset) branches. Preserves state until the wipe. Destructive. |

## PIN: unlock, recovery & lockout

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Pin unlock (subflow) | done | screens built (BIT-97) | `helpers/unlock.yaml` | Called by feature tests when the app launches into the unlock screen. |
| Forgot PIN (non-destructive) | done | screens built (BIT-97) | `features/forgot_pin.yaml` | Forgot PIN → confirm Reset → mnemonic in RestoreVC → new PIN back to 1234 → Home with the same wallet. Needs the `MNEMONIC` env var. |
| Wrong-PIN warning → Forgot PIN | done | screens built (BIT-97) | `features/pin_warning.yaml` | 3 wrong entries surface the warning alert (Okay + Forgot PIN); Forgot PIN jumps straight to the mnemonic reset. Self-contained (runs `restore_wallet` first). Non-destructive. |
| Forgot PIN → remove wallet | done | not started — needs BIT-6 | `features/forgot_pin_remove_wallet.yaml` | Removes the wallet via the Forgot-PIN path → Signup1; both channel/no-channel branches. Self-provisions a channel via `helpers/create_wallet_with_channel.yaml`. Destructive. |
| Wrong-PIN lockout (no channel) | done | screens built (BIT-97) | `features/wrong_pin.yaml` | 10 wrong PINs → immediate wipe → Signup1. Self-provisions via `restore_wallet`. Shares `helpers/wrong_pin_until_lockout.yaml`. Destructive. |
| Wrong-PIN lockout (with channel) | done | not started — needs BIT-6 | `features/wrong_pin_with_channel.yaml` | 10 wrong PINs → cooperative channel close + "Try again" retry loop → wipe → Signup1. Self-provisions via `helpers/ensure_bittr_channel.yaml`. Channel detection is best-effort (unverified). Destructive. |

## Helper subflows & orchestration

Reusable building blocks (not standalone features) and the full-suite runner.

| Flow | Purpose |
|---|---|
| `helpers/unlock.yaml` | Enter PIN 1234 on the unlock screen (also listed above). |
| `helpers/show_onchain_address.yaml` | From a freshly-opened Receive screen, make sure the onchain address is the one shown. |
| `helpers/show_invoice.yaml` | From a freshly-opened Receive screen, switch the type to a lightning invoice. |
| `helpers/show_lnurl.yaml` | From a freshly-opened Receive screen, switch the type to the user's own lightning address, asserting the LNURL card row. Needs a channel (no More button without one). |
| `helpers/wrong_pin_until_lockout.yaml` | Enter the wrong PIN ten times to trigger the lockout/wipe; shared by `wrong_pin` and `wrong_pin_with_channel`. |
| `helpers/create_wallet_with_channel.yaml` | Provision a fresh wallet *with* an open channel (onboarding + `buy_incoming`); used by `forgot_pin_remove_wallet`. |
| `helpers/ensure_bittr_channel.yaml` | Ensure an open channel exists, building the bittr account/channel as needed; used by `wrong_pin_with_channel`. **Unverified** — not yet run against Maestro. |
| `suite.yaml` | Hand-ordered orchestrator that runs every flow back-to-back in dependency order (destructive flows last). Start the helper servers via `shared/flows/test_suite.sh`; needs the `MNEMONIC` env for `forgot_pin`. |

## Not yet covered by flows

The gaps below come from a full iOS-code audit (every view controller, app target and notification path cross-referenced against the flow suite). Each item exists in the iOS app but has no flow exercising it. Grouped by priority for the Android parity effort.

Previously listed here and now covered: Restore wallet (`onboarding/restore_wallet.yaml`), Settings (`features/settings.yaml`), Profits (within the buy flows), the QR scanner (within `features/send_onchain.yaml`), the article reader (within `onboarding/happy_path_wallet.yaml`), and the Receive "LNURL" type (`features/receive_lnurl.yaml`). Send end-to-end is covered onchain (`features/send_onchain.yaml`) and lightning LNURL-**pay** (`features/send_lightning.yaml`).

### Production-scope features needing a flow (high priority)

| Feature | Where (iOS) | Notes |
|---|---|---|
| LNURL-withdraw | `SendVC/SendLNURL.swift` (`handleWithdrawAmountCompletion`, `sendWithdrawRequest`, k1) | In active production scope. Only LNURL-pay is covered today; the withdraw path has no flow. |
| External deep links | `SceneDelegate.swift`, `Core/URIs.swift`, `Info.plist` (`bitcoin:` / `lightning:` schemes) | Opening the app / Send screen from an external URI. Send flows only use the in-app Paste button. |
| Swap-file export / share | `SwapStatusViewController.swift:350` (`downloadSwapFileTapped`) | No flow taps the swap-file download/share. |

### Push notifications — in scope for parity, flows to come later

`.lightningPayout` (`buy_more.yaml` / `buy_incoming.yaml`), the three
QuestionViewController-backed types — `.information`, `.htlcExpired` and
`.unknown` (all in `notification_information.yaml`), `.lnUrl`
(`notification_lnurl.yaml`) and `.htlcIncoming`
(`notification_htlcincoming.yaml`) are exercised. The one remaining
`BittrNotificationType` case has no flow and should get an APNS-injection flow
(same technique via `scripts/push_notification.js`):

| Type | Handler (iOS) |
|---|---|
| `.swap` | `HandleSwapNotification` — swap UI is covered, but the push entry point is not |

### Per-screen interactions not yet exercised (medium priority)

Within otherwise-covered screens:

- **Receive**: description/memo field; the Bitcoin and Sats currency options (only € is tapped).
- **Confirm Send**: the **Medium** fee option (only Fast/Slow tested); the lightning-fee "?"; the back button.
- **Move**: its own Receive/Send buttons (flows launch these from Home instead); the swap-with-no-channel "instant payments" alert.
- **Value**: the **Week** chart span (month / year / 5y + scrub are tested; week is only ever the default).
- **Transaction**: the lightning-channel-fee "?"; the **Surcharge** fee explanation button (transfer + bittr fee are tested).
- **Buy**: the IBAN-card copy buttons (iban / name / code — flows read the labels but never tap copy).

### Validation / error / edge-path alerts (low priority)

Mostly defensive alerts on the onboarding/auth screens, with no flow:

- **Signup**: article cards.
- **Restore**: empty-field & invalid-mnemonic alerts; forgot-PIN wrong-mnemonic / no-cached-mnemonic alerts; Restore3 PIN-mismatch; back buttons.
- **Settings/Device**: dark-mode **device/auto** option (sun/moon tested); **Copy** for public key & device token; **pending-payout confirm** branch (only the no-payout path is tested).
- **Buy**: payment-mode server-error/retry and `lightningnotready` guard paths.

### Not parity-tracked

- **LNURL-auth (login)** — `SendLNURL.swift`, in-app-browser path in `WebsiteViewController.swift`. Not in product scope; intentionally untracked.
- **Widget** — `BittrWidget/*` price widget + `widget-deeplink://` → "openvalue". Can't be driven by Maestro (home-screen widget); the deeplink→Value path could be tested if desired. **In scope for the port but not for the v1 Maestro gate** (it can't be in a gate it can't be tested by); specified from source in [`widget-spec.md`](widget-spec.md) instead of from a screenshot, and scheduled as Phase 4 item 11. Decision: BIT-11.
- **Swap Live Activity** — `BittrWidget/SwapLiveActivity.swift` + `SwapActivityAttributes.swift`, rendered in the Dynamic Island / Lock Screen and driven by remote pushes. Maestro can't drive either surface, so it's absent from the screenshot catalog for the same reason the price widget is. Five `SwapPhase` states, each with its own copy/icon/tint. **Not yet scoped for Android** (the equivalent is an ongoing notification, not a widget) and has no spec — see `widget-spec.md` §8.
- **QR scanner (live scan)** — camera not available in the simulator; `ScannerViewController` is exercised via the "scanning not supported" path only (`send_onchain.yaml`).

### Confirmed absent in iOS (not parity gaps — do not build for parity)

No biometric / Face ID unlock (PIN only), no clipboard auto-detection on foreground, no Universal Links / associated domains, no Siri / Intents / Spotlight, no App Clip, no Share/Action extension.

## Legend

- `done` — feature is shipped and the Maestro flow passes
- `wip` — actively being ported
- `not started` — Android implementation not begun
- `blocked` — waiting on something (note in description)
- `n/a` — intentionally platform-specific (e.g., iOS Widget vs Android Glance equivalent tracked separately)
</content>
