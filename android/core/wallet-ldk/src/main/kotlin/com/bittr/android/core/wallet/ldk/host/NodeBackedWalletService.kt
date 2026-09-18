package com.bittr.android.core.wallet.ldk.host

import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.WalletService
import com.bittr.android.core.wallet.WalletState
import kotlinx.coroutines.flow.StateFlow

/**
 * The wire BIT-126 exists to make: `WalletService.start`/`stop` bound to a real
 * node instead of to the stub's no-ops.
 *
 * Everything about the *seed* — the BIP-39 phrase, the PIN verifier, the failed
 * attempt counter, the state machine — stays with [seed], which is
 * `:core:wallet-seed`'s `SeedWalletService` in production and a fake in tests.
 * This class adds five overrides and delegates the other seven, because five
 * is how many of `WalletService`'s methods have anything to do with a node.
 *
 * ## Why a decorator and not a second implementation
 *
 * `SeedWalletService` is 230 lines of PBKDF2, constant-time comparison and
 * ordering rules that a wipe depends on being right, and every one of them is
 * covered by `SeedWalletServiceTest`. A node-backed `WalletService` written as
 * its own class would have to reproduce them, and the copy would drift — the
 * interesting drift being the failed-attempt counter, where a divergence buys an
 * attacker guesses. Delegation means there is one implementation of the PIN
 * gate and one test suite proving it.
 *
 * It also keeps the module boundary honest. This class names
 * [com.bittr.android.core.wallet.WalletService] and nothing else from the seed
 * side; `:core:wallet-ldk` does not depend on `:core:wallet-seed`, and the app's
 * wallet module is the one place the two are put together.
 *
 * ## The five overrides
 *
 * [start] and [stop] are the issue. [removeWallet] is the ordering the issue
 * asks about, and it is the one with a rule worth stating. [createWallet] and
 * [restoreWallet] put a new seed on the device, and the node state already
 * there may belong to the one before it.
 *
 * Proved by `NodeBackedWalletServiceTest`.
 */
