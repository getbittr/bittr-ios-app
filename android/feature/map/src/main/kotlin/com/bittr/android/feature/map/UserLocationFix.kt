package com.bittr.android.feature.map

import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.bittr.android.core.permissions.BittrPermissions
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * One position fix, for centring the map — and **one is the whole design**.
 *
 * iOS calls `requestLocation()` and centres once (`MapVCLocations.swift:38, 47,
 * 190`). Compliance corrected the approved rationale from "it just won't *follow*
 * you" to "it just won't *centre* on you" precisely because of that, so a
 * subscription here would not merely be a different implementation — it would
 * re-open a wording that has already been signed off. `LocationEgressGuardTest`
 * fails the build for the subscription APIs.
 *
 * The permission asked for is [BittrPermissions.LOCATION], which is coarse and only
 * coarse. That is what keeps "bittr needs your approximate location" true whatever
 * the user taps, and it is also why the provider below is the network one: the
 * precise provider would be refused by a coarse grant anyway.
 */
internal object UserLocationFix {

    /** Whether the coarse permission has been granted. */
    fun isPermitted(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, BittrPermissions.LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    fun isAvailable(context: Context): Boolean {
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        return manager?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
    }

    /**
     * A single fix, or null when there is none to be had.
     *
     * Null is an ordinary outcome, not an error: an emulator with no simulated
     * position, a device indoors with the radio cold, a denied permission. The
     * caller falls back to the default region, which is exactly what
     * `showDefaultSwitzerlandRegion` is for.
     */
    @Suppress("MissingPermission")
    suspend fun current(context: Context): Location? {
        if (!isPermitted(context)) return null
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null

        // `getCurrentLocation` is the single-shot API and arrived in API 30. Below
        // that, the last known fix is the only non-subscribing option — and it is the
        // honest one: it reads a value the system already has rather than starting
        // anything.
        val lastKnown = runCatching {
            manager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
        }.getOrNull()

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return lastKnown

        return suspendCancellableCoroutine { continuation ->
            val signal = android.os.CancellationSignal()
            continuation.invokeOnCancellation { signal.cancel() }
            runCatching {
                manager.getCurrentLocation(
                    LocationManager.NETWORK_PROVIDER,
                    signal,
                    ContextCompat.getMainExecutor(context),
                ) { fix -> if (continuation.isActive) continuation.resume(fix ?: lastKnown) }
            }.onFailure { if (continuation.isActive) continuation.resume(lastKnown) }
        }
    }
}
