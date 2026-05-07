# Strings

Canonical i18n source for both apps. One JSON file per locale (`en.json`, `nl.json`, …). A generator script produces `Localizable.xcstrings` for iOS and `strings.xml` for Android.

Plurals and gender variations use ICU MessageFormat (understood by both platforms).

## Migration plan

The iOS app currently has strings in scattered `*Language.swift` files. Phase 0 walks each screen for Maestro flows; while there, the strings get migrated into the canonical JSON.

## Generator

To be added (`build.{js,py,sh}`). Runs in CI before each platform build, and on demand during dev. Generated platform files are committed for diff visibility.
