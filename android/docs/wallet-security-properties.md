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
| 2 | …and the key is usable with the device **locked** | Unwrap and key generation driven with a real lock-screen credential set and the keyguard up | `SeedReadableWhileLockedTest` (BIT-123 / K2) | **written** — compiles, is in `REQUIRED` by name, and has never executed; it is wired into the `wallet-instrumented` job and awaits its first run. This is the *behavioural* half of rule 2: the two rows above are what we asked for and what the flags report, and below API 37 `KeyInfo.isUnlockedDeviceRequired` does not exist, so this is the only row that shows the key is usable while locked rather than merely declared to be |
| 2 | …and it survives a lock-screen change | — | **BIT-18 / K1**, device matrix | separate issue |
| 3 | The wrapped blob is a cache, never the only copy | Blob loss routes to the restore screen; terminal failures classify as "no usable mnemonic" | `BlobDestroyedRecoversTest` | green |
| 4 | The blob is excluded from Auto Backup | `allowBackup="false"` + `dataExtractionRules` + siting under `getNoBackupFilesDir()` | `BackupExclusionRulesTest` + `StateDirLocationTest` (configuration, JVM) · `InstalledBackupConfigurationTest` (installed artefact, emulator) · `BackupExclusionTest` (both backup paths + `bmgr`, emulator) + `check-backup-set.sh` (the set itself, host) | configuration green; behaviour **partly proven (device-transfer half only), earned on `d073424`.** The set is pulled and **decoded** (`decode-backup-set.py`), and that run enumerated a 4-member tar in which the canary — which no rule excludes — **is** present and no wallet marker is, so the §5.3 halt search ran over decoded members rather than opaque bytes. Every earlier "empty set" was this grep failing to see into a tar, not the transport. Limits: one device, one API level, one set; the **cloud** half is still green only because `allowBackup="false"` makes the package ineligible, which is not evidence; and the wallet absence is overdetermined across all three layers, since every wallet path sits under `getNoBackupFilesDir()`. Separately proven on the same run: the `dataExtractionRules` `<exclude domain="file">` entries **are** live (both decoys excluded while the canary in the same domain survived). Since BIT-59 the suite runs on every push (`wallet-instrumented` job); see §4** |
| 5 | No PIN-derived wrapping | PIN stays a salted-SHA-256 verifier; the unwrap path takes no PIN argument | `WalletKeystorePolicyGuardTest` (bans `PBEKeySpec`/PBKDF2) · `BlobWriteVerifiedTest` (unwrap signature takes no PIN) | green |

### BIT-20 — the LDK state quarantine guard

| # | Rule | Android mechanism | Test | Status |
|---|---|---|---|---|
| 6 | Discriminator is a full-width SHA-256 of the BIP84 account xpub, constant-time compared | Domain-separated SHA-256 over the serialized account xpub, hex, inside the state directory; `MessageDigest.isEqual` | `DiscriminatorSpecTest` | green |
| 7 | match → keep · mismatch → quarantine · absent → quarantine | `SeedImportGuard` | `BlobDestroyedRecoversTest` (match, mismatch) · `ForeignStateQuarantinedTest` (absent) | green |
| 8 | Three-way blob classification; transient ≠ absence | Classification on exception type, no fallback branch meaning "absent" | `TransientKeystoreFailureAbortsTest` | green |
| 9 | Quarantine never overwrites a prior quarantine | Uniquely-named subdirectory under `no_backup/foreign_ldk_state/` | `QuarantineDoesNotClobberTest` | green |
| 10 | Exclusion widens to the LDK state directory, both backup paths | The three layers in rule 4, scoped to the whole wallet directory | as rule 4 | configuration green; behaviour **partly proven (device-transfer half only) — this row's evidence is rule 4's, so its status tracks rule 4's, including its limits; see §4** |

### Port-faithfulness fixes carried without a separate ruling

| Rule | Why | Test | Status |
|---|---|---|---|
| Quarantine before the blob write, durably | Crash between them is unrecoverable in one order and clean in the other | `QuarantineOrderingCrashTest` | green |
| The blob write is read back before success is reported | Ports `persistSecret`'s `writeVerificationFailed` (`CacheManager.swift:528–539`) | `BlobWriteVerifiedTest` | green |
| The blob lives in credential-encrypted storage | A non-auth-bound key is usable during Direct Boot; CE storage is what reproduces `afterFirstUnlock` | `StateDirLocationTest` · `WalletKeystorePolicyGuardTest` | green |
| Derivation is byte-identical to iOS | The backend verifies signatures from these keys | `IosDerivationVectorTest`, against the vector pinned at `BitcoinMessage.swift:363–367` | green |
| A restore reproduces the same **addresses** as iOS, not just the same account | `Bip84Addresses` on bitcoin-kmp, anchored to the vectors BIP84 publishes; BDK peeks the same 20 receive + 20 change addresses on a device | `Bip84AddressVectorTest` (JVM, 11 cases) · `BdkAddressParityTest` (emulator, 5 cases) | JVM half **green**; parity half **written** — has never run. See §6 |

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

## 4. The one claim only partly proven, and the stop condition attached to it

**Rule 4/10's behavioural half.** `BackupExclusionRulesTest` proves the
configuration: `allowBackup="false"`, `dataExtractionRules` wired up, both
`<cloud-backup>` and `<device-transfer>` excluding the wallet directory, no
`<include>` that could re-admit it. `StateDirLocationTest` proves every wallet
path resolves under `no_backup`.

