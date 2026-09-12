package com.bittr.android.feature.map

/**
 * BTCMap's icon slug → the words the place sheet shows.
 *
 * Ported from `categoryDescription()` in `ios/bittr/Map/PlaceCategories.swift`,
 * entry for entry and with the same default: an unrecognised slug reads "Business"
 * rather than the raw slug, so a new BTCMap category shows something sensible
 * instead of `vaping_rooms`.
 *
 * The sibling `iconName()` is deliberately **not** ported: it maps to SF Symbols,
 * which do not exist here, and inventing an Android icon set for 40 categories is
 * design work rather than transcription. The sheet shows the words until it has one.
 */
internal fun categoryDescription(icon: String?): String = when (icon) {
    // Food & drink
    "local_cafe" -> "Café"
    "restaurant", "local_dining" -> "Restaurant"
    "lunch_dining" -> "Eatery"
    "local_pizza" -> "Pizza place"
    "local_bar" -> "Bar"
    "sports_bar" -> "Sports bar"
    "cake" -> "Bakery"
    "icecream" -> "Ice cream shop"
    "liquor" -> "Liquor store"

    // Stay
    "hotel" -> "Hotel"
    "cottage" -> "Accommodation"

    // Bitcoin / finance
    "local_atm" -> "Bitcoin ATM"
    "account_balance" -> "Financial services"

    // Retail
    "shopping_cart", "store", "supermarket" -> "Shop"
    "storefront" -> "Store"
    "local_grocery_store" -> "Grocery store"
    "card_giftcard" -> "Gift shop"
    "business" -> "Business"

    // Health & beauty
    "spa" -> "Spa"
    "medical_services" -> "Medical services"
    "fitness_center" -> "Gym"
    "content_cut" -> "Hairdresser"

    // Vehicles & transport
    "directions_car" -> "Car dealer"
    "car_repair" -> "Car repair"
    "commute" -> "Transport"
    "luggage" -> "Travel services"

    // Tech
    "computer" -> "Computer store"
    "smartphone" -> "Phone shop"

    // Outdoor & leisure
    "pedal_bike" -> "Bike shop"
    "pool" -> "Watersports"
    "grass" -> "Garden services"

    // Education & work
    "school" -> "School"
    "group" -> "Community"
    "engineering" -> "Engineering"
    "design_services" -> "Design services"
    "palette" -> "Art"

    // Misc
    "visibility" -> "Optical services"
    "question_mark" -> "Business"
    "sports_soccer" -> "Sports club"
    "vaping_rooms" -> "Vape shop"

    else -> "Business"
}

/**
 * The website as the sheet shows it: scheme and `www.` stripped, no trailing slash.
 *
 * Ported from `showWebsite` (`OnePlaceViewController.swift:79-89`). The stripping is
 * display only — the in-app browser is handed the original string, because
 * `example.com` with no scheme is not a URL a `WebView` will load.
 */
internal fun displayWebsite(website: String): String =
    website
        .removePrefix("https://")
        .removePrefix("http://")
        .removePrefix("www.")
        .removeSuffix("/")
