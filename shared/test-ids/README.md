# Test IDs

Canonical accessibility/test ID constants used by Maestro flows. Defined here once, generated to:

- Swift constants for iOS (`accessibilityIdentifier`)
- Kotlin constants for Android (`Modifier.testTag` / `contentDescription`)

## Format (TBD)

Likely `test-ids.json` with hierarchical naming, e.g.:

```json
{
  "wallet": {
    "create": {
      "mnemonicField": "wallet.create.mnemonicField",
      "continueButton": "wallet.create.continueButton"
    }
  }
}
```

## Generator

To be added. Outputs:
- `ios/bittr/Generated/TestIDs.swift`
- `android/app/src/main/java/com/bittr/generated/TestIDs.kt`

Both files are gitignored (regenerated from the JSON each build) or committed for diff visibility — TBD.
