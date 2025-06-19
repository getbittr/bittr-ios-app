//
//  BoltzRefund.swift
//  bittr
//
//  Created by Ruben Waterman on 20/03/2025.
//
import Musig2Bitcoin
import P256K

class BoltzRefund {
    /// Represents a complete MuSig2 session for Boltz refund
    struct MusigSession {
        let ourKey: P256K.Schnorr.PrivateKey
        let theirKey: P256K.Schnorr.PublicKey
        let aggregatedPublicKey: P256K.MuSig.PublicKey
        let tweakedKey: P256K.MuSig.PublicKey
        let sessionID: [UInt8]
        let scriptTweak: [UInt8]
        let refundScript: [UInt8]
        
        init(ourKey: P256K.Schnorr.PrivateKey, theirKey: P256K.Schnorr.PublicKey, refundScript: [UInt8]) throws {
            print("🔧 Creating MusigSession...")
            
            self.ourKey = ourKey
            self.theirKey = theirKey
            
            print("🔧 Aggregating public keys...")
            print("   Our public key: \(ourKey.publicKey.dataRepresentation.hex)")
            print("   Their public key: \(theirKey.dataRepresentation.hex)")
            
            // Try the original order from your working code
            self.aggregatedPublicKey = try P256K.MuSig.aggregate([theirKey, ourKey.publicKey])
            print("✅ Public keys aggregated successfully")
            print("   Aggregated key: \(self.aggregatedPublicKey.dataRepresentation.hex)")
            
            // If that fails, we can try the reverse order
            // self.aggregatedPublicKey = try P256K.MuSig.aggregate([ourKey.publicKey, theirKey])
            
            print("🔧 Generating session ID...")
            self.sessionID = Array(SecureBytes(count: 32))
            print("✅ Session ID generated: \(self.sessionID.hex)")
            
            self.refundScript = refundScript
            
            // Extract the 32-byte tweak from the script (skip the first byte)
            print("🔧 Extracting script tweak...")
            guard refundScript.first == 0x20 else {
                print("❌ Invalid script format - first byte is \(refundScript.first ?? 0), expected 0x20")
                throw NSError(domain: "BoltzRefund", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid script format"])
            }
            self.scriptTweak = Array(refundScript.dropFirst().prefix(32))
            print("✅ Script tweak extracted: \(self.scriptTweak.hex)")
            print("   Script tweak length: \(self.scriptTweak.count) bytes")
            
            print("🔧 Adding tweak to aggregated key...")
            print("   Aggregated key format: \(self.aggregatedPublicKey.dataRepresentation.count) bytes")
            print("   Tweak format: \(self.scriptTweak.count) bytes")
            
            // Try with compressed format first to see if that works
            do {
                self.tweakedKey = try self.aggregatedPublicKey.add(self.scriptTweak, format: .compressed)
                print("✅ Tweaked key created successfully (compressed)")
            } catch {
                print("❌ Failed with compressed format: \(error)")
                // Try uncompressed format
                do {
                    self.tweakedKey = try self.aggregatedPublicKey.add(self.scriptTweak, format: .uncompressed)
                    print("✅ Tweaked key created successfully (uncompressed)")
                } catch {
                    print("❌ Failed with uncompressed format: \(error)")
                    throw error
                }
            }
        }
    }
    
