# K1 — does a non-auth-bound Keystore key survive a lock-screen change?

**BIT-18.** Split out of BIT-6 by the BIT-8 decision (option (a), Ruben, 2026-09-10).
This test does not gate the storage design — it *verifies* one of its rules.

## Status

**The harness is complete and the result table is empty.** No row below has been
run on a device. Nothing in this file may be quoted as evidence for rule 2 yet.

That is a hardware gap, not an unfinished harness — see [What is blocking the
run](#what-is-blocking-the-run).

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

| case | BIT-18 mutation | secure before → after | auth-bound control |
|---|---|---|---|
| M1 | 1. set a lock screen where none existed | no → yes | — |
| M2 | 2. change PIN → PIN | yes → yes | — |
| M3 | 3. change PIN → password | yes → yes | — |
| M4 | 3. change PIN → pattern | yes → yes | — |
| M5 | 4. remove the lock screen entirely | yes → no | yes |
| M6 | 5. forced reset of the secure lock screen | yes → no | yes |

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
3. **The device-side witness passed.** `K1OpenTest` asserts the post-mutation
   `KeyguardManager` state *before* it decrypts, so a run that mutated nothing
   fails its start-state assertion instead of reporting survival.
4. **The host-side witness passed.** `locksettings verify` against the **old**
   credential must succeed before the mutation and fail after it.

Item 4 is what carries M2, M3 and M4. Those three are secure on both sides of the
mutation, so `KeyguardManager` cannot tell that anything happened and item 3
degrades to "the driver did not do literally nothing". The asymmetry is real and
is recorded here rather than hidden behind an assertion that would look stronger
than it is.

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

**This script changes a real lock screen.** It refuses a physical device holding
user accounts unless `--i-know` is passed, refuses `--with-device-owner` on
anything it does not recognise as an emulator, and restores the device to "no lock
screen" on exit. Never point it at a device holding a real wallet.

## Results

**Empty. Nothing here has been run.**

Table format, one block per device — `M2 | PASS | old-credential-rejected | TRUSTED_ENVIRONMENT`:

| device | API | M1 | M2 | M3 | M4 | M5 | M6 |
|---|---|---|---|---|---|---|---|
| emulator | 26 | — | — | — | — | — | — |
| emulator | 30 | — | — | — | — | — | — |
| emulator | 33 | — | — | — | — | — | — |
| emulator | 34 | — | — | — | — | — | — |
| emulator | 35 | — | — | — | — | — | — |
| physical Samsung | — | — | — | — | — | — | — |
| physical Xiaomi | — | — | — | — | — | — | — |

`—` = not run · `PASS` / `FAIL` = a real observation · `not reachable` = the
mutation could not be driven on this device, with the reason recorded

**`not reachable` is a finding, not a gap.** BIT-18 says "where reachable" of
mutation 5, and M6 is expected to be unreachable on physical devices: a device
owner cannot be removed without a factory reset, so the script refuses to set one
on a handset. Recording that is the honest answer to the question the issue asked.

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

The CI container this harness was built in has **no emulator, no `/dev/kvm`, and
no attached device**. `/opt/android-sdk` carries `platform-tools` and platforms
but no `emulator` package, so not one of the seven rows can be produced here.

Two things are needed, and they are different asks:

- **The five emulator rows** need a host with KVM. The project already documents
  one — `self-hosted-runner.md`, written for the Maestro job — and the emulator
  rows could run there under the same label switch.
- **The Samsung and Xiaomi rows cannot be automated into CI at all.** They need
  physical handsets someone owns, and they are the rows that actually matter:
  emulators run AOSP, and K1 exists precisely because *OEM builds diverge*. Five
  green emulator rows would confirm the AOSP javadoc that rule 2 already rests
  on — which is not the same as confirming rule 2.

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
