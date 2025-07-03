import Foundation
import CryptoKit
import P256K
// MARK: - Data Extensions

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        
        self = data
    }
    
//   func hexString() -> String {
//       return map { String(format: "%02x", $0) }.joined()
//   }
    
    func reversedData() -> Data {
        return Data(self.reversed())
    }
}

// MARK: - Integer Extensions

extension UInt16 {
    var littleEndianBytes: Data {
        return withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}

extension UInt32 {
    var littleEndianBytes: Data {
        return withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}

extension UInt64 {
    var littleEndianBytes: Data {
        return withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}

// MARK: - Bech32 Implementation

struct Bech32 {
    private static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private static let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    
    struct DecodedAddress {
        let prefix: String
        let version: UInt8
        let data: Data
    }
    
    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1
        for value in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(value)
            for i in 0..<5 {
                chk ^= ((top >> i) & 1) == 0 ? 0 : generator[i]
            }
        }
        return chk
    }
    
    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let hrpBytes = Array(hrp.utf8)
        var ret = hrpBytes.map { $0 >> 5 }
        ret.append(0)
        ret.append(contentsOf: hrpBytes.map { $0 & 31 })
        return ret
    }
    
    private static func verifyChecksum(_ hrp: String, _ data: [UInt8]) -> Bool {
        return polymod(hrpExpand(hrp) + data) == 1
    }
    
    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0
        var bits = 0
        var ret: [UInt8] = []
        let maxv = (1 << toBits) - 1
        let maxAcc = (1 << (fromBits + toBits - 1)) - 1
        
        for value in data {
            if Int(value) >> fromBits != 0 {
                return nil
            }
            acc = ((acc << fromBits) | Int(value)) & maxAcc
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                ret.append(UInt8((acc >> bits) & maxv))
            }
        }
        
        if pad {
            if bits > 0 {
                ret.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
        
        return ret
    }
    
    static func decode(_ address: String) -> DecodedAddress? {
        guard address.count >= 8 && address.count <= 90 else { return nil }
        
        // Find the last occurrence of '1'
        guard let pos = address.lastIndex(of: "1") else { return nil }
        let hrp = String(address[..<pos])
        let data = String(address[address.index(after: pos)...])
        
        guard hrp.count >= 1 && data.count >= 6 else { return nil }
        
        // Convert data characters to their numeric values
        var values: [UInt8] = []
        for char in data {
            guard let index = charset.firstIndex(of: char) else { return nil }
            values.append(UInt8(charset.distance(from: charset.startIndex, to: index)))
        }
        
        // Verify checksum
        guard verifyChecksum(hrp, values) else { return nil }
        
        // Remove checksum (last 6 characters)
        let dataValues = Array(values.prefix(values.count - 6))
        guard !dataValues.isEmpty else { return nil }
        
        let version = dataValues[0]
        let program = Array(dataValues[1...])
        
        // Convert from 5-bit to 8-bit
        guard let decoded = convertBits(data: program, fromBits: 5, toBits: 8, pad: false) else { return nil }
        
        // Validate program length based on version
        if version == 0 {
            guard decoded.count == 20 || decoded.count == 32 else { return nil }
        } else if version == 1 {
            guard decoded.count == 32 else { return nil }
        } else {
            guard decoded.count >= 2 && decoded.count <= 40 else { return nil }
        }
        
        return DecodedAddress(prefix: hrp, version: version, data: Data(decoded))
    }
}

// MARK: - Network Definitions

struct BitcoinNetwork {
    let bech32Prefix: String
    let pubKeyHashVersion: UInt8
    let scriptHashVersion: UInt8
    
    static let bitcoin = BitcoinNetwork(bech32Prefix: "bc", pubKeyHashVersion: 0x00, scriptHashVersion: 0x05)
    static let testnet = BitcoinNetwork(bech32Prefix: "tb", pubKeyHashVersion: 0x6f, scriptHashVersion: 0xc4)
    static let regtest = BitcoinNetwork(bech32Prefix: "bcrt", pubKeyHashVersion: 0x6f, scriptHashVersion: 0xc4)
}

// MARK: - Address Handling

