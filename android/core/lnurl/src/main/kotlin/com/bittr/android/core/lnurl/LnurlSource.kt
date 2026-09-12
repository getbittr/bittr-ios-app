package com.bittr.android.core.lnurl

/**
 * Where an LNURL came from.
 *
 * **This type is the whole point of BIT-33 (R-5).** Read the reasoning before
 * changing it, because the obvious simplification here re-opens a fund-loss hole.
 *
 * On iOS `handleLNURL` is a `UIViewController` extension shared by the Send screen
 * and the in-app browser, and every downstream step begins
 * `let sendVC = self as? SendViewController`. Called from `WebsiteViewController`
 * that downcast is nil, so `sendPayRequest` fetches an invoice and then calls
 * `sendVC?.checkSendLightning()` — and nothing happens. **The web-originated pay
 * path is inert on iOS purely by accident.** Nothing states the rule, nothing
 * tests it, and the control it stands in for does not exist: at
 * `SendLNURL.swift:243–247`, when `minSendable == maxSendable` the code goes
 * straight to paying with no amount entry and no confirmation.
 *
 * The idiomatic Kotlin port is one handler shared by Send and the browser. There
 * is no nil to save it. So the source is carried as a value instead of being
 * implied by which object happens to be `this`, and [LnurlSourcePolicy] decides
 * against it explicitly for pay, withdraw and auth.
 *
 * ### Note what is *not* here
 *
 * There is no `ThirdPartyWeb`. That is not an omission — it is R-2 expressed in
 * the type system. A third-party page (a BTCMap `website`, the block explorer,
 * anything reached by navigation from either) has no way to produce an
 * `LnurlSource`, because no bridge is attached to it and its `lightning:`/`lnurl`
 * navigations are cancelled and dropped rather than parsed. Adding a variant for
 * it would be the change that ships the hole.
 */
sealed interface LnurlSource {

    /** The user pointed the camera at a QR code. A deliberate physical act. */
    data object QrScan : LnurlSource

    /** The app was opened by a `lightning:` link from outside. */
    data object Deeplink : LnurlSource

    /**
     * A page on a first-party origin handed us an LNURL through the in-app
     * browser's message bridge.
     *
     * **No such bridge ships in v1** — see `FirstPartyOrigins` in
     * `:feature:website` and the DEV-56 note in `shared/docs/parity.md`. This
     * variant exists so that the policy below is already written, tested and
     * enforced if the bridge is ever added, rather than being designed under
     * time pressure by whoever adds it.
     *
     * @param origin the scheme-and-host the message actually arrived from, e.g.
     *   `https://getbittr.com`. Never a value a page supplied about itself —
     *   only what the WebView reported. R-9 requires it be shown to the user
     *   verbatim in the auth dialog.
     * @param pageTitle the title of the page making the request, for naming it
     *   in that dialog. Attacker-controlled text; display it as untrusted.
     */
    data class FirstPartyWeb(
        val origin: String,
        val pageTitle: String?,
    ) : LnurlSource
}

/** The three things an LNURL can ask the wallet to do. */
enum class LnurlAction {
    /** LNURL-pay — funds leave the wallet. */
    Pay,

    /** LNURL-withdraw — funds arrive, but a signed invoice is handed to a stranger. */
    Withdraw,

    /** LNURL-auth — the wallet's key signs a challenge, proving identity. */
    Auth,
}

/** Whether a given [LnurlAction] may proceed from a given [LnurlSource]. */
sealed interface LnurlPermission {

    data object Allowed : LnurlPermission

    /**
     * @param reason user-facing, and written to be read by a user rather than a
     *   log: it is the message shown when a page tries something it may not.
     */
    data class Denied(val reason: String) : LnurlPermission
}

/**
 * The source check every LNURL action passes through (R-5).
 *
 * One function, one `when` per action, no defaults — so a new [LnurlSource] or a
 * new [LnurlAction] fails to compile until someone has decided what it may do.
 * That is the only property here worth defending: the failure mode this replaces
 * is a shared handler that silently inherits whatever the last caller was allowed
 * to do.
 */
object LnurlSourcePolicy {

    /**
     * Deny messages are deliberately concrete about *why*, because the alternative
     * — "something went wrong" — is what makes a security control get relaxed six
     * months later by someone who cannot tell it apart from a bug.
     */
    private const val WEB_PAY_DENIED =
        "This page tried to start a Lightning payment. Payments can only be " +
            "started by scanning a code or opening a Lightning link yourself."

    private const val WEB_WITHDRAW_DENIED =
        "This page tried to start a Lightning withdrawal. Withdrawals can only " +
            "be started by scanning a code yourself."

    fun permit(action: LnurlAction, source: LnurlSource): LnurlPermission = when (action) {
        // R-4, final sentence: web-originated LNURLs must not reach the pay path
        // in v1. This is the line that makes the Android port no worse than the
        // accident that protects iOS.
        LnurlAction.Pay -> when (source) {
            LnurlSource.QrScan, LnurlSource.Deeplink -> LnurlPermission.Allowed
            is LnurlSource.FirstPartyWeb -> LnurlPermission.Denied(WEB_PAY_DENIED)
        }

        // Not spelled out in BIT-33, so this is the conservative reading and it is
        // flagged on the issue rather than buried here. LNURL-withdraw brings funds
        // in, which sounds harmless, but it hands a stranger's callback a wallet
        // invoice on a page's initiative and it is the half of the LNURL surface
        // with no confirmation requirement written for it. Nothing in v1 needs it
        // from a web page; if a first-party page ever does, this is a one-line
        // change made on purpose with a confirmation designed alongside it.
        LnurlAction.Withdraw -> when (source) {
            LnurlSource.QrScan, LnurlSource.Deeplink -> LnurlPermission.Allowed
            is LnurlSource.FirstPartyWeb -> LnurlPermission.Denied(WEB_WITHDRAW_DENIED)
        }

        // R-9: web-originated auth is first-party-only. The type system already
        // guarantees that — there is no third-party web source to deny — so the
        // remaining obligation is on the dialog, which must show the full callback
        // origin and name the requesting page. See LnurlAuthPrompt.
        LnurlAction.Auth -> when (source) {
            LnurlSource.QrScan, LnurlSource.Deeplink -> LnurlPermission.Allowed
            is LnurlSource.FirstPartyWeb -> LnurlPermission.Allowed
        }
    }
}
