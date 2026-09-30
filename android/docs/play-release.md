# Releasing to Play: the upload key, the bundle, and the first release

This is the procedure for getting a build onto Google Play. It is written to be
followed rather than re-derived.

> **Status, 2026-09-30: no release has been made yet.** The build produces a
> signed bundle (verified end to end with a throwaway key), the app exists in
> Play Console, and no binary has been uploaded. Everything below the line
> marked **first release only** happens once and then never again.

## What signs what

Play App Signing holds the **app signing key** — the one devices verify. You
hold the **upload key**, which is only how Google knows an upload is from you.
They are different keys and only the second one is your problem.

Losing the upload key is recoverable but slow: it takes a support request to
Google to register a replacement. Losing it also does *not* lock users out of
updates, because the app signing key is Google's. Back it up anyway, somewhere
that is not the machine that built it.

## Generating the upload key

Once, ever:

```bash
keytool -genkeypair -v \
  -keystore ~/.bittr/bittr-upload.jks \
  -alias bittr-upload \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -storetype JKS
```

`-validity 10000` is ~27 years. A key that expires is a key that stops being
able to sign updates, and Play has no renewal flow for an upload key that has
already lapsed.

Keep the keystore out of the repository. `.gitignore` refuses `*.jks` and
`*.keystore` anywhere in the tree, which is a backstop and not a filing system —
`~/.bittr/` is where the node environment already lives.

## Building a bundle

Four values, supplied as environment variables or `bittr.upload.*` Gradle
properties (`app/build.gradle.kts` reads either, in that order):

```bash
export BITTR_UPLOAD_STORE_FILE=~/.bittr/bittr-upload.jks
export BITTR_UPLOAD_STORE_PASSWORD=...
export BITTR_UPLOAD_KEY_ALIAS=bittr-upload
export BITTR_UPLOAD_KEY_PASSWORD=...

./gradlew :app:bundleRelease
```

The bundle lands at `app/build/outputs/bundle/release/app-release.aab`, ~61 MB.

**Without all four, `bundleRelease` refuses to run.** That is deliberate: the
release build type falls back to the debug signing key so `assembleRelease`
stays runnable in CI without a keystore on the runner, and a debug-signed bundle
is something Play rejects only after a build, an upload and a wait. The check is
at the bottom of `app/build.gradle.kts`.

The bundle carries `arm64-v8a`, `armeabi-v7a` and `x86_64` and nothing else —
see `abi-packaging.md` for why `x86` in particular must not come back.

## Checking what you built

```bash
unzip -l app/build/outputs/bundle/release/app-release.aab | grep -o "lib/[a-z0-9_-]*/" | sort -u
```

Three ABIs. A fourth means `defaultConfig.ndk.abiFilters` has been widened or
bypassed, and `lib/x86/` specifically means devices that can install the app and
then die on the first `System.loadLibrary` the wallet makes.

---

## First release only

### 1. The package name is decided by the first upload

Play Console's "create app" dialog asks for a display name, not a package name.
The package is bound permanently by the **first bundle uploaded**, and this app
is `com.bittr.android` — 622 files say so, both Firebase apps are keyed to it
(`com.bittr.android` for release, `com.bittr.android.regtest` for debug), and
the push backend routes tokens by it. The store's display name is independent
and editable under *Store settings → App details*.

### 2. App content, before the track will accept a rollout

Internal testing does **not** need screenshots or a finished store listing,
which is what `play-store-screenshots.md` is blocked on. It does need the *App
content* declarations completed:

- Privacy policy URL
- Data safety
- Content rating questionnaire
- Target audience
- **Financial features** — this is a self-custodial Bitcoin wallet, so the
  crypto declarations apply
- **App access** — a reviewer who launches the app meets a PIN screen and
  cannot get past it. Supply credentials or instructions here or the review
  stalls on a screen nobody can pass.

### 3. Upload the first bundle by hand

The Play Developer API has no "create app" call and refuses uploads for an app
that has never had one through the Console. Both fastlane's `supply` and the
Gradle Play Publisher plugin document this. So the first `app-release.aab` goes
up through the Console's internal-testing page, by hand, once.

### 4. Then automate the rest

After that upload exists, releases can go from the command line. The service
account setup is the remaining piece:

1. A Google Cloud project with the **Google Play Android Developer API** enabled.
2. A service account in it, with a JSON key.
3. In Play Console, *Users and permissions* → invite that service account's
   email → grant it release access to this app. Propagation is not instant;
   an immediately-following API call can still 401.

The plugin to reach for is Gradle Play Publisher (`com.github.triplet.play`),
not fastlane: this repo is already all-Gradle with a version catalog, and
fastlane would add a Ruby toolchain for one task. It is **not wired up yet** —
that is the follow-up once step 3 has happened.

## versionCode

`versionCode = 1` in `app/build.gradle.kts`. Play rejects any upload whose
`versionCode` is not higher than the last one it accepted, per track, and there
is no way to reuse a number — including for a build that was uploaded and then
discarded. Bump it in the same commit that cuts a release.