None of that proves a backup set produced by a real device contains none of it.
That is `BackupExclusionTest` (`app/src/androidTest`, BIT-101), which has now
run on a device once — run 107 of the wallet emulator job, API 34 `aosp_atd`.

**What it does.** Plants a wallet-bearing install — wrapped blob, ldk-node
state, discriminator, BDK database, the event ledger, and a quarantine
subdirectory under the uniquely-generated name BIT-20 rule 4 gives it — then
drives `bmgr` to produce
a real set and leaves that set on the local transport. Once on the cloud-backup
path and once with the local transport in device-transfer mode, because API 31+
configures the two separately. The **verdict** comes from
`android/scripts/check-backup-set.sh`, which greps the transport's own on-disk
tree from the host in the same job.

**The plant list grew after the recorded run — BIT-128.** The event ledger
(`no_backup/wallet/cache/handled_events`, the port of
`CacheManager.hasHandledEvent`) is the fifth wallet marker, and it was added
after `d073424`. So the evidence in rule 4's cell covers four of the five; the
fifth is proven by siting (`WalletPathsCreateDirectoriesTest`,
`StateDirLocationTest`, which enumerate `WalletPaths` by reflection and so
covered it the moment it was declared) and by
`BackupExclusionInstrumentationGuardTest`, which is what forced it into the plant
list at all. It is named here rather than left to the next reader to notice,
because a marker planted after the run that produced the evidence is exactly the
kind of thing that quietly turns "four of five" into "all of them". It carries
the most sensitive non-key material the wallet stores — every ldk-node event the
app has shown, which for a successful payment includes the preimage — so the
next wallet-instrumented run is worth reading for it specifically.

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
would go missing exactly when something had gone wrong. BIT-114 later found that
the element does not exist in the writer at all, and took the same way out for
the observations — see the `BACKUP_EXCLUSION` lines later in this section. The
hand-off stays its own file regardless: it means "the plant is on disk and the
host may back up", which is an interlock rather than a record, and permission
must not be inferrable from a line describing what was planted.

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
every one of them died mid-backup. **As of that merge neither `partly proven`
nor the §5.3 halt had been earned**: the first run on a tree carrying both
halves is what produces the answer, and until it reported, rule 4/10 stayed
where it was. (Four runs later it did — see the `d073424` entry below, which is
what moved rule 4/10 to `partly proven` and what the table now reflects. This
paragraph is the state at the merge, kept because the next four entries only
make sense as a sequence.)

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

**And the set is not empty.** The run for `9dc0b64` measured it:

```
-rw------- 1 system system 4608 …/files/1/_full/com.bittr.android.regtest
```

4608 bytes. The framework wrote real data on the device-transfer path — and
**none of the three prefixes was greppable in it**, not the wallet marker, not
the canary, not the decoys. The canary sits in `files/`, which no rule excludes,
so it would be in any set that stored file contents verbatim.

That moves the finding from the transport to the **format**, and it invalidates
an inference this check had been making since it was written: *no canary* was
being reported as *empty set*, which was sound only while the set could not be
measured. It can be measured now, and it is false. A full backup reaches the
transport as a tar stream, and the bytes on disk need not hold contents as
plaintext; compression alone defeats a literal-string search.

**The serious half is what this says about the halt.** The `BIT101-WALLET-MARKER-`
grep that decides §5.3 is the same kind of literal search over the same
unreadable bytes. So wallet material could be sitting in that 4608-byte set and
this check would report exactly what it reported. *A non-halt on the
device-transfer path is not evidence of no leak* — it is a search that could not
have succeeded either way. The check now says so in as many words rather than
filing the result under "the set was empty", which reads as benign.

This is not a §5.3 halt: the halt requires the marker to be **found**, and
nothing was found. It is a gap in the instrument, and rule 4/10 stays
`not yet proven` — now for a sharper reason than before.

Tracked as BIT-116, which stays open. What it needs is no longer a run: it is a
way to **read** the set — untar/inflate it on the host, or assert over the
transport's own API — because no number of runs of a plaintext grep over a
tar stream will answer rule 5 on this path.

**The set is now read rather than grepped (`d073424`).** The first of those two
options is built. `check-backup-set.sh` pulls every regular file under the
discovered set paths to the host and hands them to
`android/scripts/decode-backup-set.py`, which identifies the container — tar,
gzip, zlib, or none of those — enumerates the archive members, and searches
their **decoded** contents for the three BIT101 prefixes. The script still
decides the outcome; the decoder only answers "what is actually in this".

Three things about the shape of that change matter for what the result can be
trusted to mean:

- **Both searches are kept.** The on-device `grep` covers the whole transport
  tree, including journals and pending directories that are not part of any set
  and are not pulled; the decode covers only the set files, but can see inside
  them. Neither subsumes the other, their blind spots differ, and **either one
  finding the wallet marker is the halt**.
- **Truncation is the expected case, not an error.** `LocalTransport` writes the
  bytes it receives from the framework's socket, so what lands on disk is a
  *prefix* of the stream and need not carry tar's end-of-archive blocks. Members
  are read one at a time and whatever arrived is kept and reported, because the
  members that did arrive are the ones a marker could be hiding in. A decoder
  that called a truncated tar "not a tar" would report an unreadable set on every
  real run while passing every well-formed test.
- **Anything unread demotes the whole set.** If one pulled blob will not decode,
  or one set file will not pull, the set is reported as unreadable rather than as
  clean — the marker could be in the part that is missing. A pull is counted only
  when the file actually lands on the host, because `adb pull` exits 0 in cases
  where nothing arrives.

