# Android wallet — security properties, and the test that proves each one

**Owner:** Bitcoin Wallet Engineer (Android) · BIT-6
**Binding inputs:** BIT-8 (seed storage & recovery model) and BIT-20 (LDK state
quarantine guard), both decided by Ruben and reproduced as scope in the BIT-6
description. The implementation spec is the `seed-storage-security` document on
BIT-6.

This is the statement the definition of done asks for: *which security
properties hold on which Android versions, each claim naming the test that
proves it.*

Two things it deliberately does differently from the usual security doc.

**Every row names a test, and says whether that test has run.** A claim whose
test exists but has never executed is not a proven claim, and the difference is
recorded in the *Status* column rather than smoothed over. "Safe" is not a
status.

**The properties are ordered by what they protect.** Keystore strength governs
how hard the wrapped blob is to steal off a compromised device. It never
governs whether the user can recover — under BIT-8 rule 1 the mnemonic is the
single root of recovery and the blob is a cache. That ordering is the
decision's, not a framing choice here.

---

## 1. The decided rules and their proofs

Status key: **green** = test exists and passes in CI · **written** = test
exists, has never been run (needs hardware) · **pending** = named, not yet
written.

### BIT-8 — seed storage and recovery

| # | Rule | Android mechanism | Test | Status |
|---|---|---|---|---|
| 1 | The mnemonic is the single root of recovery | Nothing persisted that is not BIP32-derivable from the seed. Swap refund keys stay at `m/503'/0'/0'/0/<i>` | `SwapRefundKeyDerivationTest` | green |
| 2 | The Keystore key is non-auth-bound | `KeyGenParameterSpec` with neither `setUserAuthenticationRequired(true)` nor `setUnlockedDeviceRequired(true)`; AES-256/GCM; `setRandomizedEncryptionRequired(true)` | `KeystoreKeySpecTest` (asked for) · `WalletKeystorePolicyGuardTest` (stays that way) | green |
| 2 | …and what the device actually produced | `KeyInfo` read back off a generated key | `KeystoreKeyInfoTest` | written — no device in CI |
| 2 | …and it survives a lock-screen change | — | **BIT-18 / K1**, device matrix | separate issue |
| 3 | The wrapped blob is a cache, never the only copy | Blob loss routes to the restore screen; terminal failures classify as "no usable mnemonic" | `BlobDestroyedRecoversTest` | green |
| 4 | The blob is excluded from Auto Backup | `allowBackup="false"` + `dataExtractionRules` + siting under `getNoBackupFilesDir()` | `BackupExclusionRulesTest` + `StateDirLocationTest` (configuration) · `BackupExclusionTest` (behaviour) + `check-backup-set.sh` (the set itself) | configuration green; behaviour **partly proven on one device — run 107 inspected a real set and found no wallet material, but could not show the set was non-empty; see §4** |
| 5 | No PIN-derived wrapping | PIN stays a salted-SHA-256 verifier; the unwrap path takes no PIN argument | `WalletKeystorePolicyGuardTest` (bans `PBEKeySpec`/PBKDF2) · `BlobWriteVerifiedTest` (unwrap signature takes no PIN) | green |

### BIT-20 — the LDK state quarantine guard

| # | Rule | Android mechanism | Test | Status |
|---|---|---|---|---|
| 6 | Discriminator is a full-width SHA-256 of the BIP84 account xpub, constant-time compared | Domain-separated SHA-256 over the serialized account xpub, hex, inside the state directory; `MessageDigest.isEqual` | `DiscriminatorSpecTest` | green |
| 7 | match → keep · mismatch → quarantine · absent → quarantine | `SeedImportGuard` | `BlobDestroyedRecoversTest` (match, mismatch) · `ForeignStateQuarantinedTest` (absent) | green |
| 8 | Three-way blob classification; transient ≠ absence | Classification on exception type, no fallback branch meaning "absent" | `TransientKeystoreFailureAbortsTest` | green |
| 9 | Quarantine never overwrites a prior quarantine | Uniquely-named subdirectory under `no_backup/foreign_ldk_state/` | `QuarantineDoesNotClobberTest` | green |
| 10 | Exclusion widens to the LDK state directory, both backup paths | The three layers in rule 4, scoped to the whole wallet directory | as rule 4 | configuration green; behaviour **partly proven on one device, see §4** |