class AddressHandler {
    static func toOutputScript(address: String, network: BitcoinNetwork = .regtest) -> Data? {
        // Try bech32 decoding first
        if let decoded = Bech32.decode(address) {
            // Verify network prefix matches
            guard decoded.prefix == network.bech32Prefix else { return nil }
            
            if decoded.version == 0 {
                // SegWit v0 (P2WPKH or P2WSH)
                if decoded.data.count == 20 {
                    // P2WPKH: OP_0 + PUSH_20 + hash
                    var script = Data()
                    script.append(0x00) // OP_0
                    script.append(0x14) // PUSH 20 bytes
                    script.append(decoded.data)
                    return script
                } else if decoded.data.count == 32 {
                    // P2WSH: OP_0 + PUSH_32 + hash
                    var script = Data()
                    script.append(0x00) // OP_0
                    script.append(0x20) // PUSH 32 bytes
                    script.append(decoded.data)
                    return script
                }
            } else if decoded.version == 1 {
                // SegWit v1 (P2TR)
                if decoded.data.count == 32 {
                    // P2TR: OP_1 + PUSH_32 + pubkey
                    var script = Data()
                    script.append(0x51) // OP_1
                    script.append(0x20) // PUSH 32 bytes
                    script.append(decoded.data)
                    return script
                }
            } else {
                // Future SegWit versions
                if decoded.version >= 2 && decoded.version <= 16 {
                    var script = Data()
                    script.append(0x50 + decoded.version) // OP_N where N = version
                    script.append(UInt8(decoded.data.count)) // PUSH data.length
                    script.append(decoded.data)
                    return script
                }
            }
        }
        
        // TODO: Add base58 decoding for legacy addresses if needed
        // For now, return nil for non-bech32 addresses
        return nil
    }
}

// MARK: - Bitcoin Transaction Data Structures

struct SwapOutput {
    let value: UInt64
    let script: Data
    let vout: UInt32
}

struct RawBitcoinTransactionInput {
    let previousTxHash: Data
    let previousOutputIndex: UInt32
    let script: Data
    let sequence: UInt32
}

struct RawBitcoinTransactionOutput {
    let value: UInt64
    let script: Data
}

struct RawBitcoinTransaction {
    let version: UInt32
    let inputs: [RawBitcoinTransactionInput]
    let outputs: [RawBitcoinTransactionOutput]
    let locktime: UInt32
    let witnessData: [[Data]]?
}

// MARK: - Bitcoin Transaction Parser

class BitcoinRawBitcoinTransactionParser {
    
    /// Parse a hex transaction string into a RawBitcoinTransaction object
    static func parseRawBitcoinTransaction(from hexString: String) -> RawBitcoinTransaction? {
        guard let data = Data(hexString: hexString) else { return nil }
        return parseRawBitcoinTransaction(from: data)
    }
    
    /// Parse transaction data into a RawBitcoinTransaction object
    static func parseRawBitcoinTransaction(from data: Data) -> RawBitcoinTransaction? {
        var offset = 0
        
        // Parse version (4 bytes, little endian)
        guard data.count >= offset + 4 else { return nil }
        let version = data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4
        
        // Check for witness data (if first byte after version is 0x00)
        let hasWitness = data.count > offset && data[offset] == 0x00
        if hasWitness {
            offset += 2 // Skip marker and flag
        }
        
        // Parse input count (varint)
        let inputCount = parseVarInt(from: data, offset: &offset)
        guard inputCount > 0 else { return nil }
        
        // Parse inputs
        var inputs: [RawBitcoinTransactionInput] = []
        for _ in 0..<inputCount {
            guard let input = parseInput(from: data, offset: &offset) else { return nil }
            inputs.append(input)
        }
        
        // Parse output count (varint)
        let outputCount = parseVarInt(from: data, offset: &offset)
        guard outputCount > 0 else { return nil }
        
        // Parse outputs
        var outputs: [RawBitcoinTransactionOutput] = []
        for _ in 0..<outputCount {
            guard let output = parseOutput(from: data, offset: &offset) else { return nil }
            outputs.append(output)
        }
        
        // Parse witness data if present
        var witnessData: [[Data]]? = nil
        if hasWitness {
            witnessData = parseWitnessData(from: data, offset: &offset, inputCount: inputCount)
        }
        
        // Parse locktime (4 bytes, little endian)
        guard data.count >= offset + 4 else { return nil }
        let locktime = data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        
        return RawBitcoinTransaction(
            version: version,
            inputs: inputs,
            outputs: outputs,
            locktime: locktime,
            witnessData: witnessData
        )
    }
    
