# Regtest environment

Deterministic environment that drives Maestro flows on both platforms. Every component is **hosted by bittr** — no local infrastructure required to run the flows on a fresh dev machine, beyond the iOS simulator itself and the local Node helper for push notifications.

## How a regtest build is produced

The **build configuration** selects the environment — there's no build script:

- **Debug** → regtest. The `DEBUG` compilation condition makes
  `ios/bittr/Helpers/EnvironmentConfig.swift` return `.development`, which picks
  the regtest endpoints below. The Debug configuration also sets the bundle id
  to `com.bittr.bittr-regtest` and the display name to **bittr regtest**
  (`PRODUCT_BUNDLE_IDENTIFIER` / `INFOPLIST_KEY_CFBundleDisplayName`, both per
  build configuration); the widget extension follows suit
  (`com.bittr.bittr-regtest.BittrWidget`).
- **Release** → production, bundle id `com.bittr.bittr`, display name **bittr**.

So building/running the **Debug** configuration from Xcode produces a complete
regtest build — bundle id `com.bittr.bittr-regtest`, named "bittr regtest" on the
home screen, talking to the hosted regtest backend. Release is the production
"bittr" build for TestFlight. Nothing has to be changed by hand to switch
between the two.

> The Maestro flows target `appId: com.bittr.bittr-regtest`, which the Debug
> build now produces automatically — no manual bundle-id edit before a test run.
> (A previous `ios/set-environment.sh` build phase tried to do all of this from
> the git branch name; it didn't actually work and has been removed.)

## Endpoints (regtest)

| Component | URL |
|---|---|
| Bittr backend | `https://staging.getbittr.com/api` |
| Boltz API | `https://boltz-api.bittr.io/v2` |
| Boltz WebSocket | `wss://boltz-api.bittr.io/v2/ws` |
| Esplora | `https://esplora.bittr.io/api` |
| Electrum | `tcp://staging.getbittr.com:19001` |
| RGS (lightning) | `https://rapidsync.lightningdevkit.org/testnet/snapshot/` |
| Lightning peer | `0252fcaa7d532a288200a165b896219e83ededcd38bdf2f5fae909e8d6b09c99b7@109.205.181.232:9735` |

BDK and LDK both use **regtest network**.

## E2E backend endpoints

The backend exposes a couple of fixture endpoints that Maestro flows POST to (relative to the bittr API base URL):

- `POST /e2e/bank-transaction` — simulates a SEPA deposit. Body: `{ deposit_code, amount? }`. Returns `notification_id` and `bitcoin_amount`. See `shared/flows/scripts/trigger_bank_transaction.js`.
- `POST /e2e/mine-blocks` — mines N regtest blocks. Body: `{ blocks }`. See `shared/flows/scripts/mine_blocks.js`.

## Fake APNS push

Maestro's JS sandbox can't shell out, so a local Node helper bridges it:

```sh
node shared/flows/scripts/push_server.js   # leave running on :8888
```

Flows that need an incoming-payment push (`features/buy_more.yaml`) POST the APNS payload to `http://localhost:8888/push`. The helper writes it to a temp file and runs `xcrun simctl push booted com.bittr.bittr-regtest <file>`.

## Resetting state

Two ways, depending on how aggressive a wipe you need:

- **Wallet wipe** — `onboarding/fresh_install.yaml` runs `launchApp` with `clearState: true` and `clearKeychain: true`. This is what every "from scratch" test starts with.
- **Lightning channel** — opens exactly once per app install (in `buy_incoming.yaml`). Re-opening requires a fresh install.

## Still to document

These details are not yet captured here — pull from the bittr ops notes when ready:

- How the `staging.getbittr.com` backend, bitcoind/electrs behind `esplora.bittr.io`, the Lightning peer at `109.205.181.232:9735`, and `boltz-api.bittr.io` are administered. Useful for the Android dev environment too, even though Android flows talk to the same hosted infra.
- How to reset shared regtest state if multiple devs run conflicting fixtures at the same time.
