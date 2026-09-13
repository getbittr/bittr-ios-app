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
| 4 | The blob is excluded from Auto Backup | `allowBackup="false"` + `dataExtractionRules` + siting under `getNoBackupFilesDir()` | `BackupExclusionRulesTest` + `StateDirLocationTest` (configuration, JVM) · `InstalledBackupConfigurationTest` (installed artefact, emulator) · `BackupExclusionTest` (both backup paths + `bmgr`, emulator) + `check-backup-set.sh` (the set itself, host) | configuration green; behaviour **not yet proven. Run 107 inspected a real set and found no wallet material but could not show the set was non-empty. The canary gate that tells those apart, and the BIT-108 fix that keeps the device-transfer backup from killing the process, were built on separate branches and first met on one tree at the BIT-59/BIT-108 merge — so no run has yet carried both, and neither `partly proven` nor the §5.3 halt is earned. Since BIT-59 the suite runs on every push (`wallet-instrumented` job); see §4** |
| 5 | No PIN-derived wrapping | PIN stays a salted-SHA-256 verifier; the unwrap path takes no PIN argument | `WalletKeystorePolicyGuardTest` (bans `PBEKeySpec`/PBKDF2) · `BlobWriteVerifiedTest` (unwrap signature takes no PIN) | green |

### BIT-20 — the LDK state quarantine guard

| # | Rule | Android mechanism | Test | Status |
|---|---|---|---|---|
| 6 | Discriminator is a full-width SHA-256 of the BIP84 account xpub, constant-time compared | Domain-separated SHA-256 over the serialized account xpub, hex, inside the state directory; `MessageDigest.isEqual` | `DiscriminatorSpecTest` | green |
| 7 | match → keep · mismatch → quarantine · absent → quarantine | `SeedImportGuard` | `BlobDestroyedRecoversTest` (match, mismatch) · `ForeignStateQuarantinedTest` (absent) | green |
| 8 | Three-way blob classification; transient ≠ absence | Classification on exception type, no fallback branch meaning "absent" | `TransientKeystoreFailureAbortsTest` | green |
| 9 | Quarantine never overwrites a prior quarantine | Uniquely-named subdirectory under `no_backup/foreign_ldk_state/` | `QuarantineDoesNotClobberTest` | green |
| 10 | Exclusion widens to the LDK state directory, both backup paths | The three layers in rule 4, scoped to the whole wallet directory | as rule 4 | configuration green; behaviour **not yet proven — this row's evidence is rule 4's, so its status tracks rule 4's; see §4** |

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

**Removing the restore was necessary and not sufficient — run 133.** Run 133
(`0dd62293` on `android-parity`) is the first run to carry the restore-free
suite, and it reproduced run 107's signature exactly: `deviceTransfer…` with an
empty `<failure>`, all four `InstalledBackupConfigurationTest` cases never
reached. The restore was one of two things in that method that killed the
process.

The other is **`bmgr backupnow` itself, on the device-transfer path**. The
framework binds a backup agent inside the target process to service a backup and
kills that process when it tears the agent down; the instrumentation lives in
that process. It is the same structural fault as the restore, one step earlier
in the same method, and it is not fixable in-process either.

The two paths discriminate the mechanism rather than leaving it a guess. On the
cloud path `allowBackup="false"` makes the package ineligible, so no agent is
ever bound and nothing is torn down — that case has passed on every run. On the
device-transfer path `allowBackup="false"` does not apply, which is the entire
reason the path is tested separately; the package is eligible, an agent is bound,
and the process dies — that case has died on every run. Note what this says about
the cloud path's green: it survives because nothing happens on it, by the same
argument that made the restore worthless. It is not evidence that driving a
backup from inside the suite is safe, and if `allowBackup` were ever set back to
`true` that case would start dying too.

So the device-transfer backup moved to the host as well. The suite plants the
wallet material, the canary and the decoys, arms the `is_device_transfer` hook,
clears the stale dataset, and writes a hand-off file into
`getNoBackupFilesDir()`. `ci-wallet-instrumented.sh` reads that file with `adb
root` and only then drives `bmgr backupnow`, after Gradle has exited and with no
instrumentation process left to kill. `check-backup-set.sh` then greps the set it
produced.

