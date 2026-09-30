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
  -keyalg RSA -keysize 4096 -validity 10000
chmod 600 ~/.bittr/bittr-upload.jks
```

No `-storetype`: the JDK default is PKCS12, which is what the signing path here
was verified against, and asking for JKS only earns a warning telling you to
migrate to PKCS12. `keytool` writes the file 644, hence the `chmod`.

`-validity 10000` is ~27 years. A key that expires is a key that stops being
able to sign updates, and Play has no renewal flow for an upload key that has
already lapsed.

### The two passwords are invented at the prompts

`keytool` asks twice:

```
Enter keystore password:        ← BITTR_UPLOAD_STORE_PASSWORD
Re-enter new password:
Enter key password for <bittr-upload>
        (RETURN if same as keystore password):  ← BITTR_UPLOAD_KEY_PASSWORD
```

They are not looked up anywhere and they are not derived from anything. Pressing
RETURN at the second prompt makes the key password equal to the store password,
which is the common choice and means both variables carry the same value.

**Nothing can recover them from the keystore.** Lost passwords are a lost upload
key, and a replacement takes a support request to Google. Password manager, not
only the env file below.

To check a password you think is right, without changing anything:

```bash
keytool -list -keystore ~/.bittr/bittr-upload.jks
```

It prompts, then either prints the entry or says the password was incorrect.

Keep the keystore out of the repository. `.gitignore` refuses `*.jks` and
`*.keystore` anywhere in the tree, which is a backstop and not a filing system —
`~/.bittr/` is where the node environment already lives, and where this belongs.

## What the bundle points at

`BITTR_ENVIRONMENT` is hard-coded to `PRODUCTION` for the release variant, but the
six `BITTR_LDK_*` values are read from the environment in `defaultConfig`, so
**every variant gets whatever the shell was carrying**. A release built in a shell
holding the regtest configuration is a bundle that talks to the real bittr backend
over a private regtest network. One was built on 2026-09-30 and not uploaded;
`bundleRelease` now refuses rather than producing it again.

That matters more since `.envrc` arrived: sourcing the regtest environment used to
be a deliberate act per shell and is now automatic on `cd`.

Keep the production values in `~/.bittr/android-production.env` and **do not add
it to `.envrc`** — the whole point is that a production node configuration is
something you opt into for one command, not something every debug build inherits.
The variable names are the same, so sourcing it over the regtest values replaces
them:

```bash
set -a; source ~/.bittr/android-production.env; set +a
./gradlew :app:bundleRelease
```

The values themselves are not secret — they are already in the repository, in
`ios/bittr/Helpers/EnvironmentConfig.swift`, which is the source of truth for
both platforms:

| Variable | Production value | iOS source |
|---|---|---|
| `BITTR_LDK_CHAIN_SOURCE_URL` | `https://esplora.getbittr.com/api` | `esploraURL` |
| `BITTR_LDK_ELECTRUM_URL` | `ssl://esplora.getbittr.com:50002` | `electrumURL` |
| `BITTR_LDK_RAPID_GOSSIP_SYNC_URL` | `https://rapidsync.lightningdevkit.org/snapshot/v2` | `RGSServerURLs.bitcoin` |
| `BITTR_LDK_LIGHTNING_NODE_ID` | `03e8d988a67ee7de983cd39d9d3d4d19771019305da4d2332be76c8b9fb1687776` | `lightningNodeId` |
| `BITTR_LDK_LIGHTNING_NODE_ADDRESS` | `86.104.228.24:9735` | `lightningNodeAddress` |
| `BITTR_LDK_LSPS2_TOKEN` | *(empty)* | `BitcoinManager.swift:171`, `token: ""` |

An empty `BITTR_LDK_LSPS2_TOKEN` is correct, not missing: iOS passes `token: ""`
to `setLiquiditySourceLsps2` on both environments.

### Verifying what a built bundle points at

The guard is a tripwire on known markers, not a network validator, so it is worth
checking the artefact itself before an upload that matters:

```bash
python3 - <<'EOF'
import zipfile
z = zipfile.ZipFile("app/build/outputs/bundle/release/app-release.aab")
blob = b"".join(z.read(n) for n in z.namelist() if n.endswith(".dex"))
for marker in (b"esplora.getbittr.com", b"esplora-regtest", b"rapidsync"):
    print(marker.decode(), "->", marker in blob)
EOF
```

## Building a bundle

Four values, supplied as environment variables or `bittr.upload.*` Gradle
properties (`app/build.gradle.kts` reads either, in that order):

They live in `~/.bittr/upload-key.env`, mode 600, exactly as the node's
configuration lives in `android-regtest.env` beside it:

```
BITTR_UPLOAD_STORE_FILE=/Users/you/.bittr/bittr-upload.jks
BITTR_UPLOAD_STORE_PASSWORD=
BITTR_UPLOAD_KEY_ALIAS=bittr-upload
BITTR_UPLOAD_KEY_PASSWORD=
```

Fill the two passwords in with an editor rather than on the command line: an
`export` with a password on it is written to `~/.zsh_history` in the clear, and
the shell has no notion that this one was worth forgetting.

```bash
set -a; source ~/.bittr/upload-key.env; set +a
./gradlew :app:bundleRelease
```

Or let direnv do it: the repo's `.envrc` loads that file (and the node's) on
`cd`, so a shell in this directory already has them. It is committed and holds
no secrets — it only reads `~/.bittr/`. `direnv allow` once per checkout.

**Android Studio does not see direnv.** A GUI Gradle run inherits the launcher's
environment, not a shell's, so `bundleRelease` from the IDE will report the key
as missing however well the terminal works. The build reads
`bittr.upload.storeFile` and friends as Gradle properties for exactly this case:
put them in `~/.gradle/gradle.properties`, which is outside the repo and read by
every Gradle invocation regardless of how it was started.

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

`versionCode = 2` in `app/build.gradle.kts`. Play rejects any upload whose
`versionCode` is not higher than the last one it accepted, and there is no way to
reuse a number — **including for a bundle that was uploaded and never released**.
That is how 1 went: it was spent on 2026-09-30 by a bundle that reached the
Console and shipped to nobody. Bump this in the same commit that cuts a release.

The number is burned at upload. If you upload a bundle you then think better of,
the next one needs a higher number regardless of what happened to the first.
