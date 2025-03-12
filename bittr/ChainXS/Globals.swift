//
//  Globals.swift
//
//  Created by raidshift
//

import Foundation
import secp256k1

enum CHAINXS_ERR: Error {
    case INVALID_PUB_KEY
    case INVALID_PRIV_KEY
    case INVALID_CHAIN_CODE
    case INVALID_FINGERPRINT
    case INVALID_EXTENDED_KEY
    case INVALID_CHILD_HD_NODE
    case HARDENED_HD_NODE_NOT_ALLOWED
    case PRIV_KEY_NOT_ACCESSIBLE
    case INVALID_DERIVATION_PATH
    case INVALID_ENTROPY_LENGTH
    case INVALID_MENMONIC
    case INVALID_SEED
    case INVALID_DATA
    case UNKNOWN_KEY
}

enum Network {
    case TEST
    case MAIN
}

enum ExtendedKeyPrefix {
    case BIP32 // xpub,xprv,tpub,tprv
    case BIP49 // ypub,xprv,upub,uprv
    case BIP84 // zpub,zprv,vpub,vprv
}

let PUB_KEY = 0
let P2PKH_KEY = 1
// let P2SH_P2WPK_KEY = 2
let P2WPKH_KEY: Int = 2
let XPUB_KEY = 3
let YPUB_KEY = 4
let ZPUB_KEY = 5
let ETH_ADDRESS_KEY = 6
let TRX_ADDRESS_KEY = 7
let KAS_ADDRESS_KEY = 8
let KAS_TEST_ADDRESS_KEY = 9
let PRIV_KEY = 10
let WIF_KEY = 11
let XPRV_KEY = 12
let YPRV_KEY = 13
let ZPRV_KEY = 14

let KEY_LAST_ELEMENT = 14
let PRIV_KEYS_AFTER = 9

let KEYS = [
    PUB_KEY: "Public Key",
    P2PKH_KEY: "Bitcoin Address (P2PKH)",
    // P2SH_P2WPK_KEY: "Bitcoin Address (P2SH-P2WPK)",
    P2WPKH_KEY: "Bitcoin Address (P2WPKH)",
    XPUB_KEY: "Extended Public Key (xpub)",
    YPUB_KEY: "Extended Public Key (ypub)",
    ZPUB_KEY: "Extended Public Key (zpub)",
    ETH_ADDRESS_KEY: "Ethereum Address",
    TRX_ADDRESS_KEY: "Tron Address",
    KAS_ADDRESS_KEY: "Kaspa Address",
    KAS_TEST_ADDRESS_KEY: "Kaspa Test Address",
    PRIV_KEY: "Private Key",
    WIF_KEY: "Private Key (WIF)",
    XPRV_KEY: "Extended Private Key (xprv)",
    YPRV_KEY: "Extended Private Key (yprv)",
    ZPRV_KEY: "Extended Private Key (zprv)",
]

enum DERIVATION_PATH {
    case DEFAULT_PRIVATE_DERIVATION_PATH
    case DEFAULT_PUBLIC_DERIVATION_PATH
    case BIP44_BTC_DERIVATION_PATH
    case BIP44_ETH_DERIVATION_PATH
    case BIP44_TRX_DERIVATION_PATH
    case BIP44_KAS_DERIVATION_PATH
    case BIP49_BTC_DERIVATION_PATH
    case BIP84_BTC_DERIVATION_PATH
}

