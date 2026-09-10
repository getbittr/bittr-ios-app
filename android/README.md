# bittr Android

Native Android app — Kotlin + Jetpack Compose + Material 3.

**Status: scaffold, verified on a device, unverified in CI.** The project builds, the
unit tests pass, the DI graph resolves and navigation renders one screen. There is no
feature code and no wallet. See `../ANDROID_PORT_PLAN.md` for where this is going.

**The Maestro flow has run green on a real emulator** — 2026-09-10, on a MacBook
following `docs/local-setup-macos.md`. That closes the assumption the scaffold rested
on: Compose `testTag`s really are reachable by Maestro's `id:` selectors through
`testTagsAsResourceId`, which no JVM test can prove (Robolectric reads the semantics
tree directly and passes with the flag either way). Details in that doc under "What
the first run proved".

**It has still never run in CI.** The emulator job — AVD cache, boot on a runner,
artefact upload — remains untested code; the environment the scaffold was built in
has no `/dev/kvm`. BIT-5's definition of done is three consecutive green *CI* runs
plus a wall-clock number, so it stays open. For the local half of that evidence use
`scripts/smoke-consecutive.sh`, which runs the flow N times and reports the per-run
wall clock without retries.

## Build

```sh
cd android
./gradlew :app:assembleDebug        # debug == regtest variant
./gradlew test                      # JVM unit tests, all modules
```

Use `test`, **not** `testDebugUnitTest`. `:core:common`, `:core:wallet` and
`:core:wallet-stub` are pure-Kotlin modules with no Android variants, so
`testDebugUnitTest` reports `NO-SOURCE` for them and goes green having run a
fraction of the suite.

Requires JDK 17+ and an Android SDK with `platforms;android-37.0` (`compileSdk = 37`
— note the `.0`, the API level carries a minor component now and `android-37` is not
a package that exists). Point Gradle at the SDK with `ANDROID_HOME`, or a
`local.properties` containing `sdk.dir=/path/to/sdk` (gitignored — never commit it).

Verified from a pristine `git clone` of this branch with no `local.properties` —
2m01s, 195 tasks, APK produced — so the checkout is self-contained.

Step-by-step for a Mac: `docs/local-setup-macos.md`. If you only want to *look* at
the scaffold screen, that doc's "Seeing the screen" section gets you there through
Android Studio's Compose preview without booting an emulator at all.

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

## Unlock, biometrics, and the test build

**`BiometricPrompt` must never appear in the build Maestro runs against.** This is
the single most load-bearing constraint on the scaffold, because PIN entry is the
deepest shared dependency in the suite: 28 flows call `helpers/unlock.yaml`, 7 tap
the PIN pad directly, and **296 of the 329 `takeScreenshot` steps — 90% — sit
behind a PIN entry**. A biometric prompt ahead of the PIN pad doesn't degrade the
suite, it collapses it, and it collapses it early enough that every downstream flow
looks independently broken.

Biometric unlock (DEV-17) is an Android-convention *addition*, not a port —
`shared/docs/parity.md` lists "no biometric / Face ID unlock" under *Confirmed
absent in iOS*. So no shared flow will ever exercise it, and it needs its own
Android-only test.

Three things enforce this, none of which depends on how the emulator image is
configured:

| Mechanism | What it catches |
|---|---|
| `BuildConfig.BIOMETRIC_UNLOCK_ENABLED` — `false` in debug, `true` otherwise | the flag itself |
| `core/common/.../AuthCapabilities.kt`, injected via `di/AuthModule.kt` | feature modules can't read `:app`'s `BuildConfig`, so this is the one binding to audit |
| `BiometricUnlockFlagTest`, `BiometricApiGuardTest` (`:app` unit tests) | the flag being flipped, and any use of `BiometricPrompt`/`BiometricManager` that doesn't route through the gate |

`BiometricApiGuardTest` is a **routing rule, not a ban** — shipping the prompt is
expected. Add the file to its `ALLOWED_FILES` once the call reads
`biometricUnlockEnabled` first. It is a text scan over `android/**.kt`, so it also
trips on the API names in comments; that conservatism is deliberate.

Note the emulator's own enrolment state is never consulted. If unlock ever asks
`BiometricManager.canAuthenticate()` before checking the gate, a CI image with a
fingerprint enrolled behaves differently from one without, and that difference is
exactly the flakiness this design exists to prevent.

### FLAG_SECURE will blank the whole screenshot suite if you set it app-wide

`FLAG_SECURE` is Android's answer to the iOS seed-phrase screenshot warning
(DEV-18). It is the right answer, and it is a **window** flag — this app has one
window. Set it in `MainActivity.onCreate` and it stays set for the session, so all
329 `takeScreenshot` steps capture black frames. They do not fail; Maestro is
perfectly happy to screenshot a black screen. CI stays green and the artefacts are
worthless.

Scope it to the screen that needs it — a `DisposableEffect` that adds the flag on
enter and clears it on dispose. `ScreenshotBlockingGuardTest` fails the build if it
appears in `MainActivity.kt` or `BittrApplication.kt`.

## Stack

- Kotlin 2.4.20, AGP 9.4.0, Gradle 9.7.1
- Jetpack Compose (BOM 2026.08.00) + Material 3
- minSdk 26 (Android 8.0) — full Keystore/biometric support, no legacy key-storage
  workarounds for the wallet layer
- compileSdk 37, targetSdk 36
- Hilt for DI, Coroutines/Flow
- Compose Navigation, single-Activity

Versions are pinned in `gradle/libs.versions.toml` — read that file rather than
this list. Two traps live there:

- **KSP no longer tracks the Kotlin version.** The scheme changed at KSP 2.3.0;
  it used to be `<kotlin>-<ksp>` (e.g. `2.2.21-2.0.5`) and is now independent.
  Don't go looking for a KSP release matching the Kotlin version — there isn't one.
- **AGP 9 is not optional.** Hilt's Gradle plugin dropped AGP 8 at 2.59, and Hilt
  is the DI container.

### AGP 9 only unit-tests the debug variant

`./gradlew test` still describes itself as "Run unit tests for all variants", but
AGP 9 creates a unit-test component for `debug` only. A test asserting something
about the release build therefore never runs and reports success. `app/build.gradle.kts`
turns the release component on explicitly via `androidComponents { beforeVariants … }`
— without it, `BiometricUnlockFlagTest`'s "biometrics stay on in the shipped build"
half is silently dead.

Still to come, per `../ANDROID_PORT_PLAN.md`: Retrofit + OkHttp, Room, DataStore,
WorkManager, FCM, Sentry, BiometricPrompt, Android Keystore.
