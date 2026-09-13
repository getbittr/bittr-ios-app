# K2, K7, K8 — what runs, what is closed unrun, and what each unrun row needs

**BIT-123.** `wallet-core-spec` §6 names three claims that cannot be written
until a node actually starts. This document is the second branch of that issue's
definition of done:

> Each of K2, K7 and K8 either passing in the `wallet-instrumented` job, or
> carrying a written statement of what hardware it needs and why CI cannot supply
> it — the BIT-18 precedent, where the emulator matrix closed and the
> Samsung/Xiaomi rows were closed *unrun* with the risk named and accepted rather
> than quietly dropped.

The precedent matters more than the format. BIT-18 closed K1 at five rows with
two of them unrun, and the reason that was honest rather than convenient is that
the unrun rows say what they would have cost and what would have to exist to run
them. A row deleted from a table reads, a year later, exactly like a row that
passed.

## Summary

| Leg | State | Carried on | Where |
|---|---|---|---|
| K2 — the seed is usable with the device locked | **written, not yet run** | — | `SeedReadableWhileLockedTest`, `wallet-instrumented` |
| K2 — an FCM data message wakes the process | closed **unrun** | **BIT-133** | §1 below |
| K2 — *force-stop* then wake | **withdrawn as specified** | **BIT-133** | §2 below |
| K7 — interrupted payment resolves to one outcome | closed **unrun** | **BIT-132** | §3 below |
| K8 — Doze and App Standby machinery | closed **unrun** | **BIT-132** | §4 below |
| K8 — channel-monitor freshness after wake | closed **unrun** | **BIT-132** | §4 below |
| `data_loss_protect` on channel re-establish | **verified, as far as a binary can be** | — | §5 below |

## The precondition that is upstream of three of these rows

**The `wallet-instrumented` job builds a wallet with no node in it.** This is not
an oversight and it is the single biggest reason K7 and K8 cannot run today,
ahead of any question about hardware.

`LdkEnvironmentConfig.fromBuildConfig()` returns null unless all six
`BuildConfig` fields are supplied at build time, and their committed defaults are
the empty string — which is what keeps BIT-123's own note (*never mainnet keys,
never production node access, never real funds*) true of a clone rather than true
of a convention. A build with no environment composes `SeedWalletService`, which
is the app as it was before BIT-126: no `WalletNodeHost`, no
`WalletForegroundService`, no `NodeLifecycle`, no ldk-node.

So "give the runner a phone" does not make K7 runnable. The job would also have
to build a **configured regtest** APK, which means the infrastructure in §3 has
to exist before the build is even meaningful. Any plan that starts with hardware
has the order wrong. **BIT-132** carries it.

`SeedReadableWhileLockedTest` is unaffected by this, and that is why it is the
leg that could be delivered: the Keystore is a device service and the seed vault
is reachable from `:core:wallet-ldk` without any node at all.

**Its status is *written*, not *green*, and the distinction is this repository's
own.** It compiles and it is in `REQUIRED` by name, and it has not executed on
any device — running it needs the `wallet-instrumented` job. Commit `dd50f457`
on this branch exists because that difference was elided once before, and
`KeystoreKeyInfoTest` is what it cost: that class carried an inverted assertion
for its entire unrun life, demanding the plaintext BE present in the wrapped
blob. This row moves to **passing** when a run shows it passing, and not
before.

---

## 1. K2 — the FCM leg

**Claim.** A data message delivered while the device is locked and the process is
not running reaches `Node.start()`.

**Why CI cannot supply it.** Three independent blockers, and the first is not
about CI at all:

1. **There is no receiver.** The app has no `FirebaseMessagingService` and no
   `firebase-messaging` dependency. `android/scripts/verify-fcm-service-account.sh`
   is a *backend* credential check; nothing on the client listens. A test for a
   wake path that does not exist would be a test of the test.
2. **The image cannot deliver one.** `wallet-instrumented` runs `aosp_atd`, and
   that choice is load-bearing for a different claim: the suite needs
   `com.android.localtransport`, which is an AOSP component absent from
   Play-flavoured images. FCM needs exactly the Google Play services those images
   have and this one does not. The two requirements are mutually exclusive on one
   AVD, so this leg needs a **second emulator job on a `google_apis` image**, not
   a change to this one.
3. **Sending one needs a project.** A data message has to come from somewhere,
   and the only FCM project this repository knows about is production. BIT-123
   forbids production node access; the same reasoning covers pushing through the
   production sender.

**What it would need.** A `FirebaseMessagingService` in the app (a feature, not a
test); a `google_apis` AVD in a job of its own; and a non-production FCM project
whose service-account key is a repository secret. Roughly a day's work of which
none is the test.

**Risk accepted by not running it.** The wake path does not exist, so there is no
behaviour to regress. This row becomes live the moment background wake is built,
and should be a condition of that work rather than a follow-up to it — which is
why **BIT-133** owns the receiver *and* this row, rather than the row being filed
against a feature somebody else may or may not build.

## 2. K2 — the force-stop leg, withdrawn as specified

**Claim as written.** *Force-stop the app, lock the device, deliver an FCM data
message, assert node start reaches `Node.start()`.*

**This does not describe a path that exists.** An app that the user or
`am force-stop` has stopped is in Android's **stopped state**, and the framework
does not deliver broadcasts — FCM's included — to a stopped package until
something launches it again. That has been the platform's behaviour since Android
3.1. So the specified test asserts that something happens which Android
guarantees will not, and it could only ever go red — or, worse, go green on an
image that got the stopped-state rule wrong.

