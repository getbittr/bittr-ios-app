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
| K7 — interrupted payment resolves to one outcome | **written, not yet run** | **BIT-132** | §3 below |
| K8 — Doze and App Standby machinery | **unrun; its precondition is now solved** | **BIT-132** | §4 below |
| K8 — channel-monitor freshness after wake | **unrun; needs the soak job** | **BIT-132** | §4 below |
| The configured regtest build and the private network | **built, and one green leg deep** | — | §0 below |
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
has the order wrong. **BIT-132** carries it, and **§0 below is what it has
built** — the paragraph above is now a description of `wallet-instrumented`
rather than of every job in the repository.

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

**And the first thing keeping *written* from becoming *green* was the image, not
the claim.** The job ran `aosp_atd`. ATD images are stripped by removing what an
automated test is assumed not to need, and the keyguard is one of those things —
so `locksettings set-pin` exits 0 and the device still reports
`isDeviceSecure=false`. That is verbatim the precondition this test asserts in
`@Before`, which means all three of its methods would have failed there, before
reaching the Keystore, on a device that simply cannot hold the state the test
measures.

This was **not a new discovery, and that is the uncomfortable part**: K1 lost
runs #1–#3 to it on this same runner, at this same API level, and both
`k1-keystore-lockscreen.yml`'s image step and `k1-lockscreen-matrix.sh`'s
`lockscreen_preflight` were written to say so. The test was authored against a
job whose image had already been ruled out for exactly this question, by this
repository, in writing.

The job now runs **`default`** — still AOSP, so the local backup transport the
other half of the suite depends on is still present, and `default` is the full
image ATD is a stripped subset of, so moving up cannot remove an AOSP component.
K1 runs #7 and #8 went five-for-five on API 34 `default` x86_64, and the
`instrumented` job in the same workflow already boots it. The AVD cache key
changed with the image, because otherwise the old snapshot is restored under the
new config and the fix is a no-op that reads as a fix.

`ci-wallet-instrumented.sh` now asserts `android.software.secure_lock_screen`
before either Gradle run, so a future image swap fails in one legible line rather
than as three Keystore tests failing for a reason that is not about the Keystore.

---

## 0. The configured build and the private network — built

**BIT-132's first two scope items, and they are done rather than described.**

- **The network.** `android/regtest/` — bitcoind in regtest, Blockstream's
  electrs serving *both* chain endpoints (Esplora over HTTP for ldk-node,
  Electrum over TCP for BDK), and LND as the counterparty. `up.sh` brings it up,
  mines to a spendable height and writes down what came up; `down.sh` removes the
  chain as well as the containers, because a chain inherited by the next run fails
  late and quietly. `android/regtest/README.md` is the document to read.
- **The configured APK.** `android/scripts/regtest-ldk-env.py` turns the
  network's published ports into the four required `BITTR_LDK_*` values, from the
  device's point of view — 10.0.2.2 is the emulator's alias for the host that
  published them. Verified locally rather than asserted: with those `-P`
  arguments, `:app:generateDebugBuildConfig` writes real values into
  `LDK_CHAIN_SOURCE_URL`, `LDK_ELECTRUM_URL`, `LDK_LIGHTNING_NODE_ID` and
  `LDK_LIGHTNING_NODE_ADDRESS`, and `missingFields()` is empty. **The six
  committed defaults are untouched and must stay that way.**
- **The job.** `.github/workflows/wallet-regtest-nightly.yml`. Nightly and not
  per-push: K8's useful form is a soak, a cold run builds electrs from source, and
  `wallet-instrumented` already sits inside a 45-minute timeout that one
  self-hosted runner serialises against two other emulator jobs.
- **One green leg, and it is the vacuity guard for the rest.**
  `RegtestEnvironmentTest` asserts on the device that this APK is on the
  node-backed side of the `fromBuildConfig()` branch, that every endpoint names
  the emulator's own host, and that all four of them answer. Six methods, all in
  `check-wallet-regtest-results.py`'s `REQUIRED` set by name.
- **K7 now runs after it in the same job** — four host-driven phases, written and
  not yet executed. §3 says what a first run is the first thing to test.

**What it cost the repository, stated because a future reader will hit it:**

- **Docker is a new host requirement.** `android/docs/self-hosted-runner.md` did
  not ask for it before BIT-132.
