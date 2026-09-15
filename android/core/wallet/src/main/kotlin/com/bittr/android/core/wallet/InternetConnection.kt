package com.bittr.android.core.wallet

/**
 * Whether the device is online — iOS's `Reachability.isConnectedToNetwork()`, asked before a
 * pull-to-refresh (`checkInternetConnection()`). `:app` binds it over `ConnectivityManager`.
 */
fun interface InternetConnection {

    fun isConnected(): Boolean

    companion object {
        /** Always online — for previews and tests that don't care. */
        val Always = InternetConnection { true }
    }
}
