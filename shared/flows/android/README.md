# Android Maestro flows

Android-only flows live here. The goal is that this directory stays **small** — the
shared suite in `../onboarding/` and `../features/` is meant to drive both platforms
off the same test IDs, and anything that ends up here permanently is a parity gap
worth writing down in `shared/docs/parity.md`.

## What's here

Nothing, and that is the intended state.

It held `scaffold_smoke.yaml` until BIT-102: an Android copy of
`../onboarding/smoke.yaml` that asserted the same three test IDs and differed only
in its `appId` and in dropping `clearKeychain`. Both of those reasons are now gone
(see below), so the duplicate went with them — `android/scripts/ci-smoke.sh` runs
the shared `../onboarding/smoke.yaml` itself, with `--env APP_ID`.

If you are about to add a file here, the question to answer first is *why can't the
shared flow do this?* A real answer (a platform-only screen, a permission dialog
that only exists on one OS) is a parity gap: write it down in
`shared/docs/parity.md` and then add the flow. "The shared one doesn't quite work
yet" is not — fix the shared one.

## Running locally

```sh
cd android && ./gradlew :app:installDebug
cd .. && APP_ID=com.bittr.android.regtest maestro test shared/flows/onboarding/smoke.yaml
```

Or, for the three-consecutive-runs number, which reads `APP_ID` off the workflow
so you don't have to:

```sh
android/scripts/smoke-consecutive.sh
```

## One thing that will bite you

**Compose test tags are invisible to Maestro by default.**
`Modifier.testTag(...)` does not reach the accessibility tree that Maestro reads.
It only works because `MainActivity.kt` sets `testTagsAsResourceId = true` on the
root node. Remove that and every `assertVisible: id:` in every flow fails with
"element not found" while the app looks completely fine on screen. If a flow
suddenly cannot see anything, check that first.

A near relative, worth knowing before you spend an emulator boot on it: a
`Modifier.testTag` **nested inside a `clickable` container** is swallowed too —
the clickable merges its subtree's semantics, so the inner tag never appears in
the tree Maestro reads.

## What used to be the second thing: the app id

iOS debug is `com.bittr.bittr-regtest`. Android `applicationId`s cannot contain
hyphens, so the Android debug build is `com.bittr.android.regtest` (`applicationId`
`com.bittr.android` + the debug `applicationIdSuffix`).

This is no longer a trap, because no flow names either id. Every shared flow reads
`appId: ${APP_ID}` and each platform's runner passes its own value — the iOS
default lives in `shared/flows/test_suite.sh`, the Android one in
`.github/workflows/android-maestro.yml` (`env.APP_ID`). That is the only
difference between the two runs of the same file, and
`shared/flows/check_app_ids.py` fails the build if a literal id comes back.

Two details of that unification are worth keeping, because they are not obvious
from the YAML and both were read out of Maestro 2.10.0's own bytecode rather than
guessed:

- **`clearKeychain` needs no platform guard.** `AndroidDriver.clearKeychain()` is
  an empty method — and it is the *only* no-op in that driver; nothing in it
  throws "unsupported". So every directive the shared flows use is implemented on
  Android, and the one iOS-only directive among them is free to leave in place.
- **`appId` in the config header is interpolated for `launchApp` and friends, but
  not everywhere.** Maestro bakes the config's `appId` into each
  `launchApp` / `clearState` / `stopApp` / `killApp` / `setPermissions` command at
  parse time and evaluates `${...}` per command, which is why the unification
  works. Two consumers read the *raw* header instead: `tapOn`'s app-settle check
  and `openLink`. On iOS that is inert (the iOS driver ignores the argument). On
  Android `tapOn` falls back from the window-updating check to screenshot-diff
  settling — the same path Maestro takes when no `appId` is configured. Nothing
  fails; taps just settle the slower way. The first tap-heavy Android flow to run
  in CI is what measures whether that costs anything worth fixing.