### Port-faithfulness fixes carried without a separate ruling

| Rule | Why | Test | Status |
|---|---|---|---|
| Quarantine before the blob write, durably | Crash between them is unrecoverable in one order and clean in the other | `QuarantineOrderingCrashTest` | green |
| The blob write is read back before success is reported | Ports `persistSecret`'s `writeVerificationFailed` (`CacheManager.swift:528–539`) | `BlobWriteVerifiedTest` | green |
| The blob lives in credential-encrypted storage | A non-auth-bound key is usable during Direct Boot; CE storage is what reproduces `afterFirstUnlock` | `StateDirLocationTest` · `WalletKeystorePolicyGuardTest` | green |
| Derivation is byte-identical to iOS | The backend verifies signatures from these keys | `IosDerivationVectorTest`, against the vector pinned at `BitcoinMessage.swift:363–367` | green |

---

## 2. What we actually get, by API level

`minSdk 26`, `targetSdk 36`, `compileSdk 37`. What we get, not what we would
like.

| API | Key storage | `setUnlockedDeviceRequired` | StrongBox | What we claim |
|---|---|---|---|---|
| 26–27 | TEE-backed on most devices, **software fallback on some**; no API to require hardware | unavailable (API 28+) | unavailable | The blob is AES-256/GCM under a key that is *usually* non-exportable. On a software-keystore device, an attacker with root can extract it. **We do not claim hardware backing at 26–27.** |
| 28–30 | TEE, optionally StrongBox | available (**deliberately unused** — rule 2) | `setIsStrongBoxBacked`, `FEATURE_STRONGBOX_KEYSTORE` | As above, plus the security level is observable |
| 31–33 | as above | as above | as above | `KeyInfo.getSecurityLevel()` replaces the deprecated `isInsideSecureHardware()`; recorded per device |
| 34–36 | as above | as above | as above | No change |

Recorded, not asserted, by `KeystoreKeyInfoTest.recordTheObservedSecurityLevel`
— API 26–27 devices legitimately vary, so a fixed expectation would be a test
that fails honestly on hardware we support.

Two caveats that belong in a founder-facing statement rather than a footnote:

- **Hardware backing is observed, not attested.** Android key attestation
  produces a certificate chain for *asymmetric* keys. Our wrapping key is
  symmetric, so `KeyInfo.getSecurityLevel()` is a local self-report from the
  same system an attacker would already have subverted. Good enough to log per
  device; not a cryptographic proof. A real proof means an attested asymmetric
  key wrapping the AES key — extra scope, not currently justified.
- **None of this is what protects the funds.** See the ordering note at the
  top.

---

## 3. Divergences from iOS, on the record

| Event | iOS today | Android | Divergence |
|---|---|---|---|
| Change / remove lock screen | seed survives | survives iff the key is non-auth-bound — **BIT-18/K1** | pending K1 |
| Device backup / restore to a new device | seed not in backup (`ThisDeviceOnly`) → mnemonic-only | Keystore key not backed up → mnemonic-only | none |
| Factory reset / device loss | mnemonic-only | mnemonic-only | none |
| Uninstall → reinstall | the Keychain item can survive | Keystore key and app data destroyed → mnemonic-only | **real, accepted** (BIT-8; the restore screen is the reinstall path) |
| Blob destroyed, LDK state intact | guard quarantines the state | **guard keeps it** if the discriminator matches | **deliberate — BIT-20**, and the reason the guard was changed |
| Quarantine fires twice | cannot (one-shot migration) | second quarantine does not replace the first | **deliberate — BIT-20 rule 4** |

