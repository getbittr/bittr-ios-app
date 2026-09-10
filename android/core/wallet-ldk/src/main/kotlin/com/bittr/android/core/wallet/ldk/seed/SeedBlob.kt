package com.bittr.android.core.wallet.ldk.seed

import android.security.keystore.KeyPermanentlyInvalidatedException
import java.io.FileNotFoundException
import java.security.UnrecoverableKeyException
import javax.crypto.AEADBadTagException

/**
 * What reading the wrapped seed blob told us. Three outcomes, not two.
 *
 * iOS classifies two ways — present, or absent — and treats a Keychain read
 * failure as a hard error that propagates out of the seed import
 * (`CacheManager.readSecretOrThrow`, `:570-576`, called under `try` at `:363`).
 * Android needs a third row, and needs it in a specific direction:
 *
 * | Outcome | Meaning | Action |
 * |---|---|---|
 * | [Present] | blob decrypted | return early, touch nothing (iOS behaviour) |
 * | [NoUsableMnemonic] | alias/blob genuinely gone, or terminally undecryptable | fall through to the identity check |
 * | [TransientFailure] | provider busy/unavailable | **abort the import and retry — never quarantine** |
 *
 * [NoUsableMnemonic] is a deliberate divergence from what iOS actually does, and
 * it is mandated by rule 3: "blob destroyed, state intact" is a routine Android
 * state that must degrade to *restore from mnemonic*. Propagating instead — iOS's
 * real behaviour — would turn rule 3's routine case into "cannot restore", which
 * is loss of access.
 *
 * [TransientFailure] exists because collapsing it into [NoUsableMnemonic] would
 * quarantine live channel state on a single flaky Keystore call. That is the
 * fund-loss outcome arriving by the back door, and it is why the classifier keys
 * on exception *type* rather than on a nullable return.
 */
sealed interface SeedBlobOutcome {

    /** The blob decrypted. [mnemonic] is UTF-8 bytes; callers should [wipe] it. */
    class Present(val mnemonic: ByteArray) : SeedBlobOutcome {
        fun wipe() = mnemonic.fill(0)
    }

    /** No usable mnemonic on this device. Recoverable by re-entering the words. */
    data class NoUsableMnemonic(val reason: Reason) : SeedBlobOutcome {
        enum class Reason { BlobAbsent, KeyAbsent, KeyInvalidated, BlobUndecryptable }
    }

    /** The Keystore could not answer. Not the same as answering "nothing here". */
    data class TransientFailure(val cause: Throwable) : SeedBlobOutcome
}

/**
 * Maps a throwable from the unwrap path onto [SeedBlobOutcome].
 *
 * The `when` below is exhaustive by intent and **has no fallback branch meaning
 * "absent"**. An unrecognised throwable is [SeedBlobOutcome.TransientFailure] —
 * abort and retry. The default has to fail towards *not* quarantining, because
 * the cost of a wrong "absent" is a destroyed channel state and the cost of a
 * wrong "transient" is a retry.
 *
 * This asymmetry is the whole design. Android Keystore signals several unrelated
 * conditions through the same exception classes with different causes, so any
 * classifier that tried to be clever about the boundary would drift over time in
 * the dangerous direction. `TransientKeystoreFailureAbortsTest` asserts that an
 * unrecognised type takes the abort path, so the drift is caught rather than
 * assumed away.
 */
object SeedBlobClassifier {

    fun classify(t: Throwable): SeedBlobOutcome = when (t) {
        // Terminal for the blob: the words are gone from this device, and no
        // amount of retrying brings them back. Recoverable only by re-entry,
        // which is exactly what rule 3 says must happen.
        is KeyPermanentlyInvalidatedException ->
            SeedBlobOutcome.NoUsableMnemonic(SeedBlobOutcome.NoUsableMnemonic.Reason.KeyInvalidated)

        is AEADBadTagException ->
            SeedBlobOutcome.NoUsableMnemonic(SeedBlobOutcome.NoUsableMnemonic.Reason.BlobUndecryptable)

        is UnrecoverableKeyException ->
            SeedBlobOutcome.NoUsableMnemonic(SeedBlobOutcome.NoUsableMnemonic.Reason.KeyAbsent)

        is FileNotFoundException ->
            SeedBlobOutcome.NoUsableMnemonic(SeedBlobOutcome.NoUsableMnemonic.Reason.BlobAbsent)

        // Everything else — KeyStoreException, ProviderException, IOException,
        // anything a future OEM provider invents. Retry; do not touch state.
        else -> SeedBlobOutcome.TransientFailure(t)
    }
}