    /// Parse a variable-length integer
    private static func parseVarInt(from data: Data, offset: inout Int) -> UInt64 {
        guard data.count > offset else { return 0 }
        
        let firstByte = data[offset]
        offset += 1
        
        switch firstByte {
        case 0xfd:
            guard data.count >= offset + 2 else { return 0 }
            let bytes = data[offset..<offset+2]
            let value = UInt64(bytes[0]) | (UInt64(bytes[1]) << 8)
            offset += 2
            return value
        case 0xfe:
            guard data.count >= offset + 4 else { return 0 }
            let bytes = data[offset..<offset+4]
            let value = UInt64(bytes[0]) | (UInt64(bytes[1]) << 8) | (UInt64(bytes[2]) << 16) | (UInt64(bytes[3]) << 24)
            offset += 4
            return value
        case 0xff:
            guard data.count >= offset + 8 else { return 0 }
            let bytes = data[offset..<offset+8]
            let low32 = UInt64(bytes[0]) | (UInt64(bytes[1]) << 8) | (UInt64(bytes[2]) << 16) | (UInt64(bytes[3]) << 24)
            let high32 = UInt64(bytes[4]) | (UInt64(bytes[5]) << 8) | (UInt64(bytes[6]) << 16) | (UInt64(bytes[7]) << 24)
            let value = low32 | (high32 << 32)
            offset += 8
            return value
        default:
            return UInt64(firstByte)
        }
    }
    
    /// Parse a transaction input
    private static func parseInput(from data: Data, offset: inout Int) -> RawBitcoinTransactionInput? {
        guard data.count >= offset + 36 else { return nil }
        
        // Previous transaction hash (32 bytes, little endian)
        let previousTxHash = data[offset..<offset+32].reversedData()
        offset += 32
        
        // Previous output index (4 bytes, little endian)
        let previousOutputIndex = data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4
        
        // Script length (varint)
        let scriptLength = parseVarInt(from: data, offset: &offset)
        guard data.count >= offset + Int(scriptLength) else { return nil }
        
        // Script
        let script = data[offset..<offset+Int(scriptLength)]
        offset += Int(scriptLength)
        
        // Sequence (4 bytes, little endian)
        guard data.count >= offset + 4 else { return nil }
        let sequence = data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4
        
        return RawBitcoinTransactionInput(
            previousTxHash: Data(previousTxHash),
            previousOutputIndex: previousOutputIndex,
            script: Data(script),
            sequence: sequence
        )
    }
    
    /// Parse a transaction output
    private static func parseOutput(from data: Data, offset: inout Int) -> RawBitcoinTransactionOutput? {
        guard data.count >= offset + 8 else { return nil }
        
        // Parse value (8 bytes, little endian)
        let valueBytes = data[offset..<offset+8]
        let value = valueBytes.enumerated().reduce(0) { result, element in
            result | (UInt64(element.element) << (element.offset * 8))
        }
        offset += 8
        
        // Parse script length
        let scriptLength = parseVarInt(from: data, offset: &offset)
        guard data.count >= offset + Int(scriptLength) else { return nil }
        
        // Parse script
        let script = data[offset..<offset+Int(scriptLength)]
        offset += Int(scriptLength)
        
        return RawBitcoinTransactionOutput(
            value: value,
            script: Data(script)
        )
    }
    
    /// Parse witness data
    private static func parseWitnessData(from data: Data, offset: inout Int, inputCount: UInt64) -> [[Data]]? {
        var witnessData: [[Data]] = []
        
        for _ in 0..<inputCount {
            let witnessCount = parseVarInt(from: data, offset: &offset)
            var witnessItems: [Data] = []
            
            for _ in 0..<witnessCount {
                let itemLength = parseVarInt(from: data, offset: &offset)
                guard data.count >= offset + Int(itemLength) else { return nil }
                let item = data[offset..<offset+Int(itemLength)]
                witnessItems.append(Data(item))
                offset += Int(itemLength)
            }
            
            witnessData.append(witnessItems)
        }
        
        return witnessData
    }
}