- **A source set that nothing normally compiles.**
  `android/app/src/androidTestRegtest/` is added to `androidTest` only when a
  `BITTR_LDK_*` value was supplied. That is a build-time switch rather than a
  JUnit `@Assume`, because `check-wallet-instrumented-results.py` treats **any**
  `<skipped/>` as a failed run — so an assumption would have turned that green job
  red for behaving correctly. The `build` job compiles the directory with
  throwaway `.invalid` values on every push, since a nightly-only suite otherwise
  rots into a suite that is broken at night.

**None of this is a K7 or a K8 result.** It is the precondition those two were
blocked on, and it is now measured rather than argued. §3 and §4 say what each
still needs.

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
2. **The image cannot deliver one.** `wallet-instrumented` runs `default` — an
   AOSP image, and that is load-bearing for a different claim: the suite needs
   `com.android.localtransport`, which is an AOSP component absent from
   Play-flavoured images. FCM needs exactly the Google Play services those images
   have and an AOSP one does not. The two requirements are mutually exclusive on
   one AVD, so this leg needs a **second emulator job on a `google_apis` image**,
   not a change to this one.

   (This job ran `aosp_atd` until BIT-123 moved it to `default` so the lock
   screen would exist — see *The precondition that is upstream of three of these
   rows*, above. That swap does not touch this argument: both are AOSP images,
   and neither carries Play services.)
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

### State: written, not green, and the distinction is this document's own

`K7InterruptedPaymentTest` (four phases) and
`android/scripts/k7-interrupted-payment.sh` (the host between them) exist and
compile. **Neither has executed against a device.** This row moves to *passing*
when a nightly run shows it passing, and not before — the same rule
`SeedReadableWhileLockedTest` is held to above, for the same reason: commit
`dd50f457` exists because that difference was elided once, and
`KeystoreKeyInfoTest` is what it cost, carrying an inverted assertion for its
entire unrun life.

What is checked without a device, and it is more than nothing:

- It compiles, on every push. The `build` job's *Compile the regtest
  instrumented sources* step builds this source set with throwaway `.invalid`
  values, so a missing import in K7 is a red on the push that wrote it rather
  than at 03:20 UTC.
- The joins between the host script and the device phases are pinned by
  `android/scripts/test_k7_host_phase.sh`, also in the `build` job: the installed
  package name, the four method names in both directions, `@HostDriven` on every
  phase *and* the filter on the run that has to apply it, the hand-off path, the
  three instrumentation arguments, and every phase's presence in
  `check-wallet-regtest-results.py`'s `REQUIRED` set. Each of those checks was
  driven to red and back.
- All four phases are in `REQUIRED` by name, so a phase that silently stops
  running fails the nightly job rather than leaving it green.

What is **not** checked until a device runs it — and this is the honest list, in
the order a first run is likely to hit it:

1. That the address `NodeOnchainPort` reveals is one ldk-node will actually spend
   from at `openChannel`. Phase 2 is the first thing that finds out.
2. That `sendBolt11` returns a value equal to the payment hash the host chose the
   preimage for. Phase 3 asserts it rather than assuming it, because phase 4
   looks the payment up *by* that value; ldk-node's BOLT11 `PaymentId` is
   documented as the hash and this is where the documentation meets the binary.
3. That an in-flight HTLC actually reaches LND and sticks — route-finding over a
   one-hop channel, which should be the easy case and is the one thing between a
   wide window and a narrow one.
4. That the instrumented process really is torn down when phase 3 returns. The
   script does not rely on it (`am kill` follows, and the run refuses to start
   phase 4 while any process of the package is alive), but the pid phase 4
   asserts against is read *during* the window and a device could still surprise
   it.

### How it is driven, and why not from the test

Four `am instrument` runs against one emulator boot, sequenced from the host,
with wallet state surviving between them under `no_backup`
(`leaveApksInstalledAfterRun=true` stops AGP uninstalling it; phase 2 onward
*assert* they found the wallet phase 1 created rather than quietly making a
second one):

| Phase | The device does | The host then does |
|---|---|---|
| 1 | starts the node, reveals ldk-node's on-chain address | sends 0.02 BTC to it, mines 3 |
| 2 | waits for the confirmed coins, opens a 0.01 BTC channel to LND | mines until LND reports the channel active |
| 3 | waits for the channel to be usable, pays a **hold** invoice, blocks on the hand-off | polls `lookupinvoice` to `ACCEPTED`, records the pid, writes the hand-off |
| — | *(phase 3 returns; the framework tears the process down)* | `am kill`, then waits until no process of the package exists |
| — | | `settleinvoice` — while nothing is listening |
| 4 | restarts, asserts one terminal outcome and that it sticks | reads the verdict |