class NodeBackedWalletService(
    private val seed: WalletService,
    private val host: WalletNodeHost,
    /**
     * Erase whatever the *node* holds, once it is down: ldk-node's state
     * directory, BDK's store, the wrapped seed blob if this build keeps one.
     *
     * Separate from [seed]'s own erase because the two are different stores with
     * different failure modes, and because this one runs while the wallet is
     * held down by [WalletNodeHost.withWalletDown] and the other does not have
     * to. Defaulted to a no-op so a build with no node configured composes
     * without pretending to wipe something it never wrote.
     */
    private val wipeNodeState: suspend () -> Unit = {},
    /**
     * Make the node state on disk fit the seed that was just written: keep it
     * if it is that seed's, quarantine it if it is not, and record whose it is
     * now — `SeedImportGuard.prepareStateFor` in production. Throws
     * [com.bittr.android.core.wallet.WalletStorageException] when state that had
     * to be moved could not be, which signup shows as its save-failed alert.
     * Defaulted to a no-op for the same reason [wipeNodeState] is.
     */
    private val prepareNodeState: suspend (Mnemonic) -> Unit = {},
) : WalletService {

    override val state: StateFlow<WalletState> get() = seed.state

    /**
     * A new seed, and the node state made to fit it before any node can start.
     *
     * Removal erases the seed and deliberately leaves ldk-node's state
     * directory, because it is the only thing that can sweep a force-closed
     * channel. Without this step the next wallet builds a node over the last
     * one's on-chain store, and ldk-node refuses it ("Failed to setup onchain
     * wallet") — decision 37 in the port log.
     *
     * **After the seed write, not before it**, which is the reverse of
     * `SeedImporter` and is sound here for a reason `SeedImporter` cannot lean
     * on: a seed without a PIN is not a wallet. `SeedWalletService` keeps the
     * state `Uninitialized` until `setPin`, nothing starts a node for an
     * uninitialized wallet, and running the arc again writes a fresh seed and
     * comes back through here. So a crash between the write and the quarantine
     * leaves no node running over foreign state, only a signup to do again.
     * The phrase `createWallet` generates is also not known until it returns.
     *
     * Held down by [WalletNodeHost.withWalletDown] like [removeWallet], because
     * a quarantine moves the directory a running node has open.
     */
    override suspend fun createWallet(): Mnemonic = host.withWalletDown {
        seed.createWallet().also { prepareNodeState(it) }
    }

    /** As [createWallet]: the restored phrase's own state is kept, anything else quarantined. */
    override suspend fun restoreWallet(mnemonic: Mnemonic) = host.withWalletDown {
        seed.restoreWallet(mnemonic)
        prepareNodeState(mnemonic)
    }

    override suspend fun setPin(pin: String) = seed.setPin(pin)

    override suspend fun unlock(pin: String): Boolean = seed.unlock(pin)

    override suspend fun failedUnlockAttempts(): Int = seed.failedUnlockAttempts()

    override suspend fun holdsSeed(mnemonic: Mnemonic): Boolean = seed.holdsSeed(mnemonic)

    override suspend fun resetPin(mnemonic: Mnemonic, pin: String) = seed.resetPin(mnemonic, pin)

    /**
     * Bring the node up.
     *
     * Returns `Unit` because the interface does, which loses the
     * `NodeStartResult` — deliberately, for now. `UnlockViewModel` is the caller
     * and it has no branch to put the outcome in: iOS's equivalent shows a
     * retry alert off `didStartLDK`'s false, and porting that alert is a screen
     * change with approved copy behind it, not something to smuggle in under a
     * lifecycle issue. The outcome is not discarded, it is *not yet asked for* —
     * [WalletNodeHost.start] returns it and BIT-123 is where it becomes UI.
     *
     * What the caller does get, and did not have before, is the timing: this
     * suspends until the node is up or has definitively failed, so a screen that
     * awaits it is awaiting a fact rather than a request.
     */
    override suspend fun start() {
        host.start()
    }

    override suspend fun stop() = host.stop()

    /**
     * Erase the wallet, with the node down first.
     *
     * The order is: node down → node state gone → key material gone. Two
     * separate reasons, and they point the same way:
     *
     * - **A running node holds the state directory.** ldk-node keeps its SQLite
     *   store open; deleting underneath it is the two-writers case
     *   `LdkNodeStartErrors` refuses to retry, arriving as a wipe instead of as
     *   a second start.
     * - **`WalletService.removeWallet`'s own ordering survives.** The counter
     *   and the PIN go before the seed, so a failure part-way leaves a wallet
     *   that can still be unlocked. That rule is [seed]'s and is not restated
     *   here; what is added is only that all of it happens after the node is
     *   down, which is iOS's ordering too — `CacheManager.deleteClientInfo()`
     *   runs only once the node has stopped and the files are gone.
     *
     * **Node state before key material**, and that is the ordering that costs
     * something to get backwards. The state directory is the only thing that can
     * sweep a force-closed channel, and a seed alone cannot reconstruct it — so
     * a failure between the two wants to leave the *recoverable* half. Deleting
     * the seed first and then failing to delete the state leaves channel
     * monitors on the device for a wallet nobody can open: unsweepable, and
     * indistinguishable from foreign state to the BIT-20 guard on the next
     * install.
     *
     * **What this does not do is close channels.** `WalletService.removeWallet`
     * says the cooperative close is BIT-6's and unimplemented, and it stays
     * that way here — see [WalletNodeHost.withWalletDown] for why the decision
     * (`WipeSafety.channelsFullyClosedAndSwept`) cannot live inside this call:
     * it needs the node running to answer, and by this point it is not. The
     * caller that asks the user "are you sure" is where it goes.
     */
    override suspend fun removeWallet() = host.withWalletDown {
        wipeNodeState()
        seed.removeWallet()
    }
}
