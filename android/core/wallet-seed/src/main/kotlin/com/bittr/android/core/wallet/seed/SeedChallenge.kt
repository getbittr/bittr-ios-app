package com.bittr.android.core.wallet.seed

import com.bittr.android.core.wallet.Mnemonic
import java.security.SecureRandom

/**
 * The "type three of your words back" check, ported from `Signup4ViewController`.
 *
 * It is a pure function of the phrase and the three answers, kept out of the
 * composable so the rejection rules can be tested directly. BIT-19 records that the
 * iOS side has no negative coverage on this gate at all — the suite only ever walks
 * the happy path — so the port arrives with the wrong-word cases tested.
 *
 * @param positions the three 0-based indices being asked about, ascending and
 *   distinct, matching how iOS sorts them before labelling the fields.
 */
class SeedChallenge(
    private val mnemonic: Mnemonic,
    val positions: List<Int>,
) {

    init {
        require(positions.size == ASK_COUNT) { "The check asks for $ASK_COUNT words" }
        require(positions.distinct() == positions) { "Positions must be distinct" }
        require(positions.sorted() == positions) { "Positions must be ascending" }
        require(positions.all { it in mnemonic.words.indices }) { "Position out of range" }
    }

    /** 1-based word numbers, which is what the labels show. */
    val labels: List<Int> get() = positions.map { it + 1 }

    /**
     * Check [answers] in field order.
     *
     * The order of the checks is the order iOS reports them in, and it matters: an
     * empty field is a different message from a misspelling, and a misspelling is a
     * different message from the wrong word. Collapsing them into one "try again"
     * would leave a user who typed `abandonn` with no idea why.
     */
    fun check(answers: List<String>): SeedCheck {
        require(answers.size == ASK_COUNT) { "Expected $ASK_COUNT answers" }
        val normalised = answers.map { it.trim().lowercase() }

        if (normalised.any { it.isEmpty() }) return SeedCheck.Missing
        if (normalised.any { !Bip39.isValidWord(it) }) return SeedCheck.NotInWordlist

        val expected = positions.map { mnemonic.words[it] }
        // Deliberately no per-field feedback on a mismatch: saying *which* word was
        // wrong hands a shoulder-surfer two thirds of the check for free, and iOS's
        // incorrectphrase2 copy is careful not to reveal the correct words either.
        return if (normalised == expected) SeedCheck.Correct else SeedCheck.Incorrect
    }

    companion object {
        const val ASK_COUNT = 3

        /** Pick [ASK_COUNT] distinct positions, ascending — `Signup4.setMnemonic()`. */
        fun random(mnemonic: Mnemonic, random: SecureRandom = SecureRandom()): SeedChallenge {
            val positions = sortedSetOf<Int>()
            while (positions.size < ASK_COUNT) {
                positions.add(random.nextInt(mnemonic.words.size))
            }
            return SeedChallenge(mnemonic, positions.toList())
        }
    }
}

/** Outcome of [SeedChallenge.check]. Each case maps to one iOS alert. */
enum class SeedCheck {
    /** At least one field is blank — `missingwords` / `missingwords2`. */
    Missing,

    /** A word is not in the BIP-39 list at all — `invalidwords` / `invalidwords2`. */
    NotInWordlist,

    /** Real words, wrong ones — `incorrectphrase` / `incorrectphrase2`. */
    Incorrect,

    /** All three match. */
    Correct,
}
