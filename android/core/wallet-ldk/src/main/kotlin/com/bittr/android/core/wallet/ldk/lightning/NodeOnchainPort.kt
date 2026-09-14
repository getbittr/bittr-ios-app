package com.bittr.android.core.wallet.ldk.lightning

/**
 * An address on the chain, from **the node's** on-chain wallet.
 *
 * A wrapper around a string, and the wrapper is the point: this repository has
 * two on-chain wallets derived from the same twelve words, and a bare `String`
 * called `address` gives a caller no way to notice it is holding the wrong
 * one's. See [NodeOnchainPort] for which is which and what confusing them
 * costs.
 *
 * Not validated here. What makes an address valid is the network it is for, and
 * the only thing in the process that knows the node's network is the node —
 * `LdkEnvironmentConfig` decides it at build time and `RegtestEnvironmentTest`
 * asserts it on the device. A regex here would be a second, weaker opinion.
 */
@JvmInline
value class OnchainAddressView(val address: String)

/**
 * The node's on-chain receive surface — **the wallet that funds a channel**.
 *
 * BIT-132, `android/docs/wallet-node-device-tests.md` §3 item 1. K7 pays a hold
 * invoice from the device and kills the process mid-flight; before it can pay
 * anything it needs a channel, and before it can open a channel it needs a
 * confirmed UTXO of its own. The host has bitcoind and can send to any address
 * it is given — so the only missing piece was a way to *ask the device* which
 * address to send to.
 *
 * ## Why the host cannot derive the address instead
 *
 * The shortcut that does not work, recorded because it is the first thing
 * anyone will try: pick the mnemonic on the host, derive the first receive
 * address there, fund it before the emulator boots. That needs ldk-node 0.7.0's
 * exact derivation, and it is not recoverable from the artefact — `strings`
 * over `libldk_node.so` in all three shipped ABIs finds the descriptor and
 * BIP-32 machinery and **no derivation-path literal**. A guess produces a test
 * that funds an address nothing is watching and then fails at `openChannel`
 * with an insufficient-funds error that says nothing whatever about
 * derivation. So the device is asked, and asking is a port.
 *
 * ## Which of the two on-chain wallets this is, and why it matters
 *
 * **ldk-node's, never BDK's.** Both are derived from the same seed —
 * `WalletModule` hands one `SecureStoreSeedVault` to `LdkNodeFactory` and to
 * `BdkOnchainWalletHolder` precisely so they cannot disagree about the
 * mnemonic — but they are two wallets with two descriptors and two address
 * sequences, and only ldk-node's is the one `openChannel` spends from.
 *
 * Funding `BdkOnchainWalletHolder`'s address instead is the quiet failure this
 * type exists to prevent: the transaction confirms, the chain is right, BDK
 * reports a balance, and the channel open fails for want of funds. That is also
 * why this interface is in `lightning/` next to [LightningNodePort] rather than
 * in `onchain/`, which is BDK's package — filing it beside `BdkStore` would put
 * the two address sources one directory listing apart, and BIT-126 already
 * found that the on-chain *balance* the app shows is ldk-node's rather than
 * BDK's for a related reason.
 *
 * ## Why it is not a widening of `LightningNodePort`
 *
 * That port is channels, peers and payments — Lightning — and it is the surface
 * the send and home screens will inject. This is the chain. They are separate
 * interfaces for the same reason `LdkEnvironment.chainSourceUrl` and
 * `electrumUrl` are separate fields: two protocols that happen to be reached
 * through one object are still two things, and a caller that needs a receive
 * address should not be handed `forceCloseChannel`.
 *
 * ## Send
 *
 * [sendToAddress] and [sendAllToAddress] are the Send screen's broadcast —
 * `BitcoinManager.sendOnchainPayment` / `sendAllOnchainPayment`. BDK builds the
 * previews the screen quotes from; ldk-node's wallet is the one that spends,
 * because it is the one that knows which outputs back a channel reserve.
 *
 * ## Read or write
 *
 * [newReceiveAddress] is a **write**, and it throws [NodeUnavailableException]
 * with no node, rather than answering null the way [LightningNodePort]'s reads
 * do. That is not a style choice: `newAddress()` reveals the next unused
 * address and persists the advanced index, so it changes the wallet's durable
 * state. There is also no honest empty value for it — a caller that asked for
 * an address and received null would have to invent one, and the addresses a
 * caller invents are the addresses nobody is watching.
 */
interface NodeOnchainPort {

    /**
     * Reveal the node's next unused receive address, advancing its index.
     *
     * @throws NodeUnavailableException when no node is running — a teardown, a
     *   service restart racing the call, or an unconfigured build, which is the
     *   one CI assembles and Maestro installs.
     */
    fun newReceiveAddress(): OnchainAddressView

    /**
     * Broadcast [amountSats] to [address] at [feeRateSatPerVb] (at least 1). Returns the txid.
     *
     * @throws NodeUnavailableException when no node is running.
     */
    fun sendToAddress(address: String, amountSats: Long, feeRateSatPerVb: ULong): String

    /**
     * Send everything spendable to [address], keeping the anchor-channel reserve
     * (`retainReserve: true`, as iOS does). Returns the txid.
     *
     * @throws NodeUnavailableException when no node is running.
     */
    fun sendAllToAddress(address: String, feeRateSatPerVb: ULong): String
}