// MARK: - Taproot Detection

class TaprootDetector {
    
    /// Detect a Taproot swap output in a transaction
    static func detectSwap(tweakedKey: Data, transaction: RawBitcoinTransaction) -> SwapOutput? {
        for (index, output) in transaction.outputs.enumerated() {
            if isTaprootOutput(output.script) && matchesTweakedKey(output.script, tweakedKey: tweakedKey) {
                return SwapOutput(
                    value: output.value,
                    script: output.script,
                    vout: UInt32(index)
                )
            }
        }
        return nil
    }
    
    /// Check if a script is a Taproot output script
    private static func isTaprootOutput(_ script: Data) -> Bool {
        // Taproot output scripts start with 0x51 (OP_1) followed by 0x20 (32 bytes) and then the public key
        return script.count == 34 && script[0] == 0x51 && script[1] == 0x20
    }
    
    /// Check if a Taproot script matches the given tweaked key
    private static func matchesTweakedKey(_ script: Data, tweakedKey: Data) -> Bool {
        // Extract the public key from the script (bytes 2-33)
        guard script.count >= 34 else { return false }
        let scriptKey = script[2..<34]
        
        // Compare with the tweaked key
        return scriptKey == tweakedKey
    }
}

// MARK: - Main Detect Swap Function

/// Main function equivalent to the JavaScript detectSwap
func detectSwap(tweakedKey: Data, transactionHex: String) -> SwapOutput? {
    // Parse transaction hex to data
    guard let txData = Data(hexString: transactionHex) else { return nil }
    
    var offset = 0
    
    // Skip version (4 bytes)
    offset += 4
    
    // Check for witness data
    let hasWitness = txData.count > offset && txData[offset] == 0x00
    if hasWitness {
        offset += 2 // Skip marker and flag
    }
    
    // Parse input count
    let inputCount = parseVarInt(data: txData, offset: &offset)
    
    // Skip all inputs
    for _ in 0..<inputCount {
        guard skipInput(data: txData, offset: &offset) else { return nil }
    }
    
    // Parse output count
    let outputCount = parseVarInt(data: txData, offset: &offset)
    
    // Parse outputs and look for Taproot
    for (index, _) in (0..<outputCount).enumerated() {
        guard let output = parseOutput(data: txData, offset: &offset) else { return nil }
        
        // Check if this is a Taproot output matching our tweaked key
        if isTaprootOutput(output.script) && matchesTweakedKey(output.script, tweakedKey: tweakedKey) {
            return SwapOutput(
                value: output.value,
                script: output.script,
                vout: UInt32(index)
            )
        }
    }
    
    return nil
}

private func parseVarInt(data: Data, offset: inout Int) -> UInt64 {
    guard data.count > offset else { return 0 }
    
    let firstByte = data[offset]
    offset += 1
    
    switch firstByte {
    case 0xfd:
        guard data.count >= offset + 2 else { return 0 }
        let bytes = data[offset..<offset+2]
        let value = UInt64(bytes[0]) | (UInt64(bytes[1]) << 8)
        offset += 2
        return value
    case 0xfe:
        guard data.count >= offset + 4 else { return 0 }
        let bytes = data[offset..<offset+4]
        let value = UInt64(bytes[0]) | (UInt64(bytes[1]) << 8) | (UInt64(bytes[2]) << 16) | (UInt64(bytes[3]) << 24)
        offset += 4
        return value
    case 0xff:
        guard data.count >= offset + 8 else { return 0 }
        let bytes = data[offset..<offset+8]
        let low32 = UInt64(bytes[0]) | (UInt64(bytes[1]) << 8) | (UInt64(bytes[2]) << 16) | (UInt64(bytes[3]) << 24)
        let high32 = UInt64(bytes[4]) | (UInt64(bytes[5]) << 8) | (UInt64(bytes[6]) << 16) | (UInt64(bytes[7]) << 24)
        let value = low32 | (high32 << 32)
        offset += 8
        return value
    default:
        return UInt64(firstByte)
    }
}

