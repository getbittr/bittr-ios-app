package com.bittr.android.navigation

import androidx.lifecycle.SavedStateHandle
import androidx.navigation.NavController
import com.bittr.android.core.common.destination.BitcoinNetwork
import com.bittr.android.core.common.destination.Destination
import com.bittr.android.core.common.destination.DestinationParser

/**
 * How the scanner hands what it read back to whoever opened it.
 *
 * BIT-72 built the scanner and left this half open on purpose: the route's
 * `onScanned` callback called `popBackStack()` and dropped the string, because there
 * was no Send screen to give it to. That is the seam BIT-100 closes — not by
 * inventing a consumer, but by making the scanner *return a value* so the consumer
 * can be written later without touching the scanner again.
 *
 * The result travels in the **previous** back stack entry's [SavedStateHandle],
 * which is the standard Navigation-Compose answer to "a destination needs to return
 * something". The alternative — a callback threaded down from the activity — would
 * put the scanner's caller in `MainActivity`, where it does not belong, and would
 * not survive the process death that Android inflicts on a camera screen more
 * readily than on most.
 *
 * It is a parsed [Destination] rather than the raw string on purpose: parsing
 * belongs to the one entry point both scan and paste go through
 * (`DestinationParser`, from iOS's `AddressParsing.swift:15`). If the raw string
 * travelled instead, the paste control would end up with its own parse call and the
 * two would drift.
 */
object ScannerResult {

    /**
     * Key for the returned [Destination].
     *
     * Namespaced because a `SavedStateHandle` on a back stack entry is shared with
     * whatever else that destination decides to keep there.
     */
    const val KEY = "scanner.destination"

    /**
     * What the scanner route does with a decoded QR: parse it, hand it back, close.
     *
     * A named function rather than a lambda in the navigation graph so that the seam
     * BIT-100 exists to close can be tested directly — `ScannerSeamTest` drives this
     * against a real `NavController` and reads the result out the other side.
     *
     * The order matters. [deliver] writes to `previousBackStackEntry`, so it has to
     * happen **before** the pop: afterwards the scanner's own entry is gone and
     * "previous" means the screen before the caller.
     */
    fun handleScan(navController: NavController, scanned: String, network: BitcoinNetwork) {
        deliver(navController, DestinationParser.parse(scanned, network))
        navController.popBackStack()
    }

    /**
     * Puts [destination] where the screen that opened the scanner will find it.
     *
     * A scan that resolved to [Destination.Unrecognised] is still delivered rather
     * than swallowed. The caller has to show "no bitcoin address found" — iOS's
     * `else` branch (`AddressParsing.swift:71-77`) — and it cannot do that if a
     * failed scan is indistinguishable from the user pressing Back.
     */
    fun deliver(navController: NavController, destination: Destination) {
        navController.previousBackStackEntry
            ?.savedStateHandle
            ?.set(KEY, destination)
    }

    /**
     * Reads and clears a delivered result.
     *
     * Clearing is what stops the same scan being consumed twice — Send recomposes
     * for reasons unrelated to scanning, and a result left in place would refill the
     * address field after the user had cleared it.
     */
    fun consume(savedStateHandle: SavedStateHandle): Destination? =
        savedStateHandle.remove<Destination>(KEY)
}
