package com.bittr.android.core.wallet

/**
 * A BIP-39 recovery phrase.
 *
 * **Deliberately not a `data class`.** A data class would synthesise a [toString]
 * that prints the words, and the one thing that must never reach a log line, a crash
 * report or a `Log.d` left in during debugging is the seed. iOS solves the same
 * problem at the reporting layer (`RedactionManager`); doing it in the type is
 * cheaper and cannot be forgotten at a call site. [words] is still public — the
 * Mnemonic screen has to render it — but you have to ask for it.
 *
 * @param words the phrase in order. 12 or 24 lowercase words, per BIP-39's supported
 *   lengths; bittr issues 12, matching iOS.
 */
class Mnemonic(words: List<String>) {

    val words: List<String> = words.toList()

    init {
        require(this.words.size == 12 || this.words.size == 24) {
            "A BIP-39 phrase is 12 or 24 words, got ${this.words.size}"
        }
        require(this.words.all { it.isNotEmpty() && it == it.lowercase() }) {
            "BIP-39 words are lowercase and non-empty"
        }
    }

    /** The space-separated phrase, which is the form BIP-39 seeds are derived from. */
    val phrase: String get() = words.joinToString(" ")

    /** 1-based, the way the screens and `TestID.Signup.Create.Mnemonic.wordAt` number them. */
    fun wordAt(position: Int): String = words[position]

    override fun equals(other: Any?): Boolean =
        this === other || (other is Mnemonic && other.words == words)

    override fun hashCode(): Int = words.hashCode()

    /** Redacted on purpose — see the class docs. */
    override fun toString(): String = "Mnemonic(${words.size} words, redacted)"
}