Two states that previously printed the same words are now separate outcomes, and
the distinction is the whole point of this issue:

- **The set was decoded and holds none of our files.** A real negative: the halt
  search ran over decoded members, so "no wallet marker" means one was looked for
  and not found. Still *not* evidence for rule 5 — the canary sits in `files/`,
  which no rule excludes, so a set without it is a set the exclusion rules were
  never consulted about.
- **The set could not be decoded.** The dead end it always was, but the
  annotation now carries the container identification and a head-byte sample, so
  an unhandled format is a one-function fix in the decoder rather than an open
  question. The old wording is kept, including that it is *not* a clean bill of
  health.

The evidence outcome now also states **which** search found the canary, because
resting on the plaintext grep alone is the weaker claim — it proves the set holds
our file contents verbatim, and says nothing about parts of a set a literal
search cannot reach.

**The read answered it, and the set was never empty (BIT-116, closed).** The run
for `d073424` is the first to inspect a set the framework populated, and it
carries its own negative control:

```
decoder readable = yes
containers       = [ …_full_com.bittr.android.regtest : tar ]
4 member(s) enumerated:
  apps/com.bittr.android.regtest/_manifest            (1527)
  apps/com.bittr.android.regtest/r/app_dxmaker_cache     (0)
  apps/com.bittr.android.regtest/f/backup_canary.txt    (44)
  apps/com.bittr.android.regtest/f/profileInstalled     (24)

canary in decoded members         = [ …/f/backup_canary.txt = BIT101-CANARY-MARKER-… ]
canary in the on-device plaintext grep = (none)
```

Those last two lines are the finding. **The same canary, in the same set, on the
same run: found by decoding, invisible to the grep.** That is the cause of every
"empty" device-transfer set on record, and it is a fault in the instrument, not
in the transport or the product. The set was a **tar container** sitting exactly
where the check had been looking all along — `/data/data/com.android.localtransport/files`,
one of the three roots it greps. So of the two candidate states BIT-116 was
opened to distinguish, neither was right: the roots were never wrong, and the
transport never streamed the set somewhere unreachable. The bytes were always
there and always unreadable by a literal search.

This closes out the chain the last four entries were walking: a malformed
`adb shell` command hid the set (`ecd2e5e`), the set turned out to exist
(`d823265`), it turned out to be 4608 bytes rather than empty (`9dc0b64`), and
the bytes turn out to be a tar whose members the grep could never see
(`d073424`). At no point was the transport misbehaving.

**Rule 4/10's device-transfer half moves to `partly proven`.** The bar §4 set
for it — "no wallet marker **and** the canary present in the transport's tree" —
is met, and met in the strong form: the canary came from a decoded read, so the
`BIT101-WALLET-MARKER-` search that decides §5.3 ran over enumerated members
rather than over opaque bytes. A non-halt here is a marker that was genuinely
looked for and not found. It is still one device, one API level, one set.

Three limits on that, stated because the row is now making a positive claim:

- **The cloud half is not evidence and does not become any.** It passes because
  `allowBackup="false"` makes the package ineligible, so nothing is ever offered
  to the transport — green by the same "nothing happened" argument that made the
  original restore assertion worthless.
- **This run cannot say which of the three layers kept the wallet material out.**
  Every wallet path is sited under `getNoBackupFilesDir()`, which the framework
  excludes categorically, so `allowBackup`, the `dataExtractionRules` entries and
  the siting all predict the same absence. The absence is real and it is
  overdetermined.
- **What the run *does* separate is the rules layer**, via the decoys — below.

**The `<exclude domain="file">` entries are live, and that was an open
question.** `data_extraction_rules.xml` says in its own header that it will not
assert from memory whether entries rooted at `getFilesDir()` match anything,
given the wallet directory is under the sibling `getNoBackupFilesDir()`, and it
plants a decoy at each of the two paths those entries name so a device answers
instead. Read the member list above against that: `f/backup_canary.txt` is in the
set, and `f/wallet/decoy.txt` and `f/no_backup/decoy.txt` are not. One file in,
two out, same `files/` domain, same set, same run — the framework populated that
domain and the rules kept exactly the two named paths out of it.

So the entries are **not** a no-op and the `no_backup` siting is not carrying
rule 5 alone. This is a finding about the *rules layer only* and is scoped that
way everywhere it is reported; it does not by itself carry rule 5, for the
overdetermination reason above.

That verdict was reaching the job log and nowhere else. On this public repo the
log answers 403 without a token, so the negative case — by far the more likely
one — was a finding nobody could read; it had to be reconstructed by diffing the
member list against the test source. Both polarities are now annotations.

**And the negative case had to be conditioned before it could be published.** It
had announced "the `<exclude domain="file">` entries excluded the paths they
name" whenever no decoy was found — unconditionally. On runs 107, 133 and
`7e4da43` no decoy was found because *nothing* was found, so the line claimed the
rules worked on precisely the runs that demonstrated nothing. That is the same
vacuity this whole file exists to refuse, one branch deeper. The claim is now
gated on the canary having been found by a decoded read — the control that makes
a decoy's absence mean something rather than nothing — and is withheld as
explicitly **open** otherwise.