private func skipInput(data: Data, offset: inout Int) -> Bool {
    // Skip previous tx hash (32 bytes)
    offset += 32
    // Skip previous output index (4 bytes)
    offset += 4
    // Skip script
    let scriptLength = parseVarInt(data: data, offset: &offset)
    offset += Int(scriptLength)
    // Skip sequence (4 bytes)
    offset += 4
    return true
}

private func parseOutput(data: Data, offset: inout Int) -> (value: UInt64, script: Data)? {
    guard data.count >= offset + 8 else { return nil }
    
    // Parse value (8 bytes, little endian)
    let valueBytes = data[offset..<offset+8]
    let value = valueBytes.enumerated().reduce(0) { result, element in
        result | (UInt64(element.element) << (element.offset * 8))
    }
    offset += 8
    
    // Parse script length
    let scriptLength = parseVarInt(data: data, offset: &offset)
    guard data.count >= offset + Int(scriptLength) else { return nil }
    
    // Parse script
    let script = data[offset..<offset+Int(scriptLength)]
    offset += Int(scriptLength)
    
    return (value: value, script: Data(script))
}

private func isTaprootOutput(_ script: Data) -> Bool {
    // Taproot output: OP_1 (0x51) + 0x20 (32 bytes) + public key
    return script.count == 34 && script[0] == 0x51 && script[1] == 0x20
}

private func matchesTweakedKey(_ script: Data, tweakedKey: Data) -> Bool {
    // Extract public key from script (bytes 2-33)
    guard script.count >= 34 else { return false }
    let scriptKey = script[2..<34]
    return scriptKey == tweakedKey
}

// MARK: - Bitcoin Claim Transaction

class BoltzClaimTransaction {
    private var version: UInt32 = 1
    internal var inputs: [(txHash: Data, vout: UInt32, sequence: UInt32)] = []
    internal var outputs: [(value: UInt64, script: Data)] = []
    private var locktime: UInt32 = 0
    private var witnesses: [[Data]] = []
    
    init() {}
    
    func addInput(txHash: Data, vout: UInt32, sequence: UInt32 = 0xfffffffd) {
        inputs.append((txHash: txHash, vout: vout, sequence: sequence))
        witnesses.append([]) // Initialize empty witness
    }
    
    func addOutput(value: UInt64, script: Data) {
        outputs.append((value: value, script: script))
    }
    
    func setWitness(inputIndex: Int, witness: [Data]) {
        guard inputIndex < witnesses.count else { return }
        witnesses[inputIndex] = witness
    }
    
    /// Convenience method to set the signature for a Taproot input
    func setSignature(inputIndex: Int, signature: Data) {
        setWitness(inputIndex: inputIndex, witness: [signature])
    }
    
    private func encodeVarInt(_ value: UInt64) -> Data {
        var data = Data()
        
        if value < 0xfd {
            data.append(UInt8(value))
        } else if value <= 0xffff {
            data.append(0xfd)
            data.append(UInt16(value).littleEndianBytes)
        } else if value <= 0xffffffff {
            data.append(0xfe)
            data.append(UInt32(value).littleEndianBytes)
        } else {
            data.append(0xff)
            data.append(value.littleEndianBytes)
        }
        
        return data
    }
    
    private func hasWitness() -> Bool {
        return witnesses.contains { !$0.isEmpty }
    }
    
    func serialize() -> Data {
        var data = Data()
        
        // Version
        data.append(version.littleEndianBytes)
        
        // Witness marker and flag (always include for witness transactions)
        if hasWitness() {
            data.append(0x00) // marker
            data.append(0x01) // flag
        }
        
        // Input count
        data.append(encodeVarInt(UInt64(inputs.count)))
        
        // Inputs
        for input in inputs {
            data.append(input.txHash.reversedData()) // Reverse to big-endian for transaction serialization
            data.append(input.vout.littleEndianBytes)
            data.append(encodeVarInt(0)) // Empty script
            data.append(input.sequence.littleEndianBytes)
        }
        
        // Output count
        data.append(encodeVarInt(UInt64(outputs.count)))
        
        // Outputs
        for output in outputs {
            data.append(output.value.littleEndianBytes)
            data.append(encodeVarInt(UInt64(output.script.count)))
            data.append(output.script)
        }
        
        // Witness data
        if hasWitness() {
            for witness in witnesses {
                data.append(encodeVarInt(UInt64(witness.count)))
                for item in witness {
                    data.append(encodeVarInt(UInt64(item.count)))
                    data.append(item)
                }
            }
        }
        
        // Locktime
        data.append(locktime.littleEndianBytes)
        
        return data
    }
    
