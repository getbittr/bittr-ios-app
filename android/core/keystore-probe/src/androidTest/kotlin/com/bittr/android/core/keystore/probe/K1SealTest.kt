package com.bittr.android.core.keystore.probe

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
        val secureAtSeal = K1Harness.isDeviceSecure()
        assertEquals(
            "case ${case.id} (${case.summary}) requires isDeviceSecure=${case.startsSecure} " +
                "before sealing, but the device reports $secureAtSeal — the driver script did " +
                "not reach the start state",
            case.startsSecure,
            secureAtSeal,
        )

        K1Probe.generate(K1KeySpecs.nonAuthBound(case.nonAuthAlias))

        // Rule 2, read back from Keystore rather than assumed from the builder. Without this,
        // an edit to K1KeySpecs.nonAuthBound that bound the key to authentication would leave
        // K1 green while testing a key the decision is not about.
        val facts = K1Probe.describe(case.nonAuthAlias)
        assertFalse(
            "BIT-8 rule 2 violated: ${case.nonAuthAlias} reports isUserAuthenticationRequired=true",
            facts.userAuthenticationRequired,
        )
        assertFalse(
            "BIT-8 rule 2 violated: ${case.nonAuthAlias} reports isUnlockedDeviceRequired=true",
            facts.unlockedDeviceRequired,
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
            ),
        )

        K1Harness.report(
            phase = "seal",
            case = case,
            facts = mapOf(
                "deviceSecure" to secureAtSeal.toString(),
                "authControl" to controlCreated.toString(),
                "securityLevel" to facts.securityLevel,
                "envelopeBytes" to envelope.size.toString(),
            ),
        )
    }
}
