# bittr Android

Native Android app — Kotlin + Jetpack Compose + Material 3.

Currently empty. The native dependency PoC (Phase 1 in `../ANDROID_PORT_PLAN.md`) lands here first: a throwaway Android project that wires up `bdk-android`, `ldk-node-jvm`, and `boltz-android` against the regtest environment in `../shared/docs/regtest.md`. Real scaffolding follows in Phase 3.

## Stack (planned)

- Kotlin 2.x
- Jetpack Compose + Material 3
- Min SDK 26 (Android 8.0)
- Hilt for DI, Coroutines/Flow
- Retrofit + OkHttp (talks to existing BittrService backend, no API changes)
- Room (replaces iOS CacheManager storage), DataStore
- WorkManager (replaces BackgroundSync)
- FCM (with backend dual-sending APNs + FCM by platform)
- Sentry, BiometricPrompt, Android Keystore

See `../ANDROID_PORT_PLAN.md` for the full plan.
