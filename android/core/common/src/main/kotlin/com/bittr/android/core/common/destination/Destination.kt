package com.bittr.android.core.common.destination

import java.io.Serializable

/**
 * What a scanned or pasted string turned out to be.
 *
 * On iOS there is no such type: `handleScannedOrPastedString` writes straight into
 * `toTextField`, `amountTextField`, `onchainOrLightning` and `bitcoinQR`
 * (`AddressParsing.swift:15-81`), so "what was scanned" only ever exists as a
 * scattering of view state. That is precisely why a QR arriving from the scanner
 * route on Android had nowhere to go except `popBackStack()`.
 *
 * Making the answer a value has one concrete consequence worth stating: the parser
 * can be tested without a screen, a camera or a node, which is the whole reason
 * BIT-100 could be done in Wave 1 instead of waiting behind BIT-6.
 *
 * [Serializable] so it survives a trip through `SavedStateHandle` — see
 * `ScannerResult`.
 */
sealed interface Destination : Serializable {

    /**
     * A bitcoin address, optionally with an amount a BIP-21 URI asked for.
     *
     * @param amountSats iOS only fills the amount field when the parsed amount is
     *   non-zero (`if let amount, amount != 0`, `AddressParsing.swift:66`), so
     *   `bitcoin:addr?amount=0` lands here as `null` rather than `0`.
     */
    data class OnChain(
        val address: String,
        val amountSats: Long? = null,
    ) : Destination

    /**
     * A BOLT-11 invoice, plus the on-chain address a unified QR offered alongside it.
     *
     * [onChainFallback] is the port of a decision this parser deliberately does not
     * make. iOS re-routes to the on-chain address when the invoice asks for more
     * than the channel can send:
     *
     * ```swift
     * if invoiceAmount > availableLightningBalance, bitcoinAddress != nil {
     *     self.handleScannedOrPastedString(bitcoinAddress!)
     * ```
     * (`AddressParsing.swift:43-48`)
     *
     * That needs `outboundCapacityMsat` — the engine, which is BIT-6. So the parser
     * reports both rails and Send picks, rather than the parser pretending to know a
     * balance. Keeping it visible in the type is what stops the fallback being
     * quietly forgotten when Send is built.
     */
    data class Lightning(
        val invoice: String,
        val amountSats: Long? = null,
        val onChainFallback: OnChain? = null,
    ) : Destination

    /** An LNURL, a lightning address, or an LNURL-auth challenge. */
    data class Lnurl(
        val raw: String,
        val target: LnurlTarget,
    ) : Destination

    /**
     * Nothing usable. iOS's `else` branch: clear both fields and show
     * "no bitcoin address found" (`AddressParsing.swift:71-77`).
     *
     * A distinct case rather than a `null` return because the caller has to *do*
     * something — the alert is part of the flow, and an optional invites a silent
     * `?.let` that shows the user nothing at all.
     */
    data object Unrecognised : Destination
}

/** Where an LNURL points once decoded. See [Lnurl] for the case-sensitivity note. */
sealed interface LnurlTarget : Serializable {

    /**
     * LNURL-auth (`tag=login`): a challenge to sign, not a payment.
     *
     * Separate from [Service] because it is the one LNURL that must never be fetched
     * blind — iOS shows a confirmation sheet first (`showLNURLAuthConfirmation`,
     * `SendLNURL.swift:160`) and the k1 is signed with the wallet key.
     */
    data class Auth(val callbackUrl: String, val k1Hex: String, val action: String?) : LnurlTarget

    /**
     * Anything else — pay, withdraw, channel. Which one it is arrives in the
     * response body, so it cannot be decided without a network call.
     */
    data class Service(val url: String) : LnurlTarget
}
