package com.bittr.android.feature.map

/**
 * The map's user-visible words.
 *
 * Two of these are not ordinary copy and must not be edited here.
 * [POWERED_BY] and [POWERED_BY_ALERT] are the **only** strings in either app that
 * already live in `shared/strings/en.json` (BIT-56), because they carry a privacy
 * representation that went through a compliance read (BIT-69) and a factual check
 * against the code (BIT-70). `shared/strings/README.md` records the review trail and
 * two standing conditions on future edits.
 *
 * They are duplicated here rather than read from the JSON because the generator that
 * turns `shared/strings/` into `strings.xml` does not exist yet — the README says so
 * and says to keep the copies identical by hand until it does. `SharedStringsTest`
 * asserts that character for character, so the duplication cannot drift silently.
 *
 * The rest are iOS `Language.swift` entries, carried across with their ids for the
 * BIT-12 migration, as `ScannerCopy` does.
 */
internal object MapCopy {

    object Id {
        const val TITLE = "paywithbitcoin"
        const val TOP_LABEL = "mapvctoplabel"
        const val POWERED_BY = "mapvcpoweredby"
        const val POWERED_BY_ALERT = "mapvcpoweredbyalert"
        const val NO_PLACES = "noplaces"
        const val PLACES_ERROR = "placeserror"
        const val LOCATION_UNAVAILABLE = "locationunavailable"
        const val OPEN_IN_MAPS = "openinmaps"
        const val UNAVAILABLE = "unavailable"
        const val OOPS = "oops"
        const val OKAY = "okay"
        const val CLOSE = "close"
    }

    const val TITLE: String = "Pay with bitcoin"

    const val TOP_LABEL: String = "Find spots in your area that accept bitcoin payments."

    /** `shared/strings/en.json`. Do not edit — see the class doc. */
    const val POWERED_BY: String = "Powered by BTCMap.org"

    /** `shared/strings/en.json`. Do not edit — see the class doc. */
    const val POWERED_BY_ALERT: String =
        "<b>BTCMap.org</b> uses OpenStreetMap to tag places that accept bitcoin, and " +
            "display those merchants in their beautiful apps.<br><br>Their apps and the " +
            "underlying data are free and open-source.<br><br>Your phone downloads the " +
            "whole list of places and picks out the nearby ones itself, so your location " +
            "is never sent to bittr or to BTCMap.org.<br><br>Drawing the map is the part " +
            "that leaves your phone: it fetches map images a screen at a time, so whoever " +
            "serves them sees the area you are looking at — and if you allow location, " +
            "that starts with the area around you."

    const val NO_PLACES: String =
        "There seem to be no businesses in this area that accept bitcoin payments."

    const val PLACES_ERROR: String =
        "We could not download map data at this time. Please try again later."

    /**
     * iOS's wording names the iOS settings path. Android's is different, and BIT-57
     * settled that the permanently-denied copy names the Android path — `AppSettings`
     * in `:core:permissions` owns the deep link it sends the user to.
     */
    const val LOCATION_UNAVAILABLE: String =
        "Your location details are unavailable to us.\n\nOn your device, open " +
            "<b>Settings > Apps > Bittr > Permissions</b> to check your location permissions."

    const val OPEN_IN_MAPS: String = "Open in Maps"
    const val UNAVAILABLE: String = "Unavailable"
    const val OOPS: String = "Oops!"
    const val OKAY: String = "Okay"
    const val CLOSE: String = "Close"
    const val PLACE_FALLBACK_NAME: String = "Bitcoin place"
}
