package com.bittr.android.removal

import android.content.Context
import android.util.Log
import androidx.lifecycle.ViewModel
import com.bittr.android.core.wallet.ldk.lightning.ChannelView
import com.bittr.android.core.wallet.ldk.lightning.WalletNodeReading
import com.bittr.android.core.wallet.ldk.node.LdkEnvironment
import com.bittr.android.di.LdkEnvironmentConfig
import com.bittr.android.di.WalletComposition
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

@Module
@InstallIn(SingletonComponent::class)
object RemovalModule {

    /**
     * One coordinator for the process: the removal it tracks outlives the screen it started on.
     * Its scope is `Main` because it only moves state and hops to IO for the node calls.
     */
    @Provides
    @Singleton
    fun provideWalletRemovalCoordinator(
        @ApplicationContext context: Context,
        composition: WalletComposition,
    ): WalletRemovalCoordinator = WalletRemovalCoordinator(
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
        wallet = composition.wallet,
        node = CompositionRemovalNode(composition, LdkEnvironmentConfig.fromBuildConfig()),
        flag = FileRemovalFlagStore(File(context.noBackupFilesDir, "wallet_removal_in_progress")),
    )
}

/** How the navigation graph reaches the singleton coordinator. */
@HiltViewModel
class WalletRemovalViewModel @Inject constructor(
    val coordinator: WalletRemovalCoordinator,
) : ViewModel()

/** [RemovalNode] over the one wallet composition, bittr's peer from the build's [LdkEnvironment]. */
internal class CompositionRemovalNode(
    private val composition: WalletComposition,
    private val environment: LdkEnvironment?,
) : RemovalNode {

    override val hasNode: Boolean get() = environment != null

    private val lightning get() = composition.lightning

    override fun isSynced(): Boolean =
        !hasNode || (composition.overview.overview.value.hasSynced && lightning.nodeId() != null)

    override suspend fun startAndSync(): Boolean {
        composition.wallet.start()
        if (lightning.nodeId() == null) {
            Log.w(TAG, "No node id after start; removal cannot verify the channel")
            return false
        }
        // A failed sync is not a reason to refuse outright: stale state errs towards "still
        // closing", which blocks the erase rather than allowing it.
        runCatching { lightning.syncWallets() }.onFailure { Log.w(TAG, "Sync before removal failed", it) }
        return true
    }

    override fun read(): WalletNodeReading? = lightning.readWalletState()

    override fun isPeerConnected(): Boolean {
        val peer = environment?.lightningNodeId ?: return false
        return lightning.listPeers().any { it.nodeId == peer && it.isConnected }
    }

    override suspend fun connectPeer(): Boolean = composition.bittrPeer.ensureConnected()

    override fun closeChannel(channel: ChannelView) =
        lightning.closeChannel(channel.userChannelId, channel.counterpartyNodeId)

    override fun forceCloseChannel(channel: ChannelView) =
        lightning.forceCloseChannel(channel.userChannelId, channel.counterpartyNodeId)

    override fun didCloseChannel() {
        runCatching { lightning.syncWallets() }
        composition.refresh()
    }

    private companion object {
        const val TAG = "WalletRemoval"
    }
}

/**
 * The in-progress flag as a marker file under `no_backup`, so a device restored from backup does
 * not offer to remove a wallet it never started removing.
 */
internal class FileRemovalFlagStore(private val marker: File) : RemovalFlagStore {
    override var inProgress: Boolean
        get() = marker.exists()
        set(value) {
            runCatching { if (value) marker.createNewFile() else marker.delete() }
        }
}
