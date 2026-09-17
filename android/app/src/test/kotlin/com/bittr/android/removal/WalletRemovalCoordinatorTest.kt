package com.bittr.android.removal

import com.bittr.android.core.wallet.Mnemonic
import com.bittr.android.core.wallet.PinLockout
import com.bittr.android.core.wallet.SecureStore
import com.bittr.android.core.wallet.WalletState
import com.bittr.android.core.wallet.WalletStorageException
import com.bittr.android.core.wallet.ldk.lightning.BalanceView
import com.bittr.android.core.wallet.ldk.lightning.ChannelView
import com.bittr.android.core.wallet.ldk.lightning.PendingSweepView
import com.bittr.android.core.wallet.ldk.lightning.WalletNodeReading
import com.bittr.android.core.wallet.seed.SeedWalletService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `ResetApp.swift`'s decisions, without a node. The one property every test comes back to:
 * the seed survives until [com.bittr.android.core.wallet.ldk.lightning.WipeSafety] says the
 * channel funds have settled.
 */
class WalletRemovalCoordinatorTest {

    private class MemoryStore(var failRemoves: Boolean = false) : SecureStore {
        val values = mutableMapOf<String, ByteArray>()
        override fun read(key: String): ByteArray? = values[key]
        override fun write(key: String, value: ByteArray) { values[key] = value }
        override fun contains(key: String): Boolean = key in values
        override fun remove(key: String) {
            if (failRemoves) throw WalletStorageException("remove failed")
            values.remove(key)
        }
    }

    private class FakeNode : RemovalNode {
        override var hasNode = true
        var synced = true
        var starts = true
        var peerConnected = true
        var connects = true
        var closeFails = false
        var reading: WalletNodeReading? = reading()
        val closed = mutableListOf<String>()
        val forceClosed = mutableListOf<String>()

        override fun isSynced() = synced
        override suspend fun startAndSync() = starts
        override fun read() = reading
        override fun isPeerConnected() = peerConnected
        override suspend fun connectPeer(): Boolean {
            if (connects) peerConnected = true
            return connects
        }
        override fun closeChannel(channel: ChannelView) {
            if (closeFails) error("peer refused")
            closed += channel.userChannelId
        }
        override fun forceCloseChannel(channel: ChannelView) {
            forceClosed += channel.userChannelId
        }
        override fun didCloseChannel() = Unit
    }

    private class Flag : RemovalFlagStore {
        override var inProgress = false
    }

    private val store = MemoryStore()
    private val wallet = SeedWalletService(store, derivation = Dispatchers.Unconfined)
    private val node = FakeNode()
    private val flag = Flag()
    private val removal = WalletRemovalCoordinator(
        scope = CoroutineScope(Dispatchers.Unconfined),
        wallet = wallet,
        node = node,
        flag = flag,
        io = Dispatchers.Unconfined,
    )

    init {
        runBlocking {
            wallet.restoreWallet(Mnemonic(WORDS))
            wallet.setPin("1234")
        }
    }

    private val alert get() = removal.uiState.value.alert
    private val seedIsThere get() = store.contains(SeedWalletService.KEY_SEED)

    private fun tap(index: Int) = removal.press(alert!!.buttons[index])

    @Test
    fun `settings with no channel confirms twice, then erases`() {
        removal.removeWalletTapped(RemovalOrigin.Settings)
        assertEquals(RemovalStrings.RESTORE_WALLET_2, alert?.message)
        tap(1)
        assertEquals(RemovalStrings.RESTORE_WALLET_3, alert?.message)
        assertTrue(seedIsThere)
        tap(1)

        assertFalse(seedIsThere)
        assertEquals(WalletState.Uninitialized, wallet.state.value)
        assertTrue(removal.handOff.value)
        assertFalse(removal.uiState.value.busy)
    }

