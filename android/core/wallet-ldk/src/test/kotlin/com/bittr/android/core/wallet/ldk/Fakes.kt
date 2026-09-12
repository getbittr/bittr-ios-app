package com.bittr.android.core.wallet.ldk

import com.bittr.android.core.wallet.ldk.seed.BlobCodec
import com.bittr.android.core.wallet.ldk.seed.BlobStore
import java.io.File

/**
 * Test doubles for the two device services the wallet layer sits on.
 *
 * These stand in for the Android Keystore and the blob file so the decisions
 * that matter — the three-way classification, the write read-back, the
 * quarantine ordering — can be driven from failures a device will not produce
 * on demand. The real implementations are covered by the instrumented tests in
 * `src/androidTest`.
 */

/**
 * Reversible "encryption". Not a cipher and not pretending to be one: what is
 * under test here is the surrounding logic, and a real cipher would only add a
 * way for these tests to fail for a reason that is not the reason.
 */
class FakeBlobCodec : BlobCodec {

    /** Set to make the next [unwrap] throw. Cleared by nothing; tests set it explicitly. */
    var unwrapFailure: (() -> Throwable)? = null

    /** Set to make [wrap] throw. */
    var wrapFailure: (() -> Throwable)? = null

    var keyDeleted: Boolean = false
        private set

    /**
     * Models a key the platform has invalidated.
     *
     * Set it and every [unwrap] throws. A [wrap] clears it, because that is
     * what the real codec does: `KeyPermanentlyInvalidatedException` is raised
     * on encrypt as well as decrypt, so
     * [com.bittr.android.core.wallet.ldk.seed.AndroidKeystoreBlobCodec.wrap]
     * deletes the stale alias and generates a fresh key rather than letting a
     * dead key make the restore path unreachable.
     */
    var keyInvalidated: Boolean = false

    override fun wrap(plaintext: ByteArray): ByteArray {
        wrapFailure?.let { throw it() }
        if (keyInvalidated) {
            keyInvalidated = false
            keyDeleted = true
        }
        return plaintext.map { (it.toInt() xor 0x5a).toByte() }.toByteArray()
    }

    override fun unwrap(blob: ByteArray): ByteArray {
        unwrapFailure?.let { throw it() }
        if (keyInvalidated) {
            throw android.security.keystore.KeyPermanentlyInvalidatedException(
                "the wrapping key was invalidated by the platform",
            )
        }
        return blob.map { (it.toInt() xor 0x5a).toByte() }.toByteArray()
    }

    override fun deleteKey() {
        keyDeleted = true
    }
}

/** An in-memory [BlobStore] that can be told to lose writes or fail reads. */
class FakeBlobStore(private var blob: ByteArray? = null) : BlobStore {

    /** When true, [write] reports success and stores nothing. */
    var dropWrites: Boolean = false

    /** Set to make [read] throw rather than return. */
    var readFailure: (() -> Throwable)? = null

    override fun read(): ByteArray? {
        readFailure?.let { throw it() }
        return blob
    }

    override fun write(blob: ByteArray) {
        if (!dropWrites) this.blob = blob
    }

    override fun delete() {
        blob = null
    }

    fun destroy() {
        blob = null
    }
}

/** Write a plausible ldk-node state file so `hasLightningState()` is true. */
fun seedStateDirectory(stateDir: File, marker: String = "channel-monitor") {
    stateDir.mkdirs()
    File(stateDir, "ldk_node_data.sqlite").writeText(marker)
    File(stateDir, "ldk_node_data.sqlite-wal").writeText("$marker-wal")
}

/**
 * The two mnemonics the recovery tests turn on. Test vectors only — the first
 * is the one already pinned in the iOS source
 * (`BitcoinMessage.swift:363–367`), so the Android and iOS suites are reasoning
 * about the same wallet.
 */
object Mnemonics {
    const val IOS_VECTOR = "void super old faith primary cradle behave crucial vault minor walk random"
    const val OTHER = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
}
