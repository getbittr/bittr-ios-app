package com.bittr.android.feature.map

import org.json.JSONArray
import org.json.JSONObject

/**
 * A place that accepts bitcoin, as BTCMap publishes it.
 *
 * Ported field for field from `ios/bittr/Map/BitcoinPlace.swift`. The coordinate
 * fields keep BTCMap's own short names rather than being spelled out, because that
 * is what the API returns and this type is the decode of that response; the map
 * screen converts them to the renderer's type at the edge.
 */
internal data class BitcoinPlace(
    val id: Int,
    val lat: Double?,
    val lon: Double?,
    val icon: String?,
    val name: String?,
    val address: String?,
    val updatedAt: String?,
    val deletedAt: String?,
    val website: String?,
    val openingHours: String?,
) {

    /** A place with no position cannot be drawn or sorted; iOS skips those too. */
    val hasPosition: Boolean get() = lat != null && lon != null
}

/**
 * The BTCMap request. **Its shape is a compliance constraint, not an optimisation.**
 *
 * Three parameters: which fields to return, whether tombstones are included, and how
 * far back to sync from. No position of any kind. That is what lets the approved
 * alert (`shared/strings/en.json`, `mapvcpoweredbyalert`) say the phone downloads
 * the whole list and picks the nearby ones out itself — the claim is about this URL,
 * and it was checked against this URL on BIT-70.
 *
 * Narrowing the request to the part of the world on screen is cheaper, renders
 * identically, and would make that sentence false. `MapSdkGuardTest` fails the build
 * for it; read `shared/strings/README.md` before deciding this file is the place to
 * optimise.
 */
internal fun bitcoinMapUrl(updatedSince: String?, includeDeleted: Boolean): String {
    val fields = listOf(
        "id", "lat", "lon", "icon", "name", "address",
        "website", "opening_hours", "updated_at", "deleted_at",
    ).joinToString(",")

    val query = buildString {
        append("fields=").append(fields)
        append("&include_deleted=").append(if (includeDeleted) "true" else "false")
        if (updatedSince != null) append("&updated_since=").append(updatedSince)
    }
    return "$BTC_MAP_PLACES_ENDPOINT?$query"
}

private const val BTC_MAP_PLACES_ENDPOINT = "https://api.btcmap.org/v4/places"

/** Decodes the array the places endpoint returns, skipping anything malformed. */
internal fun parsePlaces(json: String): List<BitcoinPlace> {
    val array = JSONArray(json)
    return (0 until array.length()).mapNotNull { index ->
        array.optJSONObject(index)?.let(::parsePlace)
    }
}

private fun parsePlace(item: JSONObject): BitcoinPlace? {
    if (!item.has("id")) return null
    return BitcoinPlace(
        id = item.optInt("id"),
        lat = item.optDoubleOrNull("lat"),
        lon = item.optDoubleOrNull("lon"),
        icon = item.optStringOrNull("icon"),
        name = item.optStringOrNull("name"),
        address = item.optStringOrNull("address"),
        updatedAt = item.optStringOrNull("updated_at"),
        deletedAt = item.optStringOrNull("deleted_at"),
        website = item.optStringOrNull("website"),
        openingHours = item.optStringOrNull("opening_hours"),
    )
}

/** Re-encodes the cache. Same field names, so a cache file round-trips through [parsePlaces]. */
internal fun encodePlaces(places: List<BitcoinPlace>): String {
    val array = JSONArray()
    places.forEach { place ->
        array.put(
            JSONObject().apply {
                put("id", place.id)
                place.lat?.let { put("lat", it) }
                place.lon?.let { put("lon", it) }
                place.icon?.let { put("icon", it) }
                place.name?.let { put("name", it) }
                place.address?.let { put("address", it) }
                place.updatedAt?.let { put("updated_at", it) }
                place.deletedAt?.let { put("deleted_at", it) }
                place.website?.let { put("website", it) }
                place.openingHours?.let { put("opening_hours", it) }
            },
        )
    }
    return array.toString()
}

/**
 * Folds a sync response into the cached set.
 *
 * Ported from `BitcoinPlacesCache.applySyncedPlaces`. An incremental sync asks for
 * tombstones, so a row carrying `deleted_at` is a removal rather than an update — a
 * closed shop that keeps being drawn is the bug this avoids.
 */
internal fun applySyncedPlaces(
    synced: List<BitcoinPlace>,
    cached: List<BitcoinPlace>,
): List<BitcoinPlace> {
    val byId = cached.associateByTo(LinkedHashMap()) { it.id }
    synced.forEach { place ->
        if (place.deletedAt != null) byId.remove(place.id) else byId[place.id] = place
    }
    return byId.values.toList()
}

/**
 * The watermark the next incremental sync asks from: the newest `updated_at` in the
 * response, or null when the response carried none.
 *
 * iOS only advances it once the merged set is on disk (`BitcoinPlace.swift:196-203`)
 * — a watermark written before a failed save means the places between the two syncs
 * are never fetched again.
 */
internal fun newestUpdatedAt(synced: List<BitcoinPlace>): String? =
    synced.mapNotNull { it.updatedAt }.maxOrNull()

/**
 * The places within [radiusKm] of the point the map is centred on, nearest first.
 *
 * This is the filter the shipped copy rests on: the whole dataset is in memory and
 * the proximity test happens here, in the app, on a value that never leaves it.
 * iOS's two passes (`nearbyBTCPlaces` then `sortByProximity`) are one pass here —
 * they are called together at the only call site.
 *
 * @param limit iOS caps at 200 (`MapVCLocations.swift:113`). Zoomed all the way out,
 *   the default region matches thousands of places, and drawing a marker for each
 *   plus reloading the list freezes the screen.
 */
internal fun List<BitcoinPlace>.nearby(
    centerLat: Double,
    centerLon: Double,
    radiusKm: Double,
    limit: Int = MAX_VISIBLE_PLACES,
): List<BitcoinPlace> =
    asSequence()
        .filter { it.hasPosition }
        .map { it to distanceKm(centerLat, centerLon, it.lat!!, it.lon!!) }
        .filter { (_, distance) -> distance <= radiusKm }
        .sortedBy { (_, distance) -> distance }
        .take(limit)
        .map { (place, _) -> place }
        .toList()

internal const val MAX_VISIBLE_PLACES = 200

/**
 * Great-circle distance in kilometres.
 *
 * iOS gets this from `CLLocation.distance(from:)`; there is no platform equivalent
 * that does not want a `Location` object per point, and this runs over the whole
 * dataset on every map move.
 */
internal fun distanceKm(aLat: Double, aLon: Double, bLat: Double, bLon: Double): Double {
    val earthRadiusKm = 6371.0088
    val dLat = Math.toRadians(bLat - aLat)
    val dLon = Math.toRadians(bLon - aLon)
    val h = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(Math.toRadians(aLat)) * Math.cos(Math.toRadians(bLat)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2)
    return 2 * earthRadiusKm * Math.asin(Math.min(1.0, Math.sqrt(h)))
}

private fun JSONObject.optStringOrNull(key: String): String? =
    if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }

private fun JSONObject.optDoubleOrNull(key: String): Double? =
    if (isNull(key)) null else optDouble(key).takeIf { !it.isNaN() }