    @Test
    fun `cancel on either confirmation erases nothing`() {
        removal.removeWalletTapped(RemovalOrigin.Settings)
        tap(0)
        assertNull(alert)
        removal.removeWalletTapped(RemovalOrigin.Settings)
        tap(1)
        tap(0)
        assertTrue(seedIsThere)
        assertFalse(removal.handOff.value)
    }

    @Test
    fun `settings before the first sync only says the wallet is syncing`() {
        node.synced = false
        removal.removeWalletTapped(RemovalOrigin.Settings)
        assertEquals(RemovalStrings.SYNCING_WALLET_2, alert?.message)
        assertEquals(1, alert?.buttons?.size)
        assertTrue(seedIsThere)
    }

    @Test
    fun `settings with an open channel closes it cooperatively and keeps the wallet`() {
        node.reading = reading(channels = listOf(openChannel()))
        removal.removeWalletTapped(RemovalOrigin.Settings)
        assertEquals(RemovalStrings.RESTORE_WALLET_4, alert?.message)
        tap(1)
        assertEquals(RemovalStrings.CLOSE_CHANNEL_2, alert?.message)
        tap(1)

        assertEquals(listOf("user-1"), node.closed)
        assertEquals(RemovalStrings.STILL_CLOSING, alert?.message)
        assertTrue("A committed manual removal resumes on the next launch", flag.inProgress)
        assertTrue(seedIsThere)
        assertFalse(removal.handOff.value)
    }

    @Test
    fun `funds still settling after a close block the erase`() {
        node.reading = reading(pending = listOf(PendingSweepView.AwaitingThresholdConfirmations(5_000uL, "tx")))
        removal.removeWalletTapped(RemovalOrigin.Settings)
        assertEquals(RemovalStrings.STILL_CLOSING, alert?.message)
        assertTrue(seedIsThere)
        assertTrue(flag.inProgress)
    }

    @Test
    fun `a node that cannot be read never erases`() {
        node.reading = null
        removal.lockedOut()
        assertEquals(RemovalStrings.REMOVAL_FAILED, alert?.message)
        assertEquals(RemovalStrings.TRY_AGAIN, alert?.buttons?.single()?.label)
        assertTrue(seedIsThere)
    }

    @Test
    fun `a node that does not start never erases`() {
        node.starts = false
        removal.removeWalletTapped(RemovalOrigin.ForgotPin)
        tap(1)
        assertEquals(RemovalStrings.REMOVAL_FAILED, alert?.message)
        assertTrue(seedIsThere)
    }

    @Test
    fun `the lockout closes the channel unasked, then erases once the funds have landed`() {
        node.reading = reading(channels = listOf(openChannel()))
        removal.lockedOut()

        assertEquals(listOf("user-1"), node.closed)
        assertEquals(RemovalStrings.STILL_CLOSING, alert?.message)
        assertEquals(listOf(RemovalStrings.TRY_AGAIN), alert?.buttons?.map { it.label })
        assertTrue(seedIsThere)
        assertFalse("The lockout has its own resume path", flag.inProgress)

        // Blocks mined, funds swept.
        node.reading = reading()
        tap(0)
        assertFalse(seedIsThere)
        assertTrue(removal.handOff.value)
    }

    @Test
    fun `the lockout never force closes`() {
        node.reading = reading(channels = listOf(openChannel()))
        node.peerConnected = false
        node.connects = false
        removal.lockedOut()

        assertEquals(RemovalStrings.CLOSE_RETRY_LATER, alert?.message)
        assertTrue(node.forceClosed.isEmpty())
        assertTrue(seedIsThere)
    }

    @Test
    fun `an unreachable bittr node force-closes straight away on a manual removal, as iOS does`() {
        node.reading = reading(channels = listOf(openChannel()))
        node.peerConnected = false
        node.connects = false
        removal.removeWalletTapped(RemovalOrigin.Settings)
        tap(1)
        tap(1)

        assertTrue(node.closed.isEmpty())
        assertEquals(listOf("user-1"), node.forceClosed)
        assertEquals(RemovalStrings.FORCE_CLOSE_4, alert?.message)
        assertTrue(flag.inProgress)
        assertTrue(seedIsThere)
    }

