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
4. **Install the regtest app on the simulator** — in Xcode pick the `bittr` scheme and Cmd-R to build & run with the **Debug** configuration (the default for Run). Debug builds target the regtest backend (via the `DEBUG` compilation condition in `EnvironmentConfig`) and are automatically named "bittr regtest" with bundle id `com.bittr.bittr-regtest` — matching the `appId` the Maestro flows use; Release targets production as `com.bittr.bittr`. No manual bundle-id change is needed. After the first install you can quit it — Maestro will relaunch it.

### One-command suite

`shared/flows/test_suite.sh` wraps the whole thing: preflight checks (xcode-select, maestro, node, booted simulator, apps installed), starts the helper servers (`push_server.js`, `clipboard_server.js`; `screenshot_server.js` with `--unhappy`) if they aren't already running — cleaning up only the ones it started — then runs flows in a valid stateful order with a pass/fail summary.

```sh
shared/flows/test_suite.sh                 # core suite: fresh_install → buy_incoming → buy_more → swap
shared/flows/test_suite.sh --evil          # core + the two EvilBoltz flows
shared/flows/test_suite.sh --evil-only     # just the EvilBoltz flows
shared/flows/test_suite.sh features/receive.yaml features/send_onchain.yaml
shared/flows/test_suite.sh --keep-going    # don't stop on first failure
shared/flows/test_suite.sh --expect-vulnerable --evil-only   # red run on an
                                           # unfixed build: evil-flow failures
                                           # count as expected, exit 0
```

### Each test run

The push-notification helper bridges Maestro to the simulator's APNS push (the `buy_more`, `notification_information` and `notification_lnurl` flows need it). Leave it running in its own terminal:

```sh
# Terminal A — keep this running for the whole session
node shared/flows/scripts/push_server.js
```

The lightning send flows additionally need the clipboard helper, which bridges Maestro to `xcrun simctl pbcopy` so the in-app Paste button has something to paste (see the `send_lightning.yaml` / `send_swap_suggestion_lightning.yaml` run lines below). Start it the same way:

```sh
# Terminal A′ — needed for send_lightning.yaml and send_swap_suggestion_lightning.yaml
node shared/flows/scripts/clipboard_server.js
```

In another terminal, from the repo root, run a flow:

