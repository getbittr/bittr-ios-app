package com.bittr.android.feature.send

import com.bittr.android.core.lnurl.LnurlSource

/**
 * An LNURL handed to Send from outside it — today a first-party page's Lightning link in the
 * in-app browser. [source] is what [com.bittr.android.core.lnurl.LnurlSourcePolicy] judges it by.
 *
 * [raw] is a bearer credential for withdraw and auth: never log it, and never put it in a route or
 * a saved-state bundle.
 */
data class SendLnurlRequest(val raw: String, val source: LnurlSource)