    // Calculate virtual size
    func virtualSize() -> Int {
        let baseSize = serializedSize(includeWitness: false)
        let totalSize = serializedSize(includeWitness: true)
        let witnessSize = totalSize - baseSize
        
        return baseSize + (witnessSize + 3) / 4
    }
    
    private func serializedSize(includeWitness: Bool) -> Int {
        var size = 0
        
        // Version
        size += 4
        
        // Witness marker and flag
        if includeWitness && hasWitness() {
            size += 2
        }
        
        // Input count
        size += varIntSize(UInt64(inputs.count))
        
        // Inputs
        for _ in inputs {
            size += 32 // tx hash
            size += 4  // vout
            size += varIntSize(0) // empty script
            size += 4  // sequence
        }
        
        // Output count
        size += varIntSize(UInt64(outputs.count))
        
        // Outputs
        for output in outputs {
            size += 8 // value
            size += varIntSize(UInt64(output.script.count)) // script length
            size += output.script.count // script
        }
        
        // Witness data
        if includeWitness && hasWitness() {
            for witness in witnesses {
                size += varIntSize(UInt64(witness.count))
                for item in witness {
                    size += varIntSize(UInt64(item.count))
                    size += item.count
                }
            }
        }
        
        // Locktime
        size += 4
        
        return size
    }
    
    private func varIntSize(_ value: UInt64) -> Int {
        if value < 0xfd { return 1 }
        if value <= 0xffff { return 3 }
        if value <= 0xffffffff { return 5 }
        return 9
    }
    
    // BIP 341 signature hash calculation
    func hashForWitnessV1(
        inputIndex: Int,
        prevoutScripts: [Data],
        prevoutValues: [UInt64],
        sigHashType: UInt8 = 0x00,
        hasExtension: Bool = false
    ) -> Data {
        
        // Epoch (1 byte) - always 0 for BIP341
        var sigMsg = Data()
        sigMsg.append(0x00)
        
        // Control: hash_type (1 byte)
        sigMsg.append(sigHashType)
        
        // Transaction data: nVersion (4) + nLockTime (4)
        sigMsg.append(version.littleEndianBytes)
        sigMsg.append(locktime.littleEndianBytes)
        
        // sha_prevouts (32): SHA256 of serialization of all input outpoints
        // For sigHash calculation, use the same format as in transaction serialization
        var prevoutsData = Data()
        for input in inputs {
            prevoutsData.append(input.txHash.reversedData()) // Same as transaction serialization
            prevoutsData.append(input.vout.littleEndianBytes)
        }
        let shaPrevouts = sha256(prevoutsData)
        sigMsg.append(shaPrevouts)
        
        // sha_amounts (32): SHA256 of serialization of all spent output amounts
        var amountsData = Data()
        for value in prevoutValues {
            amountsData.append(value.littleEndianBytes)
        }
        let shaAmounts = sha256(amountsData)
        sigMsg.append(shaAmounts)
        
        // sha_scriptpubkeys (32): SHA256 of all spent outputs' scriptPubKeys with length prefix
        var scriptPubKeysData = Data()
        for script in prevoutScripts {
            scriptPubKeysData.append(encodeVarInt(UInt64(script.count)))
            scriptPubKeysData.append(script)
        }
        let shaScriptPubKeys = sha256(scriptPubKeysData)
        sigMsg.append(shaScriptPubKeys)
        
        // sha_sequences (32): SHA256 of serialization of all input nSequence
        var sequencesData = Data()
        for input in inputs {
            sequencesData.append(input.sequence.littleEndianBytes)
        }
        let shaSequences = sha256(sequencesData)
        sigMsg.append(shaSequences)
        
        // sha_outputs (32): SHA256 of serialization of all outputs in CTxOut format
        var outputsData = Data()
        for output in outputs {
            outputsData.append(output.value.littleEndianBytes)
            outputsData.append(encodeVarInt(UInt64(output.script.count)))
            outputsData.append(output.script)
        }
        let shaOutputs = sha256(outputsData)
        sigMsg.append(shaOutputs)
        
        // spend_type (1): (ext_flag * 2) + annex_present
        let extFlag: UInt8 = hasExtension ? 1 : 0
        let annexPresent: UInt8 = 0 // No annex in our case
        let spendType = (extFlag * 2) + annexPresent
        sigMsg.append(spendType)
        
        // input_index (4): index of this input in the transaction input vector
        sigMsg.append(UInt32(inputIndex).littleEndianBytes)
        
        // Create tagged hash
        return taggedSHA256("TapSighash", sigMsg)
    }
    
