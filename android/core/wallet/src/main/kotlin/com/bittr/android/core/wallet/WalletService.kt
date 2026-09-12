package com.bittr.android.core.wallet

import kotlinx.coroutines.flow.StateFlow

/**
 * The seam between the app and the wallet layer.
 *
 * Scope note: this is deliberately the smallest API the scaffold needs — enough
 * for navigation to ask "is there a wallet yet?" and for the app to drive node
 * lifecycle. It is **not** a design for the wallet layer. BIT-6 owns that, and
 * should widen this interface as ldk-node and BDK require rather than treat the
 * shape below as agreed. Nothing in :app or :feature:* may depend on a wallet
 * type that is not declared in this module.
 */
interface WalletService {

    /** Current wallet state. Cold consumers can read [StateFlow.value] for a snapshot. */
    val state: StateFlow<WalletState>

    /**
     * Bring the wallet up: load key material, start the Lightning node, begin sync.
     *
     * On Android this will not be a plain suspend call for long — process death is
     * routine, so the real implementation is expected to be backed by a foreground
     * service. See ANDROID_PORT_PLAN.md and the semantic-gap checklist in the
     * inventory doc.
     */
    suspend fun start()

    /** Take the wallet down cleanly. Must be safe to call when already stopped. */
    suspend fun stop()
}

/**
 * Coarse wallet lifecycle. Mirrors the states the iOS app's entry point branches on:
 * no wallet yet (→ signup), wallet present but locked (→ PIN), wallet usable (→ home).
 */
enum class WalletState {
    /** No key material on the device. The user has not created or restored a wallet. */
    Uninitialized,

    /** Key material exists but is not unlocked for use. */
    Locked,

    /** Wallet is unlocked and the node is running. */
    Ready,
}
