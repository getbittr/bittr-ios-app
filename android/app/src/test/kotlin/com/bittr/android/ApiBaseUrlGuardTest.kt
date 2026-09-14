package com.bittr.android

import com.bittr.android.SourceTree.code
import com.bittr.android.SourceTree.repoPath
import java.util.regex.Pattern
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Keeps every bittr **API** base URL in one file (BIT-41 item 1).
 *
 * The Android half of iOS's "Check hard-coded API URLs" build phase
 * (`ios/Scripts/check-hardcoded-api-urls.sh`), and it exists for the same reason
 * that phase does: BIT-32 is filed against three iOS call sites that build a URL
 * from a literal instead of from `EnvironmentConfig`, and one of them —
 * `DeviceViewController.swift:283`, reading `/notifications` — is authenticated by
 * a lightning-pubkey signature. A regtest build with that literal reads
 * **production** payout state for whatever pubkey it holds. One string, one
 * cross-environment read of real customer data.
 *
 * ### This is a regression test, not a precaution
 *
 * It had already happened here. `PriceRepository.kt` shipped
 * `"https://getbittr.com/api/price/btc"` as a private constant with the Wave 1
 * screens (BIT-99), so `com.bittr.android.regtest` was reading the production price
 * API. BIT-41's brief says in as many words not to reproduce BIT-32 on a fresh
 * client; it was reproduced before this module existed, by a screen ported from one
 * of the three BIT-32 call sites, without anyone deciding to.
 *
 * Price is the harmless end — an unauthenticated GET. That is the point. The
 * mistake is invisible at review (the URL is *correct*, for one of the two builds),
 * invisible at runtime (the screen works, with real data), and the next endpoint
 * ported this way is `/customer` or `/notifications`.
 *
 * ### What counts as an offence
 *
 * A bittr **API** URL, not any getbittr.com string. The repo legitimately holds
 * plenty of the latter: `getbittr.com` is a lightning-address domain all over
 * `:core:lnurl`'s tests, and Settings opens three getbittr.com pages in a WebView.
 * Those are not backend endpoints and switching environment does not change them.
 * So [API_URL] matches the shape that *is* environment-dependent — a bittr host
 * with an `/api` path — plus the staging host by name, since anything naming that
 * is by definition environment-specific.
 *
 * The WebView page URLs are a real and separate question (should the regtest build
 * open staging's privacy policy?) and deliberately not answered here. They are
 * content, not contract; BIT-112 owns them.
 */
class ApiBaseUrlGuardTest {

    private companion object {

        /**
         * The one file allowed to hold a bittr API hostname. Named rather than
         * discovered: if it is renamed or moved, this guard fails loudly instead of
         * finding nothing and passing.
         */
        const val ENVIRONMENT_FILE = "BittrEnvironment.kt"

        /**
         * Files that state this rule rather than break it.
         *
         * `BittrEnvironmentTest` is here because it asserts the two base URLs are
         * byte-for-byte the ones in `BittrAPIEnvironment.swift` — a check that has to
         * name them. That is the whole allowlist, and it should stay that short: the
         * moment a *screen* is on it, the guard has stopped doing its job.
         */
        val ALLOWED_FILES = arrayOf(
            ENVIRONMENT_FILE,
            "BittrEnvironmentTest.kt",
            "ApiBaseUrlGuardTest.kt",
        )

        /**
         * A bittr API URL: the staging host by name, or any host under
         * `getbittr.com` followed by an `/api` path segment.
         *
         * The `/api` requirement is what separates a backend endpoint from the
         * lightning-address and WebView-page URLs the repo is full of —
         * `https://getbittr.com/.well-known/lnurlp/satoshi` is not an offence and
         * must not be, or the guard gets an allowlist and stops meaning anything.
         *
         * Two details that are easy to get wrong and silently disarm this:
         *
         * - The staging branch is **first**, so a staging URL reports as the staging
         *   host rather than being swallowed by the subdomain group in the other
         *   branch. Java alternation is ordered; without this the two branches
         *   overlap and the reported match depends on which one is written first.
         * - `/api` is terminated by a negative lookahead, not by `[/?#]|$`. `$`
         *   matches the end of the *scanned file*, not the end of a line or of a
         *   string literal — so `"https://getbittr.com/api"` (the base URL on its
         *   own, with nothing appended) would not have matched at all, which is
         *   precisely the literal the rule is about.
         */
        val API_URL: Pattern = Pattern.compile(
            """https?://staging\.getbittr\.com""" +
                """|https?://(?:[A-Za-z0-9._-]+\.)?getbittr\.com/api(?![A-Za-z0-9_-])""",
        )

        /** The detector, as a pure function so it can be run against known offenders. */
        fun apiUrls(text: String): List<String> {
            val matcher = API_URL.matcher(text)
            val hits = mutableListOf<String>()
            while (matcher.find()) hits += matcher.group(0)
            return hits
        }

        /**
         * Kotlin is read with comments stripped and string literals kept — the
         * question is what value the code *holds*, and a KDoc explaining this rule
         * (there are several now) is documentation, not a request path. Everything
         * else is read raw.
         */
        fun readableText(file: java.io.File): String =
            if (file.extension == "kt") file.code() else file.readText()
    }

    @Test
    fun `no bittr API URL is hardcoded outside BittrEnvironment`() {
        val offenders = SourceTree.runtimeConfigSources(*ALLOWED_FILES)
            .flatMap { file ->
                apiUrls(readableText(file)).map { "${file.repoPath()} ($it)" }
            }

        assertTrue(
            "A bittr API URL is hardcoded outside $ENVIRONMENT_FILE.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "Whichever of the two hosts the literal names, one of the two builds is " +
                "now pointed at the wrong backend — and it will not look wrong, because " +
                "the URL is correct for the other build. That is BIT-32: the iOS call " +
                "site it was filed for reads authenticated payout state, so the regtest " +
                "build reads production customer data.\n" +
                "Take the base URL from BittrEnvironment instead. It is a parameter of " +
                "the screens that need it (see ValueScreen), read once out of BuildConfig " +
                "in BittrNavHost.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `BittrEnvironment holds both hosts and nothing else does`() {
        val file = SourceTree.runtimeConfigSources()
            .singleOrNull { it.name == ENVIRONMENT_FILE }

        assertTrue(
            "Expected exactly one $ENVIRONMENT_FILE under the android tree, holding the " +
                "single API-host configuration point. Found ${if (file == null) "none or " +
                "several" else "one"}. If it moved, point this guard at its new home in " +
                "the same commit — otherwise the scan above silently stops covering " +
                "anything.",
            file != null,
        )
        requireNotNull(file)

        // Both hosts present in the one allowed file, so the scan above is proven to
        // be looking at a tree that really does contain what it is hunting for. A
        // guard whose detector has quietly stopped matching reports the same green as
        // a clean tree.
        val found = apiUrls(file.code())
        assertTrue(
            "$ENVIRONMENT_FILE no longer holds URLs this guard recognises as bittr API " +
                "URLs (found $found). Either the environment moved or API_URL stopped " +
                "matching — and if it is the second, the tree scan above is passing " +
                "because it matches nothing at all.",
            found.any { it.contains("staging.getbittr.com") } &&
                found.any { !it.contains("staging.") },
        )
    }

    @Test
    fun `the detector fires on known violations and spares the legitimate URLs`() {
        assertEquals(
            "The detector no longer flags the exact literal PriceRepository shipped. " +
                "That is the regression this guard was written for.",
            listOf("https://getbittr.com/api"),
            apiUrls("""private const val PRICE_API = "https://getbittr.com/api/price/btc""""),
        )

        assertEquals(
            "The detector no longer flags a bare base URL — the exact string that would " +
                "be copied into a second file. It has no trailing path, which is the " +
                "case a `[/?#]|\$` terminator silently misses.",
            listOf("https://getbittr.com/api"),
            apiUrls("""val base = "https://getbittr.com/api""""),
        )

        assertEquals(
            "The detector no longer flags a staging URL, so a debug-only hardcode — the " +
                "half that looks harmless — walks straight past it.",
            listOf("https://staging.getbittr.com"),
            apiUrls("""val base = "https://staging.getbittr.com/api/customer""""),
        )

        assertEquals(
            "The detector flags a lightning address, so every :core:lnurl test becomes " +
                "an offender. It would be allowlisted, and the guard would end up " +
                "protecting less than it does now.",
            emptyList<String>(),
            apiUrls("""val a = "https://getbittr.com/.well-known/lnurlp/satoshi""""),
        )

        assertEquals(
            "The detector flags a getbittr.com page, so the three WebView URLs Settings " +
                "opens become offenders. Those are content, not contract — BIT-112 owns " +
                "the question of which environment's pages a debug build should show.",
            emptyList<String>(),
            apiUrls("""val terms = "https://getbittr.com/terms-and-conditions""""),
        )

        assertEquals(
            "The detector flags an unrelated API, so every third-party endpoint in the " +
                "tree becomes an offender.",
            emptyList<String>(),
            apiUrls("""val places = "https://api.btcmap.org/v4/places""""),
        )

        assertEquals(
            "The detector no longer flags a subdomain of the API host.",
            listOf("https://www.getbittr.com/api"),
            apiUrls("""val x = "https://www.getbittr.com/api/customer""""),
        )

        assertEquals(
            "The detector flags a path that merely starts with 'api', so an unrelated " +
                "getbittr.com URL becomes an offender.",
            emptyList<String>(),
            apiUrls("""val x = "https://getbittr.com/apiary""""),
        )
    }
}