The hand-off is a file rather than the adjacent `println` because instrumentation
stdout reaches the host only if the runner files it into the JUnit XML's
`<system-out>`, and run 133 recorded that it did not. A hand-off on that channel
would go missing exactly when something had gone wrong.

The host refuses to back up when the hand-off is absent, and that refusal is the
point: backing up a package that was never planted writes an *empty* set, and an
empty set reads identically to a clean one. Every way that phase can fail to run
ends in a `::warning::` and no verdict, never in a green.
`BackupExclusionInstrumentationGuardTest` fails the build if
`deviceTransfer…` starts driving `backupnow` again, and separately if the
hand-off strings on the two sides drift — that drift would otherwise be silent
and green.

The suite now creates the conditions and proves it created them — transport
live and local, the `is_device_transfer` hook actually taken, the plant on disk
and the stale dataset cleared, and on the cloud path `bmgr backupnow`
completing with a considered per-package result rather than a transport error —
and the host drives the device-transfer backup and reads the set.

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

It was not yet the full claim, for a reason this revision closes: the run could
not show the set was non-empty, and an empty set satisfies every exclusion check
while proving nothing about the rules. The canary now carries its own host-greppable
prefix (`BIT101-CANARY-MARKER-`, deliberately distinct from the wallet marker so
finding it is not read as the halt) and the decoys carry a third, and
`check-backup-set.sh` now **requires the canary** before it will report its
evidence outcome. "The rules excluded our wallet files" and "there was nothing in
the set to exclude" are no longer the same green: the first is a `::notice::`,
the second a `::warning::` that says in as many words that the set was empty and
the rules were never consulted. What the next run has to show for rule 4/10 to
reach *partly proven* is that notice — no wallet marker **and** the canary
present in the transport's tree.

**An empty set does not tell you which path left it empty**, and the two paths do
not go empty for the same reason. The host check runs once, over one tree, after
both paths have been driven, so it names both causes and asserts neither:

- **Cloud path.** `allowBackup="false"` makes the package ineligible and the
  framework never offers it to the transport. Expected — that flag is what we
  ship.
- **Device-transfer path.** `allowBackup` does **not** apply here; that is the
  whole reason the path exists, and the reason BIT-6 declined to assert the
  flag's reach from memory. So ineligibility does not explain an empty set on
  this path. What does is a backup that never completed — the framework binds a
  backup agent inside the *target* process, and the instrumentation lives in that
  process, so a mid-backup death produces both an empty set and an empty
  `<failure>` on the suite side of the same run. That is BIT-108, and it is why
  runs 133 and 136 are not the §5.3 answer in either direction.

**The two halves only met on one tree at the merge of BIT-108 into BIT-59.** They
were built on separate branches and each branch was missing the other's half, so
no run so far has carried both. BIT-108's fix is twice-green — runs 139 and 140
both completed `deviceTransferOf…` and ran all four
`InstalledBackupConfigurationTest` cases, the first runs ever to do so — but
those runs predate the canary gate reaching that branch, and both reported
`Backup set inspection` as the **evidence outcome on a set the host phase had
just said it never drove a backup into**. That is the false green the canary
requirement exists to refuse, observed in the wild rather than argued for. The
canary-gated runs, in turn, were all on branches without the BIT-108 fix, so
every one of them died mid-backup. **Neither `partly proven` nor the §5.3 halt
has been earned yet**: the first run on a tree carrying both halves is what
produces the answer, and until it reports, rule 4/10 stays where it is.

**That run has now reported, and the answer is neither.** On `7e4da43` all four
jobs were green; the `wallet-instrumented` job passed in 328s with the vacuity
check passed, so every required test ran. The host phase reported the
device-transfer backup as **`Success` for `com.bittr.android.regtest`** with
`is_device_transfer=true` and the wallet material planted — the process survived
making the set, which is what BIT-108 fixed and what no earlier run achieved.
And `Backup set inspection` was still the **empty-set `::warning::`**: no wallet
marker, and no canary either.

