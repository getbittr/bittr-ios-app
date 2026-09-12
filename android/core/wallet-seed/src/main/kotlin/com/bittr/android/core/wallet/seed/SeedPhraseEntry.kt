package com.bittr.android.core.wallet.seed

import com.bittr.android.core.wallet.Mnemonic

/**
 * The twelve-field restore form, as a pure function — `RestoreViewController`'s
 * `restoreButtonTapped` with the UIKit taken out.
 *
 * Sibling of [SeedChallenge], and here for the same reason: whether a phrase is
 * accepted is the one decision on the restore arc that can lose someone their money
 * if it is wrong, so it is decided in pure Kotlin where a unit test can reach it
 * rather than inside a composable where only an emulator can.
 *
 * ### Why the verdicts are finer-grained than the alerts
 *
 * iOS runs one gate here — `BitcoinManager.isValidMnemonic` — and shows one alert
 * (`invalidphrase`) whether the user mistyped a word or typed twelve real words that
 * do not checksum. [check] keeps those apart as [PhraseEntry.NotInWordlist] and
 * [PhraseEntry.ChecksumFailed] because they are genuinely different mistakes and the
 * tests need to name them, but the screen must still collapse both to the iOS copy:
 * splitting the message is a copy change, and copy changes belong to the Designer,
 * not to the port. See `RestoreWalletViewModel.submitPhrase`.
 */
object SeedPhraseEntry {

    /**
     * Read [words] in field order and decide whether they are a phrase.
     *
     * The order of the checks is the order iOS reports them in: a blank field is
     * "you have not finished", not "you are wrong".
     *
     * @param words one entry per field, untrimmed and in whatever case the keyboard
     *   produced. Normalising here rather than at the call site means a stray space
     *   pasted in from a password manager is not a rejection.
     */
    fun check(words: List<String>): PhraseEntry {
        val normalised = words.map { it.trim().lowercase() }

        // iOS checks the count implicitly — there are twelve fields and every one of
        // them has to be non-empty. Both halves are the `incompletephrase` alert.
        if (normalised.size != Bip39.WORD_COUNT) return PhraseEntry.Incomplete
        if (normalised.any { it.isEmpty() }) return PhraseEntry.Incomplete

        if (normalised.any { !Bip39.isValidWord(it) }) return PhraseEntry.NotInWordlist

        // Twelve real words that do not checksum. This is the case that matters most:
        // it is what a single swapped word or a wrong word order looks like, and a
        // wallet that accepted it would derive a different seed and silently show the
        // user an empty balance for a wallet that still has their coins in it.
        val mnemonic = Mnemonic(normalised)
        if (!Bip39.isChecksumValid(mnemonic)) return PhraseEntry.ChecksumFailed

        return PhraseEntry.Accepted(mnemonic)
    }
}

/** Outcome of [SeedPhraseEntry.check]. */
sealed interface PhraseEntry {

    /** A field is blank, or there are not twelve of them — `incompletephrase`. */
    data object Incomplete : PhraseEntry

    /** A word is not in the BIP-39 list at all — shown as `invalidphrase`. */
    data object NotInWordlist : PhraseEntry

    /** Twelve real words whose checksum does not match — shown as `invalidphrase`. */
    data object ChecksumFailed : PhraseEntry

    /**
     * A valid BIP-39 phrase.
     *
     * Accepted, not "correct": on the restore arc there is nothing on the device to
     * be correct against, which is why `restore_wallet.yaml` can bake in a fixed test
     * phrase. Checking an entered phrase against a stored one is the forgot-PIN path,
     * and it belongs with that screen.
     */
    class Accepted(val mnemonic: Mnemonic) : PhraseEntry
}
