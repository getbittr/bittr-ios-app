# The private regtest network, and how K7 gets a deterministic kill window

**BIT-132.** `android/docs/wallet-node-device-tests.md` closed K7 and K8 *unrun*
and named the precondition: the `wallet-instrumented` job builds a wallet with no
node in it, because `LdkEnvironmentConfig.fromBuildConfig()` returns null unless
all six `BuildConfig` fields are supplied and their committed defaults are the
empty string. This directory is what supplies them.

```sh
bash android/regtest/up.sh                                  # three containers, one facts file
python3 android/scripts/regtest-ldk-env.py --format gradle   # the four values, as -P arguments
bash android/regtest/down.sh                                # and its chain, deliberately
```

## The four endpoints, and why three containers is the right count

| Endpoint | Served by | Who needs it |
|---|---|---|
| bitcoind RPC + ZMQ, regtest | `bitcoind` | mining, funding, and LND's chain backend |
| Esplora REST, HTTP | `electrs` | **ldk-node**'s chain source — `NodeConfigPlan` uses Electrum only on mainnet |
| Electrum, TCP | `electrs` | **BDK**'s, via `BdkOnchainWallet`'s `ElectrumClient` |
| Lightning P2P | `lnd` | the channel counterparty |

Esplora and Electrum come out of one `electrs` process because Blockstream's
electrs *is* the implementation of both. They are two fields in `LdkEnvironment`
because they are two protocols on two ports spoken by two libraries — that field
exists to stop a development build handing `ElectrumClient` an Esplora URL — not
because they must be two daemons. One regtest chain does not need two indexes.

## Everything is outbound from the emulator

The device dials the host; the host never dials the device. That is a deliberate
constraint and it is what keeps this harness small:

- The emulator's user-mode network stack maps `10.0.2.2` to the runner's
  **loopback**, so every container publishes to `127.0.0.1` and is reachable from
  the device and from nothing else on the runner's network.
- There is no `adb reverse`, no `--externalip` that has to be right, and no
  host-to-device port forward that has to survive an emulator restart.
- **The app opens the channel**, rather than LND opening one to it. The app's node
  id does not exist until the APK has been installed and unlocked, so an
  LND-initiated channel would need the host to learn that id and then dial into
  the device. Funding the app's on-chain wallet from bitcoind and letting it call
  `openChannel` costs one extra mined block and removes that whole direction.

The one thing that crosses the other way is `adb`, which we already have and
which is how the host observes and kills.

## K7's deterministic interception point

BIT-132 says this is the hard part and that it is a decision about production
code:

> "Kill the process mid-`send`" needs a *deterministic* interception point.
> Without one the kill window is milliseconds wide, and a test that lands inside
> it sometimes is a test that reports a fund-safety property as flaky — the worst
> possible reading, since the expected result and a missed window look identical.

**The decision: the interception point goes in the counterparty, not in our send
path.** LND's `addholdinvoice` withholds the preimage, so the HTLC arrives, is
accepted, and *stays* accepted until the test settles or cancels it. The window is
not milliseconds wide; it is as wide as the test wants, it is observable from the
host (`lncli lookupinvoice` reports `state: ACCEPTED` exactly when the HTLC is in
flight), and reaching it needs no test-only code anywhere near the money.

That is why this network runs LND and not Core Lightning or Eclair: `invoicesrpc`
is compiled into every released LND, where the other two need a plugin.

### Why not a seam in the send path

The alternative BIT-132 offers first is "a seam in the send path that the test can
block on". Rejected, and the reason is not tidiness:

- A latch inside `LdkNodeSurface.sendBolt11` is a branch in the fund-handling path
  that exists only to be taken by a test. It ships in the release APK or it
  doesn't; if it ships it is a way to wedge a real payment, and if it doesn't then
  the thing under test is not the thing that ships.
- It would prove less. A seam can only pause where *we* are — before the FFI call
  or after it returns. It cannot pause inside `ChannelManager::send_payment`, and
  the interesting window is the one where the HTLC is out on the wire and our
  record of it may or may not be durable. The hold invoice puts us squarely in
  that window and holds us there.
- `WalletNodeHostTest` already covers our own ordering rules on the JVM against a
  fake node. What K7 adds is LDK's durability across a `SIGKILL`, and a seam in
  our code is the wrong instrument for a claim about someone else's.

### What the hold invoice does not cover, stated rather than discovered

There is a second window, and it is genuinely not reachable this way: inside
`bolt11Payment().send`, between the moment `ChannelManager` commits the outbound
payment and the moment it is persisted. No HTLC exists for part of it, so no
counterparty can hold anything, and it is sub-millisecond.

Two things about it. First, it is a **smaller** claim than the one K7 states: with
no HTLC on the wire there is nothing to double-spend and nothing to lose, so the
failure it could expose is "we forgot a payment that never went out", which costs
a retry rather than money. Second, if it is ever worth measuring, the honest
instrument is N repetitions with a stated confidence — *not* a seam, and **not**
silence, because a single run that happened to miss the window is the exact
false-green this whole document is about.

`K7InterruptedPaymentTest` — **written, not yet run**; see
`android/docs/wallet-node-device-tests.md` §3 — says which of the two windows it
entered, per run, in its evidence line. A run that reports the narrow window is
not a K7 result, and a test that cannot tell you which one it got is not a K7
test.