```sh
# Terminal B — from the repo root

# Option 1: Full reset + onboarding from scratch:
maestro test shared/flows/onboarding/fresh_install.yaml

# Option 1b: Full reset + wallet creation, skipping the bittr signup
# (taps "Skip" on Signup7 and lands on Home):
maestro test shared/flows/onboarding/fresh_install_skip_signup.yaml

# Option 1c: Full reset + wallet creation through every validation gate
# (confirm-statements / screenshot-warning / invalid-word / wrong-phrase /
# PIN-length alerts), then Skip to Home — the onboarding error-path counterpart.
# To exercise the seed-phrase screenshot warning (optional): run
# "node shared/flows/scripts/screenshot_server.js" (needs Accessibility
# permission), AND on the simulated device turn OFF Settings > General > Screen
# Capture > Full-Screen Previews (else the screenshot preview covers the app and
# blocks the flow). Without this setup the screenshot step is skipped.
maestro test shared/flows/onboarding/fresh_install_unhappy.yaml

# Option 2: Full reset + restore existing wallet.
# Followed by onboarding through the Buy page.
maestro test shared/flows/onboarding/restore_wallet.yaml
maestro test shared/flows/features/buy_signup.yaml

# Buy-signup validation + notification-gate test (unhappy path, then on-chain
# fallback). Requires an existing wallet without a bittr account (run
# fresh_install_skip_signup.yaml first) — it only unlocks, no auto-create.
# launchApp's permissions config makes Maestro auto-deny the iOS notification
# dialog. On the OTP screen it first exercises resend (resend → email-resent
# alert; a second tap in cooldown → wait-30s alert → Change email → re-verify).
# It enters a wrong OTP first (incorrect-code alert), then the correct one; at
# each denied-notifications gate it taps "Continue" to finish signup on-chain.
# On the Transfer3 success screen it copies the IBAN/name/code (Copied alerts)
# and taps Screenshot (Saved alert), on Transfer4 taps Back → Transfer3 → Finish,
# then ends on Buy with the payout-mode switch OFF:
maestro test shared/flows/features/buy_signup_no_notifications.yaml

# Then a feature test on the resulting wallet — opens the lightning channel:
maestro test shared/flows/features/buy_incoming.yaml

# Subsequent feature tests reuse that channel:
maestro test shared/flows/features/buy_more.yaml

# The three QuestionViewController-backed push types (.information, .htlcExpired,
# .unknown), injected back-to-back → each opens the QuestionViewController.
# Independent of wallet state (auto-provisions if needed); needs push_server.js:
maestro test shared/flows/features/notification_information.yaml

# The .lnUrl (Lightning-Address) push, fired on the PIN screen → "please sign in"
# alert, then deferred processing on unlock. Needs push_server.js:
maestro test shared/flows/features/notification_lnurl.yaml

# The .htlcIncoming push, fired on the PIN screen (silent) → deferred processing
# on unlock through to the terminal "Incoming payment" alert. Needs push_server.js:
maestro test shared/flows/features/notification_htlcincoming.yaml

maestro test shared/flows/features/receive.yaml
maestro test shared/flows/features/receive_onchain.yaml
maestro test shared/flows/features/receive_invoice.yaml
maestro test shared/flows/features/send_onchain.yaml
maestro test shared/flows/features/send_onchain_all.yaml
maestro test shared/flows/features/swap.yaml

# Payout-mode toggle (lightning <-> onchain) on the Buy card. Self-provisioning
# (restores a wallet + creates an order if needed), so it can run on its own:
maestro test shared/flows/features/payment_mode.yaml

# Lightning send (normal + zero-amount invoice + Lightning Address). All three
# targets are server-side now (invoices via the e2e endpoint / request_invoice.js,
# address = fixed e2e e2ebittr@staging.getbittr.com), so no --env is needed.
# Needs "node shared/flows/scripts/clipboard_server.js" running (Terminal A, alongside push_server)
# so the in-app Paste button has something to paste:
maestro test shared/flows/features/send_lightning.yaml

# Pay a lightning invoice with NO channel — the app suggests "Swap and pay",
# which runs an onchain->lightning swap that pays the recipient. Requires a
# wallet with onchain funds and no usable channel; also needs clipboard_server.js:
maestro test shared/flows/features/send_swap_suggestion_lightning.yaml

# The mirror image — pay an onchain address with too little onchain balance but a
# funded channel; the app suggests "Swap and pay", running a lightning->onchain
# swap that pays the address. Reads the balances from the Move screen, sizes the
# payment off the lightning balance, and pays one of its own receive addresses.
# Requires < 50000 sats onchain and > 75000 sats of Lightning outbound. No
# clipboard helper needed (it copies its own address in-app):
maestro test shared/flows/features/send_swap_suggestion_onchain.yaml

maestro test shared/flows/features/remove_wallet.yaml
maestro test shared/flows/features/forgot_pin_remove_wallet.yaml
# PIN lockout, no open channel (immediate wipe):
maestro test shared/flows/features/wrong_pin.yaml
# PIN lockout with an open channel (close + Try again retry loop) — set up a
# channel first (e.g. run buy_incoming.yaml):
maestro test shared/flows/features/wrong_pin_with_channel.yaml
maestro test shared/flows/features/bitcoin_value.yaml
# Bitcoin map: open a place, optionally its website (in-app browser), tap Open
# in Maps → Apple Maps and return via a coordinate tap on the "‹ bittr regtest"
# breadcrumb (fixed iPhone 15 geometry). Needs an existing wallet (unlocks PIN):
maestro test shared/flows/features/bitcoin_map.yaml
# Academy: play a lesson to completion (Next → Complete), tapping Back to page 1
# and forward again on page 2 to exercise the Back button; then open the next
# unlocked lesson. Needs an existing wallet (unlocks with PIN):
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

### EvilBoltz swap-tamper testing ("bittr evil" app)

The shared **`bittr evil`** scheme builds the `Debug-EvilBoltz` configuration: the regtest app with the [EvilBoltz](../ios/bittr/Helpers/EvilBoltz.swift) fault-injection harness **armed by default** (mode `all`), its own bundle id `com.bittr.bittr-evil` and display name "bittr evil". It installs alongside "bittr regtest" and has a **separate keychain/wallet** (SecureStore scopes to the bundle id), so destructive swap tests never touch your normal test wallet. Build & run it once from Xcode like any other scheme.

It simulates a malicious Boltz server (SEC-01/SEC-02, see `SECURITY_REVIEW.md`): reverse swaps receive a real regtest invoice whose preimage only the "attacker" knows; submarine swaps receive an attacker-controlled lockup address. A vulnerable build pays/sends and loses the funds; a fixed build must abort at swap creation before any payment.

```yaml
# In a Maestro flow — no arguments needed, the app is armed out of the box:
- launchApp:
    appId: com.bittr.bittr-evil