Pinned both ways and negative-controlled: 50 cases in `test_check_backup_set.sh`
(whose `adb` stub grew a `pull` verb, so those cases run end-to-end through the
real decoder on real archives) and 42 in `test_decode_backup_set.py`. The
load-bearing one is `a_wallet_marker_in_a_COMPRESSED_set_is_now_the_halt`:
a gzipped set carrying wallet material with **both** on-device greps returning
nothing, which is exactly what a literal search does against a compressed
container. Removing the decoded half of the halt condition makes that case pass
as clean again — which is the behaviour every run before `d073424` had, and the
bug.

**What runs, and where.** The `wallet-instrumented` job boots an API 34
`default` emulator and runs `android/scripts/ci-wallet-instrumented.sh`, which
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

  Those lines did not reach a reader on any run between 110 and 140, and BIT-114
  is why: the gate read them off `<system-out>` in the result XML, and the writer
  AGP uses for connected tests — ddmlib's `XmlTestRunListener` — has a
  `system-err` element and **no `system-out` element at all**. Nothing was being
  dropped on the device; the gate was reading a channel nothing writes to, which
  is why runs 139 and 140 reported no lines while green with every test run. It
  survived thirty runs because its failure mode is a green run that reports an
  absence, and it was survivable at all only because the verdict had already
  moved to the host — it was not, before BIT-108.

  They now arrive on the same shape of hand-off the device-transfer backup uses:
  `EvidenceLog` (one copy per module, in the androidTest sources) appends each
  line to a file under the app's `no_backup` directory, and
  `ci-wallet-instrumented.sh` reads it back with `adb root` after Gradle exits,
  passing it to the gate with `--evidence-file`. A host that cannot read it says
  so in its own `Instrumentation evidence` warning, so "the tests never got that
  far" and "nobody read the device" stay distinguishable — which is the property
  whose absence made this worth an issue.

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

Since BIT-116 it does not only grep. It also **pulls the set and decodes it**
(`decode-backup-set.py`), and searches the decoded archive members — because a
literal search cannot see into a compressed container, and a halt grep that
cannot fail is not a gate. Both searches run; either one finding the wallet
marker is the halt.

It distinguishes five outcomes, and only one is evidence:

| outcome | exit | evidence? |
|---|---|---|
| wallet marker found, by either search | 1 | the §5.3 **halt** |
| no marker, **and the canary present** | 0 `::notice::` | **yes** — reachable, searched, provably non-empty, clean. The annotation says whether the canary came from the decode (strong) or the plaintext grep alone (weaker) |
| no marker, no canary, set measurably **empty** | 0 `::warning::` | no — nothing was in the set to exclude |
| no marker, no canary, non-empty set **that decoded** | 0 `::warning::` | no — but a real negative: the halt search did run over decoded members |
| no marker, no canary, non-empty set that **would not decode**, or *could not look* at all | 0 `::warning::` | no — and **not** a clean bill of health either |

Decoy findings are reported alongside whichever outcome the run got and never
trip the halt. Read the `Backup set inspection` annotation to see which one it
was.

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

A crashed process is not that halt, and run 107 is not it. Neither is an
unreadable set: from `d073424` the halt search runs over **decoded** archive
members, and before that it was a literal grep over tar bytes it could not see
into — so no run before `d073424` could have fired the halt whatever was in the
set. That is worth stating plainly, because a long row of non-halts reads like
accumulating reassurance and until `d073424` it was not.

`d073424` is the first run that could have fired it and did not, on a set proven
non-empty by a control planted in the same domain. So `match → keep` now ships
on a proven *configuration* and a *partly* proven behaviour, and the row above
says so.

What is still owed is breadth rather than a missing instrument: one device, one
API level, one set, and only the device-transfer half — the cloud half stays
green by ineligibility, which demonstrates nothing and would start to
demonstrate something only if `allowBackup` were ever set back to `true`. The
per-run absence of wallet material also remains overdetermined across the three
layers; separating them for the wallet paths would need the material sited
somewhere the framework does not categorically exclude, which is not a change
worth making to the product to satisfy a test.

---

## 5. What this document does not cover yet

