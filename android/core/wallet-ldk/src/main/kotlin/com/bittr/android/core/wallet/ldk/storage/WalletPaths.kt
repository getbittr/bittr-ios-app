package com.bittr.android.core.wallet.ldk.storage

import android.content.Context
import java.io.File

/**
 * Every path the wallet layer is allowed to write to, and the reason each one is
 * where it is.
 *
 * Two properties are load-bearing and both come from the directory choice rather
 * than from anything the code does later:
 *
 * **1. Under `getNoBackupFilesDir()`** — rule 4 (BIT-8) and rule 10 (BIT-20).
 * `android:allowBackup="false"` and `dataExtractionRules` are manifest state that
 * a later PR can weaken without touching this module; siting is a property of the
 * path, so it survives that. This is the direct analogue of the per-file
 * `excludeFromBackup()` pass iOS does in `LightningStorage.swift:38-43` — iOS
 * excludes the directory *and* each file individually, precisely because the
 * directory-level flag alone was not judged enough.
 *
 * Note what this protects against and what it does not. Exclusion closes the
 * *migration* vector: LDK state arriving on a second device without the user
 * knowing. That is the precondition that makes BIT-20's `match -> keep` sound at
 * all — a discriminator proves state is *yours*, never that it is *current*, and
 * same-seed stale state signs fine. Signing a revoked commitment hands the
 * channel balance to the counterparty. See [com.bittr.android.core.wallet.ldk.guard.BackupExclusionProof].
 *
 * **2. Under credential-encrypted (CE) storage** — the second clause of rule 2.
 * The mnemonic's iOS class is `afterFirstUnlockThisDeviceOnly`
 * (`CacheManager.swift:358`): unreadable until the first unlock after boot,
 * readable thereafter. Android Keystore has no equivalent flag, and rule 2
 * mandates a *non-auth-bound* key — which on its own is usable during Direct
 * Boot, i.e. strictly weaker than the class we are porting. The missing half
 * comes from CE storage, which is not readable until first unlock. So the blob
 * must never be sited in device-encrypted (DE) storage, and [WalletPaths]
 * refuses a DE context rather than trusting callers to remember.
 *
 * `getNoBackupFilesDir()` is `<CE-data-dir>/no_backup`, so both properties hold
 * at once with no tension between them.
 *
 * Proven by `StateDirLocationTest` and `DirectBootStorageTest`; the negative half
 * (nobody reintroduces a DE context elsewhere) is `DirectBootStorageGuardTest`.
 */
class WalletPaths private constructor(val root: File) {

    /** The Keystore-wrapped mnemonic. A cache, never the only copy — rule 3. */
    val seedBlob: File get() = File(root, "seed.blob")

    /** ldk-node's storage directory: channel state, monitors, the network graph. */
    val ldkStateDir: File get() = File(root, "ldk")

    /**
     * The seed discriminator, sited *inside* [ldkStateDir] on purpose: it must
     * travel with the state or not at all. A discriminator that could be
     * separated from its state would turn a `mismatch` into an `absent`, and
     * `absent` is a different row of the guard (BIT-20 rule 2).
     */
    val discriminator: File get() = File(ldkStateDir, "state-owner.sha256")

    /**
     * Parent of the quarantine subdirectories. Never itself a quarantine.
     *
     * Because it sits under `no_backup`, each new subdirectory inherits the
     * exclusion without a per-directory call — the Android equivalent of the
     * explicit re-exclusion iOS performs at `LightningStorage.swift:99-105`.
     */
    val quarantineRoot: File get() = File(root, "foreign_ldk_state")

    /** Creates [root] if absent. Safe to call repeatedly. */
    fun ensureRoot(): File = root.apply { mkdirs() }

    companion object {

        /**
         * Resolves the wallet directory from [context], rejecting a
         * device-protected context.
         *
         * The rejection is not defensive coding for its own sake. A DE context
         * silently produces a *valid-looking* `no_backup` path under `user_de`,
         * so the mistake costs nothing at runtime and quietly downgrades the
         * mnemonic below the iOS storage class this port is defined against.
         * There is no failure a caller could observe; hence the hard failure
         * here.
         */
        fun from(context: Context): WalletPaths {
            require(!context.isDeviceProtectedStorage) {
                "Wallet storage must live in credential-encrypted storage. This context is " +
                    "device-protected, which is readable before the first unlock after boot " +
                    "and would make the wrapped mnemonic strictly weaker than the iOS class " +
                    "it ports (afterFirstUnlockThisDeviceOnly). Do not call " +
                    "createDeviceProtectedStorageContext() in the wallet layer."
            }
            return WalletPaths(File(context.noBackupFilesDir, "wallet"))
        }

        /** For tests that need a plain temporary directory rather than a Context. */
        internal fun forTesting(root: File): WalletPaths = WalletPaths(root)
    }
}
