package com.bittr.android

import com.bittr.android.SourceTree.repoPath
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Keeps a euro default out of the port, so a store screenshot cannot silently show
 * the wrong currency.
 *
 * The app ships to Switzerland only (BIT-37), but iOS defaults to EUR at every read
 * site — `CacheStore.value(for: CacheKeys.currency) ?? "EUR"` in
 * `ReceiveViewController.swift:564`, `SendViewController.swift:264`,
 * `SendVCTextFields.swift:62`, and `Transaction.swift:32`. Exactly one site branches
 * to CHF (`BittrWallet.swift:42`), and only once the cache has been set. A fresh
 * install has an empty cache, so a clean-device capture renders euros without
 * failing anything — the screenshots just come out wrong.
 *
 * That is a capture-time trap on iOS. It does not have to be one here: there is no
 * reason for this app to carry a euro default at all. This test keeps the port from
 * inheriting it, so the Play Store capture procedure
 * (`android/docs/play-store-screenshots.md`) is enforcing a property the code
 * already has rather than one a human has to remember on the day.
 *
 * Scope is deliberately narrow. It matches *fallback and default-assignment* syntax
 * only, so a currency picker that legitimately lists EUR as a selectable option is
 * not an offender — offering EUR is a product question, defaulting to it is the bug.
 * It scans `main` sources only, so test fixtures may name any currency they like.
 *
 * If this test fires, fix the default. Do not exempt the file so a capture can be
 * taken around it — that reintroduces exactly the silent failure it exists to stop.
 */
class CurrencyDefaultGuardTest {

    private companion object {
        /**
         * Euro as a fallback (`?: "EUR"`) or as a default value (`= "€"`), in either
         * the symbol or the code form. iOS stores the *symbol* for euro and the
         * *code* for franc — `selectCurrency("€")` vs `selectCurrency("CHF")` in
         * `DeviceViewController.swift:118` — so both spellings have to be caught.
         *
         * The `=` branch excludes comparison operators (`==`, `!=`, `<=`, `>=`);
         * without that, `if (code == "EUR")` reads as a default and trips the guard.
         */
        val EURO_DEFAULT = Regex("(\\?:|(?<![=!<>])=(?!=))\\s*\"(EUR|€)\"")
    }

    @Test
    fun `no euro fallback or default in main sources`() {
        val mainSources = SourceTree.kotlinSources("CurrencyDefaultGuardTest.kt")
            .filter { "${File.separator}src${File.separator}main${File.separator}" in it.path }

        assertTrue(
            "Found no main sources under ${SourceTree.root} — the src/main filter is not " +
                "matching, so this guard would scan nothing and pass without checking.",
            mainSources.isNotEmpty(),
        )

        val offenders = mainSources
            .flatMap { file ->
                file.readLines().withIndex().mapNotNull { (index, line) ->
                    if (EURO_DEFAULT.containsMatchIn(line)) {
                        "${file.repoPath()}:${index + 1}: ${line.trim()}"
                    } else {
                        null
                    }
                }
            }

        assertTrue(
            "This app serves Switzerland only, so no code path may fall back to euro. " +
                "A euro default does not fail loudly — it renders the wrong currency, " +
                "which is how a Play Store screenshot ends up denominated in euros " +
                "(android/docs/play-store-screenshots.md). Default to CHF, or make the " +
                "currency non-optional so there is nothing to default to.\n" +
                "Offending lines:\n  " + offenders.joinToString("\n  "),
            offenders.isEmpty(),
        )
    }
}
