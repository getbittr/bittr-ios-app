# Test IDs

Canonical accessibility/test ID constants used by Maestro flows. Defined here once, generated to platform-native code.

- **iOS**: `ios/bittr/Helpers/TestIDs.swift` — `enum TestID { ... }`, set on `view.accessibilityIdentifier`.
- **Android** (when scaffolded): `android/app/src/main/.../TestIDs.kt` — `object TestID { ... }`, set with `Modifier.testTag()`.

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

Regenerates `ios/bittr/Helpers/TestIDs.swift`. Run after editing `test-ids.json`. The generated file is committed for diff visibility.

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
