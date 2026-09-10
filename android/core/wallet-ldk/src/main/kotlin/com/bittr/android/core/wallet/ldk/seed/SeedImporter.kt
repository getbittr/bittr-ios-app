package com.bittr.android.core.wallet.ldk.seed

import java.io.File

/**
 * `CacheManager.storeMnemonic` (`:351–359`), ported: guard, then persist, in
 * that order and no other.
 *
 * The whole value of this class is the sequence. iOS quarantines before
 * persisting and throws out of the entire function if the quarantine fails, so
 * no mnemonic is stored over state that could not be made safe. On iOS that
 * reads as tidy error handling. On Android, where process death mid-operation
 * is routine rather than exceptional, it is the difference between a
 * recoverable interruption and an unrecoverable one:
 *
 * | crash point | next launch |
 * |---|---|
 * | after quarantine, before the blob write | no mnemonic, no state — clean, the user restores again |
 * | after the blob write, before quarantine | a mnemonic exists, so the guard returns early **forever**; foreign state is live under a new seed |
 *
 * Sequencing alone does not buy the first row — the quarantine is `fsync`'d
 * before this returns, so a buffered rename cannot land after a blob write
 * issued later. See `Fsync`.
 *
 * Proved by `QuarantineOrderingCrashTest`.
 */
class SeedImporter(
    private val vault: SeedVault,
    private val guard: SeedImportGuard,
) {

    /**
     * Import [mnemonic] onto this device.
     *
     * @throws SeedImportAbortedException when the device could not be asked a
     *   question it must answer first, or when state that had to be
     *   quarantined could not be. Both are retryable and neither is
     *   destructive.
     * @throws SeedWriteVerificationException when the blob did not read back.
     */
    fun import(mnemonic: String): SeedImportResult {
        val decision = guard.prepareForImport(mnemonic)

        when (decision) {
            is SeedImportDecision.Abort ->
                throw SeedImportAbortedException(decision.cause)

            // Nothing to do, and importantly nothing to undo: iOS returns
            // early here without touching state, and re-importing over a live
            // wallet is not a path this class offers.
            SeedImportDecision.AlreadyProvisioned ->
                return SeedImportResult(
                    alreadyProvisioned = true,
                    keptExistingState = false,
                    quarantineDirectory = null,
                    discriminatorRecorded = false,
                )

            else -> Unit
        }

        // Only now. Everything above either moved state out of the way or
        // established that it did not need moving.
        vault.store(mnemonic)

        val digest = requireNotNull(decision.discriminator) {
            "a decision that reaches the blob write must carry a discriminator"
        }
        val recorded = guard.recordDiscriminator(digest)

        return SeedImportResult(
            alreadyProvisioned = false,
            keptExistingState = decision is SeedImportDecision.KeepExistingState,
            quarantineDirectory = (decision as? SeedImportDecision.Quarantined)?.directory,
            discriminatorRecorded = recorded,
        )
    }
}

/**
 * @property keptExistingState the BIT-20 `match → keep` row fired: the user's
 *   own channel state survived a lost seed blob.
 * @property quarantineDirectory non-null when foreign or unattributable state
 *   was moved aside. Surface it to the user and name it — it is the only
 *   material that could sweep a force-closed channel, nothing prunes it, and
 *   support needs the directory name to retrieve it.
 * @property discriminatorRecorded false means the next import will see
 *   `absent` and quarantine. Recoverable (quarantine never deletes), worth an
 *   error report, not worth failing a created wallet over.
 */
data class SeedImportResult(
    val alreadyProvisioned: Boolean,
    val keptExistingState: Boolean,
    val quarantineDirectory: File?,
    val discriminatorRecorded: Boolean,
)

/** Retryable. Nothing was written and nothing was destroyed. */
class SeedImportAbortedException(cause: Throwable) :
    IllegalStateException("seed import aborted before anything was written", cause)
