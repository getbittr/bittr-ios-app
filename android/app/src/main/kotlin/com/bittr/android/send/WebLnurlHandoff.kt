package com.bittr.android.send

import androidx.lifecycle.ViewModel
import com.bittr.android.feature.send.SendLnurlRequest
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.concurrent.atomic.AtomicReference
import javax.inject.Inject
import javax.inject.Singleton

/**
 * An LNURL on its way from the in-app browser to Send.
 *
 * In memory only, and taken once. A withdraw or auth LNURL is a bearer credential, so it is not
 * put in a navigation route or a saved-state bundle, both of which can be written to disk.
 */
@Singleton
class WebLnurlHandoff @Inject constructor() {

    private val pending = AtomicReference<SendLnurlRequest?>(null)

    fun post(request: SendLnurlRequest) {
        pending.set(request)
    }

    /** The waiting request, if any, which is then gone. */
    fun take(): SendLnurlRequest? = pending.getAndSet(null)
}

/** How the navigation graph reaches [WebLnurlHandoff]. */
@HiltViewModel
class WebLnurlViewModel @Inject constructor(val handoff: WebLnurlHandoff) : ViewModel()
