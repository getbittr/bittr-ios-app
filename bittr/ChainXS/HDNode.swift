//
//  HDNode.swift
//  ChainXS
//
//  Created by raidshift
//

import CommonCrypto
import Foundation
import secp256k1

let regExMnemonic = try? NSRegularExpression(pattern: "^[a-z]+([\\s]+[a-z]+)+$", options: .caseInsensitive)
let regExMnemonicWords = try? NSRegularExpression(pattern: "[a-z]+", options: .caseInsensitive)

struct HDNode: CustomStringConvertible {
    let privKey: Data?
    let compressedPubKey: Data
    let uncompressedPubKey: Data
    let chainCode: Data
    let parentFingerprint: Data
    let index: UInt32
    let depth: UInt8

    var description: String { return "HD_NODE:\n PRIV = \(privKey == nil ? "nil" : try! createWIF(privKey: privKey!, compressedPubKey: true))\n PUB  = \(try! createP2PKHAddress(compressedPubKey))\n CC   = \(chainCode.hexString)\n FP   = \(parentFingerprint.hexString)\n IDX  = \(index)\n DPT  = \(depth)" }

    private init(key: Data, isPrivateKey: Bool, chainCode: Data, parentFingerprint: Data, index: UInt32, depth: UInt8) throws {
        if chainCode.count != 32 { throw CHAINXS_ERR.INVALID_CHAIN_CODE }
        if parentFingerprint.count != 4 { throw CHAINXS_ERR.INVALID_FINGERPRINT }
        if isPrivateKey {
            if !isValidPrivKey(key) { throw CHAINXS_ERR.INVALID_PRIV_KEY }
            privKey = key
            compressedPubKey = try createPubKey(privKey: key, compress: true)
            uncompressedPubKey = try createPubKey(privKey: key, compress: false)
        } else {
            if !isValidPubKey(key) { throw CHAINXS_ERR.INVALID_PUB_KEY }
            privKey = nil
            compressedPubKey = key
            var secp256k1PubKey: secp256k1_pubkey = .init()
            var compressedPubKeyArr = [UInt8](compressedPubKey)
            _ = secp256k1_ec_pubkey_parse(ChainXSContext.secp256k1Ctx, &secp256k1PubKey, &compressedPubKeyArr, compressedPubKeyArr.count)
            var len: Int = 65
            var pubKeySerialized = [UInt8](repeating: 0, count: len)
            _ = secp256k1_ec_pubkey_serialize(ChainXSContext.secp256k1Ctx, &pubKeySerialized, &len, &secp256k1PubKey, UInt32(SECP256K1_EC_UNCOMPRESSED))
            uncompressedPubKey = Data(pubKeySerialized)
        }
        self.chainCode = chainCode
        self.parentFingerprint = parentFingerprint
        self.index = index
        self.depth = depth
    }

    init(key: Data, isPrivateKey: Bool, chainCode: Data) throws {
        try self.init(key: key, isPrivateKey: isPrivateKey, chainCode: chainCode, parentFingerprint: Data(repeating: 0, count: 4), index: 0, depth: 0)
    }