**What the claim underneath it is.** The interesting property is *process death*,
which is a different event: the system reclaiming the process under memory
pressure leaves the package in its normal state and a later FCM message does
restart it. `am kill` reproduces that; `am force-stop` does not. Any future
version of this row should say **process death**, and should use `am kill`.

**This is a spec correction, not a hardware limit**, and it is recorded here
rather than fixed silently because `wallet-core-spec` §6 is the document other
people read. **BIT-133** owns the correction.

## 3. K7 — an interrupted payment

**Claim.** Killing the process mid-`bolt11Payment().send` leaves no double-spend
and no lost claim: on restart, LDK's payment state resolves to exactly **one**
terminal outcome.

**Carried on BIT-132**, together with the configured build above and K8.

**Why CI cannot supply it.** This needs a funded Lightning channel, which needs a
private network, which is four services rather than one:

- **bitcoind in regtest** — to mine, and to fund the channel.
- **An Esplora HTTP server** — ldk-node's chain source on every network except
  mainnet.
- **An Electrum TCP server** — BDK's, and a *separate* endpoint by design;
  `LdkEnvironment.electrumUrl` is its own field precisely because iOS only points
  both at one URL on mainnet.
- **A peer node** (LDK, CLN or LND) willing to open a channel to us and to hold
  the other end of an in-flight HTLC.

None of that is impossible on a runner — the emulator reaches host services on
`10.0.2.2`, so they can be containers beside the AVD — but it is a job that does
not exist, on top of the configured-build precondition above, inside a 45-minute
timeout that a single self-hosted runner already serialises against two other
emulator jobs.

**And the infrastructure is not the hard part.** "Kill the process
mid-`send`" needs a *deterministic* interception point. Without one the kill
window is milliseconds wide, and a test that lands inside it sometimes is a test
that reports a fund-safety property as flaky — the worst possible reading, since
the expected result and a missed window look identical. Making this honest needs
either a seam in the send path that the test can block on, or N repetitions with
a stated confidence, and that is a design decision about production code rather
than a testing one.

**Risk accepted by not running it.** Real, and the largest of the three. This is
the claim BIT-6's notes are about — *"no path where a user can lose funds"* — and
nothing else covers it: `WalletNodeHostTest` proves the ordering rules on the JVM
against a fake node, which is a proof about our code and not about LDK's
durability across a `SIGKILL`. What is on our side of the line is that
`LdkStateStore` fsyncs (`FsyncDurabilityTest`) and that the pump does not
acknowledge an event whose handler threw; what is on LDK's side is untested here.

## 4. K8 — Doze and App Standby

**Claim.** Node lifecycle is correct across Doze and App Standby: soak with
`adb shell dumpsys deviceidle force-idle`, assert channel-monitor freshness after
wake.

**Two halves, and they fail for different reasons.**

The **Doze machinery** half is emulator-capable today. `dumpsys deviceidle
force-idle` works on an AVD once `dumpsys battery unplug` has been issued, and
`dumpsys deviceidle unforce` brings it back. What is missing is not the device:
it is that in an unconfigured build there is no `WalletForegroundService` and no
runner to observe surviving the idle window, so the test would assert against
`SeedWalletService` and prove nothing. See the precondition above.

The **channel-monitor freshness** half needs §3's infrastructure in full, plus
wall-clock: App Standby buckets move on the order of hours and the useful version
of this test is a soak, not a step. A 45-minute job cannot hold it.

**What it would need.** The configured regtest build, §3's four services, and a
job with a soak budget — realistically a nightly rather than a per-push job.
**Carried on BIT-132.**

**Risk accepted by not running it.** Moderate and asymmetric. Doze suspends
network and defers alarms; for a Lightning node the cost of being wrong is a
channel force-closed by a counterparty that saw no response, which loses fees and
liquidity rather than principal. The foreground service is what is supposed to
prevent it, and `WalletForegroundServiceTest` covers its own contract on the JVM
— that the process is promoted before a start begins and demoted only on a
definite failure — without proving the platform honours it.

## 5. `data_loss_protect` on channel re-establish — verified

`wallet-security-properties.md` §5's last open item, and the one row here that
closed rather than being deferred. BIT-123 required it to be **verified against
ldk-node 0.7.0 rather than asserted from memory**, and it is:
`android/scripts/check-ldk-data-loss-protect.py` reads the AAR the build
resolved, asserts five markers in all three shipped ABIs, and runs in the `build`
job on every push. What it found, and what it does not prove, is written up in
`wallet-security-properties.md` §5 and in the script's own header.

The short version: the stale-state branch is compiled into the binary we ship,
LDK advertises `option_data_loss_protect` as a **compulsory** init feature bit
rather than an optional one, and on a re-establish that proves we are behind, LDK
refuses to broadcast. What a string in a binary cannot show is that the branch
executes correctly against a real peer — which is K7's infrastructure again.

---

## Reading this document in a year

Every row above is either passing, or unrun with a named cost. None of them is
missing. If a future reader finds a claim from `wallet-core-spec` §6 that is in
neither state, that is the failure this document exists to make visible — the
same failure as a test deleted rather than marked, and the same failure as the
two runs `BdkAccountXpubParityTest` spent executing while absent from
`check-wallet-instrumented-results.py`'s `REQUIRED` set.
