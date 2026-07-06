# Parity tracker

Per-feature status of iOS vs Android implementation. Updated as Maestro flows go green on each platform.

Every flow under `shared/flows/` is listed below. iOS is the source of truth and is implemented; Android isn't scaffolded yet, so it reads `not started` across the board until the port begins.

## Onboarding & wallet setup

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Test-ID smoke | done | n/a | `onboarding/smoke.yaml` | Verifies the JSON → build.py → Swift → Maestro pipeline reaches a real ID on Signup1. |
| Create wallet (onboarding subflow) | done | not started | `onboarding/happy_path_wallet.yaml` | Drives Signup1 → Signup7 (create wallet, mnemonic, verify, set/confirm PIN). Also opens the "What is bittr?" article on Signup1 and closes it. Reusable subflow. |
| Bittr signup (onboarding subflow) | done | not started | `onboarding/happy_path_signup.yaml` | IBAN / email / OTP / info-cards from Signup7 through to Home. Reusable subflow. |
| Fresh install (full onboarding) | done | not started | `onboarding/fresh_install.yaml` | Top-level orchestrator: clearState + clearKeychain, then runs `happy_path_wallet` + `happy_path_signup`. |
| Fresh install, skip bittr signup | done | not started | `onboarding/fresh_install_skip_signup.yaml` | Creates a wallet from scratch then taps Skip on Signup7 → Home with no bittr account. |
| Restore wallet | done | not started | `onboarding/restore_wallet.yaml` | clearState + clearKeychain, restores from a fixed test mnemonic, sets PIN 1234 → Home. |

## Buy & bittr account

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Buy — first incoming bank transaction | done | not started | `features/buy_incoming.yaml` | Opens the lightning channel; needs `fresh_install` first. Also walks the TransactionViewController (copy ID, Bittr/Transfer fee alerts, add note). |
| Buy — subsequent top up | done | not started | `features/buy_more.yaml` | Preserves wallet state; needs a prior `buy_incoming` run for the channel. Requires `scripts/push_server.js`. Also walks the TransactionViewController (copy description + ID, fee alerts, add note). |
| Buy — bittr signup from Buy | done | not started | `features/buy_signup.yaml` | Completes the bittr signup from the empty Buy card via the RegisterIban modal. Needs a wallet *without* a bittr account (run `restore_wallet` first). |
| Buy — signup validation + no notifications | done | not started | `features/buy_signup_no_notifications.yaml` | Unhappy IBAN/email validation alerts + the OTP notification-permission gate, finishing on the on-chain payout fallback. Needs `fresh_install_skip_signup` first; launchApp auto-denies the iOS notification dialog. |
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