let DERIVATION_PATHS: [DERIVATION_PATH: (path: String, atLevel: Int, desc: String)] =
    [
        .DEFAULT_PRIVATE_DERIVATION_PATH: ("m/0'/0", 2, "Default (Private)"),
        .DEFAULT_PUBLIC_DERIVATION_PATH: ("M/0/0", 2, "Default (Public)"),
        .BIP44_BTC_DERIVATION_PATH: ("m/44'/0'/0'/0/0", 3, "BIP44 (Bitcoin)"),
        .BIP44_ETH_DERIVATION_PATH: ("m/44'/60'/0'/0/0", 3, "BIP44 (Ethereum)"),
        .BIP44_TRX_DERIVATION_PATH: ("m/44'/195'/0'/0/0", 3, "BIP44 (Tron)"),
        .BIP44_KAS_DERIVATION_PATH: ("m/44'/111111'/0'/0/0", 5, "BIP44 (Kaspa)"),
        .BIP49_BTC_DERIVATION_PATH: ("m/49'/0'/0'/0/0", 3, "BIP49 (Bitcoin)"),
        .BIP84_BTC_DERIVATION_PATH: ("m/84'/0'/0'/0/0", 3, "BIP84 (Bitcoin)"),
    ]

typealias ExtendedKey = (version: UInt32, depth: UInt8, parentFingerprint: Data, index: UInt32, chainCode: Data, key: Data, isPrivate: Bool)

enum ChainXSContext {
    static var p2pkhPrefix: UInt8!
    static var p2shPrefix: UInt8!
    static var p2wpkhPrefix: String!
    static var p2wpkhVersion: Int!
    static var extendedPubKeyPrefixes: [ExtendedKeyPrefix: UInt32]!
    static var extendedPrivKeyPrefixes: [ExtendedKeyPrefix: UInt32]!
    static var kaspaPrefix: String!
    static var kaspaTestPrefix: String!
    static var kaspaVersion: Int!
    static var wifPrefix: UInt8!
    static var trxPrefix: UInt8!
    static var scriptHashPrefix: UInt8!
    static var scriptCommand_OP_0: [UInt8]!

    static var secp256k1Ctx: OpaquePointer!

    static func setNetwork(_ network: Network) {
        switch network {
        case .MAIN:
            ChainXSContext.p2pkhPrefix = 0x00
            ChainXSContext.p2shPrefix = 0x05
            ChainXSContext.p2wpkhPrefix = "bc"
            ChainXSContext.p2wpkhVersion = 0
            ChainXSContext.wifPrefix = 0x80
            ChainXSContext.extendedPubKeyPrefixes = [.BIP32: 0x0488_B21E, .BIP49: 0x049D_7CB2, .BIP84: 0x04B2_4746]
            ChainXSContext.extendedPrivKeyPrefixes = [.BIP32: 0x0488_ADE4, .BIP49: 0x049D_7878, .BIP84: 0x04B2_430C]
            ChainXSContext.kaspaVersion = 0
        case .TEST:
            ChainXSContext.p2pkhPrefix = 0x6F
            ChainXSContext.p2shPrefix = 0xCF
            ChainXSContext.p2wpkhPrefix = "tb"
            ChainXSContext.p2wpkhVersion = 0
            ChainXSContext.wifPrefix = 0xEF
            ChainXSContext.extendedPubKeyPrefixes = [.BIP32: 0x0435_87CF, .BIP49: 0x044A_5262, .BIP84: 0x045F_1CF6]
            ChainXSContext.extendedPrivKeyPrefixes = [.BIP32: 0x0435_8394, .BIP49: 0x044A_4E28, .BIP84: 0x045F_18BC]
            ChainXSContext.kaspaVersion = 0
        }
        ChainXSContext.trxPrefix = 0x41
        ChainXSContext.scriptCommand_OP_0 = [0x00, 0x14]
        ChainXSContext.kaspaPrefix = "kaspa"
        ChainXSContext.kaspaTestPrefix = "kaspatest"
    }

    static func createSecp256k1Ctx() throws {
        ChainXSContext.secp256k1Ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY))
        try Data(randomOfLength: 32).withUnsafeBytes {
            let status = secp256k1_context_randomize(ChainXSContext.secp256k1Ctx!, $0.baseAddress!.assumingMemoryBound(to: UInt8.self))
            assert(status == 1)
        }
    }

    static func destroySecp256k1Ctx() {
        if ChainXSContext.secp256k1Ctx != nil {
            secp256k1_context_destroy(ChainXSContext.secp256k1Ctx)
            ChainXSContext.secp256k1Ctx = nil
        }
    }
}
