package com.bittr.android.core.wallet.ldk.seed

import com.bittr.android.core.wallet.ldk.bip.Bip84Account
import com.bittr.android.core.wallet.ldk.state.DiscriminatorRecord
import com.bittr.android.core.wallet.ldk.state.DiscriminatorStore
import com.bittr.android.core.wallet.ldk.state.LdkStateStore
import com.bittr.android.core.wallet.ldk.state.SeedDiscriminator
import java.io.File
import java.io.IOException

/**
 * The Android port of `quarantineLightningStateBeforeSeedImport()`
 * (`CacheManager.swift:361–378`), replaced by an identity check per BIT-20.
 *
 * Read the iOS original first, because the shape survives and only the middle
 * question changes:
 *
 * ```
 * if a mnemonic already exists in the Keychain  -> do nothing
 * else if LDK state exists on disk              -> the state is FOREIGN, quarantine it
 * ```
 *
 * The `else` branch is an *inference*: no mnemonic ⇒ any state is foreign. It
 * holds on iOS because the Keychain outlives app data. BIT-8 rule 3 makes it
 * false on Android by design, so it becomes a *question we can actually
 * answer*: does the recorded discriminator match the seed being imported?
 *
 * | discriminator vs. incoming seed | action |
 * |---|---|
 * | match    | the user's own state → **keep it**, no quarantine |
 * | mismatch | genuinely foreign → quarantine (iOS behaviour) |
 * | absent   | unknown provenance → quarantine (conservative, matches iOS today) |
 *
 * **`match → keep` is only sound on top of the backup exclusion**
 * (`seed-storage-security` §5.1). A discriminator proves state is *yours*; it
 * does not prove it is *current*. Same-seed **stale** state signs fine, and
 * publishing a revoked commitment hands the channel balance to the
 * counterparty. Foreign state cannot sign, so the case the discriminator does
 * not cover is the worse one, and it is closed at the storage layer by keeping
 * the state directory off both the cloud-backup and device-transfer paths.
 * That is why BIT-20 rule 5 is a precondition of this class and not a
 * follow-up.
 *
 * Proved by `BlobDestroyedRecoversTest` (match and mismatch),
 * `ForeignStateQuarantinedTest` (absent), `TransientKeystoreFailureAbortsTest`
 * (the abort row) and `QuarantineOrderingCrashTest` (the ordering).
 */
class SeedImportGuard(
    private val vault: SeedVault,
    private val stateStore: LdkStateStore,
    private val discriminatorStore: DiscriminatorStore,
    private val mainnet: Boolean,
) {

    /**
     * Decide what to do with any LDK state on disk before [mnemonic] is
     * imported. Performs the quarantine when one is called for; does not write
     * the mnemonic.
     *
     * Ordering is the iOS ordering and it is load-bearing on Android
     * (`seed-storage-security` §7.2). Quarantine happens here, durably, and the
     * caller writes the blob only on a decision that is not
     * [SeedImportDecision.Abort]. The reverse order has an unrecoverable crash
     * window: with the blob written first, the guard's first branch returns
     * early on every subsequent launch, so foreign state stays live under a new
     * seed and the guard can never fire again.
     */
    fun prepareForImport(mnemonic: String): SeedImportDecision {
        when (val presence = vault.presence()) {
            // iOS behaviour, unchanged: something is already here. Don't touch
            // anything — including the discriminator, which describes state
            // belonging to whatever seed is already installed.
            MnemonicPresence.Present -> return SeedImportDecision.AlreadyProvisioned

            // BIT-20 rule 3, row 3. A transient Keystore failure is a failure,
            // not an absence. Quarantining on this would destroy live channel
            // state because a provider was busy.
            is MnemonicPresence.Unavailable ->
                return SeedImportDecision.Abort(presence.cause)

            MnemonicPresence.NoUsableMnemonic -> Unit
        }

        val digest = SeedDiscriminator.compute(Bip84Account.accountXpub(mnemonic, mainnet))

        if (!stateStore.hasLightningState()) {
            // Nothing to quarantine. iOS returns here too
            // (`CacheManager.swift:366–369`).
            return SeedImportDecision.NoStatePresent(digest)
        }

        val recorded = discriminatorStore.read()
        val ownState = recorded is DiscriminatorRecord.Present &&
            SeedDiscriminator.matches(recorded.digest, digest)

        if (ownState) {
            // The row that did not exist on iOS. This is what makes BIT-8
            // rule 3 deliverable rather than nominal: "blob destroyed →
            // restore from mnemonic" recovers the *channels* too, instead of
            // silently degrading to an on-chain-only sweep.
            return SeedImportDecision.KeepExistingState(digest)
        }

        return try {
            val quarantine = stateStore.quarantineLightningState()
            SeedImportDecision.Quarantined(digest, quarantine)
        } catch (failure: IOException) {
            // `storeMnemonic` throws out of the whole function if the
            // quarantine fails (`CacheManager.swift:355`), which prevents the
            // wallet being created over state we could not make safe. Same
            // here.
            SeedImportDecision.Abort(failure)
        }
    }

    /**
     * Record the discriminator for the seed that was just imported.
     *
     * Called after the blob write, because until the blob is written there is
     * no seed installed and a discriminator would be describing state that
     * belongs to nobody. A failure here is *not* fatal: an unwritten
     * discriminator reads as `absent`, which quarantines on the next import —
     * a denial of service, not a fund loss, because quarantine never deletes.
     * Returning the outcome rather than throwing lets the caller log it without
     * being tempted to fail a wallet creation that has already succeeded.
     */
    fun recordDiscriminator(digest: ByteArray): Boolean = try {
        discriminatorStore.write(digest)
        true
    } catch (_: IOException) {
        false
    }
}

/** What [SeedImportGuard.prepareForImport] concluded. */
sealed interface SeedImportDecision {

    /** The digest to record once the mnemonic is stored, or `null` if nothing should change. */
    val discriminator: ByteArray?

    /** A mnemonic is already installed. Do not import, do not touch state. */
    data object AlreadyProvisioned : SeedImportDecision {
        override val discriminator: ByteArray? = null
    }

    /** No LDK state on disk. Import freely. */
    data class NoStatePresent(override val discriminator: ByteArray) : SeedImportDecision

    /** State on disk belongs to this seed. Keep it — BIT-20 rule 2, `match → keep`. */
    data class KeepExistingState(override val discriminator: ByteArray) : SeedImportDecision

    /**
     * State on disk was foreign or unattributable and has been moved to
     * [directory], which is unique and does not replace any prior quarantine.
     *
     * Surface this to the user, naming the directory: iOS sets
     * `BitcoinManager.shared.didQuarantineForeignState = true`
     * (`CacheManager.swift:378`), and on Android the directory name is what
     * support needs to retrieve the material. Nothing prunes it — deleting
     * quarantined state is the one thing iOS refuses to do, because it is the
     * only thing that could sweep funds from a force-closed channel
     * (`LightningStorage.swift:83–84`).
     */
    data class Quarantined(
        override val discriminator: ByteArray,
        val directory: File?,
    ) : SeedImportDecision

    /** The device could not answer. Retry; do not import and do not quarantine. */
    data class Abort(val cause: Throwable) : SeedImportDecision {
        override val discriminator: ByteArray? = null
    }
}