    init(seed: Data) throws {
        let key: [UInt8] = Array("Bitcoin seed".utf8)
        var hmac = [UInt8](repeating: 0, count: 64)

        seed.withUnsafeBytes {
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA512), key, key.count, $0.baseAddress, seed.count, &hmac)
        }

        let hmacData = Data(hmac)
        try self.init(key: hmacData.left, isPrivateKey: true, chainCode: hmacData.right)
    }

    init(extendedKey: String) throws {
        let decomposedExtendedKey = try decomposeExtendedKey(extendedKey: extendedKey)

        try self.init(key: decomposedExtendedKey.key, isPrivateKey: decomposedExtendedKey.isPrivate, chainCode: decomposedExtendedKey.chainCode, parentFingerprint: decomposedExtendedKey.parentFingerprint, index: decomposedExtendedKey.index, depth: decomposedExtendedKey.depth)
    }

    func ckdPriv(childIndex: UInt32) throws -> HDNode {
        if !isValidPrivKey(privKey) { throw CHAINXS_ERR.INVALID_PRIV_KEY }

        var data: Data = childIndex >= HARDENED_KEY_TRESHOLD ? Data([0x00]) + privKey! : compressedPubKey
        var childIndexBE = childIndex.bigEndian

        data += Data(bytes: &childIndexBE, count: MemoryLayout<UInt32>.size)

        var hmac = [UInt8](repeating: 0, count: 64)
        chainCode.withUnsafeBytes { (parentChainCodePtr: UnsafeRawBufferPointer) in
            data.withUnsafeBytes { (dataPtr: UnsafeRawBufferPointer) in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA512), parentChainCodePtr.baseAddress, chainCode.count, dataPtr.baseAddress, data.count, &hmac)
            }
        }
        let hmacData = Data(bytesNoCopy: &hmac, count: hmac.count, deallocator: .none)

        let left = hmacData.left

        if !isValidPrivKey(left) { throw CHAINXS_ERR.INVALID_CHILD_HD_NODE }

        var childPrivKey = privKey!

        try childPrivKey.withUnsafeMutableBytes { (keyPtr: UnsafeMutableRawBufferPointer) in
            try left.withUnsafeBytes { (tweakPtr: UnsafeRawBufferPointer) in
                if secp256k1_ec_privkey_tweak_add(ChainXSContext.secp256k1Ctx, keyPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), tweakPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)) != 1 {
                    throw CHAINXS_ERR.INVALID_CHILD_HD_NODE
                }
            }
        }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        compressedPubKey.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(self.compressedPubKey.count), &hash) }

        return try HDNode(key: childPrivKey,
                          isPrivateKey: true,
                          chainCode: hmacData.right,
                          parentFingerprint: RIPEMD160.hash(message: Data(bytesNoCopy: &hash, count: hash.count, deallocator: .none)).subdata(in: 0 ..< 4),
                          index: childIndex,
                          depth: depth + 1)
    }

    func ckdPub(childIndex: UInt32) throws -> HDNode {
        if childIndex >= HARDENED_KEY_TRESHOLD { throw CHAINXS_ERR.HARDENED_HD_NODE_NOT_ALLOWED }

        var data = compressedPubKey
        var childIndexBE = childIndex.bigEndian

        data += Data(bytes: &childIndexBE, count: MemoryLayout<UInt32>.size)

        var hmac = [UInt8](repeating: 0, count: 64)
        chainCode.withUnsafeBytes { (parentChainCodePtr: UnsafeRawBufferPointer) in
            data.withUnsafeBytes { (dataPtr: UnsafeRawBufferPointer) in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA512), parentChainCodePtr.baseAddress, chainCode.count, dataPtr.baseAddress, data.count, &hmac)
            }
        }
        let hmacData = Data(bytesNoCopy: &hmac, count: hmac.count, deallocator: .none)

        let left = hmacData.left

        var secp256k1PubKey = secp256k1_pubkey()
        var len = 33
        var childCompressedPubKey = [UInt8](repeating: 0, count: len)

        compressedPubKey.withUnsafeBytes {
            let status = secp256k1_ec_pubkey_parse(ChainXSContext.secp256k1Ctx, &secp256k1PubKey, $0.baseAddress!.assumingMemoryBound(to: UInt8.self), compressedPubKey.count)
            assert(status == 1)
        }

        try left.withUnsafeBytes {
            if secp256k1_ec_pubkey_tweak_add(ChainXSContext.secp256k1Ctx, &secp256k1PubKey, $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) != 1 {
                throw CHAINXS_ERR.INVALID_CHILD_HD_NODE
            }
        }

        let status = secp256k1_ec_pubkey_serialize(ChainXSContext.secp256k1Ctx, &childCompressedPubKey, &len, &secp256k1PubKey, UInt32(SECP256K1_EC_COMPRESSED))
        assert(status == 1)

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        compressedPubKey.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(self.compressedPubKey.count), &hash) }

        return try HDNode(key: Data(childCompressedPubKey),
                          isPrivateKey: false,
                          chainCode: hmacData.right,
                          parentFingerprint: RIPEMD160.hash(message: Data(bytesNoCopy: &hash, count: hash.count, deallocator: .none)).subdata(in: 0 ..< 4),
                          index: childIndex,
                          depth: depth + 1)
    }

    func serialize(serializePrivKey: Bool, prefix: ExtendedKeyPrefix) throws -> String {
        var versionBE: UInt32

        if serializePrivKey {
            if privKey == nil { throw CHAINXS_ERR.PRIV_KEY_NOT_ACCESSIBLE }
            versionBE = ChainXSContext.extendedPrivKeyPrefixes[prefix]!.bigEndian
        } else {
            versionBE = ChainXSContext.extendedPubKeyPrefixes[prefix]!.bigEndian
        }

        var indexBE = index.bigEndian
        var depth = self.depth

        var serializedKey = Data()

        serializedKey += Data(bytes: &versionBE, count: MemoryLayout<UInt32>.size)
            + Data(bytes: &depth, count: MemoryLayout<UInt8>.size)
            + parentFingerprint
            + Data(bytes: &indexBE, count: MemoryLayout<UInt32>.size)
            + chainCode

        serializedKey += serializePrivKey ? Data(repeating: 0, count: 1) + privKey! : compressedPubKey

        return try appendChecksum(&serializedKey).base58CheckString
    }

    func ckdFromDerivationPath(decomomposedDerivationPath: DecomposedDerivationPath) throws -> HDNode {
        var derivedHDNode = self

        if decomomposedDerivationPath.isPrivate {
            for pathNodeIndex in decomomposedDerivationPath.pathNodeIndexes { derivedHDNode = try derivedHDNode.ckdPriv(childIndex: pathNodeIndex) }
        } else {
            for pathNodeIndex in decomomposedDerivationPath.pathNodeIndexes { derivedHDNode = try derivedHDNode.ckdPub(childIndex: pathNodeIndex) }
        }

        return derivedHDNode
    }

    func ckdFromDerivationPath(_ derivationPath: String) throws -> HDNode {
        return try ckdFromDerivationPath(decomomposedDerivationPath: decomposeDerivationPath(derivationPath))
    }

    func getKeyOrAddressByKey(_ key: Int) throws -> String {
        if key > PRIV_KEYS_AFTER, privKey == nil { throw CHAINXS_ERR.PRIV_KEY_NOT_ACCESSIBLE }

        switch key {
        case PUB_KEY:
            return compressedPubKey.hexString
        case XPUB_KEY:
            return try! serialize(serializePrivKey: false, prefix: ExtendedKeyPrefix.BIP32)
        case YPUB_KEY:
            return try! serialize(serializePrivKey: false, prefix: ExtendedKeyPrefix.BIP49)
        case ZPUB_KEY:
            return try! serialize(serializePrivKey: false, prefix: ExtendedKeyPrefix.BIP84)
        case P2PKH_KEY:
            let p2pkh = try! createP2PKHAddress(compressedPubKey)
            return p2pkh + String(repeating: " ", count: 34 - p2pkh.count)
        case P2WPKH_KEY:
            return try! createP2WPKHAddress(compressedPubKey)
        // case P2SH_P2WPK_KEY:
        //     return try! createP2SH_P2WPKAddress(compressedPubKey)
        case PRIV_KEY:
            return privKey!.hexString
        case WIF_KEY:
            return try! createWIF(privKey: privKey!, compressedPubKey: true)
        case XPRV_KEY:
            return try! serialize(serializePrivKey: true, prefix: ExtendedKeyPrefix.BIP32)
        case YPRV_KEY:
            return try! serialize(serializePrivKey: true, prefix: ExtendedKeyPrefix.BIP49)
        case ZPRV_KEY:
            return try! serialize(serializePrivKey: true, prefix: ExtendedKeyPrefix.BIP84)
        default:
            throw CHAINXS_ERR.UNKNOWN_KEY
        }
    }
}

