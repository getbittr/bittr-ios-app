package com.bittr.android.core.push

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * The wire's `bitcoin_amount` — a **BTC-denominated decimal string** — in msats.
 *
 * The unit is not in the contract's §3.1 field table, which lists the field as `String` and
 * stops; BIT-30 §2(b) pinned it from what iOS actually does:
 * `bitcoinAmountString.toNumber().inSatoshis() * 1000`
 * (`NotificationManager.swift:313-315`, `Extensions/CGFloat.swift:47-54`).
 *
 * This is a money conversion on the payout path, so it is written to match that chain
 * case for case, including the cases where iOS produces zero rather than failing.
 */
object BitcoinAmount {

    /** The 21 M supply, in satoshis. `Bitcoin.maximumSatoshis`, `Extensions/String.swift:312`. */
    const val MAXIMUM_SATOSHIS: Long = 2_100_000_000_000_000L

    private const val SATOSHIS_PER_BITCOIN: Long = 100_000_000L

    private val SATOSHIS_PER_BITCOIN_DECIMAL = BigDecimal(SATOSHIS_PER_BITCOIN)

    /**
     * Parses a machine-written decimal number the way `String.parsedNumber()` does
     * (`ios/bittr/Extensions/String.swift:69-94`): surrounding whitespace trimmed, an
     * optional leading `+`/`-`, then digits and **at most one** separator, which may be
     * either `.` or `,`.
     *
     * Accepting `,` is parity, not preference — iOS accepts it, so a payload that iOS
     * would read must not be one Android drops. The backend should still always emit `.`;
     * a wire format with two candidate separators and no canonical one is a defect waiting
     * for a locale.
     *
     * Returns null when the string is not a number at all. Callers on the payout path
     * ([btcStringToMsats]) turn that into zero because iOS's `toNumber()` does
     * (`String.swift:151-154`).
     */
    fun parsedNumber(raw: String?): BigDecimal? {
        val trimmed = raw?.trim() ?: return null
        if (trimmed.isEmpty()) return null

        val negative = trimmed.first() == '-'
        val body = if (trimmed.first() == '-' || trimmed.first() == '+') trimmed.drop(1) else trimmed

        if (!body.all { it.isDigit() || it == '.' || it == ',' }) return null
        if (body.none { it.isDigit() }) return null
        if (body.count { it == '.' || it == ',' } > 1) return null

        // BigDecimal rather than Double: an 8-decimal bitcoin amount converts to satoshis
        // exactly, instead of picking up a binary rounding error on the way. iOS uses
        // Decimal here for the same reason, then narrows to CGFloat — which is why the two
        // agree at satoshi granularity rather than bit for bit.
        val magnitude = runCatching { BigDecimal(body.replace(',', '.')) }.getOrNull() ?: return null
        return if (negative) magnitude.negate() else magnitude
    }

    /**
     * BTC decimal string to whole satoshis, rounding to the nearest satoshi.
     *
     * Mirrors `CGFloat.inSatoshis()`: anything not strictly positive — unparseable, empty,
     * zero, negative — is 0, and anything at or above the 21 M supply is clamped to it
     * rather than rejected. Neither branch throws. A push whose amount the client cannot
     * read must not crash the FCM service; it must arrive as zero and be reconciled by the
     * next foreground poll, which is BIT-30 §3's "FCM is never the only path" requirement.
     */
    fun btcStringToSatoshis(raw: String?): Long {
        val btc = parsedNumber(raw) ?: return 0L
        if (btc.signum() <= 0) return 0L

        val satoshis = btc.multiply(SATOSHIS_PER_BITCOIN_DECIMAL)
            // HALF_UP on a positive value is Swift's `rounded()`, which rounds half away
            // from zero. The negative half of that difference is unreachable: the signum
            // check above already returned.
            .setScale(0, RoundingMode.HALF_UP)

        val max = BigDecimal(MAXIMUM_SATOSHIS)
        return if (satoshis >= max) MAXIMUM_SATOSHIS else satoshis.toLong()
    }

    /**
     * BTC decimal string to msats — [btcStringToSatoshis] times 1000, which is the
     * multiplication iOS does at `NotificationManager.swift:315`.
     *
     * Long, not Int, throughout: the clamped ceiling alone is 2.1e18 msats, six orders of
     * magnitude past `Int.MAX_VALUE`.
     */
    fun btcStringToMsats(raw: String?): Long = btcStringToSatoshis(raw) * 1_000L
}
