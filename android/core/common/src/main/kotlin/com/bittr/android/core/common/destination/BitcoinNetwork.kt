package com.bittr.android.core.common.destination

/**
 * Which chain an address or invoice has to belong to for this build to accept it.
 *
 * iOS derives this from the build and nothing else — `EnvironmentConfig`:
 *
 * ```swift
 * static var bitcoinDevKitNetwork: BitcoinDevKit.Network {
 *     isDevelopment ? .regtest : .bitcoin
 * }
 * ```
 *
 * so the Debug build talks regtest and the shipped build talks mainnet. Android
 * mirrors that split already — the debug build is `com.bittr.android.regtest`, the
 * one Maestro installs — and `BuildConfig.BITCOIN_NETWORK` carries it to this
 * module, which cannot see `:app`'s `BuildConfig`.
 *
 * The network is a *parameter* of parsing rather than a global because the failure
 * it prevents is expensive and silent: a mainnet address pasted into a regtest
 * build parses fine as bech32, and the difference only shows up as a broadcast that
 * never confirms. [DestinationParser] therefore refuses an address whose prefix
 * belongs to another chain instead of shrugging and passing it on.
 *
 * [TESTNET] and [SIGNET] are here because their prefixes are the ones that would
 * otherwise be *silently accepted* by a regtest build — `tb1` and `bcrt1` are
 * distinct, but the base58 version bytes are shared across all three test chains,
 * so they have to be named to be distinguished.
 */
enum class BitcoinNetwork(
    /** The bech32/bech32m human-readable part for segwit addresses on this chain. */
    val bech32Hrp: String,
    /** The BOLT-11 currency prefix, i.e. the invoice HRP after `ln`. */
    val bolt11Prefix: String,
    /** The base58 version byte for a P2PKH address. */
    val p2pkhVersion: Int,
    /** The base58 version byte for a P2SH address. */
    val p2shVersion: Int,
) {
    MAINNET(bech32Hrp = "bc", bolt11Prefix = "bc", p2pkhVersion = 0x00, p2shVersion = 0x05),
    TESTNET(bech32Hrp = "tb", bolt11Prefix = "tb", p2pkhVersion = 0x6F, p2shVersion = 0xC4),
    SIGNET(bech32Hrp = "tb", bolt11Prefix = "tbs", p2pkhVersion = 0x6F, p2shVersion = 0xC4),
    REGTEST(bech32Hrp = "bcrt", bolt11Prefix = "bcrt", p2pkhVersion = 0x6F, p2shVersion = 0xC4),
    ;

    companion object {

        /**
         * Reads the name `:app` compiles into `BuildConfig.BITCOIN_NETWORK`.
         *
         * Unknown values fall back to [MAINNET] on purpose. A typo in a build file
         * must not turn the shipped app into one that accepts test-chain addresses;
         * the safe direction for an unrecognised network is the strictest one.
         */
        fun fromBuildConfig(name: String): BitcoinNetwork =
            entries.firstOrNull { it.name.equals(name, ignoreCase = true) } ?: MAINNET
    }
}