func createMnemonic(_ entropyLen: Int) throws -> String {
    if entropyLen % 4 > 0 || entropyLen < 16 || entropyLen > 32 {
        throw CHAINXS_ERR.INVALID_ENTROPY_LENGTH
    }

    var bytes = [UInt8](repeating: 0, count: entropyLen + 1)
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    var mnemonic = ""

    if SecRandomCopyBytes(kSecRandomDefault, entropyLen, &bytes) != 0 { throw DATA_ERR.CORE_RND }
    _ = CC_SHA256(&bytes, CC_LONG(entropyLen), &hash)
    bytes[entropyLen] = hash[0] & (0xFF << (8 - UInt8(entropyLen) / 4))

    bytes.withUnsafeBytes {
        for i in 0 ..< entropyLen * 3 / 4 {
            let j = i % 8
            let value: Int = Data(bytes: $0.baseAddress! + ((i / 8) * 11) + j, count: 4).withUnsafeBytes {
                Int(($0.load(as: UInt32.self).bigEndian << (j * 3)) >> 21)
            }
            if i > 0 { mnemonic += " " }
            mnemonic += MnemonicWordListEN[value]
        }
    }

    return mnemonic
}

func decomposeMnemonicWords(_ mnemonic: String) throws -> [String] {
    let trimmedMnemonic = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
    let nsTrimmedMnemonic = trimmedMnemonic as NSString
    var words: [String] = []

    // only chars and white spaces allowed
    if regExMnemonic!.matches(in: trimmedMnemonic, options: [], range: NSRange(location: 0, length: nsTrimmedMnemonic.length)).count != 1 {
        throw CHAINXS_ERR.INVALID_MENMONIC
    }

    // retrieve words
    var wordIdxs = try regExMnemonicWords!.matches(in: trimmedMnemonic, options: [], range: NSRange(location: 0, length: nsTrimmedMnemonic.length)).map {
        let word = nsTrimmedMnemonic.substring(with: $0.range).lowercased()
        guard let idx = MnemonicWordListEN.binarySearch(key: word) else { throw CHAINXS_ERR.INVALID_MENMONIC }
        words.append(word)
        return idx
    }

    let len = wordIdxs.count * 4 / 3
    if len % 4 > 0 || len < 16 || len > 32 { throw CHAINXS_ERR.INVALID_MENMONIC }

    wordIdxs.append(0)

    var bytes = [UInt8](repeating: 0, count: len + 1)
    var wordIdx: Int?

    for i in 0 ... len {
        let (j, k) = (i * 8).quotientAndRemainder(dividingBy: 11)

        wordIdx = wordIdxs[j]; if wordIdx == nil { throw CHAINXS_ERR.INVALID_MENMONIC }
        if k > 3 {
            bytes[i] = UInt8(wordIdx! << (k - 3) & 0x00FF)
            wordIdx = wordIdxs[j + 1]; if wordIdx == nil { throw CHAINXS_ERR.INVALID_MENMONIC }
        }
        bytes[i] ^= UInt8((wordIdx! >> ((14 - k) % 11)) & 0x00FF)
    }

    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    _ = CC_SHA256(&bytes, CC_LONG(len), &hash)
    if hash[0] & (0xFF << (8 - UInt8(len) / 4)) != bytes[len] { throw CHAINXS_ERR.INVALID_MENMONIC }

    return words
}

