package com.bittr.android.feature.home

/**
 * The balance label split into its dimmed and filled halves — `loadBalanceLabel(amount:)`
 * (`LoadWalletData.swift:245`).
 *
 * The amount is written in bitcoin with the decimals grouped `A.BC DEF GHI`. Below one
 * bitcoin, everything up to the first significant digit is dimmed and " sats" is appended,
 * so 384 414 sats reads `₿ 0.00 ` dimmed and `384 414 sats` filled — the leading zeros are
 * there to show scale, not to be read. From one bitcoin up the whole figure is filled and
 * there is no "sats".
 */
internal data class BalanceText(val dimmed: String, val filled: String)

internal fun balanceText(satoshis: Long): BalanceText {
    val sats = satoshis.coerceAtLeast(0)
    val whole = sats / SATS_PER_BITCOIN
    val decimals = (sats % SATS_PER_BITCOIN).toString().padStart(8, '0')
    val grouped = "$whole.${decimals.substring(0, 2)} ${decimals.substring(2, 5)} ${decimals.substring(5)}"

    if (sats >= SATS_PER_BITCOIN) return BalanceText(dimmed = "", filled = "$BITCOIN_SIGN$grouped")

    // No significant digit at all (a zero balance) leaves the last digit filled, as iOS does.
    val firstSignificant = grouped.indexOfFirst { it.isDigit() && it != '0' }.takeIf { it >= 0 } ?: (grouped.length - 1)
    return BalanceText(
        dimmed = BITCOIN_SIGN + grouped.substring(0, firstSignificant),
        filled = grouped.substring(firstSignificant) + " sats",
    )
}

private const val SATS_PER_BITCOIN = 100_000_000L
private const val BITCOIN_SIGN = "₿ "
