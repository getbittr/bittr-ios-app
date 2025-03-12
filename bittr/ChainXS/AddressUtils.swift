//
//  AddressUtils.swift
//
//  Created by raidshift
//

import CommonCrypto
import Foundation
import secp256k1

func isValidPubKey(_ pubKey: Data) -> Bool {
    var secp256k1_pubk = secp256k1_pubkey()

    return pubKey.withUnsafeBytes {
        secp256k1_ec_pubkey_parse(ChainXSContext.secp256k1Ctx, &secp256k1_pubk, $0.baseAddress!.assumingMemoryBound(to: UInt8.self), pubKey.count) == 1
    }
}

func isValidPrivKey(_ privKey: Data?) -> Bool {
    if privKey == nil { return false }

    return privKey!.withUnsafeBytes {
        privKey!.count == 32 && secp256k1_ec_seckey_verify(ChainXSContext.secp256k1Ctx, $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) == 1
    }
}

func createPrivKey() throws -> Data {
    return try Data(randomOfLength: 32)
}

func appendChecksum(_ data: inout Data) throws -> Data {
    if data.count < 1 { throw CHAINXS_ERR.INVALID_DATA }
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

    data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
    _ = CC_SHA256(hash, CC_LONG(hash.count), &hash)

    data.append(hash, count: 4)

    return data
}

func verifyChecksum(_ dataWithChecksum: Data) -> Bool {
    if dataWithChecksum.count < 5 { return false }

    let checksumFromData = dataWithChecksum.subdata(in: (dataWithChecksum.count - 4) ..< dataWithChecksum.count)
    let data = dataWithChecksum.subdata(in: 0 ..< (dataWithChecksum.count - 4))
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

    data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
    _ = CC_SHA256(hash, CC_LONG(hash.count), &hash)

    let checksumFromHash = Data(hash).subdata(in: 0 ..< 4)

    return checksumFromData == checksumFromHash ? true : false
}

func createWIF(privKey: Data, compressedPubKey: Bool) throws -> String {
    if !isValidPrivKey(privKey) { throw CHAINXS_ERR.INVALID_PRIV_KEY }
    var version: UInt8 = ChainXSContext.wifPrefix
    var compression: UInt8 = 0x01

    var extendedPrivKey = Data(bytes: &version, count: MemoryLayout<UInt8>.size)
    extendedPrivKey.append(privKey)
    if compressedPubKey { extendedPrivKey.append(&compression, count: MemoryLayout<UInt8>.size) }

    return try appendChecksum(&extendedPrivKey).base58CheckString
}

func createPubKey(privKey: Data, compress: Bool) throws -> Data {
    if !isValidPrivKey(privKey) { throw CHAINXS_ERR.INVALID_PRIV_KEY }

    var len: Int = compress ? 33 : 65
    var pubKeySerialized = [UInt8](repeating: 0, count: len)

    var secp256k1PubKey = secp256k1_pubkey()
    privKey.withUnsafeBytes {
        let status = secp256k1_ec_pubkey_create(ChainXSContext.secp256k1Ctx, &secp256k1PubKey, $0.baseAddress!.assumingMemoryBound(to: UInt8.self))
        assert(status == 1)
    }
    let status = secp256k1_ec_pubkey_serialize(ChainXSContext.secp256k1Ctx, &pubKeySerialized, &len, &secp256k1PubKey, compress ? UInt32(SECP256K1_EC_COMPRESSED) : UInt32(SECP256K1_EC_UNCOMPRESSED))
    assert(status == 1)

    return Data(pubKeySerialized)
}

func HASH_160(_ data: Data) -> Data {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }

    return RIPEMD160.hash(message: Data(bytes: &hash, count: hash.count))
}

func createP2PKHAddress(_ pubKey: Data) throws -> String {
    if !isValidPubKey(pubKey) { throw CHAINXS_ERR.INVALID_PUB_KEY }

    var pubAddress = Data([ChainXSContext.p2pkhPrefix] + [UInt8](HASH_160(pubKey)))

    return try appendChecksum(&pubAddress).base58CheckString
}

func createP2SH_P2WPKAddress(_ compressedPubKey: Data) throws -> String {
    if !isValidPubKey(compressedPubKey) || compressedPubKey.count != 33 { throw CHAINXS_ERR.INVALID_PUB_KEY }

    let redeemScript = Data(ChainXSContext.scriptCommand_OP_0 + [UInt8](HASH_160(compressedPubKey)))
    var pubAddress = Data([ChainXSContext.p2shPrefix] + [UInt8](HASH_160(redeemScript)))

    return try appendChecksum(&pubAddress).base58CheckString
}

func createP2WPKHAddress(_ compressedPubKey: Data) throws -> String {
    if !isValidPubKey(compressedPubKey) || compressedPubKey.count != 33 { throw CHAINXS_ERR.INVALID_PUB_KEY }

    return try SegwitAddrCoder().encode(hrp: ChainXSContext.p2wpkhPrefix, version: ChainXSContext.p2wpkhVersion, program: HASH_160(compressedPubKey))
}
