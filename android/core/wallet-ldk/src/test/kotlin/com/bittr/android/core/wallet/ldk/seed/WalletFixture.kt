package com.bittr.android.core.wallet.ldk.seed

import com.bittr.android.core.wallet.ldk.FakeBlobCodec
import com.bittr.android.core.wallet.ldk.FakeBlobStore
import com.bittr.android.core.wallet.ldk.state.DiscriminatorStore
import com.bittr.android.core.wallet.ldk.state.LdkStateStore
import com.bittr.android.core.wallet.ldk.state.WalletPaths
import java.io.File

/**
 * A whole wallet layer on a temporary directory, with the Keystore and the blob
 * file faked and everything else real.
 *
 * "Everything else real" is deliberate. The filesystem work is where the port
 * defects live, so the recovery tests run against the actual quarantine, the
 * actual discriminator file and the actual guard — only the two device
 * services are substituted, and only because a device cannot be asked to fail
 * on cue.
 */
class WalletFixture(root: File, private val mainnet: Boolean = false) {

    val paths = WalletPaths(root).also { it.createDirectories() }
    val codec = FakeBlobCodec()
    val blobStore = FakeBlobStore()
    val vault = WrappedSeedVault(codec, blobStore)
    val stateStore = LdkStateStore(paths)
    val discriminatorStore = DiscriminatorStore(paths.discriminatorFile)

    val guard get() = SeedImportGuard(vault, stateStore, discriminatorStore, mainnet)
    val importer get() = SeedImporter(vault, guard)

    /**
     * Destroy the Keystore alias *and* the blob, leaving LDK state untouched.
     *
     * This is BIT-8 rule 3's routine case, not an exotic one: a corrupted blob,
     * a key the platform invalidated, or app credentials cleared without an
     * uninstall. The decision says it must degrade to "restore from mnemonic",
     * and BIT-20 says the channels come back with it.
     */
    fun destroySeedBlob() {
        blobStore.destroy()
        codec.unwrapFailure = { javax.crypto.AEADBadTagException("blob destroyed by test") }
    }

    /** Undo [destroySeedBlob]'s codec failure so a fresh import can be read back. */
    fun allowReads() {
        codec.unwrapFailure = null
    }
}
