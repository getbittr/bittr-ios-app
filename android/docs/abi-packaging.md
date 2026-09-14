# ABI packaging decision (BIT-129)

**Decision:** bittr for Android supports **three ABIs — `arm64-v8a`, `armeabi-v7a`,
`x86_64`** — and every variant is packaged as **one APK per ABI, with no universal
APK**. CI installs the `x86_64` one, because the emulator is x86_64. Distribution
is per-ABI APKs today and an **App Bundle** when release signing exists — that is
[BIT-134](/BIT/issues/BIT-134), and [What ships](#what-ships) is what it inherits.

**Status:** decided and implemented. The ABI list and the packaging are the
`splits` block in `android/app/build.gradle.kts`; what CI installs is
`android/scripts/ci-smoke.sh` and the `Upload APK` step in
`.github/workflows/android-maestro.yml`. `AbiPackagingGuardTest` asserts all four
of those agree, and fails if any of them is simply deleted.

---

## What happened

[BIT-126](/BIT/issues/BIT-126) put `:core:wallet-ldk` on `:app`'s dependency
graph. That is correct and permanent — the app is a Lightning wallet — but it
brings `libldk_node.so` and `libbdkffi.so`, and `:app:assembleDebug` went to
**174 MB**.

Measured on `d882d1e8`, `feature/bit-6-wallet-core`, by reading the APK's central
directory rather than by estimate:

| | in the APK |
|---|---|
| `lib/` | **156.1 MB** |
| everything else (dex, resources, assets) | 18.0 MB |
| **total** | **174.1 MB** |

Every `.so` is stored **uncompressed**, which is why `lib/` is 90% of the file.
That is AGP's default (`extractNativeLibs=false`) and it is the right one — see
[Rejected: legacy packaging](#rejected-uselegacypackaging--true).

The per-ABI breakdown is where the decision came from:

| ABI | `lib/` | ldk-node | BDK | MapLibre |
|---|---|---|---|---|
| `arm64-v8a` | 53.0 MB | 26.0 | 13.9 | 11.6 |
| `x86_64` | 51.2 MB | 24.8 | 13.0 | 11.8 |
| `armeabi-v7a` | 38.2 MB | 18.6 | 9.8 | 8.4 |
| `x86` | 13.3 MB | **absent** | **absent** | 11.8 |
| `armeabi` | 0.12 MB | — | — | — |
| `mips` | 0.15 MB | — | — | — |
| `mips64` | 0.14 MB | — | — | — |

**Seven `lib/` directories, not four.** The issue said four; it is seven, and the
two extra facts in that table are what made the decision straightforward.

## The x86 hole, which is a correctness bug and not a size one

**ldk-node and BDK publish no 32-bit x86 binary. MapLibre does.**

So before this change, a 32-bit x86 device installed bittr *successfully* — the
APK had a `lib/x86/` directory, `PackageManager` was satisfied — and then died at
the first `System.loadLibrary` the wallet made. Not at install, not at launch:
somewhere inside the first wallet operation, as an `UnsatisfiedLinkError`.

Naming the three ABIs the wallet actually has binaries for turns that from
"installs, then crashes" into "not offered". An app whose entire purpose is the
node cannot claim to support an ABI the node has no build for.

`armeabi`, `mips` and `mips64` are JNA's `libjnidispatch.so`, for three ABIs the
NDK removed in r17 (2017). 0.4 MB, harmless, and noise in every size measurement
anyone takes of this APK from now on.

## What CI installs

The `maestro` job installs **`app-x86_64-debug.apk` — 69.3 MB**, down from the
174.5 MB universal APK. The build job uploads only that file, so the saving is
paid once on upload and once on download as well as at `adb install`.

### Why this is not the divergence the issue was right to worry about

The issue's objection to a debug-only ABI filter was that this repo has been
deliberate about not letting the build Maestro tests drift from the build users
get — the `androidComponents` block in `app/build.gradle.kts` exists precisely
because a release-only gap had already left an assertion silently dead.

That objection does not apply to splits, and the reason is a property of Android
rather than a judgement call:

> **`PackageManager` selects ONE primary ABI at install time and loads only that
> directory.**

The Maestro emulator is x86_64. On every run before this change, the `arm64-v8a`,
`armeabi-v7a` and `x86` libraries inside the universal APK were pushed over adb,
written to the device, and never opened. **A universal APK ships more; it does not
test more.** Splitting changes what travels and changes nothing about what
executes — the coverage is identical, byte for byte, in the only directory the
emulator was ever going to load.

What *does* differ between CI and a user's phone is the ABI itself: CI exercises
x86_64 Rust, users run arm64. That was equally true before this change, is
unaffected by it, and is the reason
[the nightly regtest suite](wallet-node-device-tests.md) exists. A universal APK
was never fixing it.

The real divergence risk here is the opposite one, and it is why `splits` is set
on `android { }` rather than inside `debug { }`: **debug and release get the same
ABI list.** There is one answer to "which ABIs does bittr support", for every
variant.

### The install-time cost is not yet measured, and will measure itself

`android/scripts/ci-smoke.sh` already prints `APK install <n>s` into the job
summary and the run annotation. The numbers on record in
[ci-evidence.md](ci-evidence.md) are `0s` and `1s` — but those are BIT-5 evidence
runs from before BIT-126, when the APK was small, so **the repo has no measurement
of what a 174 MB install cost.** The issue's "minutes, per run" is an estimate and
is labelled as one here.

The size delta is measured (174.5 → 69.3 MB, above). The time delta lands by
itself: the next Maestro run after this commit prints its own `APK install` number
against those historical ones, with no extra instrumentation.

## What ships

Everything in this section is [BIT-134](/BIT/issues/BIT-134). It is written out
here rather than left as a ticket title because the two traps below are the kind
that are cheap to avoid and expensive to discover.

**Per-ABI APKs are already what this repo produces**, for release as well as
debug. There is nothing further to do to make the release build small, and the
`x86` correctness fix applies to it too.

**The App Bundle is the distribution answer and is deferred, deliberately.** Not
because it is wrong — it is the right end state, and Play's size limits are real —
but because this repo has no release signing config at all (`release` is
debug-signed so `assembleRelease` stays runnable in CI, and says so). A bundle
pipeline built before there is anything to sign it with is a pipeline nobody can
run.

**One thing must change when it lands, and it is easy to miss:** `splits.abi` does
**not** apply to `bundle*` tasks. A bundle built today would contain all seven
`lib/` directories. The migration is to swap the `splits` block for
`defaultConfig.ndk.abiFilters` with the same three ABIs, and let Play do the
splitting.

That swap is one-for-one and not additive: **AGP 9.4.0 refuses to configure when
both are set**, even with identical values —

```
Conflicting configuration : 'armeabi-v7a,arm64-v8a,x86_64' in ndk abiFilters
cannot be present when splits abi filters are set : armeabi-v7a,x86_64,arm64-v8a
```

— verified by trying it. `AbiPackagingGuardTest` asserts the **union** of the two
mechanisms for exactly this reason, so the migration does not have to rewrite the
guard, and asserts that exactly one of them is populated so it cannot end up with
neither.

**Per-ABI APKs are not a Play upload path as they stand.** Play multi-APK requires
a distinct `versionCode` per APK; all three currently carry `versionCode = 1`.
BIT-134 either adopts the bundle (which makes the question disappear) or adds an
ABI-indexed versionCode scheme. It is written down here rather than implemented
because the wrong one of those is expensive to undo.

## Rejected: `useLegacyPackaging = true`

The obvious other size lever, and a trap worth naming so it is not tried later.

Every `.so` above is uncompressed because AGP defaults `extractNativeLibs` to
false: the loader maps the library straight out of the APK. Turning legacy
packaging on compresses them — a visibly smaller APK — and then has the installer
**decompress a second copy into `/data/app`** on the device. Slower to install,
and roughly double the on-device footprint. A smaller file and a worse app.

## Rejected: `debugSymbolLevel`

Correctly identified in the issue as not applicable. It strips native debug
symbols into a side file for the **bundle**; it does nothing to an APK, and these
`.so` files arrive prebuilt from published AARs rather than from a local NDK
build.

## What is asserted, and where

`app/src/test/kotlin/com/bittr/android/AbiPackagingGuardTest.kt`, in
`./gradlew test`. Six assertions over the two halves of the decision:

| | |
|---|---|
| the packaged ABI set is exactly the three | read from AGP's **resolved** DSL, injected as `bittr.abi.*` system properties by `app/build.gradle.kts` — not grepped out of the file, so a value set from a build type or a plugin is visible |
| exactly one mechanism declares it | neither = packages everything; both = AGP will not configure |
| no universal APK | `isUniversalApk = true` would restore the 174 MB artefact **silently**, since the upload and install paths are both named |
| the workflow's emulator arch is a supported ABI | every `arch:` in the workflow, not only Maestro's |
| the uploaded APK and the installed APK are the same file | two files, one value; disagreement fails 20 minutes into a run |
| the install names an APK rather than globbing | a `*.apk` glob resolves to three arguments, or to the unexpanded literal |

The thing being guarded is **absence**, not a wrong value. Delete the `splits`
block and the build still succeeds, the flows still pass, and the APK is quietly
174 MB again offering itself to devices the wallet has no binary for. There is no
compiler error waiting at the end of that path, which is what makes it worth a
test. Verified by negative control: disabling `splits` and restoring the glob
turns three of the six red.
