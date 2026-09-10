package com.bittr.android.core.keystore.probe

/**
 * The lock-screen mutations BIT-18 asks for, one row each.
 *
 * The issue lists five; this is six because "change PIN → pattern / password" is two different
 * credential types and there is no reason to assume they behave alike on an OEM build — the
 * entire premise of K1 is that OEM builds diverge. The mapping back to the issue is in
 * `android/docs/k1-keystore-lockscreen.md`.
 *
 * @param startsSecure whether the harness must have a lock screen set *before* the seal phase.
 *   Checked in the seal phase, so a harness that failed to reach the start state fails loudly
 *   instead of quietly testing a different mutation.
 * @param endsSecure the same for after the mutation. For the four cases where this equals
 *   [startsSecure] it only catches a harness that did nothing at all; the real
 *   mutation-effectiveness witness for those is host-side (`locksettings verify`, see
 *   `android/scripts/k1-lockscreen-matrix.sh`).
 * @param usesAuthBoundControl whether an auth-bound key is a valid witness that the mutation
 *   destroyed credentials. True only for the cases that *destroy* the credential. A PIN → PIN
 *   change re-wraps the synthetic password and auth-bound keys survive it legitimately, so
 *   asserting their death there would make K1 report false reds.
 */
enum class K1Case(
    val id: String,
    val startsSecure: Boolean,
    val endsSecure: Boolean,
    val usesAuthBoundControl: Boolean,
    val summary: String,
) {
    M1_SET_FROM_NONE("M1", false, true, false, "set a lock screen where none existed"),
    M2_PIN_TO_PIN("M2", true, true, false, "change PIN to a different PIN"),
    M3_PIN_TO_PASSWORD("M3", true, true, false, "change PIN to an alphanumeric password"),
    M4_PIN_TO_PATTERN("M4", true, true, false, "change PIN to a pattern"),
    M5_REMOVE("M5", true, false, true, "remove the lock screen entirely"),
    M6_ADMIN_RESET("M6", true, false, true, "device-owner forced reset of the secure lock screen"),
    ;

    /** The key rule 2 is about. One per case, so every case starts from a clean key. */
    val nonAuthAlias: String get() = "k1_nonauth_$id"

    /** The positive control. See [K1KeySpecs.authBoundControl]. */
    val authAlias: String get() = "k1_authbound_$id"

    companion object {
        fun byId(id: String): K1Case =
            entries.firstOrNull { it.id.equals(id, ignoreCase = true) || it.name.equals(id, ignoreCase = true) }
                ?: throw IllegalArgumentException(
                    "unknown K1 case '$id'; expected one of ${entries.joinToString { it.id }}",
                )
    }
}
