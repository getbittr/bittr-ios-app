package com.bittr.android.di

import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.ldk.host.BackgroundWake
import com.bittr.android.core.wallet.ldk.lightning.LightningNodePort
import com.bittr.android.core.wallet.ldk.lightning.NodeOnchainPort
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * A door into the wallet **the app actually built**, for a device test.
 *
 * BIT-132, `android/docs/wallet-node-device-tests.md` §3 item 4. K7 kills the
 * process mid-payment and asserts that the restarted node resolves that payment
 * to exactly one terminal outcome. To mean anything it has to drive the
 * `NodeBackedWalletService` [WalletModule] composes — not a copy of that
 * composition assembled in the test, which would prove a property of the test.
 *
 * ## Why an `@EntryPoint` here rather than in `androidTest`
 *
 * The obvious placement does not work, and it was measured on this branch
 * rather than assumed. An `@EntryPoint` declared in the `androidTest` source
 * set **compiles**: `kspDebugAndroidTestKotlin` generates the interface and
 * generates no aggregating metadata for it — `build/generated/ksp/debug/java/dagger/hilt/`
 * exists for the main variant and there is no `debugAndroidTest` equivalent —
 * so `EntryPointAccessors.fromApplication` would fail at run time, after a
 * twenty-minute emulator boot, in a job that compiled clean. That is the exact
 * shape of trap `wallet-node-device-tests.md` keeps paying for.
 *
 * The alternative was `hilt-android-testing` with `@HiltAndroidTest` and a
 * `HiltAndroidRule`. That is a new test dependency, and — the reason it lost —
 * it builds a **test** component: a graph assembled for the test, which is the
 * thing this interface exists to avoid handing K7.
 *
 * ## Why this is not the seam §3 rejected
 *
 * §3 refuses a latch inside `LdkNodeSurface.sendBolt11` that a test can block
 * on, and the refusal is about fund-handling code: a branch in the send path
 * that exists only to be taken either ships in the release APK — a way to wedge
 * a real payment — or does not ship, in which case the thing under test is not
 * the thing that ships.
 *
 * None of that applies to an accessor. This interface has no behaviour, no
 * branch, no state and nothing to do with money; it returns objects the app has
 * already built for its own reasons. It ships, and what it can do is exactly
 * what any code inside the app can already do.
 *
 * ## What it deliberately does not expose
 *
 * `WalletNodeHost`, `NodeLifecycle` and `ManagedNode` are absent on purpose. A
 * test that could reach them could start and stop a node behind
 * `NodeBackedWalletService`'s back, and the ordering rules `WalletNodeHostTest`
 * proves — nothing erases key material while a node is live, a runner is
 * relaunched when its node is — would be rules the test was free to violate
 * while claiming to measure the app. [WalletService.start] is the app's own way
 * in, and it is the one K7 uses.
 */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface WalletGraph {

    /**
     * The wallet `UnlockViewModel` drives — `SeedWalletService` in an
     * unconfigured build, `NodeBackedWalletService` in a configured one.
     *
     * Which of the two arrives is the assertion `RegtestEnvironmentTest` makes
     * before any payment test is allowed to draw a conclusion, and it is a
     * property of the build rather than of this interface. See
     * [WalletModule.provideWalletService].
     */
    fun walletService(): WalletService

    /**
     * The node's channel, peer and payment surface.
     *
     * **Today its only caller is this interface**, and that is worth stating
     * rather than discovering: `LightningNodePort` was written for BIT-122 and
     * the screens that will use it — send, home, the channel list — do not exist
     * on Android yet, so [WalletModule] binds it and nothing in the app calls
     * it. A reader who greps for a production call site will find none, and the
     * answer is "not yet", not "it was deleted".
     *
     * In an unconfigured build this is a port over no node: every read answers
     * empty or null and every write throws `NodeUnavailableException`. That is
     * [LightningNodePort]'s stated contract for a missing node and not a special
     * case for tests — see `lightningNodePort`.
     */
    fun lightningNode(): LightningNodePort

    /**
     * Where to send the coins that fund the channel — BIT-132, K7 run 1.
     *
     * The host phase cannot derive this. It would need ldk-node 0.7.0's exact
     * derivation, which is not recoverable from the shipped `.so`, and a guess
     * funds an address nothing is watching. So the first instrumented run asks
     * the device and prints the answer as an evidence line; the host sends,
     * mines, and the second run opens the channel.
     *
     * **ldk-node's on-chain wallet, not BDK's.** They are two wallets over one
     * seed, and only the first is the one `openChannel` spends from — see
     * [NodeOnchainPort], which is where that distinction is written down rather
     * than left to whoever reads `BdkOnchainWalletHolder` first.
     *
     * In an unconfigured build this throws `NodeUnavailableException`, which is
     * the port's contract for a missing node and not a special case. A test that
     * reaches this method in the `wallet-instrumented` job has misread which APK
     * it is running in; `RegtestEnvironmentTest` is the assertion that says so
     * before a payment test draws a conclusion.
     */
    fun nodeOnchain(): NodeOnchainPort

    /**
     * The background wake — BIT-133, `wallet-node-device-tests.md` §1.
     *
     * Here for its [BackgroundWake.last], which is the only way to see what a
     * wake *did* after the fact: `BittrMessagingService.deliver` returns the
     * synchronous verdict, and the phase that says the start actually ran
     * arrives later, with nobody on the call stack. `FcmWakeTest` reads it.
     *
     * **Two doors to one object, on purpose.** The production caller is
     * `WalletWakeEntryPoint`, which exposes this and nothing else. That
     * interface is not this one because a `Service` reachable from the framework
     * should not be able to reach [walletService] and [lightningNode] — the wake
     * is allowed to start the wallet and nothing more. The cost is a second
     * six-line interface; the alternative is a push receiver holding the
     * payment surface.
     */
    fun backgroundWake(): BackgroundWake
}
