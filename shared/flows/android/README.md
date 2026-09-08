# Android Maestro flows

Android-only flows live here. The goal is that this directory stays **small** — the
shared suite in `../onboarding/` and `../features/` is meant to drive both platforms
off the same test IDs, and anything that ends up here permanently is a parity gap
worth writing down in `shared/docs/parity.md`.

## What's here

| Flow | Purpose |
|---|---|
| `scaffold_smoke.yaml` | The trivial flow the CI harness is proven against. Launch, wait for `core.launchComplete`, assert the signup entry point. |

## Running locally

```sh
cd android && ./gradlew :app:installDebug
maestro test ../shared/flows/android/scaffold_smoke.yaml
```

## Two things that will bite you

**1. Compose test tags are invisible to Maestro by default.**
`Modifier.testTag(...)` does not reach the accessibility tree that Maestro reads.
It only works because `MainActivity.kt` sets `testTagsAsResourceId = true` on the
root node. Remove that and every `assertVisible: id:` in every flow fails with
"element not found" while the app looks completely fine on screen. If a flow
suddenly cannot see anything, check that first.

**2. The app id differs from iOS.**
iOS debug is `com.bittr.bittr-regtest`. Android `applicationId`s cannot contain
hyphens, so the Android debug build is `com.bittr.android.regtest` (`applicationId`
`com.bittr.android` + the debug `applicationIdSuffix`). The shared flows hardcode
the iOS id today; unifying them behind `${APP_ID}` is BIT-7, once there is more
than one Android flow to unify.
