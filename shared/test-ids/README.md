# Test IDs

Canonical accessibility/test ID constants used by Maestro flows. Defined here once, generated to platform-native code.

- **iOS**: `ios/bittr/Helpers/TestIDs.swift` — `enum TestID { ... }`, set on `view.accessibilityIdentifier`.
- **Android**: `android/core/common/src/main/kotlin/com/bittr/android/core/common/TestIDs.kt` — `object TestID { ... }`, set with `Modifier.testTag()`.

> **Android gotcha, worth knowing before you debug a flow for an hour:** Compose
> `Modifier.testTag` is *not* exposed to the accessibility tree Maestro reads. It
> works only because `testTagsAsResourceId = true` is set on the root node in
> `android/app/src/main/kotlin/com/bittr/android/MainActivity.kt`. Remove that and
> every `assertVisible: id:` fails with "element not found" while the app looks
> completely correct on screen.

## Source format

`test-ids.json` is hierarchical. Branches are JSON objects, leaves are `null`. The full ID for a leaf is the dot-joined path from the root, identical on both platforms.

```json
{
  "signup": {
    "create": {
      "start": {
        "createWalletButton": null
      }
    }
  }
}
```

→ Swift: `TestID.Signup.Create.Start.createWalletButton == "signup.create.start.createWalletButton"`
→ Kotlin: `TestID.Signup.Create.Start.createWalletButton == "signup.create.start.createWalletButton"`

JSON keys are camelCase. Branches get PascalCased in code (`Signup`, `Create`); leaves stay camelCase (`createWalletButton`). The string ID — what Maestro matches — is the lowercased dot path.

### Runtime-indexed IDs

Some IDs get a row/position number appended when the view is built: the mnemonic word labels, the history table cells, the alert buttons. The flows assert on the numbered form (`history.transactionButton0`, `alert.button.1`, `signup.create.mnemonic.word12`), so the number has to be produced by the *same rule* on both platforms — hand-interpolating it at each call site is how one platform ends up 1-based and the other 0-based.

Such a leaf carries an `_index` spec instead of `null`:

```json
"history": { "transactionButton": { "_index": { "offset": 0 } } },
"alert":   { "button":            { "_index": { "offset": 0, "separator": "." } } },
"signup":  { "create": { "mnemonic": { "word": { "_index": { "offset": 1 } } } } }
```

- `offset` — what position 0 is numbered as. `0` for table rows, `1` for the mnemonic words (`word1` … `word12`).
- `separator` — inserted before the number. Empty by default; `"."` for `alert.button.0`.

It generates the base constant *and* an `…At()` helper:

```kotlin
const val transactionButton = "history.transactionButton"
fun transactionButtonAt(position: Int) = "history.transactionButton$position"   // 0 → …Button0
fun wordAt(position: Int) = "signup.create.mnemonic.word${position + 1}"        // 0 → …word1
```

Always pass the **0-based position** — the loop index, the `indexPath.row` — and let the helper apply the offset. This mirrors iOS, where `Signup3ViewController` writes `"\(TestID.Signup.Create.Mnemonic.word)\(index + 1)"` for a 0-based `index`.

## Checking flows against the registry

```sh
./shared/test-ids/check_flow_ids.py            # fails on any unregistered ID
./shared/test-ids/check_flow_ids.py --unused   # also lists registered-but-unselected IDs
```

Every `id:` selector in `shared/flows/**` must resolve to a plain leaf or to an indexed leaf plus a number. An unregistered ID fails at run time as "element not found", which looks exactly like a missing `testTag` in the app and costs an emulator boot to diagnose. CI runs this before the build.

## Naming convention

```
<feature>.<screen>.<element>
```

- `feature`: top-level area (`signup`, `wallet`, `send`, `receive`, `settings`, `swap`, `buy`, `academy`, `map`, `profits`, `transaction`).
- `screen`: specific view within the feature (`create`, `restore`, `confirm`, `lightning`, `onchain`).
- `element`: stable name describing role, not type (`continueButton` not `button1`, `mnemonicField` not `textField3`).

## Generator

```sh
./shared/test-ids/build.py
```

Regenerates both `ios/bittr/Helpers/TestIDs.swift` and the Android `TestIDs.kt`. Run after editing `test-ids.json`. The generated files are committed for diff visibility, and CI (`.github/workflows/android-maestro.yml`) fails the build if they are stale — editing the JSON without regenerating is how the two platforms drift apart silently.

