# bittr Android

Native Android app — Kotlin + Jetpack Compose + Material 3.

**Status: scaffold.** The project builds, the DI graph resolves, navigation renders
one screen, and the Maestro harness has a flow to assert against. There is no
feature code and no wallet. See `../ANDROID_PORT_PLAN.md` for where this is going.

## Build

```sh
cd android
./gradlew :app:assembleDebug        # debug == regtest variant
./gradlew testDebugUnitTest         # JVM unit tests
```

Requires JDK 17+ and an Android SDK with platform 36. Point Gradle at the SDK with
`ANDROID_HOME`, or a `local.properties` containing `sdk.dir=/path/to/sdk`
(gitignored — never commit it).

## Maestro

```sh
./gradlew :app:installDebug
maestro test ../shared/flows/android/scaffold_smoke.yaml
```

CI runs this on every push: `.github/workflows/android-maestro.yml`.

## Module structure

```
app                  single Activity, navigation graph, DI wiring
core/common          generated TestIDs.kt (pure Kotlin, no Android)
core/designsystem    BittrTheme + tokens
core/wallet          wallet API — interfaces and models only, no implementation
core/wallet-stub     deterministic no-op wallet, used by the scaffold and CI
feature/signup       create-or-restore entry point
```

Dependencies point downward only: `feature/*` and `app` depend on `core/*`;
`core/*` never depends on a feature. Features do not depend on each other — anything
two features need belongs in `core`.

### The wallet seam

This is the part the structure exists for. `:core:wallet` is **API-only** — pure
Kotlin interfaces, no Android dependency, no ldk-node, no BDK. Everything above it
compiles against those types alone.

`:core:wallet-stub` is the implementation the scaffold and CI run against: no key
material, no disk, no sockets. That is deliberate. It means a red Maestro run has
exactly one cause (the app is broken) rather than eleven (node won't sync, regtest
is down, the channel didn't open).

BIT-6 adds `:core:wallet-ldk` as a second implementation of the same interface. The
switch is two lines — the dependency in `app/build.gradle.kts` and the binding in
`app/src/main/kotlin/com/bittr/android/di/WalletModule.kt`. **If it turns out to be
more than two lines, something upstream has taken a dependency on the
implementation instead of the interface, and that is the seam leaking.**

The interface in `:core:wallet` is sized to what the scaffold needs today and is
explicitly *not* a design for the wallet layer — the Bitcoin Wallet Engineer owns
that shape and should widen it in BIT-6.

## Test IDs

Do not hand-write test tags. `core/common/.../TestIDs.kt` is generated from
`shared/test-ids/test-ids.json` by `shared/test-ids/build.py`, which emits the Swift
and Kotlin constants from the same source so the Maestro flows see identical strings
on both platforms. Add the leaf to the JSON, run the generator, commit both
generated files. CI fails the build if they are stale.

Apply them with `Modifier.testTag(TestID.Signup.Create.Start.createWalletButton)`.

**`testTagsAsResourceId` is load-bearing.** Compose test tags are not visible to
UIAutomator — and therefore not to Maestro — unless `testTagsAsResourceId = true` is
set on an ancestor node. It is set once, on the root in `MainActivity.kt`. Delete it
and every `assertVisible: id:` in every flow fails with "element not found" while
the app renders perfectly on screen.

## Theme

`core/designsystem/.../Tokens.kt` holds the palette, currently transcribed from
`ios/bittr/Colors.swift` so the scaffold renders in Bittr's brand rather than
Compose's default purple. **These are iOS values, not an Android design system.**
BIT-4 replaces the contents of that one file; `Theme.kt` and every call site read
through the token names and do not change.

Material You dynamic colour is deliberately off — this is a brand-led financial app
with a fixed palette on iOS, and letting the wallpaper pick the accent would break
parity. Turning it on is a design decision for BIT-4, not a scaffold default.

Typography is Material 3's default. The iOS app ships Gilroy, Montserrat, Palanquin
and Syne (`ios/*.ttf`); which of those come across is BIT-4's call.

## Stack

- Kotlin 2.2.21, AGP 8.13.2, Gradle 8.14.5
- Jetpack Compose (BOM 2025.06.00) + Material 3
- minSdk 26 (Android 8.0) — full Keystore/biometric support, no legacy key-storage
  workarounds for the wallet layer
- compileSdk / targetSdk 36
- Hilt for DI, Coroutines/Flow
- Compose Navigation, single-Activity

Versions are pinned in `gradle/libs.versions.toml`. `agp`, `kotlin` and `ksp` move
in lockstep — KSP's version is `<kotlin-version>-<ksp-version>` and Hilt's codegen
runs on KSP, so bumping one alone will not resolve.

Still to come, per `../ANDROID_PORT_PLAN.md`: Retrofit + OkHttp, Room, DataStore,
WorkManager, FCM, Sentry, BiometricPrompt, Android Keystore.