## Send

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Send onchain | done | not started | `features/send_onchain.yaml` | Opens Send, opens the QR scanner (simulator shows the "scanning not supported" alert), reads the lightning-channel info via the "You can send…" question (QuestionViewController), switches to Regular, reads the Regular/Instant explanation alert and the onchain max-sendable info alert, enters an address + 5 EUR, confirms with the fast fee, sends, mines 6 blocks, then opens the new transaction. Requires an onchain balance. |
| Send onchain (max) | done | not started | `features/send_onchain_all.yaml` | Sends the full balance via "Send all", exercising the tight-fee path (fast fee exceeds balance → Update amount; failed broadcast → retry with the slowest fee past the low-fee warning), then mines 6 blocks and opens the new transaction. Requires an onchain balance. |
| Send lightning | done | not started | `features/send_lightning.yaml` | Pays a normal (amount-bearing) invoice, a zero-amount invoice (amount in BTC), and a Lightning Address (LNURL-pay), each confirmed via the TransactionViewController. Targets come from a separate live wallet via `LN_INVOICE`/`LN_ZERO_INVOICE`/`LN_ADDRESS`; the Paste steps need `scripts/clipboard_server.js`. Requires an active channel with outbound capacity. |
| Send → swap suggestion (no channel) | done | not started | `features/send_swap_suggestion_lightning.yaml` | Pay a lightning invoice with no usable channel → the "insufficient funds / Swap and pay" suggestion → SwapViewController auto-runs an onchain→lightning swap that pays the recipient (reuses swap.yaml's mine → "Swap complete" arc) → open the new transaction from Home. Requires a wallet with onchain funds and no channel; needs `scripts/clipboard_server.js`. |
| Send → swap suggestion (low onchain) | done | not started | `features/send_swap_suggestion_onchain.yaml` | The mirror image: pay an onchain address with too little onchain balance but a funded channel → the "insufficient funds / Swap and pay" suggestion → SwapViewController auto-runs a lightning→onchain swap that pays the address (same arc as swap.yaml's first leg) → open the new transaction from Home. Requires < 60000 sats onchain and > 60000 sats of Lightning outbound; needs `scripts/clipboard_server.js`. |

## Swap & read-only screens

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Swap (lightning ↔ onchain, both directions) | done | not started | `features/swap.yaml` | Re-uses the existing channel + onchain balance from a prior buy flow. Also walks a swap TransactionViewController (Swap status screen, onchain/lightning ID copy, explorer WebsiteViewController, add note). |
| Bitcoin value chart | done | not started | `features/bitcoin_value.yaml` | Opens from Home's currency icon; waits for price data, scrubs the graph, switches span m/y/5y. Needs an existing wallet (unlocks with PIN). |
| Bitcoin map | done | not started | `features/bitcoin_map.yaml` | Opens from Home's map icon; waits for the btcmap sync, opens/closes a place, moves the map, recentres on user. Grants location via launchApp; needs an existing wallet (unlocks with PIN). |
| Academy | done | not started | `features/academy.yaml` | Opens the Academy tab, plays the latest available lesson to completion (paging Next → Complete, waiting on image-download spinners), then opens the next unlocked lesson. Needs an existing wallet (unlocks with PIN). |
| Profit screen | done | not started | _within_ `features/buy_incoming.yaml`, `features/buy_more.yaml` | No dedicated flow; the ProfitViewController is opened and asserted before and after each buy to prove the profit recalculated. |

## Settings & wallet management

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Settings (all items + device details) | done | not started | `features/settings.yaml` | Exercises every Settings item and Device-details row, the website pages, dark-mode toggle and currency switch. Needs a synced wallet (unlocks with PIN). |
| Remove wallet (from Settings) | done | not started | `features/remove_wallet.yaml` | Settings → Device details → Remove wallet; covers both the no-channel (direct reset) and active-channel (close on-chain, mine, then reset) branches. Preserves state until the wipe. Destructive. |

## PIN: unlock, recovery & lockout

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Pin unlock (subflow) | done | not started | `helpers/unlock.yaml` | Called by feature tests when the app launches into the unlock screen. |
| Forgot PIN (non-destructive) | done | not started | `features/forgot_pin.yaml` | Forgot PIN → confirm Reset → mnemonic in RestoreVC → new PIN back to 1234 → Home with the same wallet. Needs the `MNEMONIC` env var. |
| Wrong-PIN warning → Forgot PIN | done | not started | `features/pin_warning.yaml` | 3 wrong entries surface the warning alert (Okay + Forgot PIN); Forgot PIN jumps straight to the mnemonic reset. Self-contained (runs `restore_wallet` first). Non-destructive. |
| Forgot PIN → remove wallet | done | not started | `features/forgot_pin_remove_wallet.yaml` | Removes the wallet via the Forgot-PIN path → Signup1; both channel/no-channel branches. Self-provisions a channel via `helpers/create_wallet_with_channel.yaml`. Destructive. |
| Wrong-PIN lockout (no channel) | done | not started | `features/wrong_pin.yaml` | 10 wrong PINs → immediate wipe → Signup1. Self-provisions via `restore_wallet`. Shares `helpers/wrong_pin_until_lockout.yaml`. Destructive. |
| Wrong-PIN lockout (with channel) | done | not started | `features/wrong_pin_with_channel.yaml` | 10 wrong PINs → cooperative channel close + "Try again" retry loop → wipe → Signup1. Self-provisions via `helpers/ensure_bittr_channel.yaml`. Channel detection is best-effort (unverified). Destructive. |

## Helper subflows & orchestration

Reusable building blocks (not standalone features) and the full-suite runner.

| Flow | Purpose |
|---|---|
| `helpers/unlock.yaml` | Enter PIN 1234 on the unlock screen (also listed above). |
| `helpers/show_onchain_address.yaml` | From a freshly-opened Receive screen, make sure the onchain address is the one shown. |
| `helpers/show_invoice.yaml` | From a freshly-opened Receive screen, switch the type to a lightning invoice. |
| `helpers/wrong_pin_until_lockout.yaml` | Enter the wrong PIN ten times to trigger the lockout/wipe; shared by `wrong_pin` and `wrong_pin_with_channel`. |
| `helpers/create_wallet_with_channel.yaml` | Provision a fresh wallet *with* an open channel (onboarding + `buy_incoming`); used by `forgot_pin_remove_wallet`. |
| `helpers/ensure_bittr_channel.yaml` | Ensure an open channel exists, building the bittr account/channel as needed; used by `wrong_pin_with_channel`. **Unverified** — not yet run against Maestro. |
| `suite.yaml` | Hand-ordered orchestrator that runs every flow back-to-back in dependency order (destructive flows last). Start the helper servers via `shared/flows/test_suite.sh`; needs the `MNEMONIC` env for `forgot_pin`. |

## Not yet covered by flows

The gaps below come from a full iOS-code audit (every view controller, app target and notification path cross-referenced against the flow suite). Each item exists in the iOS app but has no flow exercising it. Grouped by priority for the Android parity effort.

Previously listed here and now covered: Restore wallet (`onboarding/restore_wallet.yaml`), Settings (`features/settings.yaml`), Profits (within the buy flows), the QR scanner (within `features/send_onchain.yaml`), and the article reader (within `onboarding/happy_path_wallet.yaml`). Send end-to-end is covered onchain (`features/send_onchain.yaml`) and lightning LNURL-**pay** (`features/send_lightning.yaml`).

### Production-scope features needing a flow (high priority)

| Feature | Where (iOS) | Notes |
|---|---|---|
| LNURL-withdraw | `SendVC/SendLNURL.swift` (`handleWithdrawAmountCompletion`, `sendWithdrawRequest`, k1) | In active production scope. Only LNURL-pay is covered today; the withdraw path has no flow. |
| Receive "LNURL" type | `ReceiveViewController.swift` (`tappedLnurl`, More-picker option 4) | The user's own Lightning-address receive screen is never opened (onchain / invoice / Bitcoin QR are covered). |
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
- **Map / One Place**: dismiss-place-by-background; the place **Website** button; **Open in Maps** (Apple/Google).
- **Academy**: page-**back** within a lesson (only forward paging tested).
- **Buy**: the IBAN-card copy buttons (iban / name / code — flows read the labels but never tap copy).

### Validation / error / edge-path alerts (low priority)

Mostly defensive alerts on the onboarding/auth screens, with no flow:

- **Signup**: "didn't agree" (Signup2); verify-screen empty / invalid-word / wrong-word alerts (Signup4); PIN-mismatch (Signup6); article cards; mnemonic screenshot warning; back buttons.
- **Restore**: empty-field & invalid-mnemonic alerts; forgot-PIN wrong-mnemonic / no-cached-mnemonic alerts; Restore3 PIN-mismatch; back buttons.
- **PIN**: PIN > 8 digits and < 4 digits validation alerts.
- **Bittr signup (Transfer)**: "I don't have an IBAN" → Cancel branch; **Resend OTP** (cooldown + success); change-email/back path; Transfer3 copy + screenshot buttons; Transfer4 back.
- **Settings/Device**: dark-mode **device/auto** option (sun/moon tested); **Copy** for public key & device token; **pending-payout confirm** branch (only the no-payout path is tested); applying a language change (only English exists, so only Cancel is testable).
- **Buy**: payment-mode server-error/retry and `lightningnotready` guard paths.

### Not parity-tracked

- **LNURL-auth (login)** — `SendLNURL.swift`, in-app-browser path in `WebsiteViewController.swift`. Not in product scope; intentionally untracked.
- **Widget** — `BittrWidget/*` price widget + `widget-deeplink://` → "openvalue". Can't be driven by Maestro (home-screen widget); the deeplink→Value path could be tested if desired.
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
