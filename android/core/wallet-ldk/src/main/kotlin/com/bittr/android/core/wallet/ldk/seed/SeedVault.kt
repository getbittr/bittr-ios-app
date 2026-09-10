package com.bittr.android.core.wallet.ldk.seed

import com.bittr.android.core.wallet.ldk.storage.Durability
import com.bittr.android.core.wallet.ldk.storage.WalletPaths
import java.io.File
import java.io.FileNotFoundException

/** Thrown when the blob did not survive its own write. See [SeedVault.write]. */
class SeedWriteVerificationFailed(message: String) : IllegalStateException(message)

/**
 * Reads and writes the Keystore-wrapped mnemonic.
 *
 * The blob is a **cache, never the only copy** (rule 3). Everything here is
 * arranged so that losing it degrades to "restore from mnemonic" and never to an
 * error state, a wipe, or a claim that a wallet exists when nothing recoverable
 * was stored.
 */
class SeedVault(
    private val paths: WalletPaths,
    private val wrapper: SeedWrapper,
) {

    /**
     * Classifies the blob three ways. Never throws for an expected condition —
     * the outcome type carries the answer, including the failure answer.
     */
    fun read(): SeedBlobOutcome =
        try {
            val blob = paths.seedBlob
            if (!blob.isFile) {
                SeedBlobOutcome.NoUsableMnemonic(
                    SeedBlobOutcome.NoUsableMnemonic.Reason.BlobAbsent,
                )
            } else {
                SeedBlobOutcome.Present(wrapper.unwrap(blob.readBytes()))
            }
        } catch (t: Throwable) {
            SeedBlobClassifier.classify(t)
        }

    /**
     * Wraps [mnemonic] and writes it, then **decrypts it back and compares**
     * before reporting success.
     *
     * The read-back is ported from `persistSecret` (`CacheManager.swift:528-539`),
     * which writes, re-reads, and throws `writeVerificationFailed` on mismatch.
     * That is not decoration. Without it a write that fails silently — a
     * truncated file, a key invalidated between generation and use — leaves the
     * app believing a wallet exists when nothing recoverable was stored. The user
     * would find out at restore time, which is the worst possible moment.
     *
     * The onboarding seed-confirmation gate means the user has the words on paper
     * either way, so this is not the last line of defence. It is a cheap one, and
     * it is in the source we are porting.
     *
     * @throws SeedWriteVerificationFailed rather than returning a boolean,
     * because there is no caller for whom "the seed did not persist" is a
     * recoverable condition to branch on.
     */
    fun write(mnemonic: ByteArray) {
        paths.ensureRoot()
        wrapper.ensureKey()

        val blob = paths.seedBlob
        blob.writeBytes(wrapper.wrap(mnemonic))
        Durability.fsyncFile(blob)
        Durability.fsyncDir(paths.root)

        val readBack = try {
            wrapper.unwrap(blob.readBytes())
        } catch (t: Throwable) {
            throw SeedWriteVerificationFailed(
                "Wrote the seed blob to ${blob.name} but could not read it back: $t. " +
                    "Reporting wallet creation as successful here would leave the user " +
                    "believing a wallet exists when nothing recoverable was stored.",
            )
        }

        val matches = readBack.contentEquals(mnemonic)
        readBack.fill(0)
        if (!matches) {
            throw SeedWriteVerificationFailed(
                "The seed blob read back different bytes than were written. The write did not " +
                    "persist correctly; failing loudly rather than reporting success.",
            )
        }
    }

    /**
     * Destroys the wrapping key and the blob. Used by wallet removal.
     *
     * Deliberately does **not** touch [WalletPaths.ldkStateDir]: quarantined and
     * live LDK state is the only material that can sweep funds from a
     * force-closed channel (`LightningStorage.swift:83-84`), and deleting it is
     * the one thing iOS refuses to do.
     */
    fun destroy() {
        wrapper.deleteKey()
        paths.seedBlob.delete()
    }

    /** True only if a blob file exists; says nothing about whether it decrypts. */
    fun blobFilePresent(): Boolean = paths.seedBlob.isFile

    internal fun readBlobBytesOrThrow(): ByteArray =
        paths.seedBlob.takeIf(File::isFile)?.readBytes()
            ?: throw FileNotFoundException(paths.seedBlob.path)
}
