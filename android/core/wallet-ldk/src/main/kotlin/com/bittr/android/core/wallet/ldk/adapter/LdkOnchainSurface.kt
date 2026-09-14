package com.bittr.android.core.wallet.ldk.adapter

import com.bittr.android.core.wallet.ldk.lightning.NodeOnchainPort
import com.bittr.android.core.wallet.ldk.lightning.NodeUnavailableException
import com.bittr.android.core.wallet.ldk.lightning.OnchainAddressView
import com.bittr.android.core.wallet.ldk.node.NodeLifecycle
import org.lightningdevkit.ldknode.FeeRate
import org.lightningdevkit.ldknode.OnchainPaymentInterface

/**
 * [NodeOnchainPort] over whatever node [lifecycle] currently holds.
 *
 * The composition `:app` cannot write, for the same reason
 * [lightningNodePort] is here: `wallet-ldk` depends on `ldk-node-android` with
 * `implementation`, so `OnchainPaymentInterface` is not on the app's compile
 * classpath and `di/WalletModule` could not name [LdkOnchainSurface]'s
 * constructor.
 *
 * ## A null [lifecycle] is the unconfigured build
 *
 * The same real case [lightningNodePort]'s comment describes, and it must
 * still compose: CI assembles an APK with no `LdkEnvironment`, Maestro installs
 * it, and a clone builds it. The port it gets is one whose single method throws
 * [NodeUnavailableException], which is [NodeOnchainPort]'s stated contract for
 * a missing node rather than a special case for tests.
 *
 * ## The handle is fetched per call, never held — twice over
 *
 * `NodeLifecycle.current` can go null between any two statements, so the node
 * is re-read on every call; that is [LdkNodeSurface]'s argument and it applies
 * unchanged. The second reason is new here: `onchainPayment()` is a UniFFI
 * object with its own pointer, and holding one across a node stop would be
 * holding a handle into a node the rest of the app has released.
 *
 * The handle is not closed, which matches [LdkNodeSurface]'s treatment of
 * `bolt11Payment()` — UniFFI registers a cleaner for it. This port is called
 * once per funding round rather than in a loop, so the cost of that is a
 * pointer waiting for the cleaner, not a leak that grows.
 */
fun nodeOnchainPort(lifecycle: NodeLifecycle?): NodeOnchainPort =
    LdkOnchainSurface { lifecycle?.current.ldkNode()?.onchainPayment() }

/**
 * ldk-node's on-chain wallet as a [NodeOnchainPort].
 *
 * ## Why the seam is above `Node` and not at it
 *
 * [LdkNodeSurface] takes `() -> Node?`, and the cost of that is stated in its
 * own comment: the forwarding half cannot be proved on the JVM, because `Node`
 * is a concrete UniFFI class whose methods cross into Rust. Nothing a test can
 * build is a `Node`.
 *
 * This class takes `() -> OnchainPaymentInterface?` instead, and the difference
 * is deliberate. `NodeInterface.onchainPayment()` is declared to return the
 * **concrete** `OnchainPayment`, so a fake node would be no help — but
 * `OnchainPaymentInterface` is a plain Kotlin interface that `OnchainPayment`
 * implements, and a test can implement it too. Putting the seam one level above
 * the concrete type is what makes `NodeOnchainPortTest` able to assert that a
 * running node's address is forwarded unchanged, and not only that a missing
 * one throws.
 *
 * That is worth more here than it would be for a balance read. This address is
 * where a test — and one day a user — sends money, and "forwarded unchanged" is
 * the whole of what this class does. A mapping bug would be an address that is
 * *almost* the node's.
 */
class LdkOnchainSurface(
    private val onchain: () -> OnchainPaymentInterface?,
) : NodeOnchainPort {

    override fun newReceiveAddress(): OnchainAddressView {
        val payment = onchain()
            ?: throw NodeUnavailableException(
                "Cannot reveal a receive address: no Lightning node is running. This " +
                    "is a teardown or a service restart racing the call, or a build " +
                    "with no LdkEnvironment in it — see NodeLifecycle.current and " +
                    "LdkEnvironmentConfig.missingFields().",
            )
        return OnchainAddressView(payment.newAddress())
    }

    override fun sendToAddress(address: String, amountSats: Long, feeRateSatPerVb: ULong): String =
        feeRate(feeRateSatPerVb).use { rate ->
            payment("send on-chain").sendToAddress(address, amountSats.toULong(), rate)
        }

    override fun sendAllToAddress(address: String, feeRateSatPerVb: ULong): String =
        feeRate(feeRateSatPerVb).use { rate ->
            payment("send on-chain").sendAllToAddress(address, true, rate)
        }

    private fun payment(action: String): OnchainPaymentInterface =
        onchain() ?: throw NodeUnavailableException("Cannot $action: no Lightning node is running.")

    /** `FeeRate.fromSatPerVbUnchecked(satVb: max(rate, 1))` — never below 1 sat/vB. */
    private fun feeRate(satPerVb: ULong): FeeRate = FeeRate.fromSatPerVbUnchecked(maxOf(satPerVb, 1uL))
}
