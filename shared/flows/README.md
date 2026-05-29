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
  helpers/         Reusable subflows invoked via runFlow.
    unlock.yaml           Enters PIN 1234 on the unlock screen.
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