- **Node lifecycle** — on-chain sync, channel and payment handling, process
  death, Doze, background execution limits. **BIT-122**; the storage layer above
  is what it will be built on.

  This line read "tracked separately" for as long as the document existed, and
  **nothing tracked it** — there was no issue, so the sentence was doing the
  reassuring work of a reference without being one. That is the same shape as a
  named guarantee with no test behind it, in prose instead of code. BIT-122 and
  BIT-123 now exist, and the state of the node layer is worth stating plainly
  and keeping current:

  **Start and stop now have a node behind them.** `LdkNodeFactory` builds an
  ldk-node `Node` from `NodeConfigPlan` and `NodeLifecycle` owns it — one at a
  time, published only once it is up, and explicitly closed when it is not.
  Two claims there carry tests that run on the JVM, which is further than an
  adapter normally gets and is worth saying why: UniFFI generates ldk-node's
  records as plain Kotlin data classes and its `Builder` as a plain Kotlin
  interface, so `LdkNodeConfigTest` asserts the whole configuration against
  `BitcoinManager.swift` field by field with a recording fake, and
  `NodeLifecycleTest` proves the object-custody rules against a fake node.
  Neither loads a native library. What they do **not** prove is that ldk-node
  honours any of it — that needs a running node, and it is BIT-123's.

  **What each piece of the node layer now is** — this list is written with
  issue numbers for the same reason the paragraph above it was rewritten. It
  began as a list of absences and is no longer one; what is still missing is
  said in place rather than by leaving a delivered item on it.

  - **On-chain sync now runs, on the node's lifetime.** **BIT-124** built the
    BDK half — `BdkWalletFactory.open` is `didStartBDK()` from the mnemonic
    down to a `Wallet`, and `OnchainSync` is the scan sequence, generic over
    its four BDK types so the whole of it is asserted on the JVM. Both had **no
    caller in `main`** until `OnchainSyncLoop`, which is `startBDK()` plus
    `BackgroundSync` as a `NodeRunner`: open the wallet, full-scan unless a
    scan has already succeeded in this process, and only then start the
    30-second light-sync timer. It is in the host's runner list beside the
    event pump, so it is cancelled on every node stop and relaunched on every
    start.

    Three things to be plain about:

    - **A failed full scan presents an empty wallet, and nothing here retries
      it.** iOS's retry is the user reopening a screen that calls
      `didSyncBdkWallet` again; Android has no such screen yet, so the only
      thing that revives it is `WalletNodeHost.start()` relaunching a runner
      that is no longer live — the unlock path. It fails closed (balance zero,
      and a drain that refuses rather than offering a wrong number), which is
      why this is a cost rather than a fund risk. It is still the most likely
      reason an Android user sees "no funds" on a wallet that has them, and
      `BdkStore` wiping the store on every start is what makes the scan
      mandatory rather than an optimisation. **That wipe is a port of iOS and
      changing it is a deviation, so it is **BIT-131**'s decision to take and
      not one to make in code.**
    - **On-chain balance is still not read from BDK, deliberately.** Every
      on-chain figure iOS shows comes from `node.listBalances()`, never
      `bdkWallet.balance()`, because BDK does not know about the anchor-channel
      reserve and would show a spendable amount ldk-node refuses to release.
      What BDK is for here is the scan, the UTXO set and the drain.
    - **The Electrum server is a second endpoint, not the node's.**
      `LdkEnvironment.electrumUrl` is its own field: iOS only points both at
      the same URL on mainnet, and everywhere else ldk-node gets Esplora over
      HTTP while BDK gets Electrum over TCP. Collapsing them would fail as
      "sync failed" on every development build with nothing naming the cause.
      It is a required field, so a build that omits it composes the seed-only
      wallet rather than a node with a permanently zero on-chain balance.
  - Lightning channel and payment handling, and the ldk-node event loop.
    **BIT-125** — the decisions have landed; the wiring has, in part. `lightning/`
    now holds the balance arithmetic that turns ldk-node's `BalanceDetails`
    into the figure beside the on-chain balance, the guard that decides whether
    the wallet may be deleted from the device, the LSP reconnect, the BOLT12
    fee ceiling and the event pump's acknowledgement order; `LdkNodeSurface` is
    the binding, and its record-to-view mapping is asserted on the JVM for the
    same reason `LdkNodeConfigTest` can be. Three things to be plain about:
    **no test here runs against a node** (BIT-123); the pump's survival
    across backgrounding is a property of the service hosting it, not of the
    loop; and the balance arithmetic now *runs* on a running app (BIT-144,
    below) but its **figures** still have no consumer — there is no home screen
    and no caller for `OnchainDrainClamp`, so what the snapshot is read for
    today is the three cache writes and nothing else.

    **The pump does now have a caller.** BIT-126 built the host and passed it
    `runners = emptyList()`, because `EventLedger` and `ChannelClosureStore`
    both wanted `CacheManager`-shaped storage Android did not have. That
    storage is `WalletCache`, a file store under `no_backup/wallet/cache` — a
    sibling of `ldk_state/` and `bdk_store/` and a child of neither, because
    the BIT-20 quarantine *moves* the first and `BdkStore.prepare` *deletes*
    the second, and a ledger inside either forgets everything without
    reporting an error. `CacheSurvivesStateLifecyclesTest` runs a real
    quarantine and a real prepare over a populated cache. The pump's handler is
    a log line and nothing else, because Android has no payment screen yet —
    the *variant name* rather than the rendering, since a rendered
    `PaymentSuccessful` carries the payment preimage.

    **The closure scan does now have a caller too, and it was the last thing on
    this list with none.** BIT-130 wired `ChannelClosureRecorder` into
    `OnchainSync`'s `closures` parameter — the argument BIT-128 could only
    leave defaulted, because the recorder needs a Lightning channel list and
    nothing then had one to give it. It is assembled in `di/WalletModule` out of
    three layers at once: the store is `CachedChannelClosureStore` over the same
    `WalletCache` the event ledger uses, the transactions are the open BDK
    wallet's, and the channel list is `listChannels().openChannelFundingTxIds()`
    read through the *same* `LightningNodePort` the graph hands out. So a closed
    channel's closing txid is now recorded on a running app, at iOS's position —
    after the persist, on both sync paths, before success is reported.

    **And the outpoint it watches now has a writer.** BIT-144 was the half
    BIT-130 left open: `ChannelClosureRecorder`'s first step reads the funding
    outpoint out of the cache, and nothing in `main` wrote one, so on a running
    app the scan short-circuited on every sync and recorded nothing.
    `WalletBalanceReader` is the production caller `WalletBalanceSnapshot.of`
    did not have — iOS's `loadWalletData()` — and it performs the three cache
    writes the snapshot names: the funding outpoint when there is an active
    channel, the closure spending txids unconditionally, and the clear when a
    closure is pending. Four things decided there rather than ported, because
    Android has no home screen to port from:

    - **Its trigger is `OnchainSyncLoop`'s tick, not a timer of its own.** iOS
      reads on home-screen load and on the light-sync comparison
      (`BitcoinManager.swift:496`); the second has a counterpart here, because
      the sync loop's 30-second `BackgroundSync` timer is already running for
      as long as a node is up. A second timer would have the same period and
      the same lifetime and would only cost a wakeup while the app is
      backgrounded.
    - **The read runs *after* each sync, never before.** `OnchainSync` runs the
      closure scan at the end of a sync that applied, and the read's third write
      clears the very outpoint that scan needs. Reading first would clear it in
      the same tick the scan was about to use it, and the closing transaction
      would never be recorded. `OnchainSyncLoopTest` carries that as a negative
      control.
    - **What that costs is that a failed full scan takes the balance read with
      it**, because the read has no clock of its own. The two are otherwise
      unrelated — the read goes to the *node*, not to BDK — so this is
      acceptable only while the read's sole consumer is the closure scan, which
      also only runs off an applied sync. The day the drain clamp or a balance
      screen reads the snapshot, the answer is a runner of its own.
    - **The node is read through one handle.**
      `LightningNodePort.readWalletState()` takes the `Node` up front and makes
      the three FFI calls against the local, which is iOS's "take the node
      handle up front" and matters more here: `NodeLifecycle.current` goes null
      between two statements routinely, and two thirds of a wallet plus an empty
      list is indistinguishable from a wallet with no channels. Null means no
      node, and nothing is written on it.

    **Still to be plain about: on a wallet that has never opened a channel there
    is nothing to write.** `listChannels()` is empty, so
    `channelFundingOutpointToStore` is null and the scan finds no outpoint to
    watch — which is the correct behaviour for a wallet with no channels rather
    than the broken wiring it was. The channel-open path is BIT-122's remaining
    half, and when it lands it writes through the same
    `CachedChannelClosureStore.store`.

    Three more things to be plain about:

    - **`OnchainSync.closures` is no longer defaulted.** A defaulted parameter is
      a wiring step that can be forgotten in silence: `OnchainSync(port, scans)`
      compiles, syncs correctly, and never records a closure. Every construction
      site now says which it wants, and null is still a legitimate answer.
    - **The channel list is read during the scan, not before the sync**, and an
      empty answer is the safe direction rather than a bug. A torn-down node
      answers `listChannels()` with an empty list, which makes `shouldScan` say
      yes about a channel that may still be open — and that costs a walk of the
      transaction list and nothing else, because the match is on the funding
      **outpoint** and an open channel's funding output is unspent.
      `ClosureScanWiringTest` drives that case with a transaction spending the
      funding transaction's *other* output and asserts nothing is recorded;
      matching on the txid alone reddens it.
    - **`BdkWalletTransactions` has no JVM test and is the reason the wiring
      test stops where it does.** Every call on that path crosses into Rust and
      returns a concrete BDK type, so there is no seam to fake below
      `WalletTransactions` — the join above it is asserted on the JVM with a
      real `FileWalletCache` and the real channel-list expression, and the
      mapping itself belongs to the regtest suite.

    Two deliberate divergences from iOS are recorded in code and repeated here
    because they are the kind that get "tidied" back: the channel-balance
    subtraction is floored at zero rather than being allowed to wrap a `ULong`
    — Swift traps where Kotlin would show the user 184 billion bitcoin — and an
    event whose handler threw is **not** acknowledged, where iOS acknowledges
    unconditionally. The first is a display figure, the second trades a replay
    for a loss. Neither touches key handling or signing.
  **Start and stop now have a caller — in a build that was given a node.**
  BIT-126 landed the host: `WalletNodeHost` owns the wallet's process-lifetime
  `CoroutineScope`, `NodeBackedWalletService` binds `WalletService.start`/`stop`
  to `NodeLifecycle.startOnce`/`stop`, and `WalletForegroundService` is what
  keeps the process out of the frozen state while a node runs. `UnlockViewModel`
  already called `wallet.start()` after a correct PIN; that call now reaches a
  node. Four ordering rules carry JVM tests in `WalletNodeHostTest` — the
  process is held up *before* a start begins, a cancelled caller does not
  release it, a new node gets new runners, and `removeWallet` erases nothing
  until the node is down.

  Three things about that are worth stating rather than discovering:

  - **Whether it is on is a property of the build, not of the source.** The node
    needs an `LdkEnvironment`, every field of which is empty in a clone — this
    issue's note, as a build rule, asserted by `LdkEnvironmentConfigTest` against
    the compiled `BuildConfig` and by `NoCommittedNodeCredentialsTest` against
    the sources. An unconfigured build composes `SeedWalletService`, which is
    what the app was before. **CI and Maestro run the unconfigured build, so
    nothing below has been exercised against a running node.**
  - **The foreground service notification is unapproved placeholder copy.** It
    is permanently on the user's screen while the wallet runs and has no iOS
    string to port. It must go through the copy process before it ships.
  - **The scope is the host's, not the service's**, which is a deliberate
    divergence from how BIT-126 was written. A scope inside the service would
    make `ForegroundServiceStartNotAllowedException` — routine on Android 12+ for
    a backgrounded app — fatal to the node start. The reasoning is in
    `WalletNodeHost`'s class comment.

  Process death, Doze and background execution limits remain unmeasured —
  `NodeConfigPlan`'s sync intervals are still a request rather than a guarantee,
  for the reasons that data class states. The foreground service is the
  *mitigation*; **K8 is what would say whether it works**, and it needs a
  device. **BIT-123.**
