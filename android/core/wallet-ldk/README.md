# `:core:wallet-ldk`

The real binding of `:core:wallet`, against `ldk-node` + BDK — and the seed
storage and LDK-state quarantine model decided in **BIT-8** and **BIT-20**.

Start with `android/docs/wallet-security-properties.md`. It is the written
security statement the definition of done asks for: every decided rule, the
Android mechanism that implements it, the test that proves it, and whether that
test has actually run.

## Layering, and why it is not just tidiness

```
bip/     BIP39 → BIP32 → BIP84 account key            pure JVM  (bitcoin-kmp)
state/   where files live, quarantine, discriminator  pure JVM  (java.io.File)
seed/    the vault, the classification, the guard     pure JVM  + one Keystore adapter
node/    ldk-node + BDK                               device only
```

Everything that decides **what happens to the user's funds** — the seed-import
guard, the discriminator, the quarantine path, the three-way blob
classification — is written against `java.io.File` and injected interfaces, with
no ldk-node, BDK or Keystore type in its signature. The native bindings and the
Keystore appear only in adapters at the edge.

The reason is the definition of done. `bdk-android` and `ldk-node-android` are
UniFFI wrappers over native `.so` files and the Android Keystore is a device
service, so any decision expressed in terms of them is provable only on an
emulator — and a claim whose only test needs hardware CI does not have yet is a
claim with no test. `WalletKeystorePolicyGuardTest` and the `Fakes.kt`
substitutions are what keep that boundary from eroding.

## Versions, and why they are not the latest

| Dependency | Pin | Why |
|---|---|---|
| `bdk-android` | 1.2.0 | Matches the iOS `bdk-swift` pin. 3.0.0 removes `Connection` for `Persister` and splits `Network`/`NetworkKind` — a redesign of the storage seam, not a rename, while the acceptance bar is behavioural parity with the iOS suite. `wallet-core-spec` §1. |
| `ldk-node-android` | 0.7.0 | Matches the iOS `ldk-node` pin. 100% API parity verified against the surface `BitcoinManager.swift` uses — `wallet-core-spec` §2. |
| `bitcoin-kmp` | 0.31.0 | BIP39/BIP32 on the JVM, for the discriminator (which must derive from the mnemonic *before* a node is booted) and for the iOS derivation vectors (which must run without an emulator). |

`secp256k1-kmp` ships its API and its JNI implementation as separate artifacts.
Both halves are named explicitly — `-jni-android` for the app, `-jni-jvm` for
unit tests. Omitting either fails at first signature, not at build time.

## The three things most likely to be "fixed" by mistake

Each is a decided rule with a cost that is invisible from the call site, and
each is guarded by a test that names the issue to re-open.

1. **The Keystore key is deliberately not auth-bound.** No
   `setUserAuthenticationRequired(true)`, no `setUnlockedDeviceRequired(true)`.
   It looks like a missing hardening step and it is not: two seed reads in the
   shipping iOS app happen with no PIN and no biometric, and both are recovery
   paths. BIT-8 rule 2/5.
2. **A quarantine never replaces a prior quarantine.** iOS deletes the old one
   (`LightningStorage.swift:94–97`), which is safe there because the path is a
   one-shot migration. On Android it is routine, and the deleted directory is
   the only material that could sweep a force-closed channel. BIT-20 rule 4.
3. **A transient Keystore failure is not an absence.** The classifier has no
   fallback branch meaning "absent" — an unrecognised throwable aborts. Reading
   a busy provider as "no mnemonic" quarantines live channel state on one flaky
   call. BIT-20 rule 3.

## Running the tests

```
./gradlew :core:wallet-ldk:test          # host-side; runs in CI today
./gradlew :core:wallet-ldk:connectedAndroidTest   # needs a device; not in CI yet
```
