package com.bittr.android.core.common.destination

/**
 * BOLT-11 invoices, to the depth Send actually needs before the engine exists.
 *
 * iOS asks LDK: `isValidInvoice()` is a `bolt11Invoice()` decode, and the amount it
 * shows comes from `amountMilliSatoshis()` (`AddressParsing.swift:38`,
 * `:133-144`). Neither is available here — BIT-6 brings `ldk-node-android` — but
 * neither is needed either, because **the amount lives in the human-readable part**,
 * ahead of the signed payload. `lnbc1500n1p…` says 1500 nano-BTC in its first nine
 * characters.
 *
 * So this validates the bech32 checksum over the whole invoice (which does cover a
 * mis-scanned character anywhere in it) and reads the amount out of the HRP. What
 * it deliberately does *not* do is decode the tagged fields or check the signature:
 * that is the engine's job, and Send will still hand the string to LDK before it
 * pays anything. The contract here is "this is a well-formed invoice for this chain,
 * and it asks for this much" — enough to fill the amount field and pick a rail.
 *
 * BOLT-12 offers (`lno1…`) are **not** handled. iOS accepts them in
 * `isValidInvoice()` but does nothing else with them, and they use a different
 * encoding with no checksum; porting that belongs with the engine, not here.
 */
internal object Bolt11 {

    private const val MSAT_PER_BTC = 100_000_000_000L
    private const val MSAT_PER_SAT = 1_000L

    data class Invoice(
        /** The invoice as it should be handed on, always lower-case. */
        val invoice: String,
        /** The amount the invoice asks for, or `null` if it leaves it open. */
        val amountSats: Long?,
    )

    /**
     * Parses [candidate] as a BOLT-11 invoice for [network], or returns `null`.
     *
     * The `ln` prefix is checked first only as a cheap reject — iOS does the same
     * (`guard self.hasPrefix("ln")`). The checksum is what actually decides.
     */
    fun parse(candidate: String, network: BitcoinNetwork): Invoice? {
        val lowered = candidate.lowercase()
        if (!lowered.startsWith("ln")) return null

        // No length cap: a real invoice is far longer than bech32's 90-character
        // address limit, which is why that limit is a parameter and not a constant.
        val decoded = Bech32.decode(lowered, maxLength = Int.MAX_VALUE) ?: return null
        if (decoded.encoding != Bech32.Encoding.BECH32) return null

        val hrp = decoded.hrp
        if (!hrp.startsWith("ln")) return null

        val afterLn = hrp.substring(2)
        if (!afterLn.startsWith(network.bolt11Prefix)) return null

        // Anything after the currency prefix is the optional amount. If it is present
        // and unparseable, the invoice is malformed — not an invoice with no amount.
        val amountField = afterLn.substring(network.bolt11Prefix.length)
        val amountSats = if (amountField.isEmpty()) {
            null
        } else {
            parseAmountSats(amountField) ?: return null
        }

        return Invoice(invoice = lowered, amountSats = amountSats)
    }

    /**
     * The BOLT-11 amount field: digits, then an optional multiplier.
     *
     * `m` = 0.001 BTC, `u` = 1e-6, `n` = 1e-9, `p` = 1e-12; no multiplier means
     * whole BTC. `p` is only legal in multiples of 10, since a tenth of a millisat
     * cannot be expressed — the spec says so, and rejecting it here keeps a
     * nonsensical invoice from reaching the engine.
     *
     * The result is truncated to whole sats, matching iOS's
     * `Int(invoiceAmountMilli)/1000` (`AddressParsing.swift:40`).
     */
    private fun parseAmountSats(field: String): Long? {
        val last = field.last()
        val hasMultiplier = last in "munp"
        val digits = if (hasMultiplier) field.dropLast(1) else field

        if (digits.isEmpty() || digits.any { it !in '0'..'9' }) return null
        val value = digits.toLongOrNull() ?: return null

        val msat = when {
            !hasMultiplier -> value * MSAT_PER_BTC
            last == 'm' -> value * (MSAT_PER_BTC / 1_000L)
            last == 'u' -> value * (MSAT_PER_BTC / 1_000_000L)
            last == 'n' -> value * (MSAT_PER_BTC / 1_000_000_000L)
            else -> {
                if (value % 10L != 0L) return null
                value / 10L
            }
        }

        return msat / MSAT_PER_SAT
    }
}
