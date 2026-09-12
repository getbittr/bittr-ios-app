# K1 — does a non-auth-bound Keystore key survive a lock-screen change?

**BIT-18.** Split out of BIT-6 by the BIT-8 decision (option (a), Ruben, 2026-09-10).
This test does not gate the storage design — it *verifies* one of its rules.

## Status

**Two of the seven rows now have real observations; five do not, and there is no
verdict on rule 2 yet.** API 34 came back green on all five reachable cases and
API 26 on the one it can witness. That is one emulator API level and a partial
second — not the matrix, and specifically not the two OEM handsets this test was
written for. Nothing here may yet be quoted as evidence that rule 2 holds *on a
customer's phone*.

What remains is a hardware gap on two rows and three unrun emulator levels — see
[What is blocking the run](#what-is-blocking-the-run).

The harness itself is now tested, device-free, and gated in CI: see [Checking the
harness without a device](#checking-the-harness-without-a-device). That is a
statement about the driver's reasoning and nothing else. **It is not evidence
about Keystore**, and no amount of it ever will be.

The five emulator rows now have a way to be produced —
`.github/workflows/k1-keystore-lockscreen.yml`, which boots an emulator on an
ordinary GitHub-hosted runner. **Seven runs have been made. The first six
produced no rows at all**, and every defect they exposed was in this harness
rather than in Android. See [Runs so far](#runs-so-far).

Run #6 was the decisive one: it proved that `adb shell locksettings verify` exits
0 for everything on the API 34 image, which condemned every host-side witness the
driver had. Those witnesses were **rebuilt on the device side** — see [How a row
avoids being a false green](#how-a-row-avoids-being-a-false-green) — and **run #7
produced the first rows this issue has ever had**: API 34 green on all five cases
with full witnesses, API 26 short by the three cases nothing on that device can
witness. See [Results](#results). The two physical-device rows still need handsets
someone owns.

## What is being proved

BIT-8 rule 2 requires the Android seed blob to be wrapped by a **non-auth-bound**
Keystore key: no `setUserAuthenticationRequired(true)`, no
`setUnlockedDeviceRequired(true)`. That is the faithful port of the mnemonic's
actual iOS class, `afterFirstUnlockThisDeviceOnly` (`CacheManager.swift:358`),
and it is what keeps a background node start working.

The premise underneath the rule is that Keystore's documented lock-screen
invalidation applies **only to auth-bound keys**. Today that premise rests on
AOSP javadoc. Documentation is not a device and OEM builds diverge, so K1 turns
it into a per-device fact: generate a non-auth-bound `AES/GCM` key, seal a known
blob, mutate the lock screen, and open the blob from a process that did not exist
when the key was created.

**The blob under test is a known constant, not a seed.** No mainnet keys, no real
funds, on any device this ever runs against.

## The cases

BIT-18 lists five mutations. This is six rows, because "change PIN → pattern /
password" is two different credential types and the entire premise of K1 is that
OEM builds diverge — there is no reason to assume a pattern and an alphanumeric
password take the same path through an OEM's `LockSettingsService`.

| case | BIT-18 mutation | secure before → after | auth-bound control | witness | needs API |
|---|---|---|---|---|---|
| M1 | 1. set a lock screen where none existed | no → yes | — | keyguard | 26 |
| M2 | 2. change PIN → PIN | yes → yes | — | complexity bucket | 29 |
| M3 | 3. change PIN → password | yes → yes | — | complexity bucket | 29 |
| M4 | 3. change PIN → pattern | yes → yes | — | complexity bucket | 29 |
| M5 | 4. remove the lock screen entirely | yes → no | yes | keyguard + control key | 26 |
| M6 | 5. forced reset of the secure lock screen | yes → no | yes | keyguard + control key | 26 |

## How a row avoids being a false green

The expensive failure here is not a red row. It is a **green row from a run where
the mutation silently did not happen** — the key "survived" something that never
occurred, and the row gets quoted in a security statement. Four independent things
have to line up before a row reads PASS:

1. **Both instrumentation phases exited clean**, as separate `am instrument`
   invocations with a `force-stop` between them. `K1Probe` re-opens
   `AndroidKeyStore`, re-fetches the entry by alias and re-initialises the
   `Cipher` every time, so a `SecretKey` handle cached across the mutation cannot
   carry a dead key to a pass.
2. **Phase 2 emitted a `verdict=PASS` line.** A green exit with no line is scored
   as a harness failure, not a pass.
3. **The keyguard witness passed.** The device must end up on the correct side of
   the has-a-credential line: `KeyguardManager.isDeviceSecure` false → true for
   M1, true → false for M5 and M6, unchanged for M2/M3/M4. `K1OpenTest` asserts
   it *before* it decrypts, so a run that mutated nothing fails on the witness
   rather than reporting survival.
4. **The credential-change witness passed.** Where the device reports it,
   `DevicePolicyManager.getPasswordComplexity()` must have **moved bucket**
   across the mutation. A mutation command that exits 0 and does nothing leaves
   the bucket exactly where it was.

**Every one of those four is read on the device side of `adb`, and that is
recent.** Item 4 used to be `locksettings verify` on the host, and
[run #6](#run-6--the-witness-is-what-is-broken-not-the-device) established that
on the API 34 image that call exits 0 for everything — the credential just set, a
deliberately wrong one, and a bare `verify` with no argument at all. A witness
that always says yes is how a false green gets made, so the question moved across
`adb` into `K1ObserveTest`, which asks the same framework services the OS itself
locks with. `locksettings` now only ever *mutates*; it is never asked a question.

Item 4 is what carries M2, M3 and M4. Those three are secure on both sides, so
item 3 degrades to "the driver did not do literally nothing" and the bucket move
is the only evidence there is. It arrived in **API 29**, so on API 26 and 28 those
three cases have no witness at all and are recorded `NOT REACHABLE` with the
reason attached — see [Where a case cannot be
witnessed](#where-a-case-cannot-be-witnessed).

Items 3 and 4 are each checked **twice**: once by the driver between the phases,
and again inside `K1OpenTest`. That redundancy is the point rather than an
oversight. A witness failure caught by the driver is an `ERROR` — *this run has no
verdict on rule 2*. The same failure reaching `K1OpenTest` comes back as a failed
test and would be recorded `FAIL` — *this device contradicts rule 2*. Those two
rows mean opposite things and only one of them is about Android, so a harness bug
must not be able to arrive dressed as a platform finding.

### What the bucket witness can and cannot see

The credentials in `k1-lockscreen-matrix.sh` are chosen to sit in **different**
buckets, because two PINs in the same bucket would make a real PIN change
indistinguishable from no change at all:

| case | mutation | bucket move |
|---|---|---|
| M1 | none → PIN `1379` | `NONE` → `MEDIUM` |
| M2 | PIN `1379` → PIN `13795284` | `MEDIUM` → `HIGH` |
| M3 | PIN → password `k1pass99` | `MEDIUM` → `HIGH` |
| M4 | PIN → pattern `1236` | `MEDIUM` → `LOW` |
| M5 / M6 | PIN → none | `MEDIUM` → `NONE` |

**A row requires the bucket to move. It does not require it to land where that
table predicts**, and the distinction is deliberate. The mapping above is AOSP
documentation — a 4-digit non-sequential PIN is `MEDIUM`, the same at 8 digits is
`HIGH`, a pattern is always `LOW` — and the premise of this entire test is that
documentation is not a device. Failing a row because an OEM buckets credentials
differently would turn the matrix red on the strength of the thing K1 exists to
distrust. So a surprising landing is recorded as a **note beside a row that still
passes**, naming both the expected and the observed bucket.

That leaves one honest limit, stated here rather than left for someone to find
while quoting a row: **nothing public on Android reports the credential's
*type*.** A `set-password` that in fact set a pattern cannot be refuted by this
harness — the credential did change, the device is still secure, and the key's
survival is a real observation either way. What K1 *can* see is that the bucket
landed on `LOW` where a password predicts `HIGH`, and it says so in the note. The
case that used to worry this section — a `set-password` that in fact *cleared* the
lock screen, giving an M5 result printed on the M3 row — is now caught outright by
item 3, because M3 must end `isDeviceSecure=true`.

### Where a case cannot be witnessed

M2, M3 and M4 are secure on both sides of their mutation. On a device that does
not report password complexity — **API 26 and 28**, where
`getPasswordComplexity()` does not exist, or an OEM build that refuses it —
nothing can see those mutations happen, and K1 will not report rows about them.
They come back `NOT REACHABLE` with `reason=no-credential-change-witness`.

M1, M5 and M6 are unaffected: the keyguard transition is decisive and available on
every API in the matrix. An API 26 row is three results short, not empty.

**That refusal is made by the device, not by the driver.** `K1SealTest` asks
`getPasswordComplexity()` and declines the case with `assumeTrue` if it gets no
answer; the driver turns that skip into the row. The driver never infers it from
`Build.VERSION.SDK_INT` — K1 has already made exactly that mistake once, gating
the `isUnlockedDeviceRequired` readback at API 28 for a method that arrived in
36.1, where `compileSdk 37` hid it and it threw on every device in the matrix.

### The auth-bound control, and why it is not on every row

M5 and M6 additionally create a key that is *supposed* to die — an auth-bound key
bound to the device credential. If it outlives a credential **destruction**, then
the credential was not destroyed and the non-auth-bound result is evidence of
nothing.

It is deliberately **not** a witness on M2/M3/M4. A PIN → PIN change re-wraps the
synthetic password and auth-bound keys legitimately survive it. Asserting their
death there would make K1 report false **reds** — which would be read as a rule-2
contradiction and would cost a design change that the evidence did not call for.

The control key is only ever checked for existence, never decrypted: decrypting it
needs a real user authentication, and `UserNotAuthenticatedException` is not
distinguishable from invalidation for our purposes.

## Running it

```sh
# one device attached, all cases that do not need a device owner
bash android/scripts/k1-lockscreen-matrix.sh

# a single case, a named device, table written to a file
bash android/scripts/k1-lockscreen-matrix.sh -s emulator-5554 M2 --out /tmp/api33.md

# M6, emulator only — sets a device owner, which needs a factory reset to undo
bash android/scripts/k1-lockscreen-matrix.sh --with-device-owner M6
```

`connectedAndroidTest` does **not** produce a K1 result. It runs the seal and open
phases back to back with no mutation in between; phase 2 then fails its
start-state assertion. That is the designed behaviour — no false pass — but it is
not a row.

### Running the emulator rows in CI

`.github/workflows/k1-keystore-lockscreen.yml` runs the matrix on a booted
emulator, one job per API level, and uploads each table as an artefact and into
the job summary. It is how the five emulator rows get produced without anyone
owning five phones.

It runs **only when asked** — `workflow_dispatch`, or a push to a `k1-run/**`
branch. K1 is a measurement, not a gate: the answer changes only when the platform
does, and folding it into `android-maestro.yml` would multiply the cost of every
Android push by five to re-answer a question nobody asked again. The `k1-run/**`
trigger exists because GitHub offers no dispatch button until a workflow reaches
the default branch, which would otherwise move the block on this issue from "no
device" to "no button".

```sh
# before merge — the branch name says which images to boot
git push origin HEAD:k1-run/pilot              # API 34 only (no digits = one image)
git push origin HEAD:k1-run/26-30-33-34-35     # the full BIT-18 sweep

# after merge, from the Actions tab or:
gh workflow run k1-keystore-lockscreen.yml -f api_levels='[26, 30, 33, 34, 35]'
```

A branch name with no digits in it gets **one** image, API 34 — the one this
project's runner is known to boot. That default is deliberate: the first run of
any change to the harness should not boot five emulators to watch the same
mistake five times. Ask for the sweep by name once the pilot is green.

It needs the **same host as the Maestro emulator job** — KVM, and the
`ANDROID_EMULATOR_RUNNER` repository variable pointing at it. See
`self-hosted-runner.md`. On a single self-hosted runner the five jobs serialise;
budget roughly an emulator boot plus six mutations each.

Three details in that workflow are load-bearing rather than taste:

- **`force-avd-creation: true`, no snapshot save, no AVD cache.** This matrix sets,
  changes and removes the lock screen, and under M6 makes the probe a device
  owner — a state nothing short of deleting the AVD undoes. A cached AVD would
  carry it into every later run on the host, and the symptom would be M6 failing
  to set up on a machine nobody had touched. It also guarantees M1 starts from a
  device with no credential, without which M1 means nothing.
- **`fail-fast: false`.** A divergent API level is the result. If 30 comes back
  red the table still needs 26, 33, 34 and 35 to say whether it is an outlier or
  the rule.
- **M6 is off by default**, behind the `with_device_owner` input.

The job goes red when any row is not `PASS`, `ERROR` included. An `ERROR` row means
the harness could not establish what happened, which is not a pass.

### Reading a run's result back

```sh
android/scripts/k1-result.py                      # the latest run, table and all
android/scripts/k1-result.py --branch k1-run/pilot
android/scripts/k1-result.py --wait 900           # poll until the run finishes
```

Exit codes: `0` every row PASS · `1` looked, and it is not green · `2` could not
find out.

**This is not a convenience.** On `getbittr/bittr-ios-app` every other channel the
workflow writes to needs credentials:

| channel | unauthenticated |
|---|---|
| `GET /actions/jobs/:id/logs` | `403 Must have admin rights to Repository.` |
| `GET /actions/artifacts/:id/zip` | `401 Requires authentication` |
| the job summary | not exposed by the REST API at all |

Annotations are the exception — `/repos/:owner/:repo/check-runs/:id/annotations`
is readable anonymously on a public repo, the same fact `ci-runs.py` is built on.
So `k1-ci.sh` emits the whole table as one annotation (`notice` when every row is
PASS, `error` when not) and `k1-result.py` reads it back.

Run #1 is why. It failed, and the only thing any unauthenticated reader could
learn from it was `The process '/usr/bin/sh' failed with exit code 1` — which is
true of every possible cause, including a clean red result the harness reported
correctly. The table existed in an artefact nobody could open. BIT-5 lost three
rounds to exactly this (`ci-runs.py`, *WHY THIS EXISTS*); a K1 row that cannot be
read is not evidence.

### Checking the harness without a device

Three suites run anywhere — no device, no Android SDK:

```sh
bash android/scripts/test-k1-verdict.sh      # classifying `am instrument` output — ~1s
bash android/scripts/test-k1-annotation.sh   # the table's escaping on the way out — ~1s
bash android/scripts/test-k1-driver.sh       # the driver, against a fake device — ~70s
```

`test-k1-annotation.sh` covers the channel above. A workflow command is one line,
so an unescaped newline does not error — it silently truncates the table to its
first row, and the annotation still arrives looking like a result. That is the
same shape of defect as a green row from a run that measured nothing, which is why
it is tested rather than eyeballed. It also pins the substitution *order*: `%`
must be escaped before `%0A` and `%0D` are introduced, or the reader gets the
literal text `%0A` where a line break belonged.

`test-k1-driver.sh` puts a stub `adb` on `PATH` and runs the real driver end to
end inside a throwaway git repo. It models one handset — a lock-screen
credential, a property table, an instrumentation runner — and can make it
misbehave in the specific ways that would otherwise produce a green row from a
run that measured nothing: a mutation command that exits 0 and changes nothing,
a mutation that lands on the wrong credential, a start state that was never
reached, an open phase that exits clean but emits no verdict, an open phase that
reports "skipped" rather than "passed". Each of those must come out `ERROR`, and
the driver must not run the open phase at all once it knows the mutation did not
land.

It also pins the refusals — accounts on a physical device, `--with-device-owner`
off an emulator, API below `minSdk`, more than one device attached — and checks
that the device is left with **no lock screen** after a run.

**What it does not do is test Android.** Every fact about Keystore and
`locksettings` on the far side of `adb` is assumed by the stub, and those
assumptions are the entire thing BIT-18 exists to check. It tests the driver's
reasoning, not the platform's behaviour: given what a device says, the driver
draws the right conclusion and refuses to draw one when it cannot. A device is
still the only thing that can fill in the table below.

That caveat is not theoretical, and run #4 is the proof. The stub modelled
`locksettings verify --old X` as "true when X is the credential", which is the
convenient reading rather than the real one — on a device with no credential,
every X verifies. A driver that could not distinguish "the PIN is 1234" from
"there is no PIN" therefore passed the whole suite. **When this suite is green
and a device disagrees, the stub is the first thing to suspect, not the last.**
Its assumptions are the least-tested part of K1 precisely because they are the
part no test here can reach.

The stub's `verify` is now modelled as run #6 found it on a real device — **exit 0
for everything** — and deliberately kept that way even though the driver no longer
calls it. It is the regression guard: any host-side credential check reintroduced
into the driver would be answered yes by this fake and would produce exactly the
false green that six runs were spent discovering. One scenario asserts the call is
never made at all.

The suite also covers what the rebuilt witness must do: that M2/M3/M4 come back
`NOT REACHABLE` on API 26 and on a device that refuses to report complexity, that
M1/M5 still run there, that an unanswered observation is *not* read as "no lock
screen", and that the witness column carries the observed transition rather than a
word standing in for it.

**This script changes a real lock screen.** It refuses a physical device holding
user accounts unless `--i-know` is passed, refuses `--with-device-owner` on
anything it does not recognise as an emulator, and restores the device to "no lock
screen" on exit. Never point it at a device holding a real wallet.

## Results

**Empty. Nothing here has been run.**

Table format, one block per device —
`M2 | PASS | old-credential-rejected+new-credential-set | TRUSTED_ENVIRONMENT`:

| device | API | M1 | M2 | M3 | M4 | M5 | M6 |
|---|---|---|---|---|---|---|---|
| emulator | 26 | **PASS** | n/r | n/r | n/r | *no verdict* | — |
| emulator | 30 | — | — | — | — | — | — |
| emulator | 33 | — | — | — | — | — | — |
| emulator | 34 | **PASS** | **PASS** | **PASS** | **PASS** | **PASS** | — |
| emulator | 35 | — | — | — | — | — | — |
| physical Samsung | — | — | — | — | — | — | — |
| physical Xiaomi | — | — | — | — | — | — | — |

`—` = not run · `PASS` / `FAIL` = a real observation · `n/r` = not reachable, the
mutation could not be witnessed on this device and the reason is recorded ·
*no verdict* = the run could not produce a rule-2 answer, which is **not** a FAIL

**First rows, run #7 (`8c7c3e4`).** Read them with the caveats below, not off the
grid:

- **API 34 is five for five, with full witnesses on every row.** Every mutation
  was observed to happen — keyguard transition *and* complexity bucket move — and
  the non-auth-bound key opened its blob afterwards in a process that did not
  exist when the key was made. This is the first evidence on this issue that is
  about Keystore at all.
- **`securityLevel=SOFTWARE` on both rows.** Per `seed-storage-security` §4 this
  is observed, not attested, and on an emulator it means what it says: there is
  no TEE behind these keys. Five green emulator rows retire the *documentation*
  half of the doubt. They do not touch the OEM half, and they are not a hardware
  claim.
- **API 26's M5 is not a rule-2 failure**, though run #7 first recorded it as one.
  See [the control key on a software
  keystore](#the-control-key-on-a-software-keystore).
- **M2/M3/M4 on API 26 are `not reachable` as designed** —
  `getPasswordComplexity()` does not exist below API 29, so nothing on that device
  can witness a mutation that leaves it secure on both sides.

**No verdict on BIT-8 rule 2 yet.** One emulator API level is not the matrix, and
the two rows that carry the most weight are the two that need handsets.

### Runs so far

| run | ref | commit | images | outcome |
|---|---|---|---|---|
| [#1](https://github.com/getbittr/bittr-ios-app/actions/runs/34586609943) | `k1-run/pilot` | `393d229` | API 34, `aosp_atd`, `x86_64` | red — cause not readable |
| [#2](https://github.com/getbittr/bittr-ios-app/actions/runs/34588466744) | `k1-run/pilot` | `22cc4da` | API 34, `aosp_atd`, `x86_64` | red — **all five rows `ERROR` at `seal`** |
| [#3](https://github.com/getbittr/bittr-ios-app/actions/runs/34589128911) | `k1-run/pilot` | `81ba801` | API 34, `aosp_atd`, `x86_64` | red — `ERROR` at `seal`, **two causes named** |
| [#4](https://github.com/getbittr/bittr-ios-app/actions/runs/34592863770) | `k1-run/pilot` | `2e3adf6` | API 34, `default`, `x86_64` | red — **first successful seals**; `ERROR` at `mutate` |
| [#5](https://github.com/getbittr/bittr-ios-app/actions/runs/34596169712) | `k1-run/pilot` | `060b71a` | API 34, `default`, `x86_64` | **refused** — the credential witness does not work on this image |
| [#6](https://github.com/getbittr/bittr-ios-app/actions/runs/34596943875) | `k1-run/pilot` | `0ab54f3` | API 34, `default`, `x86_64` | **refused** — and named why: `locksettings verify` always exits 0 |
| [#7](https://github.com/getbittr/bittr-ios-app/actions/runs/34693098167) | `k1-run/26-34` | `8c7c3e4` | API 26 `x86`, API 34 `x86_64`, both `default` | **first rows.** API 34 five for five. API 26: M1 PASS, M2-M4 not reachable, M5 no verdict (the control key, not rule 2) |

None of the six is a row, and none may be read as one.

**Run #1** established one thing and hid the rest. The emulator booted on an
ordinary GitHub-hosted `ubuntu-latest` runner, the probe built, and the matrix ran
for 100 seconds and exited non-zero having written *some* table. Which rows, and
whether they were `FAIL` (a rule-2 contradiction) or `ERROR` (the harness could
not establish anything), was in a log and an artefact that need repository admin.
The only readable detail was `The process '/usr/bin/sh' failed with exit code 1`.
That is what the annotation channel above exists to fix.

**Run #2** is the same code plus that channel, and the table came back:

```
### unknown/Android SDK built for x86_64 (API 34)
Android/sdk_slim_x86_64/emulator64_x86_64:14/UE1A.230829.036.A1/11228894:userdebug/test-keys

| M1 | ERROR | seal | - |   ... and M2, M3, M4, M5 identically
**M1** — seal phase failed — see the run log; no verdict on rule 2
```

Every case failed in **phase 1, the seal**, before any lock-screen mutation was
attempted. That **kills the hypothesis recorded here after run #1** — `aosp_atd`
having no keyguard would have failed the *credential witness*, which the run never
reached. The stripped image may still be a problem later; it is not this problem.
Note `sdk_slim_x86_64` in the fingerprint, which does confirm the image is the ATD
one.

What failed in the seal is not yet known, and the note says why not: *"see the run
log"* — pointing at the one place an unauthenticated reader cannot go. The same
defect as run #1, one level down. `failure_excerpt` in the driver now carries the
decisive `am instrument` lines into the table itself, so the next run names the
cause instead of referring to it.

**Run #3** is that run, and the table carried two *different* causes where runs #1
and #2 had shown one indistinguishable blur. Both were invisible to every channel
except the annotation.

*Cause 1 — M1: `NoSuchMethodError` on `KeyInfo.isUnlockedDeviceRequired()`.*
`K1Probe.describe` read that flag back behind `if (SDK_INT >= P)` — API 28. The
guard is wrong by eight API levels: `setUnlockedDeviceRequired` is on
`KeyGenParameterSpec.Builder` from 28, but the **readback on `KeyInfo` arrived
only in 36.1**. Confirmed against the SDK's own `data/api-versions.xml`, not
against javadoc:

```
$ANDROID_HOME/platforms/android-37.2/data/api-versions.xml
  android/security/keystore/KeyInfo
    since=31    getSecurityLevel()I
    since=36.1  isUnlockedDeviceRequired()Z
```

It compiled because `compileSdk` is 37, and it would have thrown on **every
device in the matrix** — 26, 30, 33, 34, 35, and both handsets. Writing
`SDK_INT >= 36` instead would be wrong the same way: 36.1 is a *minor* release,
`SDK_INT` is 36 on both 36.0 and 36.1, and `Build.VERSION.SDK_INT_FULL` — the only
field that separates them — does not itself exist below 36. So the flag is now
read **reflectively**, and an absent method returns `unknown`, never `false`. A
rule-2 check that could not run must not be able to report itself as a rule-2
check that passed. Rule 2's second half is asserted against the
`KeyGenParameterSpec` as well, which is readable from API 28 on every device, and
each row records which of the two checks was actually available.

This is the issue's own premise turned on the harness: *documentation is not a
device*. The guard was written from the javadoc for a neighbouring class.

*Cause 2 — M2–M5: `locksettings set-pin` exits 0, device still reports
`isDeviceSecure=false`.* Each of those cases needs a PIN before sealing. The
driver set one, `set-pin` reported success, and the probe found the device
insecure — so it sealed against a start state that was never reached, and the
table blamed the seal phase for a setup failure three steps upstream. M1, which
requires *no* credential, passed its start-state assertion, so `KeyguardManager`
itself works on this image.

That is the third time this harness has trusted an `exit 0` (after `adb install`
and `am instrument`), and it was fixed the same way: the credential is checked
immediately after it is set, and the matrix runs a **lock-screen preflight** —
set a PIN, confirm it took, clear it, plus `pm list features` for
`android.software.secure_lock_screen` on API 29+. An image that cannot hold a
lock screen is refused with that named as the reason, instead of producing six
rows about a mutation that never happened.

> **Superseded in two details by run #6.** The check after `set-pin` was
> `locksettings verify`, which run #6 showed answers yes unconditionally; it is
> now `KeyguardManager.isDeviceSecure` read through `K1ObserveTest`. And the
> preflight now runs *after* the install rather than before it, because the
> probe it asks lives in the APK. Neither changes what this run found.

**The image has changed as a result.** K1 no longer runs on `aosp_atd`. ATD
images are stripped by removing what an automated test is assumed not to need,
and K1's entire subject is the lock screen — so it is the one image family whose
removals could silently invalidate every row. The workflow now selects `default`
at all API levels. Whether ATD was the cause of cause 2 is not yet settled; the
preflight is what will say so, and either way a lock-screen measurement should
not be taken on a stripped image.

Both causes were readable only because the table travels as an annotation. Run #3
cost one emulator boot and returned two named defects; runs #1 and #2 cost the
same and returned `failed with exit code 1`.

**Run #4** is the first run where the probe did real work. Both of run #3's causes
are gone: M2–M5 **sealed successfully** — a non-auth-bound key generated, rule 2
checked, the known blob encrypted and round-tripped — and reached the mutation
phase. The `default` image also cleared the lock-screen preflight, so it sets,
verifies and clears a credential where `aosp_atd` did not.

```
### unknown/Android SDK built for x86_64 (API 34)
Android/sdk_phone64_x86_64/emu64x:14/UE1A.230829.036.A1/11228894:userdebug/test-keys

| M1 | ERROR | seal   | - |   requires isDeviceSecure=false, device reports true
| M2 | ERROR | mutate | - |   the OLD credential still verifies after the mutation
| M3 | ERROR | mutate | - |   (same)
| M4 | ERROR | mutate | - |   (same)
| M5 | ERROR | mutate | - |   (same)
```

Still no row, and still no verdict on rule 2 — the mutations are where the
evidence is, and none of them was witnessed.

The two symptoms look opposite (M1: secure when it should not be; M2–M5: the old
credential outliving a change) and have **one root**, in the driver's own
witness:

> `locksettings verify --old X` succeeds for **every** X when no credential is
> set. With nothing to check against, the shell command has nothing to reject.

So `credential_is "$PIN_A"` was two claims at once — *"the credential is 1234"*
and *"there is no credential at all"* — and K1 could not tell which it had
observed. "The OLD credential still verifies" is exactly what a device with **no**
credential reports. Two opposite device states, one observation, and it sits on
the witness that carries M2/M3/M4, where a false *green* would have been the
serious version of this: *"the key survived a PIN change"*, reported from a
device that never had a PIN.

Fixed with a credential no case ever sets. A deliberately wrong value can only
verify on a device that has none, which makes `device_has_credential` a single
unambiguous probe; `credential_is` now requires it before the positive check.
It costs one failed credential attempt when a credential is set and Android
throttles after five, so it is called at decision points rather than in loops.

The fake device in `test-k1-driver.sh` was modelling the convenient semantics
rather than the real ones, which is why 159 device-free checks stayed green
through this. It now models the real behaviour, and a driver that cannot separate
those two states no longer passes the suite.

**Run #5** stopped at the preflight and wrote no table, which is the intended
behaviour and not a regression:

```
k1: on unknown/Android SDK built for x86_64 (API 34), 'locksettings set-pin'
    exits 0 and the credential does not verify afterwards.
k1: refusing to run the matrix — see above.
```

That reason reached a reader with no repository access, from a run that produced
no artefact and no table — the channel work from runs #1–#3 doing its job.

**What this costs, stated plainly.** K1 has now spent five emulator runs and has
zero rows. Each one found a real defect, and four of the five were in the
harness rather than in Android. The honest summary is that the measurement is
harder to instrument correctly than it looks, and that every shortcut taken to
observe it has been wrong in the direction of *looking* like it worked.

**The open question, and why run #4 matters more than run #5.** The refusal says
the PIN "does not verify", which has two very different explanations:

- **(a)** `set-pin` stores nothing — the image cannot hold a lock screen.
- **(b)** `locksettings verify` exits 0 on this image regardless of what is
  stored. Then the credential may be set correctly and the **witness** is what is
  broken.

(b) is the more serious possibility, and run #4 is consistent with it end to end:
if every `verify` answered yes, that alone explains M1 finding the device secure
after a clear *and* M2–M5 reporting the old credential surviving a change. It
would also mean the host-side witness that carries M2/M3/M4 — `locksettings
verify` against the old and new credential, per *How a row avoids being a false
green* above — **cannot be used on this image**, and a witness that always says
yes is precisely how a false green is made.

The driver now prints the raw answers to all three `verify` forms when it
refuses, instead of asserting (a). One run separates them.

**Run #6** ran it, and the answer is (b):

```
locksettings verify --old '1234'    (the credential just set)  -> exit 0
locksettings verify --old '90197'   (deliberately wrong)       -> exit 0
locksettings verify                 (no --old)                 -> exit 0
```

All three. A wrong credential cannot verify on a device that has one, and a bare
`verify` cannot succeed on a device that does — so **`locksettings verify` is not
checking anything on this image**. That is conclusive from run #6 alone, and it
condemns the witness rather than the device: every host-side witness in this
script is built on that one call.

Whether the PIN is nonetheless being stored is answered independently, and
device-side, by run #4: `set-pin` was followed by `isDeviceSecure=true` in the
probe's own process, which is how M2–M5 got far enough to seal. Taken together
the reading is that **`set-pin` works and `verify` lies**.

That also retires the theory that ATD was the culprit. The `default` image is not
noticeably better at this, and the earlier `aosp_atd` rows are equally explained
by the same broken witness. Moving off ATD was still right for K1 — a stripped
image is the wrong host for a lock-screen measurement — but it was not the fix,
and this document should not be read as claiming it was.

### What this cost, and the rebuild that answered it — including M2

Run #6 condemned the witness, not the device. The rebuild moved every question to
the device side of `adb` (`K1ObserveTest`, `K1Credential`), and it recovers
**all six cases on API 29+**, including the one this section previously recorded
as unwitnessable:

| case | mutation | witness after the rebuild |
|---|---|---|
| M1 | none → PIN | `isDeviceSecure` false → true. **Intact, every API.** |
| M2 | PIN → PIN | complexity bucket `MEDIUM` → `HIGH`. **Recovered, API 29+.** |
| M3 | PIN → password | bucket `MEDIUM` → `HIGH`. **Recovered, API 29+.** |
| M4 | PIN → pattern | bucket `MEDIUM` → `LOW`. **Recovered, API 29+.** |
| M5 | PIN → none | `isDeviceSecure` true → false, plus the auth-bound control key. **Intact, every API.** |
| M6 | admin reset | as M5. **Intact, every API.** |

**M2 was written off too early, and it is worth being precise about the mistake.**
Run #6 recorded it as having no possible witness because "the credential type does
not change". True — but the bucket is not the type. `getPasswordComplexity()`
buckets by length as well, so a PIN → *longer* PIN is a real PIN change that a
device-side signal can see. That is why `PIN_B` is now 8 digits rather than 4: the
old `1234` → `5678` was a genuine mutation that no instrument K1 has could
distinguish from doing nothing.

So the disposition changes. M2 is **not** `not reachable` in general — it is
reachable wherever complexity is readable, which is API 29 and up, which is four
of the five emulator rows and both physical handsets. It falls back to `NOT
REACHABLE` only on API 26 and 28, alongside M3 and M4, for the same reason and
with the same recorded cause. **No question for Ruben is outstanding here**; the
earlier one is withdrawn.

**`not reachable` is a finding, not a gap.** BIT-18 says "where reachable" of
mutation 5, and M6 is expected to be unreachable on physical devices: a device
owner cannot be removed without a factory reset, so the script refuses to set one
on a handset. The same treatment now covers M2/M3/M4 below API 29. Recording that
is the honest answer to the question the issue asked.

### The control key on a software keystore

Run #7's API 26 row came back `**FAIL**` on M5, and **that label was wrong** — the
harness's own bug, fixed in the same heartbeat that found it.

What actually failed was the *positive control*, not the claim. M5 and M6 create
an auth-bound key that is **supposed to die** when the credential is destroyed; if
it survives, the non-auth-bound key's survival proves nothing. On this image it
survived — `KeyInfo` reports `SOFTWARE`, so there is no hardware keystore to
enforce the invalidation Android documents. `K1OpenTest` therefore stopped
*before* decrypting anything.

So the run never tested rule 2 on that row. But `**FAIL**` is defined by this
document as *"this device contradicts BIT-8 rule 2"*, and the result cell is the
part that survives into a security statement. Writing the harder claim from the
weaker evidence is the same mistake as a false green, pointed the other way — and
this one was pointed at a design change the evidence did not call for.

Every witness assertion in `K1OpenTest` is now tagged `[K1_WITNESS_FAILURE]`, and
the driver scores a tagged failure `ERROR` ("no verdict") while leaving an
untagged one — the decrypt itself — as the real `**FAIL**`. Both directions are
covered in `test-k1-driver.sh`.

Worth stating plainly, because it is a limit of the control rather than a bug in
it: the control is checked by **existence** (`containsAlias`), never by
decryption, because decrypting an auth-bound key needs a real user authentication
and `UserNotAuthenticatedException` is not distinguishable from invalidation. A
device that leaves a dead alias in place would look identical to this. Either way
K1 declines to report M5/M6 there.

### Key security level, recorded not asserted

Each row carries what `KeyInfo` reports. Per `seed-storage-security` §4 this is
**observed, not attested** — `KeyInfo.getSecurityLevel()` is a local self-report
from the system we would be verifying, not a cryptographic proof. API 26–27 can
fall back to a software keystore with no API to require hardware, so **we do not
claim hardware backing at 26–27**, whatever the column says.

## Verdict on `wallet-core-spec`

**Not yet issued.** BIT-6's one-line verdict is due when the table has rows, and
it is deliberately not written in advance.

## What is blocking the run

The container this harness was built in has **no emulator, no `/dev/kvm`, and no
attached device**, so no row can be produced from it directly. That was the whole
blocker. It is now the blocker on two of the seven rows.

- **The five emulator rows are no longer blocked on hardware.** They run in CI on
  the KVM host the Maestro job already uses — see *Running the emulator rows in
  CI* above. Run #1 proved the mechanism: a GitHub-hosted `ubuntu-latest` runner
  has `/dev/kvm`, passed the preflight, built the probe and booted an emulator
  without `ANDROID_EMULATOR_RUNNER` being set at all. What the rows are blocked on
  now is the matrix producing `PASS` against that image, and run #1 says it did
  not. No new machine, no purchase, no new access.
- **The Samsung and Xiaomi rows cannot be automated into CI at all.** They need
  physical handsets someone owns, and they are the rows that actually matter:
  emulators run AOSP, and K1 exists precisely because *OEM builds diverge*. Five
  green emulator rows would confirm the AOSP javadoc that rule 2 already rests
  on — which is not the same as confirming rule 2.

The honest reading of that split: CI can retire the *documentation* half of the
doubt, cheaply and repeatably, and it cannot touch the *OEM* half. A physical
Samsung and a physical Xiaomi, run once by hand with `k1-lockscreen-matrix.sh`,
remain the only way to close this issue as specified.

## If a row comes back red

Do **not** silently switch designs. Comment on BIT-18 **and** on BIT-8; the
dual-wrap fallback (BIT-8 → `decision` §6) gets priced as its own issue for
Ruben.

There is also a support consequence, tracked separately: BIT-28's playbook covers
*"the app is asking for my 12 words and I didn't do anything"* (FM-3), and a red
row moves that from a rare, explainable event to something support meets weekly.
The playbook owner asked to be told directly, separately from the BIT-8 comment.

The rule that does not change whatever the table says: **Keystore holds only a
cache; the mnemonic is the root of recovery.**
