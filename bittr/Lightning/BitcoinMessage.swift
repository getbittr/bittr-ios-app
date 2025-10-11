//
//  BitcoinMessage.swift
//  bittr
//
//  Created by Ruben Waterman on 12/03/2025.
//
import Foundation
import P256K
import CryptoKit
import CommonCrypto
import libsecp256k1
import Security
import BitcoinDevKit
import Sentry

enum SegwitType {
    case p2wpkh
    case p2shP2wpkh
    case none
}

class BitcoinMessage {
    static func magicHash(message: String) -> Data {
        let messageBuffer = message.data(using: .utf8)!
        let prefixBuffer = "Bitcoin Signed Message:\n".data(using: .utf8)!
        
        let prefixLength = varintEncode(prefixBuffer.count)
        let messageLength = varintEncode(messageBuffer.count)
        
        var combined = Data()
        combined.append(prefixLength)
        combined.append(prefixBuffer)
        combined.append(messageLength)
        combined.append(messageBuffer)
        
        // Single SHA256 instead of double
        return sha256(combined)
    }
    
    static func varintEncode(_ value: Int) -> Data {
        if value < 0xfd {
            return Data([UInt8(value)])
        } else if value <= 0xffff {
            var data = Data([0xfd])
            data.append(UInt8(value & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
            return data
        } else if value <= 0xffffffff {
            var data = Data([0xfe])
            data.append(UInt8(value & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8((value >> 16) & 0xff))
            data.append(UInt8((value >> 24) & 0xff))
            return data
        } else {
            var data = Data([0xff])
            let bigValue = UInt64(value)
            for i in 0..<8 {
                data.append(UInt8((bigValue >> (i * 8)) & 0xff))
            }
            return data
        }
    }
    
    static func sha256(_ data: Data) -> Data {
        let hash = SHA256.hash(data: data)
        return Data(hash)
    }
    
    static func sign(message: String, privateKeyHex: String, segwitType: SegwitType = .none) throws -> String {
        let privateBytes = try! privateKeyHex.bytes
        let messageHash = magicHash(message: message)
        
        // Create recovery private key
        let recoveryKey = try P256K.Recovery.PrivateKey(dataRepresentation: privateBytes)
        
        // Create recovery signature
        let recoverySignature = try recoveryKey.signature(for: messageHash)
        let compactRep = try recoverySignature.compactRepresentation
        
        // Get recovery ID (0-3)
        var recoveryId = compactRep.recoveryId & 3
        
        // Adjust recovery ID based on segwit type
        switch segwitType {
        case .p2wpkh:
            recoveryId += 8 + 4  // Add 8 for segwit and 4 for P2WPKH
        case .p2shP2wpkh:
            recoveryId += 8      // Add 8 for segwit only
        case .none:
            recoveryId += 4      // Add 4 for compressed
        }
        
        // Create final signature format
        var signatureData = Data()
        signatureData.append(UInt8(27 + recoveryId))  // Base (27) + adjusted recoveryId
        signatureData.append(compactRep.signature)
        
        return signatureData.base64EncodedString()
    }
}

// MARK: - Key Derivation Implementation

enum KeyDerivationError: Error {
    case invalidPrivateKey
    case invalidPublicKey
    case invalidMnemonic
    case secp256k1Error
    case randomGenerationFailed
    case invalidDerivationPath
    case privateKeyNotAccessible
    case invalidChildNode
    case hardenedKeyNotAllowed
}

public enum KeyDerivationNetwork {
    case mainnet
    case testnet
}

private let KD_HARDENED_KEY_THRESHOLD: UInt32 = 0x80000000
private let KD_PUB_KEY = 0
private let KD_PRIV_KEY = 10

// Simplified KeyDerivation class for BitcoinMessage
public class SimpleKeyDerivation {
    private var secp256k1Context: OpaquePointer!
    private let mnemonic: String
    private let network: KeyDerivationNetwork
    
    public init(mnemonic: String, network: KeyDerivationNetwork = .mainnet) throws {
        self.mnemonic = mnemonic
        self.network = network
        
        // Initialize secp256k1 context
        secp256k1Context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY))
        
        // Randomize context
        var randomSeed = Data(count: 32)
        let result = randomSeed.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        guard result == errSecSuccess else {
            throw KeyDerivationError.randomGenerationFailed
        }
        
        randomSeed.withUnsafeBytes { bytes in
            _ = secp256k1_context_randomize(secp256k1Context, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
    }
    
    deinit {
        if secp256k1Context != nil {
            secp256k1_context_destroy(secp256k1Context)
        }
    }
    
    public func getPrivatePublicKeyForPath(_ path: String) throws -> (privateKeyHex: String, publicKeyHex: String) {
        // Create dummy master key - the real work is done in deriveKey
        let dummyMasterKey = Data(repeating: 0, count: 32)
        
        // Parse derivation path and derive key using proper BIP32
        let derivedKey = try deriveKey(from: dummyMasterKey, path: path)
        
        // Create public key
        let publicKey = try createPublicKey(from: derivedKey)
        
        return (derivedKey.hexString, publicKey.hexString)
    }
    
    
    private func deriveKey(from masterKey: Data, path: String) throws -> Data {
        // Proper BIP32 derivation implementation
        let masterSeed = try createMasterSeed(from: masterKey)
        let masterPrivateKey = masterSeed.prefix(32)
        let masterChainCode = masterSeed.suffix(32)
        
        // Parse the derivation path
        let pathComponents = try parseDerivationPath(path)
        
        var currentPrivateKey = masterPrivateKey
        var currentChainCode = masterChainCode
        
        // Derive each level in the path
        for pathIndex in pathComponents {
            let derivedData = try deriveChildKey(
                parentPrivateKey: currentPrivateKey,
                parentChainCode: currentChainCode,
                index: pathIndex
            )
            currentPrivateKey = derivedData.privateKey
            currentChainCode = derivedData.chainCode
        }
        
        return currentPrivateKey
    }
    
    private func createMasterSeed(from masterKey: Data) throws -> Data {
        // Use BDK's mnemonic implementation for proper seed generation
        let bdkMnemonic = try BitcoinDevKit.Mnemonic.fromString(mnemonic: mnemonic)
        
        // Create a DescriptorSecretKey to get the master key and chain code
        let descriptorKey = DescriptorSecretKey(network: network == .testnet ? .regtest : .bitcoin, mnemonic: bdkMnemonic, password: nil)
        
        // Get the extended key string and extract the master key
        let extendedKeyString = descriptorKey.asString()
        
        // Remove the "/*" suffix if present
        let cleanExtendedKey = extendedKeyString.replacingOccurrences(of: "/*", with: "")
        
        // Parse the extended key to extract the master private key and chain code
        let extendedKeyData = cleanExtendedKey.base58CheckData
        
        // BIP32 extended key format: version(4) + depth(1) + fingerprint(4) + index(4) + chain_code(32) + key(33)
        // For private keys, the key part starts with 0x00 followed by the 32-byte private key
        guard extendedKeyData.count == 82 else {
            throw KeyDerivationError.invalidMnemonic
        }
        
        let chainCode = extendedKeyData.subdata(in: 13..<45)  // bytes 13-44
        let privateKey = extendedKeyData.subdata(in: 46..<78) // bytes 46-77 (skip the 0x00 prefix)
        
        // Combine private key and chain code
        var result = Data()
        result.append(privateKey)
        result.append(chainCode)
        
        return result
    }
    
    private func parseDerivationPath(_ path: String) throws -> [UInt32] {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        
        guard trimmed.hasPrefix("m/") else {
            throw KeyDerivationError.invalidDerivationPath
        }
        
        let components = trimmed.dropFirst(2).components(separatedBy: "/")
        var indices: [UInt32] = []
        
        for component in components {
            let isHardened = component.hasSuffix("'")
            let numberString = isHardened ? String(component.dropLast()) : component
            
            guard let index = UInt32(numberString) else {
                throw KeyDerivationError.invalidDerivationPath
            }
            
            if isHardened {
                indices.append(index + KD_HARDENED_KEY_THRESHOLD)
            } else {
                indices.append(index)
            }
        }
        
        return indices
    }
    
    private struct ChildKeyData {
        let privateKey: Data
        let chainCode: Data
    }
    
    private func deriveChildKey(parentPrivateKey: Data, parentChainCode: Data, index: UInt32) throws -> ChildKeyData {
        var data = Data()
        
        let isHardened = index >= KD_HARDENED_KEY_THRESHOLD
        
        if isHardened {
            // Hardened derivation: use 0x00 + parent private key
            data.append(0x00)
            data.append(parentPrivateKey)
        } else {
            // Non-hardened derivation: use parent public key
            let parentPublicKey = try createPublicKey(from: parentPrivateKey)
            data.append(parentPublicKey)
        }
        
        // Append the index in big-endian format
        var indexBE = index.bigEndian
        data.append(Data(bytes: &indexBE, count: MemoryLayout<UInt32>.size))
        
        // Calculate HMAC-SHA512
        var hmac = [UInt8](repeating: 0, count: 64)
        parentChainCode.withUnsafeBytes { chainCodeBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA512), chainCodeBytes.baseAddress, parentChainCode.count, dataBytes.baseAddress, data.count, &hmac)
            }
        }
        
        let hmacData = Data(hmac)
        let left = hmacData.prefix(32)  // Child private key tweak
        let right = hmacData.suffix(32) // Child chain code
        
        // Verify the left part is a valid private key
        guard isValidPrivateKey(left) else {
            throw KeyDerivationError.invalidChildNode
        }
        
        // Add the tweak to the parent private key using secp256k1
        var childPrivateKey = parentPrivateKey
        
        let tweakResult = childPrivateKey.withUnsafeMutableBytes { keyBytes in
            left.withUnsafeBytes { tweakBytes in
                secp256k1_ec_seckey_tweak_add(
                    secp256k1Context,
                    keyBytes.bindMemory(to: UInt8.self).baseAddress!,
                    tweakBytes.bindMemory(to: UInt8.self).baseAddress!
                )
            }
        }
        
        guard tweakResult == 1 else {
            throw KeyDerivationError.invalidChildNode
        }
        
        return ChildKeyData(privateKey: childPrivateKey, chainCode: right)
    }
    