Read those two together, because the combination is new and it retires the
explanation the warning itself was offering. The empty device-transfer set had
been attributed to the target process dying mid-backup; on this run the process
did not die and the framework reported success, so **that cause is excluded and
the set was empty anyway**. What remains is a question the exclusion rules have
no part in: whether the local transport persists a device-transfer set to
`/data/data/com.android.localtransport/files`, `/data/system/backup` or
`/data/backup` at all, or streams it somewhere this check never looks. Until a
run produces a set the framework actually populated, rule 4/10 has no evidence
either way and **stays `not yet proven`** — this is emphatically not the §5.3
halt, which requires the wallet marker to be *found*, and nothing was found.

**The diagnostic ran, and the cause is in the check, not the transport.** The
run for `ecd2e5e` carried the searched roots into the annotation, and they
answered immediately: `find` came back with an unfiltered recursive listing of
`/data/backup` — `pending/`, `fb-schedule`, `ancestral`, `processed` — and not
one path matching its own `-name '*bittr*'`.

`$present` is built from `ls -d`, which emits **one path per line**, and it was
interpolated raw into the command strings handed to `adb shell`. A newline there
does not separate arguments; it separates **commands**. So

```
grep -rl 'BIT101-WALLET-MARKER-' /data/backup /data/data/com.android.localtransport/files
```

was really sent as two commands — a grep of `/data/backup` alone, then a line
the device shell tried to execute as a program, whose failure `2>/dev/null`
swallowed. Both roots are present on this image and **the sets live under the
second one**, so the tree that mattered was never read.

That makes the empty-set result across every run to date an artefact of a
malformed command rather than a fact about the transport, and it means **the
§5.3 halt grep could not have found wallet material sitting in the real backup
set**: the gate was failing as a pass on the one check that reads a live set.
Fixed by flattening `$present` to a single line before interpolation. The suite
could not have caught it — every case configured a single root, and with one
root there is no newline and no bug; there is now a two-root case that asserts
against what the stub was handed rather than against the verdict, which is
identical either way.

**With the roots actually searched, the set turns up.** The run for `d823265` —
the first in which the LocalTransport tree was really read — found it:

```
/data/data/com.android.localtransport/files/1/_full/com.bittr.android.regtest
```

So the device-transfer path **does** persist a set to a root this check already
knew about; it had simply never been searched. That retires the "or streams it
somewhere this check never looks" half of the question, and it is a directory no
previous run could have seen.

The canary still was not in it, so rule 4/10 does not move. But the remaining
question is now much narrower, and it is the last one before the claim resolves:
**the set directory exists — is anything in it?** A directory the framework
created and wrote nothing into is a backup that produced no data; one whose
contents were all excluded would be evidence. From the canary grep alone those
are identical. The empty-set warning now reports the regular files under the
discovered set paths, so the next run answers it.

Tracked as BIT-116, which stays open. Rule 4/10 stays `not yet proven`, and what
it still needs is a run — but the question left for that run has gone from
"where is the set, if anywhere" to "is the set the framework wrote empty".

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
  uniquely-generated name BIT-20 rule 4 gives it — alongside a canary in
  `files/`, which no rule excludes, and a decoy at each path the
  `dataExtractionRules` `<exclude domain="file">` entries name. Once on the
  cloud-backup path and once with the local transport in device-transfer mode,
  because API 31+ configures the two separately.

  It no longer restores, and since BIT-108 it no longer drives the
  device-transfer backup either — both kill the process the instrumentation runs
  in (see *The device-transfer path cannot be driven from inside the process*
  above). On the cloud path the package is ineligible, so no agent is ever bound
  and the test drives `bmgr backupnow` itself. On the device-transfer path it
  plants, arms `is_device_transfer=true`, asserts the hook back out of the
  settings provider so a renamed hook cannot degrade that run into a second copy
  of the cloud one, clears the stale dataset, writes a hand-off file under
  `no_backup/`, and stops. `ci-wallet-instrumented.sh` reads the hand-off and
  drives that backup from the host, where there is no instrumentation process
  left to kill.

  None of the three halves is evidence alone, and the test asserts none of the
  rule-5 verdict: it creates the conditions and proves it created them.
  `check-backup-set.sh` greps the transport's own tree and decides — and the
  canary is what tells an excluded set apart from a set the framework never
  wrote, which is the likely outcome under `allowBackup="false"` and reads
  identically otherwise.
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