    private func sha256(_ data: Data) -> Data {
        return Data(SHA256.hash(data: data))
    }
    
    private func taggedSHA256(_ tag: String, _ data: Data) -> Data {
        let tagData = tag.data(using: .utf8)!
        let tagHash = Data(SHA256.hash(data: tagData))
        
        var combined = Data()
        combined.append(tagHash)
        combined.append(tagHash)
        combined.append(data)
        
        return Data(SHA256.hash(data: combined))
    }
}

// MARK: - Helper Functions

func calculateTransactionHash(from rawTransactionHex: String) -> Data? {
    guard let txData = Data(hexString: rawTransactionHex) else { return nil }
    
    // For witness transactions, we need to calculate the hash without witness data
    // This is the "wtxid" vs "txid" difference
    var dataWithoutWitness = Data()
    var offset = 0
    
    // Version (4 bytes)
    guard txData.count >= offset + 4 else { return nil }
    dataWithoutWitness.append(txData[offset..<offset+4])
    offset += 4
    
    // Check for witness marker
    let hasWitness = txData.count > offset && txData[offset] == 0x00
    if hasWitness {
        offset += 2 // Skip witness marker and flag
    }
    
    // Input count
    let inputCount = parseVarInt(data: txData, offset: &offset)
    dataWithoutWitness.append(encodeVarInt(inputCount))
    
    // Inputs (without witness data)
    for _ in 0..<inputCount {
        // Previous tx hash (32 bytes)
        guard txData.count >= offset + 32 else { return nil }
        dataWithoutWitness.append(txData[offset..<offset+32])
        offset += 32
        
        // Previous output index (4 bytes)
        guard txData.count >= offset + 4 else { return nil }
        dataWithoutWitness.append(txData[offset..<offset+4])
        offset += 4
        
        // Script length and script
        let scriptLength = parseVarInt(data: txData, offset: &offset)
        dataWithoutWitness.append(encodeVarInt(scriptLength))
        guard txData.count >= offset + Int(scriptLength) else { return nil }
        dataWithoutWitness.append(txData[offset..<offset+Int(scriptLength)])
        offset += Int(scriptLength)
        
        // Sequence (4 bytes)
        guard txData.count >= offset + 4 else { return nil }
        dataWithoutWitness.append(txData[offset..<offset+4])
        offset += 4
    }
    
    // Output count
    let outputCount = parseVarInt(data: txData, offset: &offset)
    dataWithoutWitness.append(encodeVarInt(outputCount))
    
    // Outputs
    for _ in 0..<outputCount {
        // Value (8 bytes)
        guard txData.count >= offset + 8 else { return nil }
        dataWithoutWitness.append(txData[offset..<offset+8])
        offset += 8
        
        // Script length and script
        let scriptLength = parseVarInt(data: txData, offset: &offset)
        dataWithoutWitness.append(encodeVarInt(scriptLength))
        guard txData.count >= offset + Int(scriptLength) else { return nil }
        dataWithoutWitness.append(txData[offset..<offset+Int(scriptLength)])
        offset += Int(scriptLength)
    }
    
    // Skip witness data if present (we don't include it in txid calculation)
    if hasWitness {
        for _ in 0..<inputCount {
            let witnessCount = parseVarInt(data: txData, offset: &offset)
            for _ in 0..<witnessCount {
                let itemLength = parseVarInt(data: txData, offset: &offset)
                offset += Int(itemLength)
            }
        }
    }
    
    // Locktime (4 bytes)
    guard txData.count >= offset + 4 else { return nil }
    dataWithoutWitness.append(txData[offset..<offset+4])
    
    // Double SHA256 for transaction hash
    let firstHash = Data(SHA256.hash(data: dataWithoutWitness))
    let secondHash = Data(SHA256.hash(data: firstHash))
    
    // Return reversed for little-endian format (for use in transaction inputs)
    return secondHash.reversedData()
}