    private func createPublicKey(from privateKey: Data) throws -> Data {
        guard isValidPrivateKey(privateKey) else {
            throw KeyDerivationError.invalidPrivateKey
        }
        
        var publicKeySerialized = [UInt8](repeating: 0, count: 33)
        var len = 33
        
        var secp256k1PubKey = secp256k1_pubkey()
        
        let createResult = privateKey.withUnsafeBytes { bytes in
            secp256k1_ec_pubkey_create(secp256k1Context, &secp256k1PubKey, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        guard createResult == 1 else {
            throw KeyDerivationError.secp256k1Error
        }
        
        let serializeResult = secp256k1_ec_pubkey_serialize(
            secp256k1Context,
            &publicKeySerialized,
            &len,
            &secp256k1PubKey,
            UInt32(SECP256K1_EC_COMPRESSED)
        )
        
        guard serializeResult == 1 else {
            throw KeyDerivationError.secp256k1Error
        }
        
        return Data(publicKeySerialized)
    }
    
    private func isValidPrivateKey(_ privateKey: Data) -> Bool {
        guard privateKey.count == 32 else { return false }
        
        return privateKey.withUnsafeBytes { bytes in
            secp256k1_ec_seckey_verify(secp256k1Context, bytes.bindMemory(to: UInt8.self).baseAddress!) == 1
        }
    }
    
    // Test function to verify the key derivation
    public static func testKeyDerivation() {
        let testMnemonic = "void super old faith primary cradle behave crucial vault minor walk random"
        let testPath = "m/84'/1'/0'/0/0"
        let expectedPrivateKey = "4b596bede18150db341c9b1a71e1549bb69e3669805895ff8ad8ca873f76be09"
        let expectedPublicKey = "038338ab3db0f0e1ed78e295e4074197e6a0ab97195013690ecdf5a37998211049"
        
        do {
            // Test with BDK directly first
            let bdkMnemonic = try BitcoinDevKit.Mnemonic.fromString(mnemonic: testMnemonic)
            let bip32ExtendedRootKey = DescriptorSecretKey(network: .regtest, mnemonic: bdkMnemonic, password: nil)
            
            print("=== BDK REFERENCE TEST ===")
            print("BDK Root Key: \(bip32ExtendedRootKey.asString())")
            
            // Now test our implementation with the same logic as the actual function
            let actualNetwork: KeyDerivationNetwork = UserDefaults.standard.value(forKey: "envkey") as? Int == 0 ? .testnet : .mainnet
            print("Actual network from environment: \(actualNetwork)")
            
            let keyDerivation = try SimpleKeyDerivation(mnemonic: testMnemonic, network: actualNetwork)
            
            // Test seed generation first
            let masterSeed = try keyDerivation.createMasterSeed(from: Data())
            print("=== SEED GENERATION TEST ===")
            print("Master seed (first 32 bytes): \(masterSeed.prefix(32).hexString)")
            print("Chain code (last 32 bytes): \(masterSeed.suffix(32).hexString)")
            
            // Test path parsing
            let pathComponents = try keyDerivation.parseDerivationPath(testPath)
            print("=== PATH PARSING TEST ===")
            print("Path components: \(pathComponents.map { String(format: "0x%08x", $0) })")
            
            let (privateKeyHex, publicKeyHex) = try keyDerivation.getPrivatePublicKeyForPath(testPath)
            
            let signature = try! BitcoinMessage.sign(message: "Hello World", privateKeyHex: privateKeyHex, segwitType: .p2wpkh)
            
            print("=== KEY DERIVATION TEST ===")
            print("Mnemonic: \(testMnemonic)")
            print("Path: \(testPath)")
            print("Expected Private Key: \(expectedPrivateKey)")
            print("Actual Private Key:   \(privateKeyHex)")
            print("Private Key Match: \(privateKeyHex.lowercased() == expectedPrivateKey.lowercased())")
            print("")
            print("Expected Public Key: \(expectedPublicKey)")
            print("Actual Public Key:   \(publicKeyHex)")
            print("Public Key Match: \(publicKeyHex.lowercased() == expectedPublicKey.lowercased())")
            print("=== END TEST ===")
            print("Signature: \(signature)")
            
        } catch {
            print("Test failed with error: \(error)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "BitcoinMessage row 415", key: "context")
                }
            }
        }
    }
}

// MARK: - Extensions for Base58 and Hex String conversions

extension String {
    private static let base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    
    var base58CheckData: Data {
        let string = trimmingCharacters(in: CharacterSet.whitespaces)
        guard !string.isEmpty else { return Data() }
        
        var zerosCount = 0
        for c in string {
            if c != "1" { break }
            zerosCount += 1
        }
        
        let size = string.lengthOfBytes(using: .utf8) * 733 / 1000 + 1 - zerosCount
        var base58: [UInt8] = Array(repeating: 0, count: size)
        var length = 0
        
        for c in string where c != " " {
            guard let base58Index = String.base58Alphabet.firstIndex(of: c) else { return Data() }
            
            var carry = base58Index.utf16Offset(in: String.base58Alphabet)
            var i = 0
            
            for j in 0...base58.count where carry != 0 || i < length {
                carry += 58 * Int(base58[base58.count - j - 1])
                base58[base58.count - j - 1] = UInt8(carry % 256)
                carry /= 256
                i += 1
            }
            
            assert(carry == 0)
            length = i
        }
        
        var zerosToRemove = 0
        for b in base58 {
            if b != 0 { break }
            zerosToRemove += 1
        }
        base58.removeFirst(zerosToRemove)
        
        var result: [UInt8] = Array(repeating: 0, count: zerosCount)
        for b in base58 {
            result.append(b)
        }
        return Data(result)
    }
}

extension Data {
    public var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