**The two hazards recorded before the first run, and where they stand.** The
first — the instrumentation running inside the process whose data is being
restored, with `bmgr restore`'s effect on it undocumented either way — is
**settled, and was broader than it was written**. It kills the process, and so
does `bmgr backupnow` on the device-transfer path: the hazard is not the restore
specifically but *any* bmgr operation that makes the framework bind a backup
agent in the process the instrumentation is running in. Both are now driven from
the host and neither can come back without failing the build (BIT-108, above).
The second is open by design: `is_device_transfer` is a local-transport test
hook rather than API, so the test asserts the setting was taken rather than
assuming it, and a rename in a future platform release fails loudly instead of
quietly turning the device-transfer case into a second cloud case.

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
  writes a canary into `files/`, which no rule excludes. The canary used to be
  asserted back out of a restore; since BIT-108 there is no restore, so it is
  `check-backup-set.sh` that looks for it, in the set itself. No canary means no
  set, and the script says so instead of reporting a clean grep — the outcome-3
  warning. Nothing in the suite certifies an empty set because nothing in the
  suite certifies anything.
- **An ineligible package.** `allowBackup="false"` makes the package ineligible
  outright, and that is the expected **cloud-path** outcome — it does not reach
  the device-transfer path at all. It is a pass for rule 5 and it is *not* a
  proof that the `<device-transfer>` rules work, because they were never
  consulted. This is exactly the case the canary requirement above separates out:
  an ineligible package and an excluded one both produce "no wallet marker", and
  only the second one also produces a canary. The `BACKUP_EXCLUSION` lines
  printed on every run carry the three prefixes and the framework's own
  per-package result line, so the log says which path each result belongs to even
  when the grep cannot.

  As of run 139 those lines still do not reach `<system-out>` — the runner is not
  filing instrumentation stdout into the result XML (known since run 110). That
  is a gap in the *diagnostics*, not in the verdict, and it is only survivable
  because the verdict moved to the host. It was not before. Tracked on BIT-114.

**Since BIT-108 the verdict does not come from the suite at all.** The check that
decides rule 5 is `android/scripts/check-backup-set.sh`: `BackupExclusionTest`
prefixes every planted file's contents with `MARKER_PREFIX`, and that script
greps the transport's own on-disk tree for it from the host after `adb root`.

It was always the strongest check, for the reason its header gives — the in-test
version depended on `bmgr restore` having done something, and a restore that
silently no-ops produces "nothing came back" for the wrong reason. It is now
also the *only* one, because the restore had to go: it killed the process it
asserted from, and it was vacuous-or-fatal by construction. A restore only kills
the process when the framework has something to restore, so that assertion
passed exactly when nothing had been backed up.

The grep survives what the restore did not — it needs no restore and no living
instrumentation process, so it still answers on a run that went red. It cannot
live inside the suite either way: the set is `0700` to another uid and
`UiAutomation`'s shell runs as `shell`.

It distinguishes four outcomes, and only one is evidence — wallet marker found
(the §5.3 halt), no marker *and the canary present* (evidence: the set was
reachable, searched, provably non-empty, and clean), no marker and no canary (a
`::warning::` at exit 0 — an empty set, the expected `allowBackup="false"`
shape, and **not** evidence), and *could not look* (also a `::warning::`, also
not evidence). Decoy findings are reported alongside whichever outcome the run
got and never trip the halt. Read the `Backup set inspection` annotation to see
which one it was.

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