private func encodeVarInt(_ value: UInt64) -> Data {
    var data = Data()
    
    if value < 0xfd {
        data.append(UInt8(value))
    } else if value <= 0xffff {
        data.append(0xfd)
        data.append(UInt16(value).littleEndianBytes)
    } else if value <= 0xffffffff {
        data.append(0xfe)
        data.append(UInt32(value).littleEndianBytes)
    } else {
        data.append(0xff)
        data.append(value.littleEndianBytes)
    }
    
    return data
}

func targetFee(satPerVbyte: Int, constructTx: (Int) -> BoltzClaimTransaction) -> BoltzClaimTransaction {
    let tx = constructTx(1)
    let vsize = tx.virtualSize()
    let fee = Int(ceil(Double(vsize + tx.inputs.count) * Double(satPerVbyte)))
    return constructTx(fee)
}

func constructClaimTransaction(
    swapOutput: SwapOutput,
    destinationAddress: String,
    fee: Int,
    txHash: Data,
    network: BitcoinNetwork = .regtest
) -> BoltzClaimTransaction {
    let tx = BoltzClaimTransaction()
    
    // Add input
    tx.addInput(txHash: txHash, vout: swapOutput.vout, sequence: 0xfffffffd)
    
    // Create destination script using proper address decoding
    guard let destinationScript = AddressHandler.toOutputScript(address: destinationAddress, network: network) else {
        fatalError("Invalid destination address: \(destinationAddress)")
    }
    
    // Calculate output value
    let outputValue = swapOutput.value - UInt64(fee)
    
    // Add output
    tx.addOutput(value: outputValue, script: destinationScript)
    
    // Automatically add placeholder witness (64 zero bytes) for unsigned transaction
    // This ensures correct transaction structure for sigHash calculation
    tx.setWitness(inputIndex: 0, witness: [Data(count: 64)])
    
    return tx
}

func computeTapLeafHash(aggregatedPublicKey: P256K.MuSig.PublicKey, claimLeafOutputHex: String, refundLeafOutputHex: String) throws -> HashDigest {
    // Create the claim leaf hash
    let claimLeafOutput = try claimLeafOutputHex.bytes
    let claimLeafHash = try SHA256.taggedHash(
        tag: "TapLeaf".data(using: .utf8)!,
        data: Data([0xC0]) + Data(claimLeafOutput).compactSizePrefix
    )
    
    // Create the refund leaf hash
    let refundLeafOutput = try refundLeafOutputHex.bytes
    let refundLeafHash = try SHA256.taggedHash(
        tag: "TapLeaf".data(using: .utf8)!,
        data: Data([0xC0]) + Data(refundLeafOutput).compactSizePrefix
    )
    
    // Sort the leaves lexicographically and create the merkle root
    var leftHash, rightHash: Data
    if claimLeafHash < refundLeafHash {
        leftHash = Data(claimLeafHash)
        rightHash = Data(refundLeafHash)
    } else {
        leftHash = Data(refundLeafHash)
        rightHash = Data(claimLeafHash)
    }
    
    let merkleRoot = try SHA256.taggedHash(
        tag: "TapBranch".data(using: .utf8)!,
        data: leftHash + rightHash
    )
    
    // Create the tap tweak hash using the x-only public key and merkle root
    let xOnlyPubKey = aggregatedPublicKey.xonly.bytes
    let tapTweakHash = try SHA256.taggedHash(
        tag: "TapTweak".data(using: .utf8)!,
        data: Data(xOnlyPubKey) + Data(merkleRoot)
    )
    
    return tapTweakHash
}

