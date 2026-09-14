package com.bittr.android.core.wallet.ldk.onchain

/**
 * What a drain-the-wallet PSBT came out at.
 *
 * Port of `OnchainDrainPreview` (`BDKManager.swift:11–15`). `drainTo` produces
 * exactly one output, so its value is the maximum sendable — that invariant is
 * the adapter's to uphold when it builds this, and
 * `WalletError.drainProducedNoOutput` is what iOS throws when it does not hold.
 */
data class OnchainDrainPreview(
    val sendableSats: ULong,
    val feeSats: ULong,
    val vsize: ULong,
)

/**
 * Reconciling BDK's idea of the maximum sendable with LDK Node's.
 *
 * Port of the clamp in `maximumSendableOnchainDrain`
 * (`BDKManager.swift:420–444`). The two libraries share one on-chain wallet and
 * disagree about how much of it may leave, and iOS's comment says why:
 *
 * > BDK knows nothing about the reserve LDK Node holds back for anchor
 * > channels, so it will happily drain it; LDK's spendable balance is the
 * > authority on what may actually leave.
 *
 * That reserve is `NodeConfigPlan.ANCHOR_RESERVE_SATS` — 1000 sats per anchor
 * channel, kept so a commitment transaction can be fee-bumped. Drain it and the
 * channel loses its ability to get its own force-close confirmed, which is the
 * expensive way to find out. So the rule is **take the more conservative of the
 * two**, always.
 *
 * ## The `null` row is the whole reason this is a separate, tested function
 *
 * `satoshisOnchainSpendable` is `Int?` on iOS and the declaration says what the
 * `nil` means: *"nil until loadWalletData has read it from LDK Node"*
 * (`BittrWallet.swift:17`). iOS handles that case explicitly and comments it:
 *
 * > Balances haven't been read yet, so there's nothing to clamp against. Note
 * > this is NOT the same as a spendable balance of zero, which clamps to zero
 * > below.
 *
 * **Collapsing the two is the obvious port and it is wrong in the expensive
 * direction.** Kotlin makes it a one-character mistake — `ldkSpendableSats ?: 0`
 * reads as a tidy default and silently clamps every drain to **zero sats** for
 * the entire window between node start and the first balance read. The user sees
 * a maximum-sendable of nothing and cannot empty their own wallet. Note the rest
 * of the iOS codebase *does* use `?? 0` at its call sites
 * (`SendOnchain.swift:52`, `ConfirmSendViewController.swift:235`), so the
 * tempting precedent for the wrong behaviour is right there in the source —
 * those sites are comparing an entered amount, not computing a maximum, and the
 * distinction does not survive a careless port.
 *
 * Proved by `OnchainDrainClampTest`, which asserts the `null` and `0` rows give
 * different answers for identical previews.
 */
object OnchainDrainClamp {

    /**
     * @param preview what BDK's drain PSBT produced.
     * @param ldkSpendableSats LDK Node's `spendableOnchainBalanceSats`, or
     *   `null` if balances have not been read yet. **Not** a value to default.
     *   Signed, because iOS carries it as `Int` and clamps negatives at the call
     *   sites rather than at the source (`SendViewController.swift:189`).
     */
    fun clampToLdkSpendable(
        preview: OnchainDrainPreview,
        ldkSpendableSats: Long?,
    ): OnchainDrainPreview {
        // Nothing to clamp against. NOT zero — see the class comment.
        if (ldkSpendableSats == null) return preview

        val spendable = ldkSpendableSats.coerceAtLeast(0L).toULong()

        // iOS: `guard preview.sendableSats + preview.feeSats > spendable else
        // { return preview }`. BDK is already at or under LDK's spendable, so it
        // is the more conservative of the two and stands.
        //
        // The addition cannot overflow: both terms are satoshi amounts drawn
        // from one wallet, so their sum is bounded by the 2.1e15-sat money
        // supply, four orders of magnitude below `ULong.MAX_VALUE`.
        if (preview.sendableSats + preview.feeSats <= spendable) return preview

        // LDK is the authority and it is lower. Spend down to its limit, leaving
        // the fee intact: `spendable > fee ? spendable - fee : 0`.
        val clamped = if (spendable > preview.feeSats) spendable - preview.feeSats else 0uL
        return preview.copy(sendableSats = clamped)
    }
}
