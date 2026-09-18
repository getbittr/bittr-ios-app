package com.bittr.android.feature.map

/**
 * The map's own glyphs, as 24-unit SVG path data drawn with `rememberStrokeIcon` — the
 * same form as the design system's `BittrIconPaths`, kept here because nothing outside
 * this screen draws a fork or a bed. Drawn to the silhouette of the Material symbol the
 * design review named, not copied from it, except [MY_LOCATION], which is Material's
 * `my_location` (Apache 2.0) as the review asked for it by name — a filled path, so it is
 * drawn with `rememberFillIcon`.
 */
internal object MapIconPaths {
    const val FOOD = "M6 3v6a2 2 0 004 0V3 M8 3v18 M17 21V3c-2 1.5-3 4-3 8h3"
    const val LODGING = "M3 6v13 M3 15h18v4 M21 15v-3a3 3 0 00-3-3h-8v6 M5.5 11a1.5 1.5 0 103 0 1.5 1.5 0 10-3 0z"
    const val SHOP = "M5 8h14l-1 12H6z M9 8V6a3 3 0 016 0v2"
    const val PIN = "M12 21s-6-5.6-6-11a6 6 0 0112 0c0 5.4-6 11-6 11z M12 7.5a2.5 2.5 0 100 5 2.5 2.5 0 000-5z"
    const val CLOCK = "M12 3a9 9 0 100 18 9 9 0 000-18z M12 7v5l3 2"

    /**
     * The mark inside every pin: a B on a spine, with the two ticks above and below.
     * A path rather than the `₿` character, because U+20BF is missing from older system
     * fonts and a tofu box on every pin is the failure that would cause.
     */
    const val BITCOIN =
        "M8 5.5h5.2a3.1 3.1 0 010 6.2H8z M8 11.7h6a3.4 3.4 0 010 6.8H8z M8 5.5v13 " +
            "M10 3.5v2 M13 3.5v2 M10 18.5v2 M13 18.5v2"

    const val MY_LOCATION =
        "M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm8.94 3c-.46-4.17-3.77-7.48-7.94-7.94V1h-2v2.06" +
            "C6.83 3.52 3.52 6.83 3.06 11H1v2h2.06c.46 4.17 3.77 7.48 7.94 7.94V23h2v-2.06c4.17-.46 7.48-3.77 " +
            "7.94-7.94H23v-2h-2.06zM12 19c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z"
}

/**
 * The few icons a place row can carry. iOS maps ~40 BTCMap slugs to SF Symbols
 * (`iconName()` in `PlaceCategories.swift`); the review asked for four, which is what a
 * 20 dp glyph beside a name can usefully distinguish.
 */
internal enum class PlaceGlyph(val path: String) {
    FOOD(MapIconPaths.FOOD),
    LODGING(MapIconPaths.LODGING),
    SHOP(MapIconPaths.SHOP),
    DEFAULT(MapIconPaths.PIN),
}

/** BTCMap's icon slug → [PlaceGlyph]. Grouped as [categoryDescription] groups them. */
internal fun placeGlyph(icon: String?): PlaceGlyph = when (icon) {
    "local_cafe", "restaurant", "local_dining", "lunch_dining", "local_pizza",
    "local_bar", "sports_bar", "cake", "icecream",
    -> PlaceGlyph.FOOD

    "hotel", "cottage" -> PlaceGlyph.LODGING

    "shopping_cart", "store", "supermarket", "storefront", "local_grocery_store",
    "card_giftcard", "liquor", "computer", "smartphone", "pedal_bike",
    -> PlaceGlyph.SHOP

    else -> PlaceGlyph.DEFAULT
}