- **K2 (background wake), K7 (interrupted payment) and K8 (Doze soak)** from
  `wallet-core-spec` §6. **BIT-123**, which BIT-122 has now cleared. Each is now
  either running or closed unrun with its cost named, in
  `android/docs/wallet-node-device-tests.md` — the BIT-18 precedent. The state of
  each, because a pointer to a document is not a status:

  - **K2's load-bearing half is now written**, so rule 2's row above stops
    resting on the key's spec alone once it runs — *written*, not *green*, until
    a `wallet-instrumented` run says otherwise. `SeedReadableWhileLockedTest` sets a real
    lock-screen credential, locks the device, and unwraps the seed through the
    Keystore with the keyguard up — the property BIT-8 rule 2 chose a
    non-auth-bound key to get. It also closes the hole `KeystoreKeyInfoTest`
    leaves on every API below 37, where `KeyInfo.isUnlockedDeviceRequired` does
    not exist and the flag can only be checked on the spec side. All three of
    its methods are in `check-wallet-instrumented-results.py`'s `REQUIRED` set by
    name, including the negative control — without that one, "the seed was
    readable while locked" and "the device never locked" are the same green.
  - **K2's FCM half is closed unrun, and its force-stop half is withdrawn as
    specified.** There is no `FirebaseMessagingService` in this app, the
    AOSP image the suite needs for the backup transport has no Play
    services to deliver a message, and — separately from any of that — Android
    does not deliver FCM to a package in the *stopped state*, which is what
    `am force-stop` produces. The claim underneath is **process death**, a
    different event reproduced by `am kill`. That is a correction to
    `wallet-core-spec` §6 rather than a hardware limit.
  - **K7 and K8 are closed unrun**, and the reason is upstream of hardware: the
    `wallet-instrumented` job builds an **unconfigured** APK, which composes
    `SeedWalletService` and contains no node at all. Giving the runner a phone
    would not make either runnable. Both also need a private Lightning network —
    bitcoind, Esplora, Electrum and a peer — and K7 additionally needs a
    deterministic interception point in the send path, without which a
    fund-safety property gets reported as flaky. All of that is **BIT-132**;
    K2's wake leg and the `wallet-core-spec` §6 correction are **BIT-133**.
