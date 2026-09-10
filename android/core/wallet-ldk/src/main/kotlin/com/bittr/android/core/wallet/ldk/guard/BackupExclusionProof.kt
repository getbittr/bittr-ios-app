package com.bittr.android.core.wallet.ldk.guard

/**
 * Whether the backup exclusion has been **empirically proven on a device**, and
 * therefore whether `match -> keep` is allowed to take effect.
 *
 * ## Why this constant exists
 *
 * BIT-20 rule 5 is a precondition, not belt-and-braces: *"`match -> keep` is only
 * sound if same-seed state cannot arrive from a second device. Same-seed stale
 * state signs fine, and signing a revoked commitment hands the whole channel
 * balance to the counterparty. This must land with the discriminator, not after
 * it."*
 *
 * A discriminator proves a state directory is **yours**. It does not prove it is
 * **current**. Those come apart exactly when a state directory reaches a second
 * device under the same seed — Auto Backup restore, or a device-to-device
 * transfer. Both devices then match the discriminator, both look legitimate, and
 * the stale one can sign. Foreign state cannot sign; same-seed stale state can.
 * So the case the discriminator does *not* cover is the worse one, and it is
 * closed at the storage layer or not at all.
 *
 * `seed-storage-security` §5.3 records the halt trigger in advance so it would
 * not be a judgement call in the moment: *"`BackupExclusionTest`'s
 * `<device-transfer>` case fails, or cannot be driven on the matrix -> raise, do
 * not proceed."* Whether API 31+ device-transfer honours `no_backup` siting or
 * `dataExtractionRules` is exactly the sort of documented-behaviour claim §5.2
 * declines to assert from memory.
 *
 * ## Why it is `false`
 *
 * `BackupExclusionTest` needs a device or emulator: it drives `bmgr` and the
 * device-transfer path. No emulator has run on this port yet — BIT-5 shipped its
 * whole harness without one (no `/dev/kvm` in the build container) and the
 * self-hosted runner is the intended venue. So the precondition is **unproven,
 * not failed**, and the two are different: failed means go back to BIT-20,
 * unproven means run the test.
 *
 * Until then the guard falls back to iOS behaviour — quarantine on anything but a
 * live mnemonic — which is exactly what §5.3 says to do. The discriminator still
 * lands *with* the guard as the ruling requires; what is gated is the branch
 * whose soundness depends on the unproven claim.
 *
 * ## Flipping it
 *
 * One line, once `BackupExclusionTest` is green on **both** `<cloud-backup>` and
 * `<device-transfer>`. `MatchKeepRequiresBackupProofTest` asserts that while this
 * is false a matching discriminator still quarantines, so the gate is enforced in
 * code rather than remembered in a document.
 */
object BackupExclusionProof {

    const val PROVEN_ON_DEVICE: Boolean = false

    /** Reason surfaced in guard outcomes, so logs say why a match was not kept. */
    const val WHY_NOT_PROVEN: String =
        "BackupExclusionTest has not been run on a device yet (BIT-6). Until the " +
            "<cloud-backup> and <device-transfer> paths are both proven to exclude the LDK " +
            "state directory, same-seed state could have arrived from a second device, and " +
            "keeping it risks signing a revoked commitment."
}
