package com.bittr.android.core.common

/**
 * What this build is allowed to put in front of the user at unlock.
 *
 * This exists for one reason: **the Maestro suite must always land on the PIN pad.**
 *
 * `BiometricPrompt` at unlock (DEV-17) is an Android-convention *addition*, not a
 * port — `shared/docs/parity.md` lists "no biometric / Face ID unlock" under
 * *Confirmed absent in iOS*. So no shared flow will ever exercise it, and every
 * shared flow will break if it appears:
 *
 * - 28 flows call `helpers/unlock.yaml`, 7 tap the PIN pad directly, 32 do one or
 *   the other.
 * - 296 of the 329 `takeScreenshot` steps — 90% — sit behind a PIN entry.
 *
 * A biometric prompt ahead of the PIN pad therefore does not degrade the suite, it
 * collapses it, and it collapses it *early* — so the real cause ends up buried
 * under 28 red flows that all look independently broken.
 *
 * ### The rule
 *
 * Nothing may call `BiometricPrompt` / `BiometricManager` without first checking
 * [biometricUnlockEnabled]. That is not a convention: `BiometricApiGuardTest` in
 * `:app` fails the build on any reference to those APIs outside the files it names.
 *
 * The value comes from `BuildConfig.BIOMETRIC_UNLOCK_ENABLED`, which is `false` for
 * the debug/regtest build Maestro installs and `true` everywhere else. It is
 * injected rather than read directly because feature modules cannot see `:app`'s
 * `BuildConfig`.
 */
interface AuthCapabilities {

    /**
     * Whether unlock may offer biometrics before falling back to the PIN pad.
     *
     * `false` in `com.bittr.android.regtest` — the APK CI installs. When this is
     * `false`, unlock must render the PIN pad directly with no prompt, no
     * transient "use your fingerprint" affordance, and no biometric enrolment
     * check on the way in: an emulator with a fingerprint enrolled must be
     * indistinguishable from one without.
     */
    val biometricUnlockEnabled: Boolean
}