- **K4's address half is now covered** — it was in this list until §6 was
  written, and it is the one item that moved out of it rather than being split
  off.
- **`data_loss_protect` on channel re-establish — verified, and no longer an
  open item.** A user who deliberately restores their mnemonic on a second
  device while the first still holds live channels is outside what backup
  exclusion closes, and what stands between them and a penalty is Lightning's
  own behaviour. Inherent to mnemonic-only recovery plus Lightning, and already
  true on iOS (`LightningStorage.swift:21–23` accepts it in as many words).
  BIT-123 required it to be **verified against ldk-node 0.7.0 rather than
  asserted from memory**, and this is that verification.

  **What was read, and out of what.** `android/scripts/check-ldk-data-loss-protect.py`
  opens the `ldk-node-android` AAR the build actually resolved — not a copy it
  fetched — and asserts five markers in each of the three shipped ABIs
  (`arm64-v8a`, `armeabi-v7a`, `x86_64`). ldk-node 0.7.0 links rust-lightning
  `lightning-0.2.0` and `lightning-types-0.3.0`. Four findings:

  - **The stale-state branch is compiled in, and it refuses to broadcast.** The
    binary carries rust-lightning's *"We have fallen behind — we have received
    proof that if we broadcast our counterparty is going to claim all our
    funds"*, which continues *"…you should restart with an empty ChannelManager
    and no ChannelMonitors, reconnect to peer(s), ensure they've force-closed all
    of your previous channels"*. That refusal **is** the protection: publishing a
    revoked commitment is what hands the channel balance to the counterparty, and
    this is the path that declines to.
  - **The TLV fields exist in both directions.**
    `your_last_per_commitment_secret` is what lets us discover we are behind;
    `my_current_per_commitment_point` is what lets a *peer* recognise that a
    restored device is behind. The second-device case depends on the second
    direction, not the first.
  - **LDK requires the feature rather than offering it.**
    `set_data_loss_protect_required` is monomorphised into the binary and
    `set_data_loss_protect_optional` is not, so `option_data_loss_protect` is a
    compulsory init feature bit: a peer that does not implement it cannot
    complete feature negotiation with us at all. The check asserts that absence
    as well as the presence, because without it "required" would be an
    assumption. `option_static_remotekey` is likewise required.
  - **Peer storage is not a recovery path here.** bLIP-55
    (`set_provide_storage_optional`) is offered, not required, so a restored node
    cannot count on the LSP handing its state back. Recorded, not asserted.

  **What this does not prove, stated plainly.** A string in a binary shows a
  branch was compiled, not that it executes correctly against a real peer. The
  behavioural half is K7's, and needs the private Lightning network
  `android/docs/wallet-node-device-tests.md` §3 describes.

  **And one thing the mechanism does not cover at all, which is worth saying
  here rather than leaving to be rediscovered.** The two devices share a seed, so
  they also share the BIP84 on-chain account. `data_loss_protect` is about
  channel state; it says nothing about two wallets deriving the same addresses
  and spending the same UTXOs. That is not a penalty-transaction risk — channel
  funding outputs are 2-of-2 and outside the descriptor — but it is a real
  same-seed-two-devices hazard and it belongs to the restore flow, not to
  Lightning.

  The check runs in the `build` job on every push, after the Gradle step that
  resolves the artifact, so an ldk-node bump that drops any of this goes red in
  seconds rather than being discovered from a user.

