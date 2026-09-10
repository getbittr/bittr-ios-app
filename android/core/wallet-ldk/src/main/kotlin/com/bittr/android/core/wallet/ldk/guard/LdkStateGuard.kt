package com.bittr.android.core.wallet.ldk.guard

import com.bittr.android.core.wallet.ldk.seed.SeedBlobOutcome
import com.bittr.android.core.wallet.ldk.seed.SeedVault
import com.bittr.android.core.wallet.ldk.storage.WalletPaths
import java.io.File

/**
 * Thrown when the Keystore could not answer. The seed import must abort and be
 * retried — it must **not** fall through to the identity check, because a
 * transient failure is not evidence that the state is foreign.
 */
class SeedImportAborted(message: String, cause: Throwable?) : IllegalStateException(message, cause)

/** What the guard did, for logging and for the user-facing quarantine flag. */
sealed interface GuardOutcome {

    /** A mnemonic already exists on this device. Nothing was touched. */
    data object MnemonicAlreadyPresent : GuardOutcome

    /** There was no LDK state to judge. */
    data object NoStatePresent : GuardOutcome

    /** The state belongs to the seed being imported and was kept. */
    data object StateKept : GuardOutcome

    /** The state was moved to [directory] and left intact there. */
    data class StateQuarantined(val directory: File, val reason: Reason) : GuardOutcome {
        enum class Reason {
            /** Discriminator present and different — genuinely another wallet. */
            DiscriminatorMismatch,

            /** No discriminator, or a malformed one. Fail-safe; matches iOS today. */
            DiscriminatorAbsent,

            /** Matched, but [BackupExclusionProof.PROVEN_ON_DEVICE] is false. */
            MatchKeepNotYetProven,
        }
    }
}

/**
 * Decides what happens to existing LDK state when a mnemonic is imported.
 *
 * Runs **before** the mnemonic is persisted, mirroring
 * `CacheManager.storeMnemonic` (`:351-359`), which calls
 * `quarantineLightningStateBeforeSeedImport()` at `:355` and throws out of the
 * whole function if it fails, so no mnemonic is stored. That ordering is
 * load-bearing on Android in a way it is not on iOS — see
 * [com.bittr.android.core.wallet.ldk.storage.Durability] for the crash analysis.
 * Enforced by `QuarantineOrderingCrashTest`.
 *
 * The decision table (BIT-20 rule 2), reached only when there is no usable
 * mnemonic on the device:
 *
 * | Recorded discriminator vs. imported seed | Action |
 * |---|---|
 * | match | the user's own state -> **keep it** (gated, see [BackupExclusionProof]) |
 * | mismatch | genuinely foreign -> quarantine (iOS behaviour) |
 * | absent | unknown provenance -> quarantine (conservative, matches iOS) |
 *
 * `absent -> quarantine` is deliberately fail-safe. Deleting the discriminator to
 * force a quarantine is a denial-of-service, not a fund loss, because quarantine
 * never deletes.
 */
class LdkStateGuard(
    private val paths: WalletPaths,
    private val vault: SeedVault,
    private val quarantine: StateQuarantine,
    private val matchKeepEnabled: Boolean = BackupExclusionProof.PROVEN_ON_DEVICE,
) {

    /**
     * @param importedAccountXpub the BIP84 account xpub of the seed being
     * imported. Derivable from the mnemonic alone, which is what lets this
     * decide *before* any node boots against unverified state.
     *
     * @throws SeedImportAborted on a transient Keystore failure.
     */
    fun onSeedImport(importedAccountXpub: String): GuardOutcome {
        when (val outcome = vault.read()) {
            is SeedBlobOutcome.Present -> {
                // A mnemonic already exists on this device. iOS returns here and
                // so do we: the state and the seed are already associated, and
                // touching either would be a change we have no evidence to make.
                outcome.wipe()
                return GuardOutcome.MnemonicAlreadyPresent
            }

            is SeedBlobOutcome.TransientFailure -> {
                // Row 3. The single most important branch in this file. Falling
                // through here would quarantine live channel state because a
                // Keystore call was busy — the fund-loss outcome by the back
                // door. Abort and let the caller retry.
                throw SeedImportAborted(
                    "Aborting seed import: the Keystore could not be read. This is a failure, " +
                        "not an absence, so the LDK state has NOT been touched. Retry.",
                    outcome.cause,
                )
            }

            is SeedBlobOutcome.NoUsableMnemonic -> Unit // fall through to the identity check
        }

        if (!paths.ldkStateDir.exists()) return GuardOutcome.NoStatePresent

        val recorded = DiscriminatorFile(paths.discriminator).read()
        val expected = SeedDiscriminator.of(importedAccountXpub)

        val reason = when {
            recorded is DiscriminatorFile.State.Absent ->
                GuardOutcome.StateQuarantined.Reason.DiscriminatorAbsent

            recorded is DiscriminatorFile.State.Present &&
                !SeedDiscriminator.matches(recorded.digest, expected) ->
                GuardOutcome.StateQuarantined.Reason.DiscriminatorMismatch

            // Matched. Whether we may act on that depends on the precondition.
            !matchKeepEnabled ->
                GuardOutcome.StateQuarantined.Reason.MatchKeepNotYetProven

            else -> null
        }

        if (reason == null) return GuardOutcome.StateKept

        val directory = quarantine.quarantine() ?: return GuardOutcome.NoStatePresent
        return GuardOutcome.StateQuarantined(directory, reason)
    }

    /**
     * Records the discriminator for a newly created or restored wallet.
     *
     * Called after the state directory exists and the seed is known. Writing it
     * is what makes the *next* import decidable; without it the next import sees
     * `absent` and quarantines, which is safe but costs the user their channels.
     */
    fun recordOwnership(accountXpub: String) {
        paths.ldkStateDir.mkdirs()
        DiscriminatorFile(paths.discriminator).write(SeedDiscriminator.of(accountXpub))
    }
}
