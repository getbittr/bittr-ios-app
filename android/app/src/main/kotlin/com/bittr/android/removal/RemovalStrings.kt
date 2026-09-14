package com.bittr.android.removal

/** The wallet-removal copy, word for word from `Language.swift`. Keys in the comments. */
internal object RemovalStrings {

    /** `removewallet` / `removewalletfromdevice` — both read "Remove wallet". */
    const val REMOVE_WALLET = "Remove wallet"

    /** `restorewallet`. */
    const val RESTORE_WALLET = "Restore wallet"

    /** The label under the phrase fields on the forgot-PIN screen (`Main.storyboard`, "Remove Wallet Stack"). */
    const val REMOVE_WALLET_FROM_DEVICE = "Remove wallet from device"

    /** `removewallet1`. */
    const val REMOVE_WALLET_1 =
        "Are you sure you want to remove this wallet from your device?\n\n" +
            "You can restore the wallet using your recovery phrase."

    /** `restorewallet2`. */
    const val RESTORE_WALLET_2 =
        "Are you sure you'd like to remove this wallet from your device?\n\n" +
            "Only remove your wallet if you're sure you've properly backed up your wallet."

    /** `restorewallet3`. */
    const val RESTORE_WALLET_3 = "Are you sure you want to remove your wallet from this device?"

    /** `restorewallet4`. */
    const val RESTORE_WALLET_4 =
        "Please close your lightning connection(s) before removing your wallet from this device.\n\n" +
            "Otherwise, you may lose access to the funds in your lightning connection."

    /** `closechannel`. */
    const val CLOSE_CHANNEL = "Close connection(s)"

    /** `closechannel2`. */
    const val CLOSE_CHANNEL_2 =
        "If you close your lightning connection(s), its funds will be deposited back into your wallet.\n\n" +
            "Please wait for this transaction to show up, before definitively removing this wallet from your device."

    /** `closechannel6`. */
    const val CLOSE_CHANNEL_6 = "Connection Closure Issue"

    /** `closechannel7`. */
    const val CLOSE_CHANNEL_7 =
        "The lightning connection could not be closed normally, possibly because the bittr node is offline " +
            "or there's a connection issue.\n\nYou can close the connection unilaterally (force close), but this " +
            "will require higher transaction fees and may take longer to complete."

    /** `stillclosing`. */
    const val STILL_CLOSING =
        "Your Lightning connection is still being closed. For your safety, the wallet can only be reset once " +
            "the connection is fully closed and the funds have returned on-chain — this can take a while.\n\n" +
            "Please reopen the app later to finish the reset. Do not delete the app from your phone, as this " +
            "will lead to loss of funds."

    /** `closeretrylater`. */
    const val CLOSE_RETRY_LATER =
        "Your Lightning connection could not be closed right now — the bittr node may be temporarily offline. " +
            "Your wallet has not been reset.\n\nPlease reopen the app to try again later. Do not delete the app " +
            "from your phone, as this will lead to loss of funds."

    /** `forceclose`. */
    const val FORCE_CLOSE = "Force Close"

    /** `forceclose3`. */
    const val FORCE_CLOSE_3 = "Force close also failed. Please try again later or contact support."

    /** `forceclose4`. */
    const val FORCE_CLOSE_4 =
        "Force close initiated successfully. This may take longer than normal closure due to higher transaction fees."

    /** `removalinprogress`. */
    const val REMOVAL_IN_PROGRESS =
        "It looks like you started removing this wallet from your device, but it wasn't finished — a Lightning " +
            "connection may still have been closing.\n\nWould you like to try removing it again?"

    /** `removalfailed`. */
    const val REMOVAL_FAILED =
        "Something went wrong removing your wallet, so it hasn't been removed — your wallet and funds are safe.\n\n" +
            "Please reopen the app to try again. Do not delete the app from your phone."

    /** `pinlock`. */
    const val PIN_LOCK = "You've entered an incorrect PIN too many times. Please restore your wallet."

    /** `syncingwallet` / `syncingwallet2`. */
    const val SYNCING_WALLET = "Syncing wallet"
    const val SYNCING_WALLET_2 = "Please wait a moment while we're syncing your wallet."

    const val REMOVE = "Remove"
    const val TRY_AGAIN = "Try again"
    const val CANCEL = "Cancel"
    const val OKAY = "Okay"
}
