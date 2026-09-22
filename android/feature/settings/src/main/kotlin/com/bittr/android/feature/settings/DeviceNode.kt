package com.bittr.android.feature.settings

/**
 * What Device details asks the Lightning node and bittr — the node half of
 * `DeviceViewController`. `:app` implements it over the one wallet composition; this module
 * names no wallet engine.
 */
interface DeviceNode {

    /** `nodeId()`, or null while no node is running. */
    fun publicKey(): String?

    /**
     * The FCM registration token this install is known by, or null when there is none —
     * notifications denied, or Play services missing. iOS's `showToken`, which reads the
     * token APNs handed it.
     */
    suspend fun deviceToken(): String?

    /** `isConnectedToPeer()`: connected to the bittr node right now. */
    suspend fun isConnectedToBittr(): Boolean

    /** `didEstablishPeerConnection()`. */
    suspend fun reconnectToBittr()

    /** `checkPendingPayout()`: the signed `GET /notifications`. */
    suspend fun pendingPayout(): PendingPayoutCheck

    /** `handlePendingPayout()`: pay the payout out as if its push had just been handled. */
    fun handlePendingPayout(payout: PendingPayoutCheck.Available)

    /** No node in this build, or in a test. */
    object None : DeviceNode {
        override fun publicKey(): String? = null
        override suspend fun deviceToken(): String? = null
        override suspend fun isConnectedToBittr(): Boolean = false
        override suspend fun reconnectToBittr() = Unit
        override suspend fun pendingPayout(): PendingPayoutCheck = PendingPayoutCheck.NoNode
        override fun handlePendingPayout(payout: PendingPayoutCheck.Available) = Unit
    }
}

sealed interface PendingPayoutCheck {
    /** No node to sign with. */
    data object NoNode : PendingPayoutCheck

    /** Nothing to collect, or the check failed — iOS shows `bittrpendingpayout2` for both. */
    data object NoneAvailable : PendingPayoutCheck

    data class Available(val notificationId: String, val amountMsats: Long) : PendingPayoutCheck
}
