package com.bittr.android.core.network

/**
 * Which bittr backend this build talks to — the Android half of iOS's
 * `BittrAPIEnvironment` (`ios/BittrWidget/BittrAPIEnvironment.swift`).
 *
 * **This is the only file in `android/` allowed to hold a bittr API hostname**, and
 * `ApiBaseUrlGuardTest` in `:app` fails the build if a second one appears. iOS makes
 * the same rule the same way, with the "Check hard-coded API URLs" build phase
 * (`ios/Scripts/check-hardcoded-api-urls.sh`).
 *
 * ### Why one file, enforced
 *
 * BIT-32 is filed against three iOS call sites that build their URL from a literal
 * instead of from `EnvironmentConfig`, and one of them matters a lot:
 * `DeviceViewController.swift:283` reads `/notifications`, which is authenticated by
 * a lightning-pubkey signature — so a regtest build reads **production** payout
 * state for whatever pubkey it holds. That is a cross-environment read of real
 * customer data produced by a single hardcoded string.
 *
 * BIT-41 says not to reproduce that on a fresh client. It had already happened:
 * `PriceRepository.kt` shipped `"https://getbittr.com/api/price/btc"` with the Wave
 * 1 screens (BIT-99), so the regtest build was reading the production price API
 * before this module existed. That is the benign end of the same class — an
 * unauthenticated GET — but it is the identical mistake, it arrived without anyone
 * deciding to make it, and the next one would not be a price.
 *
 * ### Why the enum carries a name and `:app` compiles a name
 *
 * `:core:*` modules cannot see `:app`'s `BuildConfig`, so the build type has to be
 * carried across as a value. It is carried as the *name* of a case here rather than
 * as the URL itself, because a `buildConfigField` holding a URL would put a
 * hostname back in a build file — which is what the guard exists to prevent.
 * `BitcoinNetwork.fromBuildConfig` crosses the same boundary the same way.
 */
enum class BittrEnvironment(
    /**
     * Base URL **including** the `/api` path component, matching
     * `BittrAPIEnvironment.baseURL`. Append the endpoint path directly, e.g.
     * `"$apiBaseUrl/customer"` — [url] does that and normalises the join.
     */
    val apiBaseUrl: String,
) {
    /** Debug builds — `com.bittr.android.regtest`, the one Maestro installs. */
    DEVELOPMENT(apiBaseUrl = "https://staging.getbittr.com/api"),

    /** Release builds. Real customers, real money. */
    PRODUCTION(apiBaseUrl = "https://getbittr.com/api"),

    ;

    /**
     * [apiBaseUrl] joined to [path], tolerating a leading slash on the path so call
     * sites can write either form without producing a `//`.
     */
    fun url(path: String): String = "$apiBaseUrl/${path.trimStart('/')}"

    companion object {

        /**
         * Reads the name `:app` compiles into `BuildConfig.BITTR_ENVIRONMENT`.
         *
         * **Throws on an unrecognised value, and deliberately does not mirror
         * [com.bittr.android.core.common.destination.BitcoinNetwork.fromBuildConfig],
         * which falls back to `MAINNET`.** That fallback is justified there by there
         * being a strictest direction: an unknown network name resolving to mainnet
         * refuses test-chain addresses, so the failure is a rejection.
         *
         * Here there is no safe direction, only two different harms. Defaulting to
         * [PRODUCTION] would point a mistyped debug build at the production backend —
         * precisely the BIT-32 harm this type exists to prevent. Defaulting to
         * [DEVELOPMENT] would ship a release build talking to staging, which is worse:
         * customers' signups and payouts would land on the wrong backend and the app
         * would look like it was working.
         *
         * So it fails loudly instead. The value is a constant compiled into the APK,
         * read once at startup, and covered for both variants by
         * `ApiEnvironmentFlagTest` in `:app` — a typo is caught by the test run, not
         * by a customer.
         */
        fun fromBuildConfig(name: String): BittrEnvironment =
            entries.firstOrNull { it.name.equals(name, ignoreCase = true) }
                ?: throw IllegalArgumentException(
                    "Unknown BITTR_ENVIRONMENT '$name'. Expected one of " +
                        "${entries.map { it.name }}. This value is set by a " +
                        "buildConfigField in app/build.gradle.kts and decides which " +
                        "backend the build talks to; there is no safe default to fall " +
                        "back to, so it fails here rather than guessing.",
                )
    }
}