Two accepted trade-offs, Ruben's, not to be re-litigated in review:
uninstall→reinstall requires re-entering the mnemonic; and a user who loses
their device without having written down the seed loses their funds — already
true on iOS, the non-custodial model rather than a regression.

---

## 4. The one claim not yet proven, and the stop condition attached to it

**Rule 4/10's behavioural half.** `BackupExclusionRulesTest` proves the
configuration: `allowBackup="false"`, `dataExtractionRules` wired up, both
`<cloud-backup>` and `<device-transfer>` excluding the wallet directory, no
`<include>` that could re-admit it. `StateDirLocationTest` proves every wallet
path resolves under `no_backup`.

None of that proves a backup set produced by a real device contains none of it.
That is `BackupExclusionTest` (`app/src/androidTest`, BIT-101), which has now
run on a device once — run 107 of the wallet emulator job, API 34 `aosp_atd`.

**What it does.** Plants a wallet-bearing install — wrapped blob, ldk-node
state, discriminator, BDK database, and a quarantine subdirectory under the
uniquely-generated name BIT-20 rule 4 gives it — then drives `bmgr` to produce
a real set and leaves that set on the local transport. Once on the cloud-backup
path and once with the local transport in device-transfer mode, because API 31+
configures the two separately. The **verdict** comes from
`android/scripts/check-backup-set.sh`, which greps the transport's own on-disk
tree from the host in the same job.

**Why the verdict is not in the test — BIT-108.** The first version deleted what
it planted, ran `bmgr restore`, and asserted nothing came back. On run 107 the
device-transfer case produced an empty `<failure>` and every case of
`InstalledBackupConfigurationTest` after it never ran: `bmgr restore` kills the
target process, and the instrumentation runs inside it. That is not fixable by
writing the assertion more carefully.

It was also worth less than it looked. A restore only kills the process when the
framework has something to restore, so the assertion passed exactly when the
package was ineligible and nothing had been backed up — the case where it had
nothing to check — and died exactly when there was a set worth checking. Run 107
is that shape end to end: cloud passed, device-transfer died. So the restore is
gone from both paths, not just from the one that crashed, and
`BackupExclusionInstrumentationGuardTest` fails the build if it is reintroduced.
The suite now creates the conditions and proves it created them — transport
live and local, the `is_device_transfer` hook actually taken, `bmgr backupnow`
completing with a considered per-package result rather than a transport error —
and the host script reads the set.

The same guard keeps the `bmgr wipe` out of the suite's `@After`. The host reads
the transport after Gradle exits, so a wipe there deletes the only artefact the
run produces; on run 107 the one inspectable set survived purely because the
crash skipped teardown. The wipe now runs before each backup, which also makes
the surviving set deterministically the device-transfer one — `NAME_ASCENDING`
puts that method last, and it is the path the flag may not cover.

**What run 107 actually reported.** The transport was live and the set was real:
`backupManagerAndTheLocalTransportAreLiveOnThisDevice` and the cloud case both
passed. `check-backup-set.sh` ran, emitted neither its "could not gain root" nor
its "no candidate directory" warning, and found no wallet marker — so on that
device the backup set that survived to be inspected carried none of the planted
wallet material. That is the strongest evidence rule 5 has so far, and it is
still one device, one API level, and one set.

It is not yet the full claim, for a reason the current revision closes: the run
could not show the set was non-empty. `allowBackup="false"` making the package
ineligible produces an empty set, which satisfies every exclusion check while
proving nothing about the rules. The canary now carries its own host-greppable
prefix (`BIT101-CANARY-MARKER-`, deliberately distinct from the wallet marker so
finding it is not read as the halt) and the decoys carry a third. Once
`check-backup-set.sh` requires the canary before reporting its evidence outcome,
"the rules excluded our wallet files" and "the framework never offered this
package to the transport" stop being the same green. That is the outstanding
half, tracked on BIT-108.