**It goes further than reporting, because reporting alone is not enough.** A
phase that returns straight after `send` would be torn down *somewhere*, most
likely in the narrow window, and would then honestly report a result that is not
a K7 result — which is a truthful evidence line under a green row, and that is
the shape of false green this file exists to refuse. So the narrow window is
refused rather than labelled: `android/scripts/k7-interrupted-payment.sh` polls
`lncli lookupinvoice` and writes a hand-off only on `ACCEPTED`, phase 3 blocks on
that hand-off and asserts on its contents, and a run where the HTLC never reaches
LND fails in phase 3 and never reaches the kill at all.

## What K8 uses this network for, which is not what K7 uses it for

K7 needs a **counterparty that will hold**. K8's freshness half needs a **chain
that keeps moving while the device cannot see it** — so its use of this directory
is `bitcoind` and nothing else: `android/scripts/k8-doze-soak.sh` sends to the
node's own on-chain address and mines, *during* the forced deep-idle window, and
the wake then has something to catch up to. A node that "caught up" to a chain
that never moved is a pass that measured nothing, which is why the device fails
rather than passes when the host's hand-off never arrives.

It runs **after** K7 and over the channel K7 opened and never closed. That is a
deliberate trade with a stated price — `wallet-node-device-tests.md` §4 — and the
price is that a red K7 phase 2 makes K8's freshness half unrunnable rather than
merely unreadable. The gate reports it as *"did not run at all"*, which is the
accurate verdict.

### The two hand-off directions are different mechanisms, and that is not a style choice

K7's hand-off goes host → device: `adb shell` writes a file under
`/data/local/tmp` and the device reads it with `cat`. K8 needs that direction too
— *"I have mined"* — and it uses the same one.

K8 also needs **device → host**: *"I am inside the idle window, and here is the
address to fund."* That one cannot be a file. `UiAutomation.executeShellCommand`
hands its string to `Runtime.exec`, which splits on whitespace and executes the
binary directly — there is no shell, so a device-side `echo … > /data/local/tmp/x`
passes `>` to `echo` as a literal argument and writes nothing. So that direction
is `Log.i` under the `K8_DOZE_SOAK` tag, which the host polls with
`adb logcat -d -s`.

Neither end has a compiler behind it. `android/scripts/test_k8_doze_soak.sh` pins
the tag, both markers, the hand-off path and the address token against the test in
the `build` job, on a machine with no emulator.

## Costs, so nobody is surprised by them

- **electrs is built from source.** There is no first-party Blockstream electrs
  image, and the popular third-party ones are the *other* electrs (romanz's,
  Electrum-only, no Esplora HTTP API at all). A cold build is 8–12 minutes; the
  layer is then cached. See `electrs/Dockerfile`.
- **Docker is a new host requirement.** `android/docs/self-hosted-runner.md` did
  not ask for it before BIT-132. `up.sh` preflights it and names that document.
- **This is not a per-push job.** K8's useful form is a soak across App Standby
  buckets, which is hours, and `wallet-instrumented` already sits inside a
  45-minute timeout that one self-hosted runner serialises against two other
  emulator jobs. The home for this is `.github/workflows/wallet-regtest-nightly.yml`.

## The bring-up order is load-bearing: mine before starting electrs and LND

`up.sh` starts **bitcoind alone**, mines, and only then starts the other two.
That is not tidiness, and the obvious simplification — one `compose up --wait`
over all three services — is what the first two runs of this network did. It
cannot work, and it fails by timing out rather than by saying anything.

Neither dependent will report healthy on a chain still sitting on the genesis
block, and each refuses for its own reason:

| Service | Waits for | Where | Healthcheck therefore |
|---|---|---|---|
| `electrs` | bitcoind to leave initial block download | `src/daemon.rs`, `Daemon::new` loops on `getblockchaininfo` before returning | never binds `:3002`, so `curl /blocks/tip/height` gets connection refused — not an empty answer |
| `lnd` | `Wallet.IsSynced()` | `lnd.go` blocks there before `SetServerActive`; `lnwallet/btcwallet` returns false while the best header is **more than two hours old** | `lncli getinfo` is refused, because the RPC server has not started |

Bitcoin's genesis block is timestamped **2011-02-02**, and on a fresh regtest
chain it is the tip — so bitcoind reports `initialblockdownload: true` and the
tip reads as fifteen years stale. Both predicates are about the tip's timestamp,
and mining is the only thing that clears either. With the mining on the far side
of a wait that requires all three healthy, the wait can never return.

Two consequences worth keeping:

- **A tall chain is not a recent one.** `up.sh` is idempotent, so the warm case
  is real: a network left up overnight has 101 blocks and a nine-hour-old tip,
  which passes the height check and fails LND's two-hour one exactly like a fresh
  chain. `up.sh` mines one block whenever the tip is over an hour old.
- **The precondition is asserted, not assumed.** `up.sh` reads
  `initialblockdownload` back from bitcoind before starting the other two, so
  getting this wrong again costs one RPC call instead of a ten-minute healthcheck
  timeout and an annotation full of a daemon reporting that it is waiting.

## Never mainnet, and what actually enforces it

`up.sh` writes `"network": "regtest"` and `regtest-ldk-env.py` refuses to emit an
environment from a facts file that says anything else — including `signet`, whose
peers are also somebody else's nodes. It then re-checks its own output: every URL
it emits must name `10.0.2.2` and nothing else, so a future edit that
parameterises the host has to come to `check_emitted()` and argue for it.
`android/scripts/test_regtest_ldk_env.py` drives both refusals with negative
controls, because a guard whose only runs are green ones is indistinguishable from
no guard.

The six `BuildConfig` defaults stay the empty string. That is what keeps a clone
and every other CI job building a wallet with no node in it, which is the correct
state for everything except this one job.