The phases are `@HostDriven`, and `ci-wallet-regtest.sh`'s undirected suite run
passes `notAnnotation=com.bittr.android.HostDriven` so they are **absent** from
it rather than skipped — `check-wallet-regtest-results.py` treats a `<skipped/>`
as a failed run, correctly. Each phase's JUnit XML is preserved under
`androidTest-results/k7/phaseN` because every Gradle run overwrites
`.../connected`, and the gate is handed all five directories explicitly.

**The host settles rather than cancels, and that is the asymmetric direction.**
The money has left and the counterparty holds the preimage, so the wallet must
come back knowing the payment *succeeded*. A wallet reporting `Failed` there has
lost the claim: it shows the user a failed payment they were charged for, and a
retry pays twice. Cancelling tests the cheaper direction — funds returned,
payment failed — and is the obvious second run for this suite once the first is
green. It is not a substitute.

### The kill window — decided, and the decision is not the one this section expected

The paragraph below this one says the infrastructure is not the hard part, and
that is still true. What has changed is the answer.

> "Kill the process mid-`send`" needs a *deterministic* interception point […]
> either a seam in the send path that the test can block on, or N repetitions with
> a stated confidence.

**It is neither. The interception point goes in the counterparty.** LND's
`addholdinvoice` withholds the preimage, so the HTLC arrives at the peer, is
accepted, and *stays* accepted until the test settles or cancels it. The window is
not milliseconds wide — it is as wide as the test wants; it is observable from the
host, because `lncli lookupinvoice` reports `state: ACCEPTED` exactly when the
HTLC is in flight; and reaching it needs **no test-only code anywhere near the
money**. That is why the network in §0 runs LND and not Core Lightning or Eclair:
`invoicesrpc` is compiled into every released LND, where the other two need a
plugin.

**Why not the seam.** A latch inside `LdkNodeSurface.sendBolt11` is a branch in
the fund-handling path that exists only to be taken by a test. It either ships in
the release APK — a way to wedge a real payment — or it does not, in which case
the thing under test is not the thing that ships. It would also prove *less*: a
seam can only pause where **we** are, before the FFI call or after it returns, and
never inside `ChannelManager::send_payment`. The interesting window is the one
where the HTLC is on the wire and our record of it may or may not be durable, and
a hold invoice puts us squarely in it.

**What the hold invoice does not cover, said now rather than discovered later.**
There is a second window — inside `send`, between `ChannelManager` committing the
outbound payment and that state being persisted — and it is genuinely not
reachable this way, because for part of it no HTLC exists for any counterparty to
hold. Two things about it. It is a **smaller** claim than the one K7 states: with
nothing on the wire there is nothing to double-spend and nothing to lose, so the
worst it could expose is a forgotten payment that never went out, which costs a
retry rather than money. And if it is ever worth measuring, the honest instrument
is N repetitions with a stated confidence — not a seam, and **not silence**,
because one run that happened to miss the window is the false green this whole
document exists to refuse. `K7InterruptedPaymentTest` will say which of the two
windows each run entered, in its evidence line; a run reporting the narrow one is
not a K7 result.

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

**All four now exist** (`android/regtest/docker-compose.yml`), in a job with a
90-minute budget of its own (`wallet-regtest-nightly.yml`). Four services, three
containers: Esplora and Electrum are two listeners on one `electrs`, because
Blockstream's electrs *is* the implementation of both.

**And the infrastructure is not the hard part.** "Kill the process
mid-`send`" needs a *deterministic* interception point. Without one the kill
window is milliseconds wide, and a test that lands inside it sometimes is a test
that reports a fund-safety property as flaky — the worst possible reading, since
the expected result and a missed window look identical. That is decided above: the
hold invoice, in the counterparty.

### The four things K7 needed — all four now built

Kept below as the record of what each one cost to decide, because the decisions
are the part a future reader will want and the code is the part they can grep
for. **Nothing in this list is open.** What remains is a run, and the section
above says exactly which of these claims a run is the first to test.