func createMnemonicSeed(mnemonic: String, passPhrase: String?) throws -> Data {
    let words = try decomposeMnemonicWords(mnemonic)

    var cleanMnemonic = ""
    for i in 0 ..< words.count {
        if i != 0 { cleanMnemonic += " " }
        cleanMnemonic += words[i]
    }

    let password: Data = cleanMnemonic.data(using: .utf8)!
    var salt: [UInt8] = Array(("mnemonic" + (passPhrase ?? "")).decomposedStringWithCompatibilityMapping.utf8)
    var seed = [UInt8](repeating: 0, count: 64)

    password.withUnsafeBytes {
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), $0.baseAddress!.assumingMemoryBound(to: Int8.self), password.count, &salt, salt.count, CCPBKDFAlgorithm(kCCPRFHmacAlgSHA512), 2048, &seed, seed.count)
        assert(status == 0)
    }

    return Data(seed)
}

func createMasterKey(_ seed: Data) throws -> Data {
    if seed.count != 64 { throw CHAINXS_ERR.INVALID_SEED }
    let key: [UInt8] = Array("Bitcoin seed".utf8)
    var hmac = [UInt8](repeating: 0, count: 64)

    seed.withUnsafeBytes {
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA512), key, key.count, $0.baseAddress, seed.count, &hmac)
    }

    return Data(hmac)
}

func decomposeExtendedKey(extendedKey: String) throws -> ExtendedKey {
    let extendedKeyData = extendedKey.base58CheckData

    if extendedKeyData.count != 82 || !verifyChecksum(extendedKeyData) { throw CHAINXS_ERR.INVALID_EXTENDED_KEY }

    let version = extendedKeyData.subdata(in: 0 ..< 4).withUnsafeBytes { $0.baseAddress!.load(as: UInt32.self) }.bigEndian
    let depth = extendedKeyData.subdata(in: 4 ..< 5).withUnsafeBytes { $0.baseAddress!.load(as: UInt8.self) }
    let parentFingerprint = extendedKeyData.subdata(in: 5 ..< 9)
    let index = extendedKeyData.subdata(in: 9 ..< 13).withUnsafeBytes { $0.baseAddress!.load(as: UInt32.self) }.bigEndian
    let chainCode = extendedKeyData.subdata(in: 13 ..< 45)

    let key: Data

    var isPrivateKey = false

    if ChainXSContext.extendedPubKeyPrefixes.values.contains(version) {
        key = extendedKeyData.subdata(in: 45 ..< 78)
        if !isValidPubKey(key) { throw CHAINXS_ERR.INVALID_PUB_KEY }
    } else if ChainXSContext.extendedPrivKeyPrefixes.values.contains(version) {
        try extendedKeyData.subdata(in: 45 ..< 46).withUnsafeBytes {
            if $0.baseAddress!.load(as: UInt8.self) != 0x00 { throw CHAINXS_ERR.INVALID_EXTENDED_KEY }
        }

        key = extendedKeyData.subdata(in: 46 ..< 78)
        if !isValidPrivKey(key) { throw CHAINXS_ERR.INVALID_PRIV_KEY }
        isPrivateKey = true
    } else {
        throw CHAINXS_ERR.INVALID_EXTENDED_KEY
    }

    return (version, depth, parentFingerprint, index, chainCode, key, isPrivateKey)
}