    @Test
    fun `a failed close offers a force close, which also keeps the wallet`() {
        node.reading = reading(channels = listOf(openChannel()))
        node.closeFails = true
        removal.removeWalletTapped(RemovalOrigin.Settings)
        tap(1)
        tap(1)
        assertEquals(RemovalStrings.CLOSE_CHANNEL_7, alert?.message)
        assertTrue(node.forceClosed.isEmpty())

        tap(1)
        assertEquals(listOf("user-1"), node.forceClosed)
        assertEquals(RemovalStrings.FORCE_CLOSE_4, alert?.message)
        assertTrue(seedIsThere)
    }

    @Test
    fun `forgot PIN with no channel asks once and erases`() {
        removal.removeWalletTapped(RemovalOrigin.ForgotPin)
        assertEquals(RemovalStrings.REMOVE_WALLET_1, alert?.message)
        tap(1)
        assertFalse(seedIsThere)
        assertTrue(removal.handOff.value)
    }

    @Test
    fun `a build with no node erases without a reading`() {
        node.hasNode = false
        node.reading = null
        removal.removeWalletTapped(RemovalOrigin.ForgotPin)
        tap(1)
        assertFalse(seedIsThere)
    }

    @Test
    fun `a failed erase says so and can be retried`() {
        store.failRemoves = true
        removal.lockedOut()
        assertEquals(RemovalStrings.REMOVAL_FAILED, alert?.message)
        assertFalse(removal.handOff.value)

        store.failRemoves = false
        tap(0)
        assertFalse(seedIsThere)
    }

    @Test
    fun `launch resumes an earned lockout without a PIN`() {
        runBlocking { repeat(PinLockout.WIPE_AT) { wallet.unlock("1111") } }
        removal.checkOnLaunch()
        assertFalse(seedIsThere)
    }

    @Test
    fun `launch offers to finish a removal, and cancel forgets it`() {
        flag.inProgress = true
        removal.checkOnLaunch()
        assertEquals(RemovalStrings.REMOVAL_IN_PROGRESS, alert?.message)
        tap(0)
        assertFalse(flag.inProgress)
        assertTrue(seedIsThere)
    }

    @Test
    fun `launch resume finishes once the channel has settled`() {
        flag.inProgress = true
        removal.checkOnLaunch()
        tap(1)
        assertFalse(seedIsThere)
        assertFalse(flag.inProgress)
    }

    private companion object {
        val WORDS = listOf(
            "attack", "urge", "across", "cupboard", "year", "armor",
            "list", "vital", "outer", "leader", "anxiety", "endorse",
        )

        fun openChannel() = ChannelView(
            channelId = "channel-1",
            userChannelId = "user-1",
            counterpartyNodeId = "02".padEnd(66, 'a'),
            fundingTxo = null,
            channelValueSats = 100_000uL,
            outboundCapacityMsat = 50_000_000uL,
            inboundCapacityMsat = 0uL,
            unspendablePunishmentReserveSats = null,
            counterpartyUnspendablePunishmentReserveSats = 0uL,
            isChannelReady = true,
            isUsable = true,
        )

        fun reading(
            channels: List<ChannelView> = emptyList(),
            pending: List<PendingSweepView> = emptyList(),
        ) = WalletNodeReading(
            channels = channels,
            balances = BalanceView(
                totalOnchainBalanceSats = 0uL,
                spendableOnchainBalanceSats = 0uL,
                totalAnchorChannelsReserveSats = 0uL,
                totalLightningBalanceSats = if (channels.isEmpty()) 0uL else 50_000uL,
                lightningBalances = emptyList(),
                pendingBalancesFromChannelClosures = pending,
            ),
            payments = emptyList(),
        )
    }
}