**Why it is in `:app` rather than `:core:wallet-ldk`, where BIT-101 asked for
it.** A library module's instrumented tests are self-instrumenting: the package
under test would be `…core.wallet.ldk.test`, whose manifest carries neither
`allowBackup="false"` nor `dataExtractionRules`. That set would be produced for
a default-configured package and would say nothing about the install we ship.
`com.bittr.android` is the only package whose backup configuration is the
product's. The cost is duplicated path literals, since `:app` does not depend on
`:core:wallet-ldk` yet; `BackupExclusionInstrumentationGuardTest` (JVM, runs on
every `check`) fails the build if those literals stop matching `WalletPaths`, and
fails it again if the instrumented class is `@Ignore`d or drops below three
cases. A test that needs hardware is a test nobody watches rot.

**The two hazards recorded before the first run, and where they stand.** The
first — the instrumentation running inside the process whose data is being
restored, with `bmgr restore`'s effect on it undocumented either way — is
**settled**: it kills the process, and the restore is gone (BIT-108, above).
The second is open by design: `is_device_transfer` is a local-transport test
hook rather than API, so the test asserts the setting was taken rather than
assuming it, and a rename in a future platform release fails loudly instead of
quietly turning the device-transfer case into a second cloud case.

Also unresolved, and deliberately left to the device: the root of
`domain="file"` is `getFilesDir()`, while the wallet directory is under
`getNoBackupFilesDir()` — a sibling of it, not a child. If that is so, the
`<exclude>` entries name paths the product never writes to and the `no_backup`
siting is carrying rule 5 alone. `BackupExclusionTest` plants a decoy at each of
the two paths those entries name. Whichever way it comes out, the answer is to
fix the rules, never to relax the rule.

This matters more than a normal missing test, because BIT-20 rule 5 makes it a
**precondition** of the `match → keep` guard rather than a follow-up. A
discriminator proves state is *yours*; it does not prove it is *current*.
Same-seed **stale** state signs fine, and publishing a revoked commitment hands
the channel balance to the counterparty — so the failure the discriminator does
not cover is the worse one, and it is closed at the storage layer or not at
all.

**Stop condition, recorded so it is not a judgement call in the moment.** If
the API 31+ device-transfer path turns out not to be excludable — not by
`dataExtractionRules`, not by `no_backup` siting, not by `allowBackup="false"` —
that is a **halt**, not a smaller test. The finding goes back to BIT-20 with
the empirical result attached, and the guard reverts to iOS behaviour
(quarantine on anything but a live mnemonic) until it is re-decided.

A crashed process is not that halt, and run 107 is not it. It also is not a
clean bill of health for the device-transfer path: what it shows is a set that
was inspected and carried no wallet material, on one device, at one API level,
without the run being able to say the set was non-empty.

So `match → keep` is still shipping on a proven *configuration* and a
*partly* proven behaviour, and the row above says so. The remaining step is
small and named: the canary has to be required by the host-side check before
its evidence outcome is reported, so an ineligible package and an excluded one
stop producing the same green.

---

## 5. What this document does not cover yet

- **Node lifecycle** — on-chain sync, channel and payment handling, process
  death, Doze, background execution limits. Tracked separately; the storage
  layer above is what it will be built on.
- **K7 (interrupted payment) and K8 (Doze soak)** from `wallet-core-spec` §6.
  Both need a device.
- **`data_loss_protect` on channel re-establish.** A user who deliberately
  restores their mnemonic on a second device while the first still holds live
  channels is outside what backup exclusion closes, and what stands between
  them and a penalty is Lightning's own behaviour. Inherent to mnemonic-only
  recovery plus Lightning, already true on iOS
  (`LightningStorage.swift:21–23` accepts it in as many words), and to be
  verified against ldk-node 0.7.0 rather than asserted from memory.
