# Maestro flows

Single source of truth for end-to-end UI tests. The same YAML drives iOS and Android, using shared test IDs from `shared/test-ids/`.

## Layout

```
shared/flows/
  onboarding/      Wallet + bittr signup flows.
    fresh_install.yaml    Wipes state, then runs happy_path_wallet +
                          happy_path_signup (Signup1 → Home). Top-level entry.
    fresh_install_skip_signup.yaml
                          Wipes state, runs happy_path_wallet, then taps
                          "Skip" on Signup7 to land on Home without the
                          bittr signup. Top-level entry.
    fresh_install_unhappy.yaml
                          Wipes state and walks wallet creation through every
                          validation gate — confirm-statements alert, the seed
                          screenshot warning (real screenshot triggered via
                          scripts/screenshot_server.js; best-effort), an invalid
                          non-BIP39 word then a wrong recovery phrase, and the PIN
                          too-short / too-long / mismatch alerts — before
                          creating the wallet, then continuing into the bittr
                          signup and exiting via "I don't have an IBAN" →
                          "Go to wallet" to Home. The error-branch counterpart
                          to happy_path_wallet. Top-level entry.
    happy_path_wallet.yaml  Reusable subflow: wallet creation, Signup1 →
                          the wallet-ready screen (Signup7).
    happy_path_signup.yaml  Reusable subflow: bittr signup, Signup7 → Home.
    restore_wallet.yaml   Wipes state and runs the "Restore wallet" path
                          from Signup1 with a fixed test mnemonic, PIN 1234.
    smoke.yaml            Bare-minimum check that the test-ID pipeline reaches Maestro.
  features/        One file per feature, run against a non-clean state.
    buy_incoming.yaml     First-time top up — opens the lightning channel.
    buy_more.yaml         Subsequent top up — channel already open.
    notification_information.yaml  Injects the three push types that render in
                          the QuestionViewController — `.information`
                          (`bittr_notification`), `.htlcExpired`
                          (`htlc_notification` + `expired: true`) and `.unknown`
                          (unrecognised payload → fallback "Oops!") — back-to-back
                          via scripts/push_notification.js, asserting each opens
                          with the expected header + body, then closing it. Each
                          is re-pushed until it clears the app's 10s
                          notification-dedup window. Independent of wallet state
                          (auto-provisions if needed); needs
                          scripts/push_server.js.
    notification_lnurl.yaml  Fires a `.lnUrl`
                          (`lightning_address_notification`) push on the PIN
                          screen → the "Payment Request — please sign in" alert,
                          unlocks, and asserts the deferred processing re-runs on
                          sign-in (generate invoice → POST) and fails gracefully
                          ("Payment Request Failed") since no e2e endpoint accepts
                          the invoice. Metadata is gathered from the e2e Lightning
                          Address via scripts/resolve_lnurl.js. Auto-provisions a
                          wallet if needed; needs scripts/push_server.js.
    notification_htlcincoming.yaml  Fires a `.htlcIncoming` (`htlc_notification`)
                          push on the PIN screen (silent while locked), pauses so
                          it's handled before sign-in (scripts/sleep.js), unlocks,
                          and follows the deferred path through the "syncing
                          wallet" → "receiving payment" pending views to the
                          terminal "Incoming payment" alert (the no-real-payment
                          terminal state). Auto-provisions a wallet if needed;
                          needs scripts/push_server.js.
    receive.yaml          Receive screen (auto-recovers via happy_path if no wallet).
    receive_onchain.yaml  Onchain receive → send round-trip: show the onchain
                          address (waiting out the verification spinner), read
                          its info + copy it, paste into Send and assert it
                          lands as Regular/onchain (no amount, then with a 5000
                          sat amount), then renew the address until the pool is
                          exhausted. Uses helpers/show_onchain_address.yaml.
    receive_invoice.yaml  Lightning invoice receive → send round-trip: switch
                          the type to a lightning invoice, read its info + copy
                          it, paste into Send and assert it lands as lightning
                          (no amount, then with a 2000 sat amount). Needs an
                          active channel. Uses helpers/show_invoice.yaml.
    send_onchain.yaml     Onchain send end-to-end: open Send, switch to
                          Regular, wait out the BDK sync spinner, enter an
                          address and a 5 EUR amount, confirm on the Confirm
                          screen (address + euro amount, fast fee), send,
                          mine 6 blocks, then open the new transaction from
                          the history table.
    send_onchain_all.yaml Onchain send of the maximum balance: tap "Send all",
                          then exercise the tight-fee path — fast fee exceeds
                          the balance → Update amount, and on a failed broadcast
                          retry with the slowest fee — before mining and opening
                          the new transaction.
    send_lightning.yaml   Lightning send end-to-end across all three invoice
                          types — a normal (amount-bearing) invoice, a
                          zero-amount invoice (enter the amount in BTC), and a
                          Lightning Address (LNURL-pay). All three targets are
                          server-side now: the two invoices come from the e2e
                          endpoint (scripts/request_invoice.js) and the address
                          is the fixed e2e e2ebittr@staging.getbittr.com — no env vars.
                          The Paste steps need scripts/clipboard_server.js
                          running. Requires an active channel with outbound
                          capacity.
    send_swap_suggestion_lightning.yaml  Pay a lightning invoice with NO channel:
                          Send → paste an amount-bearing invoice → Next → the
                          "insufficient funds / Swap and pay" suggestion →
                          SwapViewController auto-runs an onchain→lightning swap
                          that pays the recipient (reusing swap.yaml's reverse-
                          swap mine → "Swap complete" arc), then opens the new
                          transaction from Home. Requires a wallet with onchain
                          funds and no usable channel; needs
                          scripts/clipboard_server.js.
    send_swap_suggestion_onchain.yaml  The mirror image: pay an onchain address
                          with too little onchain balance but a funded channel.
                          Send → paste an onchain address (switches to Regular) →
                          enter 60000 → Next → the "insufficient funds / Swap and
                          pay" suggestion → SwapViewController auto-runs a
                          lightning→onchain swap that pays the address (same arc
                          as swap.yaml's first leg: Proceed → "Swap complete" →
                          mine), then opens the new transaction from Home.
                          Requires a wallet with < 60000 sats onchain and > 60000
                          sats of Lightning outbound; needs
                          scripts/clipboard_server.js.
    swap.yaml             Lightning ↔ onchain, both directions.
    payment_mode.yaml     The lightning/onchain payout-mode toggle on the Buy
                          card (PATCH /customer/payment-mode). Self-provisions:
                          restores a wallet if none and creates an order
                          (buy_signup) if there's no deposit code, then toggles
                          the switch and asserts the server-confirmed state.
    forgot_pin.yaml       Forgot-PIN recovery from the unlock screen — types
                          the cached mnemonic and resets the PIN. Requires
                          the MNEMONIC env var (see Running below).
    buy_signup.yaml       Bittr signup from inside the Buy page — assumes a
                          wallet without a bittr account (run
                          onboarding/restore_wallet.yaml first).
    buy_signup_no_notifications.yaml
                          The unhappy-path counterpart to buy_signup: walks
                          the "I don't have an IBAN" alert, the invalid-IBAN
                          and invalid-email validation alerts, a wrong OTP
                          (incorrect-code alert), and the OTP notification gate
                          (Receive-notifications prompt → iOS system dialog,
                          which Maestro auto-denies via launchApp permissions
                          notifications:deny → the denied-notifications gate).
                          It then re-enters the correct OTP and, at each gate,
                          taps "Continue" to finish signup via the on-chain
                          fallback (payment_mode=onchain), reusing
                          buy_signup's tail, and ends on the Buy page with the
                          new cell and the payout-mode switch OFF. Requires an
                          existing wallet without a bittr account (run
                          onboarding/fresh_install_skip_signup.yaml first) —
                          it only unlocks, since auto-creating a wallet would
                          wipe the permissions config.
    remove_wallet.yaml    Settings → Device details → Remove wallet. Handles
                          both branches (active channel → close → mine →
                          re-trigger; no channel → direct confirm).
    forgot_pin_remove_wallet.yaml
                          Forgot PIN → Reset → RestoreVC → Remove wallet. The
                          resettingPin removal, same two branches as
                          remove_wallet.yaml. Destructive (drops to Signup1);
                          no MNEMONIC env var needed.
    wrong_pin.yaml        PIN lockout with NO open channel — ten wrong PINs
                          wipe the wallet (immediately, nothing to close) and
                          drop back to Signup1. Self-provisions: restores a
                          wallet first if none exists. Shares the 10 attempts via
                          helpers/wrong_pin_until_lockout.yaml.
    wrong_pin_with_channel.yaml  PIN lockout WITH an open channel — the wipe
                          cooperatively closes the channel and runs the "still
                          closing" → mine → Try again retry loop before landing
                          on Signup1. Self-provisions: restores a wallet if
                          needed and builds a channel (via
                          helpers/ensure_bittr_channel.yaml) if none is detected.
                          Same shared lockout helper.
    pin_warning.yaml      The 3-wrong-attempt warning on the unlock screen,
                          then recovery via its Forgot PIN button. Self-
                          contained — runs restore_wallet.yaml first (runFlow)
                          for a clean counter, so no env var or separate setup
                          is needed.
    bitcoin_value.yaml    Bitcoin price chart (ValueViewController) — unlock,
                          open it from Home's currency icon, wait for the
                          price data, scrub the graph, switch span to m/y/5y.
    bitcoin_map.yaml      Bitcoin map (MapViewController) — unlock, open it
                          from Home's map icon, wait for the places to sync,
                          open/close a place, move the map, recentre on user.
    academy.yaml          Academy tab (AcademyViewController) — unlock, open
                          the latest available lesson, page through it to
                          Complete, then open the next freshly-unlocked lesson.
    settings.yaml         Settings pop-up end to end — visits Get support /
                          Privacy / Terms (WebsiteViewController), then every
                          Device-details row: dark-mode toggle, language,
                          currency (EUR↔CHF, verified on Home), device token,
                          public key, Bittr peer / pending payout, and
                          Lightning connections (QuestionViewController).
  helpers/         Reusable subflows invoked via runFlow.
    unlock.yaml           Enters PIN 1234 on the unlock screen.
    wrong_pin_until_lockout.yaml  Enters the wrong PIN ten times on the unlock
                          screen to trigger the lockout + background wipe; stops
                          at the 10th confirm so the caller can handle the
                          channel/no-channel divergence. Used by wrong_pin.yaml
                          and wrong_pin_with_channel.yaml.
    ensure_bittr_channel.yaml  Ensures the wallet has an open Lightning channel:
                          runs buy_signup (if no bittr account) + buy_incoming.
                          Invoked by wrong_pin_with_channel.yaml only when no
                          channel is detected. (Best-effort / unverified.)
    show_onchain_address.yaml  From a freshly-opened Receive screen, waits out
                          the QR spinner and switches the type to the onchain
                          Address (via More → Address) when a channel is present.
    show_invoice.yaml     From a freshly-opened Receive screen, switches the
                          type to a lightning invoice (via More → Create
                          invoice) and waits out the QR spinner. Needs a channel.
  scripts/         Maestro `runScript` helpers (GraalJS).
    mine_blocks.js              POST /e2e/mine-blocks on the regtest backend.
    trigger_bank_transaction.js POST /e2e/bank-transaction (incoming SEPA).
    push_notification.js        POSTs an APNS payload to push_server.js.
    push_server.js              Local helper bridging Maestro → `xcrun simctl push`.
    set_clipboard.js            POSTs output.clipboardText to clipboard_server.js.
    clipboard_server.js         Local helper bridging Maestro → `xcrun simctl
                                pbcopy` so flows can seed the OS clipboard for
                                the in-app Paste button (send_lightning.yaml).
    parse_mnemonic.js           Splits the MNEMONIC env var into
                                output.words[1..12] for forgot_pin.yaml.
    resolve_lnurl.js            GETs a Lightning Address's /.well-known/lnurlp
                                params (metadata + username) so
                                notification_lnurl.yaml can build a realistic
                                `.lnUrl` payload; static fallback if offline.
    sleep.js                    Busy-waits output.sleepMs ms (Maestro has no
                                native sleep) so a flow can let the app handle a
                                push before the next step (notification_htlcincoming).
    trigger_screenshot.js       Asks screenshot_server.js to fire a real
                                Simulator screenshot (posts the screenshot
                                notification, unlike Maestro's takeScreenshot);
                                best-effort (fresh_install_unhappy).
    screenshot_server.js        Local helper bridging Maestro → `osascript`
                                clicking the Simulator's "Device > Trigger
                                Screenshot". Needs Accessibility permission, and
                                the device's Settings > General > Screen Capture >
                                "Full-Screen Previews" turned OFF (else the
                                preview covers the app and blocks the flow).
```

