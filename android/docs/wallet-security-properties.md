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
| 4 | The blob is excluded from Auto Backup | `allowBackup="false"` + `dataExtractionRules` + siting under `getNoBackupFilesDir()` | `BackupExclusionRulesTest` + `StateDirLocationTest` (configuration, JVM) · `InstalledBackupConfigurationTest` (installed artefact, emulator) · `BackupExclusionTest` (both backup paths + `bmgr`, emulator) | configuration green; behaviour **runs in CI on every push (BIT-59, `wallet-instrumented` job) — first result not yet recorded, see §4** |
| 5 | No PIN-derived wrapping | PIN stays a salted-SHA-256 verifier; the unwrap path takes no PIN argument | `WalletKeystorePolicyGuardTest` (bans `PBEKeySpec`/PBKDF2) · `BlobWriteVerifiedTest` (unwrap signature takes no PIN) | green |

### BIT-20 — the LDK state quarantine guard

| # | Rule | Android mechanism | Test | Status |
|---|---|---|---|---|
| 6 | Discriminator is a full-width SHA-256 of the BIP84 account xpub, constant-time compared | Domain-separated SHA-256 over the serialized account xpub, hex, inside the state directory; `MessageDigest.isEqual` | `DiscriminatorSpecTest` | green |
| 7 | match → keep · mismatch → quarantine · absent → quarantine | `SeedImportGuard` | `BlobDestroyedRecoversTest` (match, mismatch) · `ForeignStateQuarantinedTest` (absent) | green |
| 8 | Three-way blob classification; transient ≠ absence | Classification on exception type, no fallback branch meaning "absent" | `TransientKeystoreFailureAbortsTest` | green |
| 9 | Quarantine never overwrites a prior quarantine | Uniquely-named subdirectory under `no_backup/foreign_ldk_state/` | `QuarantineDoesNotClobberTest` | green |
| 10 | Exclusion widens to the LDK state directory, both backup paths | The three layers in rule 4, scoped to the whole wallet directory | as rule 4 | configuration green; behaviour **written, never run** |

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
That is `BackupExclusionTest` (`app/src/androidTest`, BIT-101), and as of
BIT-59 it runs on every push.

**What runs, and where.** The `wallet-instrumented` job boots an API 34
`aosp_atd` emulator and runs `android/scripts/ci-wallet-instrumented.sh`, which
drives `:core:wallet-ldk:connectedDebugAndroidTest` and
`:app:connectedDebugAndroidTest`. Both, because the two tests this section turns
on are in different modules and a step scoped to the library alone would exit 0
having never executed the one that touches funds-losing behaviour. The image is
AOSP rather than Play-flavoured because the suite drives
`com.android.localtransport/.LocalTransport`; a Play image offers the GMS
transports instead, which cannot be restored from on demand.

**What the tests do.**

- `BackupExclusionTest` plants a wallet-bearing install — wrapped blob, ldk-node
  state, discriminator, BDK database, and a quarantine subdirectory under the
  uniquely-generated name BIT-20 rule 4 gives it — drives `bmgr` to produce a
  real set, deletes everything it planted, restores, and asserts none of it came
  back. Once on the cloud-backup path and once with the local transport in
  device-transfer mode (`is_device_transfer=true`, asserted back out of the
  settings provider so a renamed hook cannot degrade the second run into a
  second copy of the first), because API 31+ configures the two separately.
- `InstalledBackupConfigurationTest` asserts the configuration against the
  *installed artefact* rather than the source tree: `FLAG_ALLOW_BACKUP` off the
  installed package, the `dataExtractionRules` attribute out of the merged
  binary manifest, and the compiled rules out of the APK's resources. A manifest
  merge that re-added backup, or an `<include>` that survived into the APK, now
  fails on the device rather than passing on the JVM.

They are separate classes because a red in each means a different thing. Red
configuration, green behaviour: the install is misconfigured and the platform
excluded the material anyway — fix the configuration and conclude nothing from
the green. Green configuration, red behaviour: what we wrote is what the device
is running and the device honoured none of it. That second one is the §5.3 halt
with the "we misconfigured it" explanation already ruled out.

**Why `BackupExclusionTest` is in `:app` rather than `:core:wallet-ldk`, where
BIT-59 originally asked for it.** A library module's instrumented tests are
self-instrumenting: the package under test would be `…core.wallet.ldk.test`,
whose manifest carries neither `allowBackup="false"` nor `dataExtractionRules`.
That set would be produced for a default-configured package and would say
nothing about the install we ship. `com.bittr.android` is the only package whose
backup configuration is the product's. The cost is duplicated path literals,
since `:app` does not depend on `:core:wallet-ldk` in the shipped
configuration; `BackupExclusionInstrumentationGuardTest` (JVM, runs on every
`check`) fails the build if those literals stop matching `WalletPaths`, and
fails it again if the instrumented class is `@Ignore`d or drops below three
cases.

**Three ways a green run can still be worth less than it looks**, all of them
checked rather than assumed:

- **No transport.** On an image where the Backup Manager is off or no transport
  is selected, no backup set is produced for any package, so every "the set
  excludes our files" assertion passes having run nothing.
  `ci-wallet-instrumented.sh` turns the transport on and fails loudly if it
  cannot; `backupManagerAndTheLocalTransportAreLiveOnThisDevice` asserts the
  local transport by name from inside the suite; and
  `check-wallet-instrumented-results.py` requires that test to have *passed*,
  not merely to have not failed, because a skipped test and a green one look the
  same in an exit code.
- **An empty set.** An empty set excludes everything trivially, so each path
  writes a canary into `files/`, which no rule excludes, and asserts either that
  the canary came back or that the framework is on record declining to back the
  package up. A failure naming the canary is the suite refusing to certify an
  empty set — not a backup-exclusion regression.
- **An ineligible package.** `allowBackup="false"` makes the package ineligible
  outright, and that is the expected cloud-path outcome. It is a pass for rule 5
  and it is *not* a proof that the `<device-transfer>` rules work, because they
  were never consulted. The `BACKUP_EXCLUSION` lines printed on every run say
  which of the two happened, per path: `canaryReturned=true` means a real set
  that excluded our material; `canaryReturned=false` with a declining result
  means the package was never offered to the transport.

**The strongest check does not run inside the suite at all.** The in-test
assertions depend on `bmgr restore` having done something, and a restore that
silently no-ops produces "nothing came back" for the wrong reason.
`BackupExclusionTest` therefore prefixes every planted file's contents with
`MARKER_PREFIX`, and `android/scripts/check-backup-set.sh` greps the transport's
own on-disk tree for it from the host after `adb root` — no restore involved. It
cannot live inside the suite: the set is `0700` to another uid and
`UiAutomation`'s shell runs as `shell`. It distinguishes three outcomes rather
than two — marker found (the §5.3 halt), directories present and clean
(evidence), and *could not look* (a `::warning::`, explicitly **not** evidence).
Grep a run's log for `Backup set inspection` to see which one it got.

**Also unresolved, and deliberately left to the device:** the root of
`domain="file"` is `getFilesDir()`, while the wallet directory is under
`getNoBackupFilesDir()` — a sibling of it, not a child. If that is so, the
`<exclude>` entries name paths the product never writes to and the `no_backup`
siting is carrying rule 5 alone. `BackupExclusionTest` plants a decoy at each of
the two paths those entries name. Whichever way it comes out, the answer is to
fix the rules, never to relax the rule.

**Two things that could make the first run red without the product being
wrong**, recorded now so they are not diagnosed under pressure later: the
instrumentation runs inside the process whose data is being restored, and
whether `bmgr restore` kills that process is not documented either way (method
order is `backupManager… → cloudBackup… → deviceTransfer…` so the cheap
observations reach the log first); and `is_device_transfer` is a
local-transport test hook rather than API. Both are results to record on BIT-101
and BIT-20, not to design around.

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

**First result, read and recorded — run 107 (`684791c`), 2026-09-12.** The
cloud-backup path passed. The device-transfer path came back **red, with a
completely empty `<failure>`** — no message, no stack trace — and the four
`InstalledBackupConfigurationTest` cases did not run at all.

That shape is not an assertion failing. Every assertion in
`BackupExclusionTest` carries a message, `@FixMethodOrder(NAME_ASCENDING)` puts
`deviceTransfer…` last in the class, and an empty `<failure>` followed by every
later class never starting is what the runner records when the instrumentation
process **dies** mid-test. It is the first of the two hazards this section
already predicted: *the instrumentation runs inside the process whose data is
being restored.* The device-transfer restore appears to kill it.

So the honest reading is a finding about the harness, not about the product,
and **it is not the §5.3 halt** — a halt needs the marker found in a real set,
which is a different observation from an assertion that never got to run. It is
also not a clean bill of health: the device-transfer path remains *unproven*,
now for a demonstrated reason rather than an unexamined one. It goes to BIT-101
as a test-design problem, because a restore assertion cannot live in the
process being restored.

What should have settled it in the same run could not be read.
`check-backup-set.sh` greps the transport's own tree from the host, needs no
surviving process, and therefore still answers on exactly this kind of red —
but its evidential outcome was a bare `echo` into a job log that answers 403 on
this public repo, while its two *non*-evidential outcomes emitted annotations.
The one run that proved something was the one run nobody could read without
credentials. Fixed in the same commit as this paragraph: that verdict and the
`BACKUP_EXCLUSION`/`KEYSTORE_KEY_INFO` lines are now `::notice::` annotations,
which are the only channel this repo answers 200 on without a token. The gate
also now names the empty-`<failure>`-plus-missing-tests signature in its own
annotation, so the next reader does not re-derive it — or, worse, read it as
the halt.

Until `BackupExclusionTest` is green on both paths, `match → keep` is shipping
on a proven *configuration*, a **green cloud-backup path**, and a
**device-transfer path that has run and not yet returned a readable verdict**.
That is the honest status. This row does not move to green until a run reports
the device-transfer path without the process dying under it.

BIT-59 put both halves on a machine that can answer them. Whether the answer it
gives is enough to release the `match → keep` guard is BIT-20's call, not this
document's — the stop condition above is written so that call does not have to
be made from memory either.

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