1. ~~**A host phase.**~~ **Built** — `android/scripts/k7-interrupted-payment.sh`.
   The test cannot observe its own restart. `am kill` takes the
   instrumentation process with it, which is the lesson `BackupExclusionTest`
   learned from `bmgr restore` — it used to delete what it planted, restore, and
   assert nothing came back, and that assertion died exactly when there was a set
   worth checking. So K7 is host-driven: an instrumented run that pays the hold
   invoice; `adb shell am kill` once `lncli lookupinvoice` says `ACCEPTED`; and a
   second instrumented run that asserts the restarted node resolves the payment
   to exactly one terminal outcome.

   **One thing the shape above gets wrong, corrected in the building of it.**
   "Kill it once `lookupinvoice` says `ACCEPTED`" reads as though the host waits
   for a state and then interrupts a running test. It cannot: a kill that lands
   inside the instrumentation fails the phase, and a phase that returns
   immediately after `send` is torn down *somewhere*, most likely inside the
   narrow window where K7's claim is not under test. So the wait is on the
   **device** side — phase 3 blocks on a hand-off the host writes only on
   `ACCEPTED` — and the process death is the framework's teardown of the
   returning phase, with `am kill` behind it and a pid assertion in phase 4 to
   make "it died" a checked fact rather than an assumption about instrumentation
   teardown.

   **It is more than three steps, because the device has to be funded first and
   the host cannot do that behind its back.** `android/regtest/up.sh` funds
   *LND* — it says why, and it is not the wallet under test. The wallet needs a
   confirmed UTXO of its own before `openChannel` has anything to spend, and the
   coins have to arrive at an address **ldk-node chose**, which means:

   - **The host cannot derive it.** The obvious shortcut is to pick the mnemonic
     on the host and derive the first receive address there, funding it before
     the device ever boots. That needs ldk-node 0.7.0's exact derivation, and it
     is not recoverable from the artefact: `strings` over `libldk_node.so` in all
     three ABIs finds the descriptor and BIP-32 machinery and **no derivation-path
     literal** to pin `84'/…` to. Guessing it would produce a test that funds an
     address nothing is watching and then fails at `openChannel` with an
     insufficient-funds error that says nothing about derivation.
   - **So the device is asked, and that is a phase.** Run 1: unlock, which starts
     the node, and print the on-chain address as an evidence line. Host: send,
     mine to confirm, wait for the device's node to see it. Run 2: open the
     channel to LND and wait for it to go active. Run 3 is the payment, run 4 the
     assertion. Four `am instrument` invocations against one emulator boot —
     which is the cheap part; wallet state lives under `no_backup` and survives
     between them, since neither `am instrument` nor `adb install -r` clears app
     data.

   **The gap that stopped run 1 — closed.** It was recorded here last pass as
   open: `WalletGraph` handed out a `WalletService` and a `LightningNodePort`,
   and **neither could produce a receive address.** `LightningNodePort` is
   channels, peers and payments by design; the on-chain address comes from
   ldk-node's `onchainPayment()`, and — per BIT-126's finding that the on-chain
   balance is ldk-node's rather than BDK's — it must be *that* wallet's address
   and not `BdkOnchainWalletHolder`'s, or the funds land where the channel
   opener is not looking.

   `NodeOnchainPort` is that seam, with `OnchainAddressView` as its one view
   type, `LdkOnchainSurface` as the adapter, and `WalletGraph.nodeOnchain()` as
   the door — a port beside `LightningNodePort` rather than a widening of
   `ManagedNode`, which is the shape this paragraph asked for. `WalletModule`
   binds it out of the same `WalletComposition`, so it is over the same
   `NodeLifecycle` the wallet starts; a second one would hand out addresses
   from a node nothing opens a channel from, and that failure arrives as an
   insufficient-funds error one phase later rather than where it was made.

   **It has no send.** ldk-node's on-chain surface also offers `sendToAddress`
   and `sendAllToAddress`; neither is on the port. The host holds bitcoind and
   does all the sending, nothing in the app sends on-chain today, and an unused
   fund-moving method is a liability with no caller to justify it.

   **Its forwarding half is proved on the JVM, which `LightningNodePort`'s is
   not**, and the difference is the seam's position rather than luck.
   `LdkNodeSurface` takes `() -> Node?` and `Node` is a concrete UniFFI class,
   so no test can build one. `NodeInterface.onchainPayment()` returns the
   concrete `OnchainPayment` too — but that class implements
   `OnchainPaymentInterface`, a plain Kotlin interface, so `LdkOnchainSurface`
   takes `() -> OnchainPaymentInterface?` and a fake can stand in.
   `NodeOnchainPortTest` is six methods over both halves: the address is
   forwarded verbatim, `newAddress()` is called exactly once per request (each
   call persists an advanced index), each request reveals the next address, the
   node is re-read rather than captured, and all three flavours of absence — no
   lifecycle, an unconfigured build, a lifecycle over a `ManagedNode` that is
   not ldk-node's — throw rather than inventing a value. Driven to red with a
   constant-returning body: six of six failed.

   What still needs the device is the layer under the seam — that the address
   is one ldk-node will actually spend from at `openChannel`. That is run 2's,
   and it is the first thing the host phase will find out.