## Conventions

- **Filename**: `<state>.yaml` within the appropriate subdir. Reusable subflows live in `helpers/`.
- **Test IDs only** for selectors — text-based selectors are too brittle across platforms.
- **Screenshots**: each `takeScreenshot` path is `shared/docs/screenshots/<flow_name>/<step>` — Maestro resolves it against the CWD where `maestro test` is run (the repo root), so the prefix must be the full repo-relative path.
- **Mocks**: backend calls stubbed via Maestro Mocks. Fixtures for on-chain / lightning state come from the regtest environment (see `../docs/regtest.md`).
- **Setup/teardown**: use `runScript` to reset wallet state and seed fixtures.

## Running

```sh
# Whole suite (starts the helper servers, then runs suite.yaml in order)
shared/flows/test_suite.sh
shared/flows/test_suite.sh --device "iPhone 15"   # extra args pass to maestro

# Single flow
maestro test shared/flows/onboarding/fresh_install.yaml
```

Don't run `maestro test shared/flows/` to get the whole suite: a folder run
executes flows in alphabetical order with no dependency awareness, but the
feature flows deliberately share wallet state and several are destructive
(`send_onchain_all` drains the onchain balance; `wrong_pin` / `remove_wallet`
/ `forgot_pin_remove_wallet` wipe the wallet). `suite.yaml` is a hand-ordered orchestrator that runs them so
dependencies hold and the wipes come last; `test_suite.sh` wraps it, starting
the `push`/`clipboard` helper servers (which Maestro can't start itself) and
passing the `MNEMONIC` env that `forgot_pin` needs. A failure aborts the suite
at that flow — run the individual flow above to debug.

### Push notifications

Flows that exercise incoming-payment alerts (`features/buy_more.yaml`) need a fake APNS push delivered to the simulator. Maestro's JS sandbox can't shell out, so a local helper bridges the gap:

```sh
# In a separate terminal, before running the flow:
node shared/flows/scripts/push_server.js
```

The flow then POSTs the payload to `http://localhost:8888/push`, which `xcrun simctl push`'s it to the booted simulator.

### Forgot PIN

`features/forgot_pin.yaml` exercises the "Forgot PIN" recovery path. The flow has to type the wallet's 12-word mnemonic on the RestoreVC screen, and Maestro's JS sandbox can't read it out of the simulator on its own — pass it in via env var:

```sh
maestro test --env MNEMONIC="word1 word2 ... word12" shared/flows/features/forgot_pin.yaml
```

Use the same mnemonic the wallet was set up with (the one happy_path_wallet generated during onboarding). `parse_mnemonic.js` validates the count and splits the words into `output.words[1..12]`.

### Lightning send

`features/send_lightning.yaml` pays a normal invoice, a zero-amount invoice and a Lightning Address. All three targets are server-side now — the two invoices are generated per run via the e2e endpoint (`scripts/request_invoice.js`, always fresh) and the address is the fixed e2e `e2ebittr@staging.getbittr.com` — so no env vars are needed. The flow also exercises the in-app **Paste** button, and Maestro can't write the OS clipboard itself (`copyTextFrom` only fills Maestro's own variable), so a bridge — the same pattern as `push_server.js` — pipes text to `xcrun simctl pbcopy`:

```sh
# In a separate terminal, before running the flow:
node shared/flows/scripts/clipboard_server.js

maestro test shared/flows/features/send_lightning.yaml
```

The flow sets `output.clipboardText` before each paste; `set_clipboard.js` POSTs it to the helper, which `pbcopy`'s it onto the booted simulator. iOS may show a one-off "Allow Paste" prompt — the flow accepts it automatically.

## CI

Both platforms run on every PR. Both must pass; in-flight Android features are tracked on an allowlist in `../docs/parity.md`.
