package com.bittr.android.core.wallet.ldk.seed

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.security.KeyStore
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * **K2, the half that can run on an emulator: the seed is readable while the
 * device is locked.**
 *
 * ## What claim this is, and why K1 is not it
 *
 * BIT-8 rule 2 chose a *non-auth-bound* Keystore key —
 * no `setUserAuthenticationRequired(true)`, no `setUnlockedDeviceRequired(true)`
 * — as the faithful port of the mnemonic's iOS class,
 * `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The property that choice
 * buys is the one asserted here: a payment can arrive, and a node can start,
 * while the user is nowhere near the device and the screen is locked.
 *
 * Three tests now sit on that rule and they prove different things:
 *
 * - `KeystoreKeySpecTest` (JVM) — what we *asked* the Keystore for.
 * - `KeystoreKeyInfoTest` (device) — what the platform *gave* us, read back off
 *   `KeyInfo`. On API 34 it cannot even read `isUnlockedDeviceRequired`, because
 *   the getter does not exist below API 37, so on the emulator matrix that flag
 *   is checked on the spec side only.
 * - **this** — what the key actually *does* with the device locked. It is the
 *   only one of the three that would catch an OEM or platform build where the
 *   flags read back correctly and the operation is refused anyway, and the only
 *   one that closes the gap `KeystoreKeyInfoTest` leaves on every API below 37.
 *
 * BIT-18's K1 is a fourth, different claim — that the key survives a *change* of
 * lock-screen credential — and it needs `adb` to mutate the credential between
 * two instrumentation runs, which is why it has a host driver and a device
 * matrix of its own. This one needs the credential only to exist, and only for
 * the duration of one read, so it drives itself.
 *
 * ## What this is NOT, and where the rest of K2 went
 *
 * K2 as `wallet-core-spec` §6 words it is: *force-stop the app, lock the device,
 * deliver an FCM data message, assert node start reaches `Node.start()`*. This
 * class is the middle clause only. The other two cannot run here and one of them
 * cannot run anywhere:
 *
 * - **The FCM leg has no receiver to deliver to.** There is no
 *   `FirebaseMessagingService` in this app — `verify-fcm-service-account.sh` is
 *   a backend credential check, not a client. And the `wallet-instrumented`
 *   emulator is an `aosp_atd` image, chosen for the backup transport, which has
 *   no Play services to deliver a message at all.
 * - **The force-stop leg is specified against a platform guarantee that runs
 *   the other way.** An app the user or `am force-stop` has stopped is in
 *   Android's *stopped state*, and the framework does not deliver broadcasts —
 *   including FCM's — to a stopped package until something launches it again.
 *   So "force-stop, then wake by FCM" does not describe a path that exists;
 *   the real one is *process death*, which is not the same event.
 *
 * Both are written up in `android/docs/wallet-node-device-tests.md` with what
 * they would need, per this issue's definition of done and the BIT-18 precedent:
 * a row closed *unrun* with the reason named beats a row quietly dropped.
 *
 * ## Why each assertion has a lock check next to it
 *
 * "The seed was readable while the device was locked" and "the device was never
 * locked" are the same green. That is the vacuity shape this whole suite exists
 * to refuse, so the lock state is asserted immediately before and after every
 * read rather than once in `@Before`: a keyguard that re-arms late, or that the
 * emulator dismisses on its own, would otherwise turn this class into an
 * expensive re-run of `KeystoreKeyInfoTest`.
 *
 * For the same reason a device that cannot be locked is a **failure**, not a
 * skip. A skipped test does not fail a build, and this one's absence is exactly
 * what would leave rule 2's behavioural half unproven behind a green job.
 */
@RunWith(AndroidJUnit4::class)
class SeedReadableWhileLockedTest {

    private val alias = "com.bittr.android.wallet.seed.k2-instrumentation-test"

    /**
     * Any PIN will do; it exists only so that `isDeviceSecure` is true and the
     * keyguard is a real one. Not a secret and not a credential this app ever
     * sees — `@After` clears it, and the host clears it again between the two
     * Gradle runs in `ci-wallet-instrumented.sh`, because a PIN left behind here
     * would be inherited by the `:app` suite that runs next.
     */
    private val pin = "2468"

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val keyguard: KeyguardManager
        get() = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

    @Before
    fun lockTheDevice() {
        removeTestKey()

        // `set-pin` exiting 0 is not evidence that a credential exists — BIT-18
        // learned that on real handsets, where the command succeeds and the
        // device still reports no lock screen. The device is what gets asked.
        WalletDeviceShell.run("locksettings set-pin $pin")
        assertTrue(
            "`locksettings set-pin` did not give this device a lock screen: " +
                "KeyguardManager.isDeviceSecure is still false. Without a " +
                "credential there is no keyguard, so nothing below would be " +
                "reading anything while locked and every assertion in this class " +
                "would pass having proved nothing. This is a failure rather than " +
                "a skip on purpose.",
            keyguard.isDeviceSecure,
        )

        // KEYCODE_SLEEP rather than POWER: POWER toggles, so on a device whose
        // screen is already off it turns it back ON and the keyguard goes away.
        // BIT-18's matrix script made the same choice for the same reason.
        WalletDeviceShell.run("input keyevent SLEEP")

        assertTrue(
            "The device did not report itself locked within ${LOCK_TIMEOUT_MS}ms " +
                "of KEYCODE_SLEEP, so there is no locked state to read the seed " +
                "in. Check that the image has a keyguard at all and that " +
                "`disable-animations` in the workflow has not been extended into " +
                "disabling the lock screen.",
            awaitLocked(),
        )
    }

    @After
    fun unlockAndClearTheCredential() {
        // Ordered most-important-first, and every step tolerant of the one
        // before it having failed. A test that throws part-way through leaves
        // the emulator locked with a PIN set, and the NEXT thing to run on this
        // device is `:app:connectedDebugAndroidTest` — the backup suite, whose
        // failure would then be blamed on the backup rules.
        runCatching { WalletDeviceShell.run("locksettings clear --old $pin") }
        runCatching { WalletDeviceShell.run("input keyevent WAKEUP") }
        runCatching { WalletDeviceShell.run("wm dismiss-keyguard") }
        runCatching { removeTestKey() }
    }

    /**
     * The claim itself: a blob wrapped before the lock unwraps after it.
     *
     * The wrap happens while the device is *unlocked* in the sense that matters
     * — it does not, because `@Before` has already locked it — so this is
     * stricter than the path it models. The real background wake reads a blob
     * written days earlier; reading one written seconds earlier through the same
     * key is the same Keystore operation.
     */
    @Test
    fun theSeedUnwrapsWhileTheDeviceIsLocked() {
        val mnemonic =
            "void super old faith primary cradle behave crucial vault minor walk random"
        val blob = AndroidKeystoreBlobCodec(alias).wrap(mnemonic.toByteArray())

        assertStillLocked("before the unwrap")
        val recovered = AndroidKeystoreBlobCodec(alias).unwrap(blob)
        assertStillLocked("after the unwrap")

        assertArrayEquals(
            "The seed did not survive a wrap/unwrap performed with the device " +
                "locked. If this fails while KeystoreKeyInfoTest passes, the key's " +
                "reported flags and the key's behaviour disagree, and BIT-8 rule 2 " +
                "does not hold on this device: a payment arriving while the user is " +
                "away could not start the node.",
            mnemonic.toByteArray(),
            recovered,
        )
    }

    /**
     * The first-use path: a key that does not exist yet can be *generated* with
     * the device locked.
     *
     * Separate from the unwrap because it is a different Keystore operation with
     * its own authorisation check, and because the failure it guards is not
     * hypothetical in the other direction: an auth-bound key can be generated
     * while locked and only fails on use, so a class that tested generation
     * alone would be the weaker test. Both are here; neither substitutes.
     *
     * `@Before` deletes the alias, so the `wrap` below really is a generation.
     */
    @Test
    fun aWalletKeyCanBeGeneratedWhileTheDeviceIsLocked() {
        assertTrue(
            "The test alias already exists, so the wrap below would reuse a key " +
                "rather than generate one and this test would not be testing " +
                "generation at all.",
            !keystoreContainsAlias(),
        )

        assertStillLocked("before the key generation")
        val blob = AndroidKeystoreBlobCodec(alias).wrap("first use".toByteArray())
        assertStillLocked("after the key generation")

        assertTrue(
            "Generating the wallet key with the device locked produced no blob.",
            blob.isNotEmpty(),
        )
        assertTrue(
            "The key was not created in the Android Keystore.",
            keystoreContainsAlias(),
        )
    }

    /**
     * The negative control, and the run's evidence line.
     *
     * Without this, the two tests above are indistinguishable from the same two
     * tests on a device that silently never locked — which is precisely how a
     * green run comes to prove nothing. It asserts the two conditions the other
     * methods depend on and prints them, so that a reader of the annotation can
     * see the state the reads happened in rather than taking it on trust.
     *
     * `SEED_WHILE_LOCKED` is in `check-wallet-instrumented-results.py`'s
     * `EVIDENCE_PREFIXES`, so this line is lifted into the job's annotations —
     * the only channel that answers 200 on this public repo without a token.
     */
    @Test
    fun recordTheLockStateTheseReadsHappenedIn() {
        val secure = keyguard.isDeviceSecure
        val locked = keyguard.isDeviceLocked

        println(
            "SEED_WHILE_LOCKED api=${Build.VERSION.SDK_INT} " +
                "device=${Build.MANUFACTURER}/${Build.MODEL} " +
                "isDeviceSecure=$secure isDeviceLocked=$locked " +
                "keyguardLocked=${keyguard.isKeyguardLocked}",
        )

        assertTrue("The device reports no lock-screen credential.", secure)
        assertEquals(
            "The device does not report itself locked, so the other methods in " +
                "this class read the seed on an unlocked device and prove nothing " +
                "about BIT-8 rule 2's behavioural half.",
            true,
            locked,
        )
    }

    private fun assertStillLocked(moment: String) = assertTrue(
        "The device was not locked $moment, so this read says nothing about " +
            "whether the seed is reachable during a background wake. The keyguard " +
            "was armed in @Before and something dismissed it — check for a test " +
            "running concurrently on this device, or for an image that unlocks on " +
            "its own.",
        keyguard.isDeviceLocked,
    )

    /** True once the keyguard reports locked, polled rather than slept on. */
    private fun awaitLocked(): Boolean {
        val deadline = SystemClock.uptimeMillis() + LOCK_TIMEOUT_MS
        while (SystemClock.uptimeMillis() < deadline) {
            if (keyguard.isDeviceLocked) return true
            SystemClock.sleep(POLL_MS)
        }
        return keyguard.isDeviceLocked
    }

    private fun keystoreContainsAlias(): Boolean =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.containsAlias(alias)

    private fun removeTestKey() {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.run {
            if (containsAlias(alias)) deleteEntry(alias)
        }
    }

    private companion object {
        /**
         * Generous on purpose. The keyguard arms asynchronously after
         * KEYCODE_SLEEP and a software-rendered emulator under a cold
         * `connectedAndroidTest` is the slowest case this will meet. The cost of
         * being too short is a false red on the whole suite; the cost of being
         * too long is ten seconds on a run that was going to fail anyway.
         */
        const val LOCK_TIMEOUT_MS = 10_000L
        const val POLL_MS = 100L
    }
}
