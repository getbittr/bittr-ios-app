# bittr

Bitcoin / Lightning wallet — native iOS and Android apps in one repo.

## Structure

```
ios/        Native iOS app (Swift / UIKit). Open ios/bittr.xcodeproj.
android/    Native Android app (Kotlin / Compose). Greenfield.
shared/     Cross-platform sources of truth.
  strings/    Canonical i18n JSON, generated to .xcstrings + strings.xml.
  flows/      Maestro flows — drive both apps; screenshot catalog source.
  test-ids/   Shared accessibility/test ID constants.
  assets/     Brand assets shared between platforms.
  docs/       Plan, screen inventory, parity tracker, regtest setup.
```

See `[ANDROID_PORT_PLAN.md](./ANDROID_PORT_PLAN.md)` for the Android port strategy.

## Running Maestro tests against the iOS simulator

End-to-end UI tests live in `shared/flows/` and are driven by Maestro. They run against the regtest build of the app, talking to the hosted regtest backend (see `shared/docs/regtest.md`).

### One-time setup

1. **Xcode + iOS Simulator** — install from the App Store. Open `ios/bittr.xcodeproj` and pick an iPhone 15 simulator. Then point the active developer dir at Xcode (not the Command Line Tools) so Maestro can find `simctl`:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
2. **Maestro**:
  ```sh
   curl -fsSL "https://get.maestro.mobile.dev" | bash
  ```
   Add `~/.maestro/bin` to your `PATH` if the installer doesn't do it. Verify with `maestro --version`.
3. **Node** (for the push-notification helper):
  ```sh
   brew install node
  ```
   Verify with `node --version`.
4. **Install the regtest app on the simulator** — make sure you're on a branch other than `develop` / `upgrade` (the build script flips to regtest automatically), then in Xcode pick the `bittr` scheme and Cmd-R to build & run. The app lands on the simulator as `bittrRegtest`. After the first install you can quit it — Maestro will relaunch it.

### Each test run

The push-notification helper bridges Maestro to the simulator's APNS push (the `buy_more` flow needs it). Leave it running in its own terminal:

```sh
# Terminal A — keep this running for the whole session
node shared/flows/scripts/push_server.js
```

The lightning send flow additionally needs the clipboard helper, which bridges Maestro to `xcrun simctl pbcopy` so the in-app Paste button has something to paste (see the `send_lightning.yaml` run line below). Start it the same way:

```sh
# Terminal A′ — only needed for send_lightning.yaml
node shared/flows/scripts/clipboard_server.js
```

In another terminal, from the repo root, run a flow:

```sh
# Terminal B — from the repo root

# Option 1: Full reset + onboarding from scratch:
maestro test shared/flows/onboarding/fresh_install.yaml

# Option 2: Full reset + restore existing wallet.
# Followed by onboarding through the Buy page.
maestro test shared/flows/onboarding/restore_wallet.yaml
maestro test shared/flows/features/buy_signup.yaml

# Then a feature test on the resulting wallet — opens the lightning channel:
maestro test shared/flows/features/buy_incoming.yaml

# Subsequent feature tests reuse that channel:
maestro test shared/flows/features/buy_more.yaml
maestro test shared/flows/features/receive.yaml
maestro test shared/flows/features/receive_onchain.yaml
maestro test shared/flows/features/receive_invoice.yaml
maestro test shared/flows/features/send_onchain.yaml
maestro test shared/flows/features/send_onchain_all.yaml
maestro test shared/flows/features/swap.yaml

# Lightning send (normal + zero-amount invoice + Lightning Address). All three
# targets are server-side now (invoices via the e2e endpoint / request_invoice.js,
# address = fixed e2e e2ebittr@staging.getbittr.com), so no --env is needed.
# Needs "node shared/flows/scripts/clipboard_server.js" running (Terminal A, alongside push_server)
# so the in-app Paste button has something to paste:
maestro test shared/flows/features/send_lightning.yaml

maestro test shared/flows/features/remove_wallet.yaml
# PIN lockout, no open channel (immediate wipe):
maestro test shared/flows/features/wrong_pin.yaml
# PIN lockout with an open channel (close + Try again retry loop) — set up a
# channel first (e.g. run buy_incoming.yaml):
maestro test shared/flows/features/wrong_pin_with_channel.yaml
maestro test shared/flows/features/bitcoin_value.yaml
maestro test shared/flows/features/bitcoin_map.yaml
maestro test shared/flows/features/academy.yaml
maestro test shared/flows/features/settings.yaml

# Forgot-PIN recovery test — needs the wallet's 12-word mnemonic so the
# flow can type it on the RestoreVC screen. Pass it via --env:
maestro test --env MNEMONIC="word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12" shared/flows/features/forgot_pin.yaml

# Wrong-PIN warning test — checks the 3-wrong-attempt warning appears and
# recovers via its Forgot PIN button. Self-contained (runs restore_wallet
# first via runFlow), so no env var or separate setup is needed:
maestro test shared/flows/features/pin_warning.yaml
```

Screenshots land in `shared/docs/screenshots/<flow_name>/<step>.png`.

Some flows expect specific prior state (e.g. `swap.yaml` assumes the lightning channel from `buy_incoming.yaml` is already open). The flow-level comments at the top of each YAML spell out the prerequisites.

### Troubleshooting

- **`Not enough devices connected (0) to run the requested number of shards (1)`** — `xcode-select -p` is pointing at `/Library/Developer/CommandLineTools` instead of Xcode, so Maestro can't find `simctl`. Re-run the `sudo xcode-select -s ...` command from setup step 1.
- `**push_notification.js: helper returned ...**` — the Node helper isn't running. Start it in Terminal A.
- **Flow fails on the first screen** — the simulator may not have the regtest app installed, or it's installed but not booted. Open it via Xcode once.
- **Backend errors (`/e2e/...` 502/504)** — the hosted regtest backend at `staging.getbittr.com` is down or unreachable. See `shared/docs/regtest.md`.

