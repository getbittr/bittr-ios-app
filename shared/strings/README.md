# Strings

Canonical i18n source for both apps. One JSON file per locale (`en.json`, `nl.json`, …). A generator script produces `Localizable.xcstrings` for iOS and `strings.xml` for Android.

Plurals and gender variations use ICU MessageFormat (understood by both platforms).

## Migration plan

The iOS app currently has strings in scattered `*Language.swift` files. Phase 0 walks each screen for Maestro flows; while there, the strings get migrated into the canonical JSON.

## Generator

To be added (`build.{js,py,sh}`). Runs in CI before each platform build, and on demand during dev. Generated platform files are committed for diff visibility.

Until it exists, `en.json` holds only keys that had to be agreed across both platforms ahead of the migration. The iOS copy in `ios/bittr/Language.swift` is still what ships on iOS; keep the two identical by hand for those keys. Markup in the JSON is the iOS convention (`<b>`, `<br>`) — the generator is responsible for mapping `<br>` to `\n` for `strings.xml`.

## Strings that are privacy or regulatory representations

Some strings are not marketing copy — they are statements about what the app does with user data, and a wrong one is a compliance problem rather than a typo. These carry a review trail and must not be reworded without repeating it (Compliance read + a factual check against the code):

| Key | Reviewed under | Represents |
|---|---|---|
| `mapvcpoweredbyalert` | BIT-56 (from BIT-45) | That neither bittr nor BTCMap.org receives the user's location, and that the map provider sees the on-screen area |

The `mapvcpoweredbyalert` claim depends on a specific engineering property: the client downloads the **whole** BTCMap dataset and filters by proximity on-device (`getBitcoinMapURL` sends no lat/lon or bbox). If the Android port ever fetches places by bounding box — cheaper, and the obvious thing to reach for — the claim becomes false on Android. Treat the whole-dataset sync as load-bearing, not as an implementation detail.
