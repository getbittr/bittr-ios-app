package com.bittr.android.core.common.destination

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * The single entry point for anything the user scans or pastes into Send.
 *
 * This is the port of `SendViewController.handleScannedOrPastedString`
 * (`AddressParsing.swift:15`). iOS has exactly one of these and both the camera and
 * the paste control feed it; keeping that true on Android is the point of the
 * issue, because a second, subtly different parser behind the paste button is how
 * "it works when I scan but not when I paste" bugs are born.
 *
 * ## What it is not
 *
 * It makes no network calls and touches no node, so every case below is a unit test
 * rather than an emulator run. That is what let BIT-100 land in Wave 1 instead of
 * queueing behind the engine (BIT-6). Two decisions are consequently *deferred to
 * the caller* rather than made here, and both are visible in the returned type:
 *
 * - choosing on-chain over lightning when an invoice exceeds channel capacity
 *   ([Destination.Lightning.onChainFallback]);
 * - fetching an LNURL to find out what it wants ([LnurlTarget.Service]).
 */
object DestinationParser {

    private const val SATS_PER_BTC = 100_000_000L

    /** 21 million BTC in sats — iOS's `Bitcoin.maximumSatoshis` clamp. */
    private const val MAX_SATS = 2_100_000_000_000_000L

    /**
     * The separators iOS splits on before testing each piece
     * (`AddressParsing.swift:87`, `:97`, `:105`).
     *
     * Splitting on `&:?=` is what makes one routine handle a bare address, a
     * `bitcoin:` URI, a `lightning:` URI and a unified BIP-21 QR carrying both rails
     * — every one of them is those tokens separated by those characters. It is
     * cruder than a URI parser and that is a feature: a payee whose QR encodes
     * something almost-but-not-quite well-formed still gets paid.
     */
    private val SEPARATORS = Regex("[&:?=]")

    /** `extractAmount` splits on one character fewer, keeping `=` (`:113`). */
    private val AMOUNT_SEPARATORS = Regex("[&:?]")

    /**
     * Resolves [input] to a [Destination].
     *
     * The precedence — LNURL, then invoice, then on-chain — is iOS's
     * (`AddressParsing.swift:25-77`) and it is the right way round: a unified QR
     * offers the cheapest rail first, and the caller can still fall back because
     * [Destination.Lightning.onChainFallback] carries the address it also found.
     */
    fun parse(input: String, network: BitcoinNetwork): Destination {
        val code = input.trim()
        if (code.isEmpty()) return Destination.Unrecognised

        // The address is looked for in the string **as scanned**, because base58 is
        // case-sensitive. Everything else is looked for lower-cased, because bech32
        // is not — the same split iOS makes at `AddressParsing.swift:19-22`.
        val lowered = code.lowercase()
        val onChainAddress = extractAddress(code, network)
        val invoice = extractInvoice(lowered, network)
        val lnurl = extractLnurl(code)
        val amountSats = extractAmountSats(lowered)

        return when {
            lnurl != null -> Destination.Lnurl(raw = lnurl.raw, target = lnurl.target)

            invoice != null -> Destination.Lightning(
                invoice = invoice.invoice,
                amountSats = invoice.amountSats,
                // iOS keeps the address from a unified QR in `bitcoinQR`
                // (`AddressParsing.swift:58-61`) so Send can switch rails later.
                onChainFallback = onChainAddress?.let { Destination.OnChain(it, amountSats) },
            )

            onChainAddress != null -> Destination.OnChain(
                address = onChainAddress,
                // `if let amount, amount != 0` — a BIP-21 `amount=0` is the same as
                // no amount at all, not an amount of zero (`:66`).
                amountSats = amountSats?.takeIf { it != 0L },
            )

            else -> Destination.Unrecognised
        }
    }

    private fun extractAddress(code: String, network: BitcoinNetwork): String? =
        code.split(SEPARATORS)
            .firstNotNullOfOrNull { BitcoinAddress.normalise(it, network) }

    private fun extractInvoice(lowered: String, network: BitcoinNetwork): Bolt11.Invoice? =
        lowered.split(SEPARATORS)
            .firstNotNullOfOrNull { Bolt11.parse(it, network) }

    /**
     * Finds an LNURL, a lightning address, or a bare LNURL-auth challenge.
     *
     * The first branch is the one iOS does not have. `extractLNURL` only ever looks
     * at the pieces left after splitting on `&:?=`, which shreds a URL —
     * `https://site/?tag=login&k1=…` becomes `https`, `//site/`, `tag`, `login`, `k1`,
     * `…`, and none of those starts with `lnurl`. So the auth branch at
     * `SendLNURL.swift:130` is unreachable from a scan on iOS, and a `lightning:`
     * URI carrying a login challenge simply reports "no bitcoin address found".
     *
     * Testing the whole string before splitting it costs nothing and makes that
     * branch work. It cannot misfire on an ordinary payment QR: it requires both
     * `tag=login` and a `k1` in the query.
     */
    private fun extractLnurl(code: String): Lnurl.Parsed? {
        val whole = Lnurl.parse(code.substringAfter("lightning:", code))
        if (whole != null) return whole

        return code.split(SEPARATORS)
            .filter { Lnurl.looksLikeLnurl(it) }
            .firstNotNullOfOrNull { Lnurl.parse(it) }
    }

    /**
     * The port of `extractAmount` (`AddressParsing.swift:112-118`): the BIP-21
     * `amount` parameter, which is denominated in **BTC**, converted to whole sats.
     *
     * `BigDecimal` rather than a `Double` because the conversion is the one place a
     * rounding error turns into a wrong amount of money: `0.1 + 0.2` arithmetic on
     * `amount=0.00000001` has no business deciding whether the user sends one sat or
     * none. iOS goes through `CGFloat` here and gets away with it; there is no reason
     * to reproduce that.
     */
    private fun extractAmountSats(lowered: String): Long? {
        val field = lowered.split(AMOUNT_SEPARATORS)
            .firstOrNull { it.contains("amount=") }
            ?.replace("amount=", "")
            ?.trim()
            ?: return null

        if (field.isEmpty()) return null

        val btc = field.toBigDecimalOrNull() ?: return null
        if (btc.signum() <= 0) return null

        val sats = btc.multiply(BigDecimal(SATS_PER_BTC))
            .setScale(0, RoundingMode.HALF_UP)
            .toBigInteger()

        return if (sats > BigDecimal(MAX_SATS).toBigInteger()) MAX_SATS else sats.toLong()
    }

    private fun String.toBigDecimalOrNull(): BigDecimal? =
        try {
            BigDecimal(this)
        } catch (_: NumberFormatException) {
            null
        }
}