2. **`am kill`, never `am force-stop`.** §2 above is the same correction for K2:
   force-stop puts the package in Android's *stopped state*, which is a different
   event from process death and one the platform treats differently.
3. **The payment id needs no cross-process channel.** The host chooses the hold
   invoice's payment hash, and ldk-node's BOLT11 `PaymentId` is that hash — so the
   second run can be handed the id it must look up as an instrumentation argument
   rather than reading a file the kill may have caught mid-write. The first run
   asserts the two are equal, so if that ever stops being true the test says so
   instead of silently looking up nothing.
4. ~~**A way to reach the *shipping* wallet graph from the test.**~~ **Built.**
   `com.bittr.android.di.WalletGraph`, a Hilt `@EntryPoint` in `:app`'s **main**
   source set, handing out the two things K7 needs: the `WalletService` the app
   composed and a `LightningNodePort` over the same `NodeLifecycle`.

   The test has to drive the `NodeBackedWalletService` the app really composes,
   not a copy of `WalletModule`'s composition — a test against a graph the app
   does not build would prove something about the test. The route there was
   measured on this branch rather than assumed, in both directions:

   - Declaring the `@EntryPoint` in the `androidTest` source set **compiles and
     is not enough.** `kspDebugAndroidTestKotlin` produces the interface and
     produces no aggregating metadata for it — `build/generated/ksp/debug/java/dagger/hilt/`
     exists for the main variant and there is no `debugAndroidTest` equivalent —
     so `EntryPointAccessors.fromApplication` would fail at run time, after an
     emulator boot, in a job that compiled clean. Exactly the shape of trap this
     document keeps paying for.
   - Declaring it in **main** produces the metadata, and that is checked rather
     than inferred: `:app:assembleDebug` writes
     `hilt_aggregated_deps/_com_bittr_android_di_WalletGraph.java` carrying
     `entryPoints = "com.bittr.android.di.WalletGraph"`, and
     `BittrApplication_HiltComponents.java` lists `WalletGraph` among the
     interfaces `SingletonC` extends. That is the exact artefact whose absence
     made the `androidTest` placement a run-time failure.
   - The option not taken was `hilt-android-testing` with `@HiltAndroidTest` and
     a `HiltAndroidRule`: a new test dependency, and — the reason it lost — it
     builds a **test** component, which is a graph assembled for the test rather
     than the one the app runs.

   **Why this is not the seam §3 rejects.** A graph accessor has no behaviour, no
   branch and nothing to do with funds; it returns objects the app has already
   built for its own reasons, and what it can reach is what any code inside the
   app can already reach. A latch in the send path is a code path that exists
   only to be taken. `WalletNodeHost`, `NodeLifecycle` and `ManagedNode` are
   deliberately **not** exposed — a test that could reach them could start and
   stop a node behind `NodeBackedWalletService`'s back, violating the ordering
   rules it claims to be measuring.

   **What it cost, stated because it is a real change to production
   composition.** `WalletModule` now binds a `LightningNodePort`, which it did
   not before: `LdkNodeSurface` had no construction site anywhere outside its own
   test, so BIT-122's port was unreachable code. Binding it means the module
   builds the wallet once into a `WalletComposition` and hands out its two halves,
   so the port and the wallet cannot end up over two different `NodeLifecycle`s —
   a mistake that would read as "no node is running" forever. **Its only caller
   today is `WalletGraph`**; the send and home screens that will use it do not
   exist on Android yet. `LightningNodePortTest` proves the no-node half on the
   JVM, including that an unconfigured build — the one CI assembles and Maestro
   installs — still composes a graph, with reads answering empty and writes
   throwing `NodeUnavailableException`.

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

**Three of those four now exist** (§0): the configured build, the four services,
and a nightly job. What is left for K8 is the soak itself, and one thing §0 does
not solve:

- **The budget is 90 minutes, and App Standby buckets move on the order of
  hours.** So the soak has to *drive* the buckets rather than wait for them:
  `am set-standby-bucket <pkg> rare` and `dumpsys deviceidle force-idle` put the
  device in the state, and `dumpsys deviceidle unforce` takes it out. That is a
  weaker claim than elapsed wall-clock and it must be labelled as one — a forced
  bucket is the platform being told what to believe, not the platform having
  decided.
- **The Doze half is emulator-capable today** and now has a foreground service to
  observe, which is the half that was missing. `dumpsys battery unplug` first, or
  `force-idle` refuses.
- `WalletForegroundServiceTest` still covers the JVM contract — promoted before a
  start begins, demoted only on a definite failure — without proving the platform
  honours it. That remains the gap.

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
