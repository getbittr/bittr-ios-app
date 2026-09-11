package com.bittr.android.core.wallet.ldk.state

import java.io.File
import java.io.IOException
import java.security.MessageDigest

/**
 * The BIT-20 discriminator: a non-secret value that says which seed a given LDK
 * state directory belongs to.
 *
 * **Why it exists.** iOS decides whether LDK state is foreign by inference:
 * *no mnemonic in the Keychain ⇒ any state on disk is foreign*
 * (`CacheManager.swift:361–370`). That holds on iOS because the Keychain
 * outlives app data. BIT-8 rule 3 makes it false on Android *by design* — "blob
 * destroyed, LDK state intact" is a state we have decided is routine and must
 * degrade to "restore from mnemonic". Ported literally the guard quarantines
 * the user's own channels; inverted, it lets a foreign seed be imported onto
 * live state. Neither branch is safe, so the inference is replaced by an
 * identity check.
 *
 * **Why the account xpub, and why the whole hash.** BIT-20 rule 1, decided:
 * full-width SHA-256 of the serialized BIP84 account xpub, compared in constant
 * time. Explicitly **not** the 4-byte BIP32 master fingerprint — 32 bits is
 * grindable on a laptop, and grinding a mnemonic to a chosen fingerprint turns
 * a `mismatch` back into a `match`, which is the exact loss-of-funds path this
 * guard closes. The xpub is also derivable from the mnemonic *alone*, which the
 * node id is not: obtaining a node id plausibly means booting a node against
 * the very state directory whose provenance has not been established yet, and
 * the guard has to decide before that point.
 *
 * Recording it is not a new secret, so BIT-8 rule 1 holds:
 * `Transfer2ViewController.swift:344–362` already POSTs the full account xpub
 * to our backend at signup as `xpub_key`. A local hash of it is strictly less
 * revealing than what the shipping product puts on the wire.
 *
 * Proved by `DiscriminatorSpecTest`.
 */
object SeedDiscriminator {

    /**
     * Domain separation, so this hash can never collide with some other hash of
     * the same xpub computed elsewhere in the app for another purpose.
     */
    private const val DOMAIN = "bittr/ldk-state/account-xpub/v1"

    /** SHA-256. Full width — see the class comment on why the fingerprint is not an option. */
    const val LENGTH_BYTES = 32

    fun compute(accountXpub: String): ByteArray {
        require(accountXpub.isNotBlank()) { "account xpub must not be blank" }
        return MessageDigest.getInstance("SHA-256").apply {
            update(DOMAIN.toByteArray(Charsets.US_ASCII))
            update(0)
            update(accountXpub.toByteArray(Charsets.US_ASCII))
        }.digest()
    }

    /**
     * Constant-time comparison.
     *
     * A timing oracle on a locally-stored non-secret is a weak attack and it is
     * not the reason for this. The reason is that the constant-time call is the
     * same length as the variable-time one, so there is no trade to make and
     * nothing to re-argue in review. `MessageDigest.isEqual` has been
     * constant-time since Android 4.0; `Arrays.equals`, `String.equals` and `==`
     * are not, and `DiscriminatorSpecTest` fails the build if one appears here.
     */
    fun matches(a: ByteArray, b: ByteArray): Boolean = MessageDigest.isEqual(a, b)

    fun encode(digest: ByteArray): String {
        require(digest.size == LENGTH_BYTES) { "digest must be $LENGTH_BYTES bytes, was ${digest.size}" }
        return digest.joinToString("") { "%02x".format(it) }
    }
}

/** What the discriminator file next to a state directory says about its owner. */
sealed interface DiscriminatorRecord {

    /** A well-formed 32-byte digest was read. */
    data class Present(val digest: ByteArray) : DiscriminatorRecord {
        override fun equals(other: Any?): Boolean =
            other is Present && SeedDiscriminator.matches(digest, other.digest)

        override fun hashCode(): Int = digest.contentHashCode()
    }

    /**
     * No file, an unreadable file, or a malformed one.
     *
     * BIT-20 rule 1: malformed classifies as **absent**, not as mismatch and not
     * as match. Absent is the fail-safe row — it quarantines, and quarantine
     * never deletes, so the worst an attacker gains by corrupting this file is a
     * denial of service. Reading a truncated file as a match would be the
     * fund-loss direction.
     */
    data object Absent : DiscriminatorRecord
}

/**
 * Reads and writes [DiscriminatorRecord] at [file].
 *
 * Kept separate from [SeedDiscriminator] so the digest rules can be tested
 * without a filesystem and the file rules without a hash.
 */
class DiscriminatorStore(private val file: File) {

    fun read(): DiscriminatorRecord {
        val text = try {
            if (!file.isFile) return DiscriminatorRecord.Absent
            file.readText().trim()
        } catch (_: IOException) {
            // Unreadable is not "belongs to a different seed". Fail safe.
            return DiscriminatorRecord.Absent
        }
        if (text.length != SeedDiscriminator.LENGTH_BYTES * 2) return DiscriminatorRecord.Absent
        val bytes = ByteArray(SeedDiscriminator.LENGTH_BYTES)
        for (i in bytes.indices) {
            val hi = Character.digit(text[i * 2], 16)
            val lo = Character.digit(text[i * 2 + 1], 16)
            if (hi < 0 || lo < 0) return DiscriminatorRecord.Absent
            bytes[i] = ((hi shl 4) or lo).toByte()
        }
        return DiscriminatorRecord.Present(bytes)
    }

    /**
     * Write the digest for the seed now being imported.
     *
     * Durable, and durable *before* the caller reports success: a discriminator
     * that is only in the page cache when the process dies leaves a state
     * directory whose owner is unknown. That degrades to `absent` → quarantine,
     * which is safe but is a channel the user then has to sweep by hand, so it
     * is worth one `fsync` to avoid.
     */
    fun write(digest: ByteArray) {
        file.parentFile?.mkdirs()
        file.writeText(SeedDiscriminator.encode(digest))
        Fsync.file(file)
        file.parentFile?.let { Fsync.directory(it) }
    }
}