`--platform ios|android|both` limits which file is written (default `both`). The Android port may not change iOS sources without sign-off, so registry additions made for the port are generated with `--platform android` and `TestIDs.swift` is left to lag until the iOS regeneration is signed off. CI treats a stale Kotlin file as an error and a stale Swift file as a notice, for the same reason.

Never edit a generated file directly. That drift has already happened once: `transaction.descriptionLabel` was added straight to `TestIDs.swift` and used by `TransactionViewController` and `features/remove_wallet.yaml`, but never added to `test-ids.json` — so the next regeneration would have deleted it and broken the iOS build. It is in the JSON now, and the CI staleness check exists so it cannot recur.

## Workflow when adding an ID

1. Add the leaf in `test-ids.json` at the appropriate hierarchy.
2. Run `./shared/test-ids/build.py`.
3. Reference in iOS: `view.accessibilityIdentifier = TestID.Signup.Create.Start.createWalletButton`.
4. Reference in Android (later): `Modifier.testTag(TestID.Signup.Create.Start.createWalletButton)`.
5. Reference in the Maestro flow: `tapOn: id: "signup.create.start.createWalletButton"`.

## Migrating existing `accessibilityIdentifier` data usages

The iOS app currently uses `accessibilityIdentifier` as a string-tag userInfo for buttons and views — to ferry article slugs, settings row IDs, fee levels, and similar through tap handlers. We need that field reserved for Maestro test IDs, so a helper is provided:

`UIView+AppTag.swift` adds an `appTag: String?` property (associated-object backed). Migration: replace data-storage uses of `accessibilityIdentifier` with `appTag`.

### Files to migrate

| File | Pattern |
|---|---|
| `ios/bittr/Signup/SignupSetArticle.swift` | sets `articleButton.accessibilityIdentifier = articleSlug` |
| `ios/bittr/Signup/Create Wallet/Signup1ViewController.swift` | reads slug from `sender.accessibilityIdentifier` in `articleButtonTapped` |
| `ios/bittr/Signup/Create Wallet/Signup2ViewController.swift` | same |
| `ios/bittr/Signup/Create Wallet/Signup3ViewController.swift` | same |
| `ios/bittr/Signup/Create Wallet/Signup7ViewController.swift` | same |
| `ios/bittr/Signup/Bittr Signup/Transfer1ViewController.swift` | same |
| `ios/bittr/Signup/Restore Wallet/RestoreViewController.swift` | same |
| `ios/bittr/Signup/Bittr Signup/Transfer3ViewController.swift` | IBAN/name/code data on buttons for clipboard copy |
| `ios/bittr/Buy/BuyViewController.swift` | same IBAN/name/code pattern |
| `ios/bittr/Settings/SettingsViewController.swift` | row id ("privacy"/"terms"/"support"/"restore"/"currency"/"wallets"/"device") for routing |
| `ios/bittr/Settings/DeviceViewController.swift`, `DeviceTableViewCell.swift` | cellTag dispatch |
| `ios/bittr/Move, Send, Receive/SendVC/Confirm/ConfirmSendViewController.swift` | "high"/"medium" fee level |
| `ios/bittr/Move, Send, Receive/SendVC/Send/SendViewController.swift` | "onchain"/"lightning" routing |
| `ios/bittr/Transaction/TransactionViewController.swift` | onchainID / lightningID for clipboard / URL |
| `ios/bittr/Swaps/SwapStatusVC/SwapStatusViewController.swift` | swap status string for help button |
| `ios/bittr/Value/ValueViewController.swift` | "1d"/"1w"/etc. chart span |
| `ios/bittr/Value/GraphView.swift` | `"valuecard"` view-tag marker for subview lookup |
| `ios/bittr/AlertManager.swift` | `"alertview"` view-tag marker for subview lookup |
| `ios/bittr/AppDelegate.swift` | Sentry breadcrumb redaction — keep as-is (defensive) |

Each migration is mechanical: rename `accessibilityIdentifier` → `appTag` at both the set-site and the read-site. Cannot be done blindly because `accessibilityIdentifier` legitimately exists in non-data uses too (test IDs going forward, accessibility for VoiceOver). Touch one feature at a time, verify with a smoke test.

The `appTag` extension is in `ios/bittr/Extensions/UIView+AppTag.swift`.
