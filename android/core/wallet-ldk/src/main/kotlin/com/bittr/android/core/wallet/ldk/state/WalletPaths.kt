package com.bittr.android.core.wallet.ldk.state

import android.content.Context
import java.io.File

/**
 * Where the wallet layer is allowed to write, and nowhere else.
 *
 * Two decided rules meet in this one class, and they agree rather than compete:
 *
 * **BIT-8 rule 4 / BIT-20 rule 5 — nothing wallet-shaped leaves the device.**
 * Everything below sits under [Context.getNoBackupFilesDir]. That is the direct
 * Android analogue of iOS's per-file `excludeFromBackup()`
 * (`LightningStorage.swift:38–43`): the exclusion is a property of the *path*,
 * so it survives someone later flipping `android:allowBackup`, adding an
 * include rule, or introducing a backup agent. `allowBackup="false"` and
 * `dataExtractionRules` are the other two layers; they are manifest state, and
 * manifest state is what a future PR can weaken without noticing. This one it
 * cannot.
 *
 * **The `afterFirstUnlock` half of rule 2.** A non-auth-bound Keystore key is
 * usable during Direct Boot, before any unlock has happened — strictly weaker
 * than the iOS class (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) that
 * BIT-8 says we are porting. The missing half comes from *where the blob
 * lives*, not from the key: credential-encrypted (CE) storage is unreadable
 * until first unlock after boot, which is exactly `afterFirstUnlock`.
 * `no_backup` is `<CE-data-dir>/no_backup`, so siting here satisfies both.
 *
 * Hence [forContext] takes the app [Context] and never a device-protected one.
 * `WalletKeystorePolicyGuardTest` fails the build on any
 * `createDeviceProtectedStorageContext()` call inside this module, because that
 * is the single call that would silently downgrade the storage class while
 * leaving every test here green.
 *
 * Proved by `StateDirLocationTest`.
 */
class WalletPaths(
    /** `<CE-data-dir>/no_backup`. Injected so the tests need no device. */
    val noBackupDir: File,
) {

    /** Everything this module owns, under one directory that can be asserted about. */
    val walletDir: File = File(noBackupDir, WALLET_DIR)

    /**
     * ldk-node's persistence directory.
     *
     * The iOS equivalent is the Documents directory itself, filtered by the
     * `ldk_node_data.sqlite` prefix (`LightningStorage.swift:35`). Giving it a
     * directory of its own on Android is what makes "quarantine the state" a
     * directory move rather than a prefix scan, and what lets the discriminator
     * live *inside* the thing it identifies.
     */
    val ldkStateDir: File = File(walletDir, LDK_STATE_DIR)

    /** BDK's SQLite `Connection` path. Its own file, not inside the LDK state directory. */
    val bdkDatabaseFile: File = File(walletDir, "bdk_wallet.sqlite")

    /** The Keystore-wrapped mnemonic. A cache, never the only copy — BIT-8 rule 3. */
    val seedBlobFile: File = File(walletDir, "seed.bin")

    /**
     * Parent of the uniquely-named quarantine subdirectories (BIT-20 rule 4).
     *
     * Under `no_backup`, so each new subdirectory inherits the backup exclusion
     * without a per-directory call. iOS has to re-exclude explicitly
     * (`LightningStorage.swift:99–105`) precisely because its exclusion is
     * per-file and the quarantine directory's name does not match the state
     * prefix.
     */
    val quarantineRoot: File = File(walletDir, QUARANTINE_DIR)

    /**
     * The BIT-20 discriminator, *inside* the state directory it identifies.
     *
     * That siting is deliberate: the discriminator travels with the state or
     * not at all. A state directory that arrives without its discriminator
     * reads as `absent`, which is the fail-safe row (quarantine).
     */
    val discriminatorFile: File = File(ldkStateDir, "seed_discriminator")

    fun createDirectories() {
        walletDir.mkdirs()
        ldkStateDir.mkdirs()
    }

    companion object {
        const val WALLET_DIR = "wallet"
        const val LDK_STATE_DIR = "ldk_state"
        const val QUARANTINE_DIR = "foreign_ldk_state"

        /**
         * The only supported way to build these paths in production code.
         *
         * Takes the credential-encrypted app context. Passing a
         * `createDeviceProtectedStorageContext()` context here would compile and
         * pass every test in this module while downgrading the seed blob's
         * at-rest class below iOS's — which is why the call is banned by a
         * source guard rather than only documented.
         */
        fun forContext(context: Context): WalletPaths = WalletPaths(context.noBackupFilesDir)
    }
}
