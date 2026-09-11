package com.bittr.android.core.wallet.ldk.seed

import android.security.keystore.KeyPermanentlyInvalidatedException
import java.io.FileNotFoundException
import javax.crypto.AEADBadTagException

/**
 * Turns a throwable from the Keystore or the blob file into a
 * [MnemonicPresence].
 *
 * **The rule that matters, from BIT-20 rule 3: the default fails towards *not*
 * quarantining.** The classification is an explicit, exhaustive walk over the
 * exception types known to be terminal for the blob, with **no fallback branch
 * that means "absent"**. An unrecognised throwable is
 * [MnemonicPresence.Unavailable] — abort and retry — never
 * [MnemonicPresence.NoUsableMnemonic].
 *
 * That asymmetry is the whole point. Getting it backwards costs a user their
 * channel balance on a flaky Keystore call; getting it this way round costs
 * them a retry.
 *
 * The Android Keystore makes this easy to get wrong, because it signals several
 * unrelated conditions through the *same* exception class with different
 * causes: a `KeyStoreException` from a busy or unavailable provider is
 * transient, while `AEADBadTagException` and
 * `KeyPermanentlyInvalidatedException` are terminal. So classify on the
 * exception type, and walk the cause chain — the terminal markers routinely
 * arrive wrapped.
 *
 * Proved by `TransientKeystoreFailureAbortsTest`.
 */
internal object SeedVaultFailures {

    fun classify(throwable: Throwable): MnemonicPresence {
        var cursor: Throwable? = throwable
        val seen = HashSet<Throwable>()
        while (cursor != null && seen.add(cursor)) {
            if (isTerminalForTheBlob(cursor)) return MnemonicPresence.NoUsableMnemonic
            cursor = cursor.cause
        }
        return MnemonicPresence.Unavailable(throwable)
    }

    /**
     * The closed list of "this blob will never decrypt again".
     *
     * - [KeyPermanentlyInvalidatedException] — the wrapping key is gone. Under
     *   rule 2 the key is non-auth-bound, so the documented lock-screen
     *   invalidation should not reach us; it is listed because "should not"
     *   is not "cannot", and BIT-18/K1 is what turns that into a measurement.
     * - [AEADBadTagException] — the ciphertext does not authenticate. Truncated
     *   write, bit rot, or a key that is not the key it was wrapped with.
     * - [FileNotFoundException] — no blob. The ordinary fresh-install case.
     *
     * Every one of these routes to the restore screen, which is what BIT-8
     * rule 3 requires of a lost cache.
     */
    private fun isTerminalForTheBlob(throwable: Throwable): Boolean = when (throwable) {
        is KeyPermanentlyInvalidatedException -> true
        is AEADBadTagException -> true
        is FileNotFoundException -> true
        else -> false
    }
}
