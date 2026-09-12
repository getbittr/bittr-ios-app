package com.bittr.android.core.wallet.ldk.seed

import com.bittr.android.core.wallet.ldk.state.Fsync
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

/**
 * Wraps a mnemonic under [BlobCodec] and stores the result in a file.
 *
 * The Keystore lives behind [BlobCodec] and the disk behind [BlobStore] so that
 * the two behaviours the definition of done actually names — the three-way
 * classification and the write read-back — are provable on the JVM. On a device
 * both are the real thing; see [AndroidKeystoreBlobCodec].
 */
class WrappedSeedVault(
    private val codec: BlobCodec,
    private val store: BlobStore,
) : SeedVault {

    override fun presence(): MnemonicPresence = try {
        if (readOrThrow() != null) MnemonicPresence.Present else MnemonicPresence.NoUsableMnemonic
    } catch (throwable: Throwable) {
        SeedVaultFailures.classify(throwable)
    }

    override fun read(): String? = readOrThrow()

    private fun readOrThrow(): String? {
        val blob = store.read() ?: return null
        return String(codec.unwrap(blob), Charsets.UTF_8)
    }

    /**
     * Wrap, write, then decrypt what was written and compare — the port of
     * `persistSecret`'s `writeVerificationFailed` (`CacheManager.swift:528–539`).
     *
     * The comparison is against the mnemonic in memory, on the way back out
     * through the same codec and store the reader will use. Verifying the
     * in-memory ciphertext instead would prove only that the wrap round-trips,
     * which was never the failure being guarded against.
     *
     * Throws rather than returning a flag. The caller is wallet creation, and
     * "the wallet exists" is precisely the claim this must not let through
     * unchecked. The onboarding seed-confirmation gate means the user has the
     * words either way, so this is not the last line of defence — it is a cheap
     * one, and it is in the source being ported.
     */
    override fun store(mnemonic: String) {
        require(mnemonic.isNotBlank()) { "refusing to store a blank mnemonic" }
        store.write(codec.wrap(mnemonic.toByteArray(Charsets.UTF_8)))

        val readBack = try {
            readOrThrow()
        } catch (throwable: Throwable) {
            throw SeedWriteVerificationException(
                "seed blob did not read back after writing", throwable,
            )
        }
        if (readBack != mnemonic) {
            throw SeedWriteVerificationException(
                if (readBack == null) {
                    "seed blob was absent immediately after writing"
                } else {
                    "seed blob read back as a different value than was written"
                },
            )
        }
    }

    override fun clear() {
        store.delete()
        codec.deleteKey()
    }
}

/**
 * A write that reported success and did not happen.
 *
 * Its own type so callers cannot mistake it for the ordinary "no wallet yet"
 * path: this one means the app was about to tell a user their wallet was
 * created.
 */
class SeedWriteVerificationException(
    message: String,
    cause: Throwable? = null,
) : IOException(message, cause)

/** Authenticated encryption of the seed blob. */
interface BlobCodec {
    fun wrap(plaintext: ByteArray): ByteArray

    /** @throws javax.crypto.AEADBadTagException if the blob does not authenticate. */
    fun unwrap(blob: ByteArray): ByteArray

    fun deleteKey()
}

/** Where the wrapped blob's bytes live. */
interface BlobStore {
    /** `null` when there is no blob. Throws on a read that failed for another reason. */
    fun read(): ByteArray?
    fun write(blob: ByteArray)
    fun delete()
}

/**
 * The blob on disk, under `no_backup` (see
 * [com.bittr.android.core.wallet.ldk.state.WalletPaths]).
 *
 * Writes go via a temporary file and a rename, so a process death mid-write
 * leaves either the previous blob or none — never a truncated one. A truncated
 * blob is not a corrupted file in any recoverable sense; it is
 * `AEADBadTagException` on the next read, which classifies as "no usable
 * mnemonic" and sends the user to the restore screen. Safe, but avoidable.
 */
class FileBlobStore(private val file: File) : BlobStore {

    override fun read(): ByteArray? = try {
        file.readBytes()
    } catch (_: FileNotFoundException) {
        null
    }

    override fun write(blob: ByteArray) {
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeBytes(blob)
        Fsync.file(temporary)
        if (!temporary.renameTo(file)) {
            temporary.delete()
            throw IOException("Could not move the wrapped seed into place at $file")
        }
        file.parentFile?.let { Fsync.directory(it) }
    }

    override fun delete() {
        file.delete()
    }
}
