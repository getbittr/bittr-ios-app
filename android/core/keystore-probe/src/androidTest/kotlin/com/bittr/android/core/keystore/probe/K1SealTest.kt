package com.bittr.android.core.keystore.probe

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Phase 1 of BIT-18/K1: put a clean non-auth-bound key on the device and seal the known blob
 * with it, *before* the lock screen is touched.
 *
 * Run by `android/scripts/k1-lockscreen-matrix.sh`. Running it by hand without the `-e k1_case`
 * argument is an error, not a default (see [K1Harness.case]).
 */
@RunWith(AndroidJUnit4::class)
class K1SealTest {

    @Test
    fun seal() {
        val case = K1Harness.case()
        val context = K1Harness.context

        // Every case starts from a clean key, per the issue. Deleting rather than reusing also
        // means a re-run after a red row cannot accidentally open a blob sealed under an older
        // key that predates the mutation being investigated.
        K1Probe.deleteAlias(case.nonAuthAlias)
        K1Probe.deleteAlias(case.authAlias)
        K1State.clear(context, case)

        // The harness is responsible for the start state. If it is wrong, this run is testing
        // some other mutation than the one it will report, so it stops here.
        //
        // For M2/M3/M4 this check is weak on its own — the device is secure on both sides, so it
        // only catches a driver that reached no state at all. What makes those three reportable is
        // `complexityAtSeal` above travelling into K1State and being compared in phase 2.
        val secureAtSeal = K1Harness.isDeviceSecure()
        val complexityAtSeal = K1Harness.complexity()
        assertEquals(
            "case ${case.id} (${case.summary}) requires isDeviceSecure=${case.startsSecure} " +
                "before sealing, but the device reports $secureAtSeal — the driver script did " +
                "not reach the start state",
            case.startsSecure,
            secureAtSeal,
        )

        // Can this device witness this mutation at all? Asked here, before a key is generated and
        // before anything touches the lock screen, so an unwitnessable case costs one
        // instrumentation rather than a whole seal/mutate/open cycle ending in a row nobody can
        // trust.
        //
        // Asked of the *device*, not of Build.VERSION. K1 has already made the API-level-guess
        // mistake once — the isUnlockedDeviceRequired readback was gated at API 28 for a method
        // that arrived in 36.1, and compileSdk hid it on every device in the matrix. The device is
        // the only thing that knows.
        //
        // An assumption failure rather than a failure: BIT-18 says "where reachable" of the
        // mutations it asks for, and the driver turns this into a `NOT REACHABLE` row. That is a
        // finding — "K1 cannot answer this on API 26" is a true and useful sentence — where a
        // green row from a run with no witness would be the false green this harness exists to
        // prevent.
        if (!case.hasKeyguardWitness) {
            assumeTrue(
                "reason=no-credential-change-witness — case ${case.id} (${case.summary}) leaves " +
                    "the device secure on both sides, so KeyguardManager sees nothing, and this " +
                    "device did not answer getPasswordComplexity() (API ${Build.VERSION.SDK_INT}). " +
                    "K1 will not report a row for a mutation it cannot witness.",
                K1Credential.isReadable(complexityAtSeal),
            )
        }

        // Rule 2 is checked twice, against two different things, because neither check alone
        // covers the whole matrix.
        //
        //   the spec   — what K1 asked Keystore for. Readable on every API in the matrix, so
        //                this is what catches the failure mode the checks exist for: someone
        //                edits K1KeySpecs.nonAuthBound to bind the key, and K1 keeps passing
        //                for a key the BIT-8 decision is not about.
        //   the readback — what Keystore says it actually created. Strictly better evidence,
        //                and strictly less available: KeyInfo.isUnlockedDeviceRequired only
        //                exists from 36.1 (see K1Probe.unlockedDeviceRequiredOf).
        //
        // Which ones were available goes into the row. A rule-2 check that could not run must
        // not be reported as a rule-2 check that passed.
        val spec = K1KeySpecs.nonAuthBound(case.nonAuthAlias)
        assertFalse(
            "BIT-8 rule 2 violated in the spec: ${case.nonAuthAlias} is built with " +
                "setUserAuthenticationRequired(true)",
            spec.isUserAuthenticationRequired,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            assertFalse(
                "BIT-8 rule 2 violated in the spec: ${case.nonAuthAlias} is built with " +
                    "setUnlockedDeviceRequired(true)",
                spec.isUnlockedDeviceRequired,
            )
        }

        K1Probe.generate(spec)

        val facts = K1Probe.describe(case.nonAuthAlias)
        assertFalse(
            "BIT-8 rule 2 violated: ${case.nonAuthAlias} reports isUserAuthenticationRequired=true",
            facts.userAuthenticationRequired,
        )
        // `null` is "this device cannot be asked", not "the device said no", so it is neither a
        // pass nor a failure — it is recorded as unknown and the spec check above stands in.
        assertFalse(
            "BIT-8 rule 2 violated: ${case.nonAuthAlias} reports isUnlockedDeviceRequired=true",
            facts.unlockedDeviceRequired == true,
        )

        val envelope = K1Probe.seal(case.nonAuthAlias, K1Probe.KNOWN_PLAINTEXT)

        // Open it once here, before anything is mutated. A blob that never round-tripped in the
        // first place would fail in phase 2 and read as "the mutation broke the key" — the most
        // expensive possible misreading of this test.
        assertArrayEquals(
            "the sealed blob does not round-trip before any mutation; the failure is in the " +
                "harness, not in Keystore",
            K1Probe.KNOWN_PLAINTEXT,
            K1Probe.open(case.nonAuthAlias, envelope),
        )

        var controlCreated = false
        if (case.usesAuthBoundControl) {
            K1Probe.generate(K1KeySpecs.authBoundControl(case.authAlias))
            controlCreated = K1Probe.containsAlias(case.authAlias)
            assertTrue(
                "could not create the auth-bound control key for case ${case.id}; without it " +
                    "phase 2 has no witness that the credential was actually destroyed",
                controlCreated,
            )
        }

        K1State.write(
            context,
            case,
            K1State(
                envelope = envelope,
                deviceSecureAtSeal = secureAtSeal,
                authControlCreated = controlCreated,
                securityLevel = facts.securityLevel,
                complexityAtSeal = complexityAtSeal,
            ),
        )

        K1Harness.report(
            phase = "seal",
            case = case,
            facts = mapOf(
                "deviceSecure" to secureAtSeal.toString(),
                "complexity" to complexityAtSeal,
                "authControl" to controlCreated.toString(),
                "securityLevel" to facts.securityLevel,
                "envelopeBytes" to envelope.size.toString(),
                // "unknown" means KeyInfo has no isUnlockedDeviceRequired on this device, so
                // rule 2's second half rests on the spec check alone for this row.
                "unlockedDeviceRequired" to (facts.unlockedDeviceRequired?.toString() ?: "unknown"),
            ),
        )
    }
}