# Control run (same app, harness disarmed):
- launchApp:
    appId: com.bittr.bittr-evil
    arguments: ["-evilBoltz", "off"]

# Or arm the NORMAL regtest app ad hoc:
- launchApp:
    appId: com.bittr.bittr-regtest
    arguments: ["-evilBoltz", "wrong-address"]   # or wrong-invoice / all
```

Push-driven flows against the evil app need the push helper to target its bundle id: POST to `http://localhost:8888/push?bundleId=com.bittr.bittr-evil` (default remains `com.bittr.bittr-regtest`, also overridable process-wide via `BITTR_PUSH_BUNDLE_ID`).

**End-to-end EvilBoltz flows** (SEC-01/SEC-02). Each wipes and fully reprovisions the evil app (wallet → signup → funded channel [→ onchain deposit]), then attempts the tampered swap. On a **vulnerable** build the flow drives the theft to its stuck end state and then **fails loudly** — that failure is the demonstration; on a **fixed** build the swap aborts before any payment and the flow passes:

```sh
# Terminal A — needed for the fake payout pushes:
node shared/flows/scripts/push_server.js

# SEC-01: reverse swap pays an invoice whose preimage only the attacker knows.
# Vulnerable = lightning payment goes out, no onchain coins ever arrive:
maestro test shared/flows/features/evil_boltz_wrong_invoice.yaml

# SEC-02: submarine swap pays an attacker-controlled lockup address.
# Vulnerable = onchain tx lands at the attacker's address (watch
# https://esplora.bittr.io/address/bcrt1pcz9mae53csyv8d0t4fansh446jdjey2pg2djn5utqver5e42gp5s507k3j),
# no refund path exists:
maestro test shared/flows/features/evil_boltz_wrong_address.yaml
```

Also, `onboarding/fresh_install.yaml` and `features/buy_incoming.yaml` accept an injected app: set `output.APP_ID` before `runFlow`-ing them (see `helpers/evil_bootstrap.yaml`) — the default stays `com.bittr.bittr-regtest`.

Screenshots land in `shared/docs/screenshots/<flow_name>/<step>.png`.

Some flows expect specific prior state (e.g. `swap.yaml` assumes the lightning channel from `buy_incoming.yaml` is already open). The flow-level comments at the top of each YAML spell out the prerequisites.

### Troubleshooting

- **`Not enough devices connected (0) to run the requested number of shards (1)`** — `xcode-select -p` is pointing at `/Library/Developer/CommandLineTools` instead of Xcode, so Maestro can't find `simctl`. Re-run the `sudo xcode-select -s ...` command from setup step 1.
- `**push_notification.js: helper returned ...**` — the Node helper isn't running. Start it in Terminal A.
- **Flow fails on the first screen** — the simulator may not have the regtest app installed, or it's installed but not booted. Open it via Xcode once.
- **Backend errors (`/e2e/...` 502/504)** — the hosted regtest backend at `staging.getbittr.com` is down or unreachable. See `shared/docs/regtest.md`.