---

## 6. K4 — a restore reproduces the same addresses, not just the same account

`wallet-core-spec` §6 states K4 as *"restore-from-mnemonic on a fresh install
reproduces the same descriptors, xpub and first 20 addresses as iOS."* Until this
section, the **xpub** clause was proven (`IosDerivationVectorTest`,
`BdkAccountXpubParityTest`) and the **address** clause had no implementation and
no test anywhere in the module. `Bip84Account` derived account keys and swap
refund keys; nothing derived a receive address.

**Why that gap was worse than a missing assertion.** Everything that reports on a
restore keys on the account, not on the addresses. A restore that reproduced the
right account xpub and the wrong addresses would look entirely healthy — the
backend accepts the account it registered at signup, the node starts, the balance
reads correctly for the addresses BDK is actually watching — while every address
handed to a payer is derived from a path the user's other device never scans.
There is no error at any layer. The wallet silently splits in two, and the money
goes to the half nobody is looking at.

**The anchor, and why a golden file alone would not have been one.** The obvious
test derives 20 addresses, pastes them in, and asserts they never change. That
catches a regression and nothing else: if the derivation is wrong the day the
golden is written, the golden pins it wrong and the test passes forever. So the
JVM side asserts first against the vectors **BIP84 itself publishes**, for the
mnemonic BIP84 publishes them for — three constants this repository did not
author and cannot regenerate from its own code:

| path | published address |
|---|---|
| `m/84'/0'/0'/0/0` | `bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu` |
| `m/84'/0'/0'/0/1` | `bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g` |
| `m/84'/0'/0'/1/0` | `bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el` |

Only once those hold is the golden for the iOS mnemonic pinned — a golden from a
checked implementation rather than an assumed one. Index 1 as well as 0, and the
change branch as well as the receive branch, because a derivation that dropped
the index would satisfy the first row alone and one that dropped the change level
would satisfy both receive rows.

**What makes it parity with iOS rather than with ourselves.** iOS pins
`bdk-swift 1.2.0`; this module pins `bdk-android 1.2.0` — two bindings over one
Rust core at one version. `BdkAddressParityTest` builds the BIP84 wallet on a
device, peeks the first 20 receive and 20 change addresses, and asserts them equal
to the golden. That is the same argument `BdkAccountXpubParityTest` already rests
on, and it is what lets the claim name iOS without a Swift toolchain in CI.

The golden lives in `src/sharedTest` for the reason `Mnemonics` does: `androidTest`
cannot see `test`, so a copy would turn the parity test into BDK-versus-a-stale-
snapshot-of-bitcoin-kmp — the exact failure a parity test exists to catch,
reintroduced by the fixture.

**Negative-controlled both ways, because a golden comparison is the easiest kind
of test to make vacuous.** Perturbing the bulk derivation by one index fails the
two golden cases *and* `the bulk helpers agree with the single-address
derivation` — which exists because `addressAt` is the BIP84-anchored path and the
bulk helpers are separate code that nothing else checks. Perturbing the shared
path's change level fails all three published-vector cases. Both controls were
run, not reasoned about. The suite also carries the usual refusals: different
mnemonics must produce different addresses, receive and change must not collide,
mainnet and signet must not share an address, and a change level outside {0,1}
is rejected rather than derived — a real spendable address on a path no wallet
scans is funds invisible to BDK's own recovery.

**Status, stated the way this file's status key requires.** The JVM half is
**green**: `Bip84AddressVectorTest` passes in `./gradlew test` (707 tests, 0
failures, 0 skipped across the project). The parity half is **written and has
never run** — `BdkAddressParityTest` was authored in `386aff5` and no CI run has
yet executed it on the emulator.

That distinction is the whole point of the status column, and it is worth being
exact about what is and is not established. The address *derivation* is anchored:
`Bip84Addresses` reproduces the vectors BIP84 publishes, and that is checked on
every JVM run. What is **not** yet established is that **BDK agrees with it** —
and BDK is the implementation that actually hands addresses to users, and the one
that carries the argument to iOS. Until the emulator run reports, the row above
is a claim about bitcoin-kmp and about the standard, not about the shipping path.
The two have never been compared on a device even once.

A first run was in flight when this was written and the result was not readable
(the anonymous GitHub API quota was exhausted). "In flight" is not a status
either; the row moves to green when a run reports, and not before.

**Where it runs.** `Bip84AddressVectorTest` on every `./gradlew test` (11 cases,
no device). `BdkAddressParityTest` in the `wallet-instrumented` job on the API 34
emulator, with all five methods named individually in
`check-wallet-instrumented-results.py`'s `REQUIRED` set — by method and not by
class, so four of five cannot disappear inside a green run. That listing is not
belt-and-braces: `BdkAccountXpubParityTest` spent its first two runs absent from
that set, and both runs reported `vacuity check passed` while saying nothing
whatever about it.

**What this does not claim.** It covers derivation, not discovery. Gap limits,
used-address scanning and the receive index belong to BDK's wallet, which owns
that state; nothing in `Bip84Addresses` is on the path that hands an address to a
user. It exists to be compared against the path that does. The descriptors clause
of K4 is covered only insofar as the addresses they produce match — the
descriptor *strings* are asserted for the account xpub they embed
(`DescriptorXpubTest`, `BdkAccountXpubParityTest`) and not character by character
against an iOS-generated file.
