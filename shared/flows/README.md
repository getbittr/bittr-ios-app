# Maestro flows

Single source of truth for end-to-end UI tests. The same YAML drives iOS and Android, using shared test IDs from `shared/test-ids/`.

## Conventions

- **Filename**: `<feature>_<state>.yaml` — e.g. `wallet_create_happy.yaml`, `send_lightning_invalid_invoice.yaml`.
- **Test IDs only** for selectors — text-based selectors are too brittle across platforms.
- **Screenshots**: each flow ends with `takeScreenshot` calls into `../docs/screenshots/<flow_name>/<step>.png`.
- **Mocks**: backend calls stubbed via Maestro Mocks. Fixtures for on-chain / lightning state come from the regtest environment (see `../docs/regtest.md`).
- **Setup/teardown**: use `runScript` to reset wallet state and seed fixtures.

## Running

```sh
# iOS simulator
maestro test --device "iPhone 15" shared/flows/

# Android emulator
maestro test --device "Pixel_8_API_34" shared/flows/

# Single flow
maestro test shared/flows/wallet_create_happy.yaml
```

## CI

Both platforms run on every PR. Both must pass; in-flight Android features are tracked on an allowlist in `../docs/parity.md`.
