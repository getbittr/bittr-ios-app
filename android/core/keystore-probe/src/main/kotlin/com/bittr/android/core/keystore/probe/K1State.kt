package com.bittr.android.core.keystore.probe

import android.content.Context
import java.io.File
import java.util.Properties

/**
 * What the seal phase leaves behind for the open phase.
 *
 * The two phases are separate `am instrument` invocations with a `force-stop` and a
 * lock-screen mutation between them, so nothing survives in memory — by design. A single
 * in-process test that mutated the lock screen via `UiAutomation` and then decrypted would
 * be cheaper to run and much weaker evidence: it would never leave the process that created
 * the key, and "the node starts in the background the morning after the user changed their
 * PIN" is exactly a cold-process story.
 *
 * Files go under [Context.getNoBackupFilesDir], which is `<CE-data-dir>/no_backup` — the same
 * siting seed-storage-security §3/§5 requires of the real blob, so the harness does not model
 * a storage location the product will not use.
 */
class K1State(
    val envelope: ByteArray,
    val deviceSecureAtSeal: Boolean,
    val authControlCreated: Boolean,
    val securityLevel: String,
    /**
     * [K1Credential.complexity] as it read *before* the mutation. The open phase compares it with
     * the reading after, and that comparison is the only witness M2/M3/M4 have — so it has to
     * survive the process death between the phases, which means it goes in the file.
     */
    val complexityAtSeal: String,
) {
    companion object {
        private const val KEY_SECURE_AT_SEAL = "deviceSecureAtSeal"
        private const val KEY_CONTROL = "authControlCreated"
        private const val KEY_SECURITY_LEVEL = "securityLevel"
        private const val KEY_COMPLEXITY_AT_SEAL = "complexityAtSeal"

        private fun dir(context: Context): File =
            File(context.noBackupFilesDir, "k1").apply { mkdirs() }

        private fun envelopeFile(context: Context, case: K1Case) = File(dir(context), "${case.id}.env")
        private fun propsFile(context: Context, case: K1Case) = File(dir(context), "${case.id}.props")

        fun clear(context: Context, case: K1Case) {
            envelopeFile(context, case).delete()
            propsFile(context, case).delete()
        }

        fun write(context: Context, case: K1Case, state: K1State) {
            envelopeFile(context, case).writeBytes(state.envelope)
            val props = Properties().apply {
                setProperty(KEY_SECURE_AT_SEAL, state.deviceSecureAtSeal.toString())
                setProperty(KEY_CONTROL, state.authControlCreated.toString())
                setProperty(KEY_SECURITY_LEVEL, state.securityLevel)
                setProperty(KEY_COMPLEXITY_AT_SEAL, state.complexityAtSeal)
            }
            propsFile(context, case).outputStream().use { props.store(it, "BIT-18/K1 ${case.id}") }
        }

        /**
         * Fails loudly rather than returning null. A missing state file means the seal phase
         * did not run, or the package was cleared between the phases — either way the run has
         * no verdict to report, and "no verdict" must not be reachable from a green test.
         */
        fun read(context: Context, case: K1Case): K1State {
            val env = envelopeFile(context, case)
            val props = propsFile(context, case)
            check(env.isFile && props.isFile) {
                "no sealed state for case ${case.id} at ${env.parent} — the seal phase did not run, " +
                    "or the package data was cleared between the phases"
            }
            val loaded = Properties().apply { props.inputStream().use { load(it) } }
            return K1State(
                envelope = env.readBytes(),
                deviceSecureAtSeal = loaded.getProperty(KEY_SECURE_AT_SEAL).toBoolean(),
                authControlCreated = loaded.getProperty(KEY_CONTROL).toBoolean(),
                securityLevel = loaded.getProperty(KEY_SECURITY_LEVEL) ?: "UNRECORDED",
                // A state file written before this field existed reads as "could not tell", which
                // routes into the no-witness refusal rather than into a comparison against "".
                complexityAtSeal = loaded.getProperty(KEY_COMPLEXITY_AT_SEAL) ?: K1Credential.UNREADABLE,
            )
        }
    }
}
