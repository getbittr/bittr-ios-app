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
| 2 | …and what the device actually produced | `KeyInfo` read back off a generated key | `KeystoreKeyInfoTest` | runs in CI — BIT-59, `wallet-instrumented` job, API 34 emulator |
| 2 | …and it survives a lock-screen change | — | **BIT-18 / K1**, device matrix | separate issue |
| 3 | The wrapped blob is a cache, never the only copy | Blob loss routes to the restore screen; terminal failures classify as "no usable mnemonic" | `BlobDestroyedRecoversTest` | green |
| 4 | The blob is excluded from Auto Backup | `allowBackup="false"` + `dataExtractionRules` + siting under `getNoBackupFilesDir()` | `BackupExclusionRulesTest` + `StateDirLocationTest` (configuration, JVM) · `BackupExclusionTest` (installed app + `bmgr`, emulator) | configuration green; **cloud-backup path runs in CI (BIT-59); device-transfer path still not provable — see §4** |
| 5 | No PIN-derived wrapping | PIN stays a salted-SHA-256 verifier; the unwrap path takes no PIN argument | `WalletKeystorePolicyGuardTest` (bans `PBEKeySpec`/PBKDF2) · `BlobWriteVerifiedTest` (unwrap signature takes no PIN) | green |

### BIT-20 — the LDK state quarantine guard

| # | Rule | Android mechanism | Test | Status |
|---|---|---|---|---|
| 6 | Discriminator is a full-width SHA-256 of the BIP84 account xpub, constant-time compared | Domain-separated SHA-256 over the serialized account xpub, hex, inside the state directory; `MessageDigest.isEqual` | `DiscriminatorSpecTest` | green |
| 7 | match → keep · mismatch → quarantine · absent → quarantine | `SeedImportGuard` | `BlobDestroyedRecoversTest` (match, mismatch) · `ForeignStateQuarantinedTest` (absent) | green |
| 8 | Three-way blob classification; transient ≠ absence | Classification on exception type, no fallback branch meaning "absent" | `TransientKeystoreFailureAbortsTest` | green |
| 9 | Quarantine never overwrites a prior quarantine | Uniquely-named subdirectory under `no_backup/foreign_ldk_state/` | `QuarantineDoesNotClobberTest` | green |
| 10 | Exclusion widens to the LDK state directory, both backup paths | The three layers in rule 4, scoped to the whole wallet directory | as rule 4 | configuration green; **behaviour pending** |

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
That is `BackupExclusionTest`.

**BIT-59 changed what this section says, but not all of it.** There is now a
`wallet-instrumented` job (API 34 emulator, `android/scripts/ci-wallet-instrumented.sh`)
that runs `BackupExclusionTest` and `KeystoreKeyInfoTest` on every push. What it
closed and what it did not:

| Path | Status after BIT-59 |
|---|---|
| Cloud backup | **Driven, and checked at two different strengths — see below.** `bmgr` is enabled, the local transport selected, and `bmgr backupnow` run against the installed package. |
| The installed artefact, as opposed to the source tree | **Driven.** The test reads `FLAG_ALLOW_BACKUP` off the installed package, and the `dataExtractionRules` attribute and the compiled rules out of the installed APK — so a manifest merge that re-added backup, or an `<include>` that survived into the APK, now fails on the device rather than passing on the JVM. |
| Device-to-device transfer (API 31+) | **Still not proven, and not provable this way.** `bmgr` has no D2D mode: that path runs through `BackupTransport.FLAG_DEVICE_TO_DEVICE_TRANSFER`, which the shell tool does not expose and an instrumented test cannot set. No test on an emulator can produce a real D2D transfer set and read it back. |

**The cloud-backup row is two claims, and only one of them reads a backup set.**
Worth separating here, because "driven" covered a real gap between them:

- **`bmgr`'s report.** The in-test assertion can only search `bmgr backupnow`'s
  stdout, which describes a run rather than a set — `Backup finished with
  result: Success` is printed by any run that completed, including one that
  backed the package up in full. The test names that branch `notVisiblyRefused`
  rather than anything stronger. It is accepted because the platform's decline
  wording varies by API level and image, and it is *not* evidence that nothing
  of ours was written.
- **The set itself.** `BackupExclusionTest` plants a per-run marker in the LDK
  state files it writes, and `android/scripts/check-backup-set.sh` greps the
  transport's on-disk tree for it from the host after `adb root`. This is the
  only check in the repo that reads a real backup **set**; it cannot live inside
  the suite, because the set is `0700` to another uid and `UiAutomation`'s shell
  runs as `shell`.

The second is conditional on `adb root` succeeding and on the transport's
directories existing on the image, so it distinguishes three outcomes rather
than two: marker found (the §5.3 halt), present and clean (evidence), and *could
not look* (a `::warning::`, explicitly **not** evidence). Grep a run's log for
`Backup set inspection` to see which one it got. A green `BackupExclusionTest`
from a run that could not look rests on `bmgr`'s report alone.

That last row is why this section still exists. It is also the row that matters
most, because `allowBackup="false"` is **not** documented to suppress D2D on API
31+ — which is exactly why `data_extraction_rules.xml` configures
`<device-transfer>` separately, and exactly the claim this document said it would
not assert from memory. `BackupExclusionTest.theDeviceTransferPathIsRecordedBecauseItCannotBeDriven`
prints a `BACKUP_EXCLUSION_D2D … verdict=NOT_EMPIRICALLY_PROVEN` line on every
run so a green job cannot be read as having closed it, and
`check-wallet-instrumented-results.py` repeats the gap in its own output for the
same reason.

Closing that row needs something an emulator cannot give: a real two-device
transfer, or a host-side harness that can drive a transport with the D2D flag
set. That is hardware/infrastructure work, not workflow work.

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

Until `BackupExclusionTest` is green on both paths, `match → keep` is shipping
on a proven *configuration* and a *half-proven* behaviour. That is the honest
status, and it is why the test is tracked as a blocker on this issue rather
than as a nice-to-have.

BIT-59 moved the cloud-backup half from unproven to measured and left the
device-transfer half where it was. Whether a half-proven behaviour is enough to
release the `match → keep` guard is BIT-20's call, not this document's — the
stop condition above is written so that call does not have to be made from
memory either.

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
