# Shared assets

Brand assets used by both platforms — logos, fonts, illustrations.

For now this is a stub. The iOS app's font files (`Gilroy*.ttf`, `Montserrat*.ttf`, `Palanquin-Regular.ttf`, `Syne-Regular.ttf`) currently live in `ios/` because they're bundled by the Xcode project. When the Android app starts using them, decide whether to:

- Move them here and reference from both platforms, or
- Duplicate (smaller cognitive overhead, slightly more disk).

Recommendation: move when needed, not before.
