# Maestro flows

Single source of truth for end-to-end UI tests. The same YAML drives iOS and Android, using shared test IDs from `shared/test-ids/`.

## Layout

```
shared/flows/
  onboarding/      Wallet + bittr signup flows.
    fresh_install.yaml    Wipes state and runs happy_path. Top-level entry.
    happy_path.yaml       Reusable subflow: Signup1 → Home.
    restore_wallet.yaml   Wipes state and runs the "Restore wallet" path
                          from Signup1 with a fixed test mnemonic, PIN 1234.
    smoke.yaml            Bare-minimum check that the test-ID pipeline reaches Maestro.
  features/        One file per feature, run against a non-clean state.
    buy_incoming.yaml     First-time top up — opens the lightning channel.
    buy_more.yaml         Subsequent top up — channel already open.
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
    swap.yaml             Lightning ↔ onchain, both directions.
    forgot_pin.yaml       Forgot-PIN recovery from the unlock screen — types
                          the cached mnemonic and resets the PIN. Requires
                          the MNEMONIC env var (see Running below).
    buy_signup.yaml       Bittr signup from inside the Buy page — assumes a
                          wallet without a bittr account (run
                          onboarding/restore_wallet.yaml first).
    remove_wallet.yaml    Settings → Restore wallet. Handles both branches
                          (active channel → close → mine → re-trigger; no
                          channel → direct confirm).
    wrong_pin.yaml        PIN lockout from the unlock screen — ten wrong
                          PINs wipe the wallet and drop back to Signup1
                          (run onboarding/restore_wallet.yaml first).
    bitcoin_value.yaml    Bitcoin price chart (ValueViewController) — unlock,
                          open it from Home's currency icon, wait for the
                          price data, scrub the graph, switch span to m/y/5y.
    bitcoin_map.yaml      Bitcoin map (MapViewController) — unlock, open it
                          from Home's map icon, wait for the places to sync,
                          open/close a place, move the map, recentre on user.
    academy.yaml          Academy tab (AcademyViewController) — unlock, open
                          the latest available lesson, page through it to
                          Complete, then open the next freshly-unlocked lesson.
  helpers/         Reusable subflows invoked via runFlow.
    unlock.yaml           Enters PIN 1234 on the unlock screen.
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
    parse_mnemonic.js           Splits the MNEMONIC env var into
                                output.words[1..12] for forgot_pin.yaml.
```

## Conventions

- **Filename**: `<state>.yaml` within the appropriate subdir. Reusable subflows live in `helpers/`.
- **Test IDs only** for selectors — text-based selectors are too brittle across platforms.
- **Screenshots**: each `takeScreenshot` path is `shared/docs/screenshots/<flow_name>/<step>` — Maestro resolves it against the CWD where `maestro test` is run (the repo root), so the prefix must be the full repo-relative path.
- **Mocks**: backend calls stubbed via Maestro Mocks. Fixtures for on-chain / lightning state come from the regtest environment (see `../docs/regtest.md`).
- **Setup/teardown**: use `runScript` to reset wallet state and seed fixtures.

## Running

```sh
# Whole suite, iOS simulator
maestro test --device "iPhone 15" shared/flows/

# Whole suite, Android emulator
maestro test --device "Pixel_8_API_34" shared/flows/

# Single flow
maestro test shared/flows/onboarding/fresh_install.yaml
```

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

Use the same mnemonic the wallet was set up with (the one happy_path generated during onboarding). `parse_mnemonic.js` validates the count and splits the words into `output.words[1..12]`.

## CI

Both platforms run on every PR. Both must pass; in-flight Android features are tracked on an allowlist in `../docs/parity.md`.
