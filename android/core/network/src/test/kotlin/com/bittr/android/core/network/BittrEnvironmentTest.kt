package com.bittr.android.core.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BittrEnvironmentTest {

    @Test
    fun `the two environments point at different backends`() {
        // The assertion that actually matters, stated as itself rather than left
        // implied by the two literals: if these ever became equal, every other check
        // here would still pass while the regtest build talked to production.
        assertNotEquals(
            "The debug and release builds resolve to the same backend.",
            BittrEnvironment.DEVELOPMENT.apiBaseUrl,
            BittrEnvironment.PRODUCTION.apiBaseUrl,
        )
    }

    @Test
    fun `the base URLs match the iOS client`() {
        // Byte-for-byte the values in ios/BittrWidget/BittrAPIEnvironment.swift. The
        // two platforms hitting different hosts is not a thing a test elsewhere would
        // notice — it presents as "Android signup is broken", not as a config drift.
        assertEquals(
            "https://staging.getbittr.com/api",
            BittrEnvironment.DEVELOPMENT.apiBaseUrl,
        )
        assertEquals(
            "https://getbittr.com/api",
            BittrEnvironment.PRODUCTION.apiBaseUrl,
        )
    }

    @Test
    fun `every base URL includes the api path component and no trailing slash`() {
        BittrEnvironment.entries.forEach { environment ->
            assertTrue(
                "${environment.name} must end in the /api path component, as " +
                    "BittrAPIEnvironment.baseURL does — call sites append '/customer' " +
                    "directly. Was '${environment.apiBaseUrl}'.",
                environment.apiBaseUrl.endsWith("/api"),
            )
            assertTrue(
                "${environment.name} must be https. A plaintext base URL would carry " +
                    "the signed device-token request (api-contract §2.3) in the clear.",
                environment.apiBaseUrl.startsWith("https://"),
            )
        }
    }

    @Test
    fun `url joins a path with or without a leading slash`() {
        val expected = "https://getbittr.com/api/customer/device-token"
        assertEquals(expected, BittrEnvironment.PRODUCTION.url("customer/device-token"))
        assertEquals(expected, BittrEnvironment.PRODUCTION.url("/customer/device-token"))
    }

    @Test
    fun `fromBuildConfig reads the names app compiles`() {
        // The two literals in app/build.gradle.kts. Spelled out rather than derived
        // from `entries`, so a rename of either case fails here and points at the
        // build file that has to change with it.
        assertEquals(BittrEnvironment.DEVELOPMENT, BittrEnvironment.fromBuildConfig("DEVELOPMENT"))
        assertEquals(BittrEnvironment.PRODUCTION, BittrEnvironment.fromBuildConfig("PRODUCTION"))
    }

    @Test
    fun `fromBuildConfig rejects an unknown name instead of guessing`() {
        // The divergence from BitcoinNetwork.fromBuildConfig, asserted so it cannot
        // be "tidied" back into a fallback. There is no safe default: PRODUCTION
        // points a mistyped debug build at the real backend (the BIT-32 harm), and
        // DEVELOPMENT ships a release build talking to staging.
        val thrown = runCatching { BittrEnvironment.fromBuildConfig("REGTEST") }.exceptionOrNull()

        assertTrue(
            "Expected an IllegalArgumentException for an unknown environment name, got $thrown",
            thrown is IllegalArgumentException,
        )
        assertTrue(
            "The failure must name the offending value so the build file is findable. " +
                "Was: ${thrown?.message}",
            thrown?.message?.contains("REGTEST") == true,
        )
    }

    @Test
    fun `no environment name is a substring of another`() {
        // fromBuildConfig matches case-insensitively on the whole name, so this is
        // not a correctness requirement today. It is a legibility one for the guard
        // test in :app, which greps the build file for these names.
        BittrEnvironment.entries.forEach { a ->
            BittrEnvironment.entries.filter { it != a }.forEach { b ->
                assertFalse(
                    "${a.name} contains ${b.name}",
                    a.name.contains(b.name, ignoreCase = true),
                )
            }
        }
    }
}