    static func tryBoltzRefund() async throws -> Bool {
        print("🚀 Starting Boltz refund process...")
        
        // --- Step 1: Setup keys and script ---
        print("🔧 Step 1: Setting up keys and script...")
        
        let boltzServerPublicKeyBytes = try! "034d0ec2790580f2f22b2b6e7e56ca30962ea2395f01cb563afe24440e3117fc55".bytes
        print("✅ Boltz server public key bytes: \(boltzServerPublicKeyBytes.hex)")
        
        let boltzServerPublicKey = try! P256K.Schnorr.PublicKey(
            dataRepresentation: boltzServerPublicKeyBytes,
            format: .compressed
        )
        print("✅ Boltz server public key created")
        
        let (hexPrivateKey, _) = try LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")
        print("✅ Retrieved private key from LightningNodeService")
        
        let ourPrivateKeyBytes = try! hexPrivateKey.bytes
        print("✅ Our private key bytes: \(ourPrivateKeyBytes.hex)")
        
        let ourPrivateKey = try! P256K.Schnorr.PrivateKey(dataRepresentation: ourPrivateKeyBytes)
        print("✅ Our private key created")
        
        let scriptHex = "20ef07ea4cacba6709d43a74278a7b6c792cbcef10a035f04d2f196c9069876876ad02b204b1"
        let scriptBytes = try! scriptHex.bytes
        print("✅ Script bytes: \(scriptBytes.hex)")
        
        // --- Step 2: Create MuSig session ---
        print("🔧 Step 2: Creating MuSig session...")
        let session = try MusigSession(ourKey: ourPrivateKey, theirKey: boltzServerPublicKey, refundScript: scriptBytes)
        print("✅ MuSig session created successfully")
        print("Aggregated public key: \(session.aggregatedPublicKey.dataRepresentation.hex)")
        print("Tweaked key: \(session.tweakedKey.dataRepresentation.hex)")
        
        // --- Step 3: Generate our nonce ---
        print("🔧 Step 3: Generating our nonce...")
        let message = "Vires in Numeris.".data(using: .utf8)!
        let messageHash = SHA256.hash(data: message)
        print("✅ Message hash: \(Array(messageHash).hex)")
        
        print("🔧 Generating nonce with session ID: \(session.sessionID.hex)")
        let ourNonce = try P256K.MuSig.Nonce.generate(
            sessionID: session.sessionID,
            secretKey: session.ourKey,
            publicKey: session.ourKey.publicKey,
            msg32: Array(messageHash),
            extraInput32: nil
        )
        print("✅ Nonce generated successfully")
        
        let ourNonceHex = try! ourNonce.pubnonce.serialized().hex
        print("Our nonce: \(ourNonceHex)")
        
        // --- Step 4: Build unsigned transaction ---
        print("🔧 Step 4: Building unsigned transaction...")
        let prev_txs = ["0100000000010114ee6d11384b493b84221ae947c29ac97d8905358a011ca7b9eb511631ee20500000000000feffffff02e32a22010000000016001404dee8419071b93a03164ebf7acde824918891653a960400000000002251209b1b3af865fb9cd5b1eee9a348fa5432d844544595940e2fd9af986eb8c67a8f0247304402205d9a5056a83a87433b11a22e46e440e2de6f2752bdb6aa75250a8802799d12a902200690045e74ce21913023a9023d391a4614879dd98e016d52d4e8061ffc3023a90121033ce211fdd9af1d9b4abb5feef0c902f8e6471fd2d6ed0889b25cc20b18a8703ec2000000"]
        let txids: [String] = ["2a434ca92a59741d164de40e00dedb51368f292c7ada130712f6171e773990a0"]
        let input_indexs: [UInt32] = [1]
        let addresses: [String]  = ["bcrt1qerf96x54jjg9677pa2mhwphh45vj2kqqskkyk2"]
        let amounts: [UInt64] = [299_602]
        
        let base_tx = generateRawTx(prev_txs: prev_txs, txids: txids, input_indexs:input_indexs, addresses:addresses, amounts: amounts)
        print("✅ Base transaction generated")
        
        let unsignedTx = getUnsignedTx(tx:base_tx)
        print("Unsigned tx: \(unsignedTx)")
        
        // --- Step 5: Request refund from Boltz API ---
        print("🔧 Step 5: Requesting refund from Boltz API...")
        let refundData = RefundRequest(pubNonce: ourNonceHex, transaction: unsignedTx, index: 0)
        let (theirPubNonceHex, theirPartialSignatureHex) = try await requestRefundAndProcess(swapID: "tgTKex31LpzS", refundData: refundData)
        guard let theirPubNonceHex = theirPubNonceHex, let theirPartialSignatureHex = theirPartialSignatureHex else {
            print("❌ Failed to get the data from Boltz API.")
            return false
        }
        print("✅ Received PubNonce from Boltz API: \(theirPubNonceHex)")
        print("✅ Received Partial Signature from Boltz API: \(theirPartialSignatureHex)")
        
        // --- Step 6: Aggregate nonces ---
        print("🔧 Step 6: Aggregating nonces...")
        let theirNonce = try P256K.Schnorr.Nonce(hexString: theirPubNonceHex)
        print("✅ Their nonce parsed successfully")
        
        let aggregatedNonce = try P256K.MuSig.Nonce(aggregating: [ourNonce.pubnonce, theirNonce])
        print("✅ Nonces aggregated successfully")
        
        // --- Step 7: Calculate sighash ---
        print("🔧 Step 7: Calculating sighash...")
        let sighash = getSighash(tx: base_tx, txid: txids[0], input_index: input_indexs[0], agg_pubkey: session.tweakedKey.dataRepresentation.hex, sigversion: 1, proto: "")
        print("Sighash: \(sighash)")
        
        // --- Step 8: Create our partial signature ---
        print("🔧 Step 8: Creating our partial signature...")
        let ourPartialSignature = try session.ourKey.partialSignature(
            for: sighash.bytes,
            pubnonce: ourNonce.pubnonce,
            secureNonce: ourNonce.secnonce,
            publicNonceAggregate: aggregatedNonce,
            publicKeyAggregate: session.tweakedKey
        )
        print("✅ Our partial signature created")
        print("Our partial signature: \(try ourPartialSignature.serializedHex())")
        
        // --- Step 9: Parse their partial signature ---
        print("🔧 Step 9: Parsing their partial signature...")
        let theirPartialSignature = try P256K.Schnorr.PartialSignature(
            hexString: theirPartialSignatureHex,
            session: ourPartialSignature.session
        )
        print("✅ Their partial signature parsed")
        print("Their partial signature: \(try theirPartialSignature.serializedHex())")
        
        // --- Step 10: Aggregate signatures ---
        print("🔧 Step 10: Aggregating signatures...")
        let aggregateSignature = try P256K.MuSig.aggregateSignatures([ourPartialSignature, theirPartialSignature])
        let aggregateSignatureHex = aggregateSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined()
        print("✅ Signatures aggregated successfully")
        print("Aggregate Signature Hex: \(aggregateSignatureHex)")
        
        // --- Step 11: Build and print final transaction ---
        print("🔧 Step 11: Building final transaction...")
        let final_tx = buildTaprootTx(tx: base_tx, signature: aggregateSignatureHex, txid: txids[0], input_index: input_indexs[0])
        print("✅ Final transaction built")
        print("Final transaction: \(final_tx)")
        
        print("🎉 Boltz refund process completed successfully!")
        return true
    }
    
    static func requestRefundAndProcess(swapID: String, refundData: RefundRequest) async throws -> (String?, String?) {
        try await withCheckedThrowingContinuation { continuation in
            BoltzAPI.requestRefund(swapID: swapID, refundData: refundData) { result in
                switch result {
                case .success(let response):
                    if let error = response.error {
                        continuation.resume(throwing: APIError.requestFailed(error))
                    } else {
                        continuation.resume(returning: (response.pubNonce, response.partialSignature))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Helper structs and extensions

struct SecureBytes: Sequence, Collection {
    let bytes: [UInt8]
    
    init(count: Int) {
        var randomBytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &randomBytes)
        self.bytes = randomBytes
    }
    
    // Sequence conformance
    func makeIterator() -> Array<UInt8>.Iterator {
        return bytes.makeIterator()
    }
    
    // Collection conformance
    var startIndex: Int { bytes.startIndex }
    var endIndex: Int { bytes.endIndex }
    subscript(position: Int) -> UInt8 { bytes[position] }
    func index(after i: Int) -> Int { bytes.index(after: i) }
}

extension SecureBytes {
    var data: Data {
        Data(bytes)
    }
}

extension Array where Element == UInt8 {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
