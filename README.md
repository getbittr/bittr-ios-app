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

See [`ANDROID_PORT_PLAN.md`](./ANDROID_PORT_PLAN.md) for the Android port strategy.
