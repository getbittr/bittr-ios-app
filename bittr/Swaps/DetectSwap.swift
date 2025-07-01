import Foundation

// MARK: - Data Structures

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

// MARK: - Bitcoin RawBitcoinTransaction Parser

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
            // Break down the complex expression into simpler parts
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
        let previousTxHash = data[offset..<offset+32].reversed()
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
        
        // Parse value (8 bytes, little endian) - using safer byte-by-byte reading
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
        // Break down the complex expression into simpler parts
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
    
    // Parse value (8 bytes, little endian) - using safer byte-by-byte reading
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

// MARK: - Data Extension for Hex Conversion

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
}

// MARK: - Usage Example

/*
// Example usage:
let transactionHex = "0100000000010156b32b34abb1138a2381ed7f96a33993e22eecf8cf5aa9f30b0e573867256c4f0000000000ffffffff025a10ceb200000000225120f212f94b6c9e1a7e0969d8d713e2c2edf5d86889b63203008970e9f04521807c50c30000000000002251209c1ff67571dcf338b4d417e53afeb7fe20d59b7327481a4e8f9f6504b150ec3b01404dbdd21c015dc605fa62e12d55aee0d69ad3414e54408b8eb7beeeebb70428c55763f7e45fa770575e213ec239273e5b097da052a95e24822c0b953db3ec1f8700000000"

let tweakedKeyHex = "4a0ee1eff4bc3bc6f0f4ac9d8d7df8cfd8b917690d0c9cf9104f3f856d1f6edf"
guard let tweakedKey = Data(hexString: tweakedKeyHex) else {
    print("Invalid tweaked key")
    return
}

if let swapOutput = detectSwap(tweakedKey: tweakedKey, transactionHex: transactionHex) {
    print("Found swap output:")
    print("Value: \(swapOutput.value)")
    print("Script: \(swapOutput.script.hexString)")
    print("Vout: \(swapOutput.vout)")
} else {
    print("No swap output found")
}
*/
