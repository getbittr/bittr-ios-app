//
//  BoltzRefund.swift
//  bittr
//
//  Created by Ruben Waterman on 20/03/2025.
//
import Musig2Bitcoin
import P256K

class BoltzRefund {
    static func tryBoltzClaimInternalTransactionGeneration() async throws -> Bool {
        //        {
        //            "id": "9ncXTzLM821K",
        //            "invoice": "lnbcrt505610n1p5xgg0esp5stctx4gle9vgh94fvzx0dt8a57daflertd0jvw8c439l98psyv8spp5wlrd8fl7fxtm3wnltgnpddnkxp7wphuf9gl6hhr9u5jh6qp26ppqdql2djkuepqw3hjqsj5gvsxzerywfjhxucxqyp2xqcqzyl9qyysgq0mdhsmlvq2f335d8my9963e7mxts9ry8c9xyg9yerryexwcclcm4rhg8whcnwhagkdlnasktlsx57hfuefmetunug88w9y5nfldhdqsqwpp6qq",
        //            "swapTree": {
        //                "claimLeaf": {
        //                    "version": 192,
        //                    "output": "82012088a914986067db5067f3456356c546e6ec57b2f30ebcf6882035c61bbbd4a2c348d64d3c060abdce8249d44c09e20b2d8f0c077a5ee7e3dac8ac"
        //                },
        //                "refundLeaf": {
        //                    "version": 192,
        //                    "output": "20defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5ad024b01b1"
        //                }
        //            },
        //            "lockupAddress": "bcrt1p3l7c992rtv663ql6qwq5j8g5tj3hw4h3kk5f8efshhrr7f4sxr4q7mxp4f",
        //            "refundPublicKey": "03defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5",
        //            "timeoutBlockHeight": 331
        //        }
        
        let boltzServerPublicKeyBytes = try! "03defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5".bytes
        
        let boltzServerPublicKey = try! P256K.Schnorr.PublicKey(
            dataRepresentation: boltzServerPublicKeyBytes,
            format: .compressed
        )
        
        // When we created the Swap, we used a private/public key pair from our existing wallet (in production, we should use some funny path not to mix keys)
        // hexPrivateKey: c5c8c3cac9b6c5544f0424849b1387d4868925821f2b39599c3396ccef128436
        // hexPublicKey: 02b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dc
        let (hexPrivateKey, _hexPublicKey) = try LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")
        
        // In order to aggregate the keys, I re-initialize the same key using P256K.Schnorr.PrivateKey.init but the public/private key still looks the same
        let ourPrivateKeyBytes = try! hexPrivateKey.bytes
        let ourPrivateKey = try! P256K.Schnorr.PrivateKey.init(dataRepresentation: ourPrivateKeyBytes)
        
        // For some reason, when I want to later on use the getSighash function, that only accepts uncompressed keys, so we're using that as the format here already
        // Aggregate public keys without sorting
        let publicKeys = [boltzServerPublicKey, ourPrivateKey.publicKey]
        let aggregatedPublicKey = try P256K.MuSig.aggregate(publicKeys, sortKeys: false)
        
        print("\n=== AGGREGATED PUBLIC KEY ===")
        print("Aggregated public key: \(aggregatedPublicKey.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
        print("Aggregated x-only public key: \(aggregatedPublicKey.xonly.bytes.map { String(format: "%02x", $0) }.joined())")

        // --- BIP-341 Taproot tweak computation using swapTree ---
        // Based on the swapTree structure from the API response:
        //        "swapTree": {
        //        "claimLeaf": {
        //            "version": 192,
        //            "output": "82012088a914986067db5067f3456356c546e6ec57b2f30ebcf6882035c61bbbd4a2c348d64d3c060abdce8249d44c09e20b2d8f0c077a5ee7e3dac8ac"
        //        },
        //        "refundLeaf": {
        //            "version": 192,
        //            "output": "20defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5ad024b01b1"
        //        }
        //    }
        
        // Create the claim leaf hash
        let claimLeafOutput = try "82012088a914986067db5067f3456356c546e6ec57b2f30ebcf6882035c61bbbd4a2c348d64d3c060abdce8249d44c09e20b2d8f0c077a5ee7e3dac8ac".bytes
        let claimLeafHash = try SHA256.taggedHash(
            tag: "TapLeaf".data(using: .utf8)!,
            data: Data([0xC0]) + Data(claimLeafOutput).compactSizePrefix
        )
        
        // Create the refund leaf hash
        let refundLeafOutput = try "20defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5ad024b01b1".bytes
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
        
        print("\n=== TAPROOT TWEAK COMPUTATION ===")
        print("X-only public key for tweak: \(xOnlyPubKey.map { String(format: "%02x", $0) }.joined())")
        print("Claim leaf hash: \(Data(claimLeafHash).map { String(format: "%02x", $0) }.joined())")
        print("Refund leaf hash: \(Data(refundLeafHash).map { String(format: "%02x", $0) }.joined())")
        print("Merkle root: \(Data(merkleRoot).map { String(format: "%02x", $0) }.joined())")
        print("Tap tweak hash: \(Data(tapTweakHash).map { String(format: "%02x", $0) }.joined())")
        
        // Apply the x-only tweak to the aggregated public key's x-only key
        // For Taproot, we need to use x-only tweaking which properly updates the key aggregation cache
        let tweakedXonlyKey = try aggregatedPublicKey.xonly.add(Array(Data(tapTweakHash)))
        
        // Create a new MuSig public key from the tweaked x-only key (preserves the cache)
        let tweakedKey = try aggregatedPublicKey.add(Array(Data(tapTweakHash)))
        print("Sharon's key: \(tweakedKey.dataRepresentation.map { String(format: "%02x", $0) }.joined())")

        let tweakedKeyHex = tweakedXonlyKey.bytes.map { String(format: "%02x", $0) }.joined()
        
        print("\n=== TWEAKED PUBLIC KEY ===")
        print("Tweaked x-only public key: \(tweakedKeyHex)")
        //        print("Expected result: 9c1ff67571dcf338b4d417e53afeb7fe20d59b7327481a4e8f9f6504b150ec3b")
        
        let transactionHex = "01000000000101878adf0a543eaab5ff89986241aabd807aeda05d2e0f1dd6695443e12bd3b17e0000000000ffffffff0250c30000000000002251208ffd8295435b35a883fa0381491d145ca37756f1b5a893e530bdc63f26b030ea6699cfb20000000022512050c44b238470d24adcc504821bf8c62ff8a2a9a1a3645062087c46435f620c450247304402201055d855417308c4054858e4275cef69ca09a65a195ac70c64604a603d6e807f0220405808eb8a3c0ba67af612aaaa5ca852b534fb58604747180ece0862d66e0d81012102d61001c7ab68ced0e89c9141e48cbb6870a1dcfa14333d33a296158a6f951e1500000000"
        
        
        guard let tweakedKey = Data(hexString: tweakedKeyHex) else {
            print("Invalid tweaked key")
            return false
        }

        if let swapOutput = detectSwap(tweakedKey: tweakedKey, transactionHex: transactionHex) {
            print("Found swap output:")
            print("Value: \(swapOutput.value)")
            print("Script: \(swapOutput.script.hexString)")
            print("Vout: \(swapOutput.vout)")
            return true
        } else {
            print("No swap output found")
            return false
        }
        
//        // The next few lintes will create the raw transaction of our refund, so that we can send the unsigned transaction to the Boltz API
//        // and later on calculate the sighash that we AND the boltz API need to sign
//        let prev_txs = ["01000000000101878adf0a543eaab5ff89986241aabd807aeda05d2e0f1dd6695443e12bd3b17e0000000000ffffffff0250c30000000000002251208ffd8295435b35a883fa0381491d145ca37756f1b5a893e530bdc63f26b030ea6699cfb20000000022512050c44b238470d24adcc504821bf8c62ff8a2a9a1a3645062087c46435f620c450247304402201055d855417308c4054858e4275cef69ca09a65a195ac70c64604a603d6e807f0220405808eb8a3c0ba67af612aaaa5ca852b534fb58604747180ece0862d66e0d81012102d61001c7ab68ced0e89c9141e48cbb6870a1dcfa14333d33a296158a6f951e1500000000"];
//        let txids: [String] = ["8b0e6b29fed7de2b25cffc722438b15d0181255f354fff4502c5e8c3ec72f1b1"];
//        let input_indexs: [UInt32] = [0];
//        let addresses: [String]  = ["bcrt1qekjssnr0rahwxtk0jaeth9x5gyavec7pgkgugh"];
//        let amounts: [UInt64] = [49_000];
//        
//        let base_tx = generateRawTx(prev_txs: prev_txs, txids: txids, input_indexs:input_indexs, addresses:addresses, amounts: amounts);
//        
//        let unsignedTx = getUnsignedTx(tx:base_tx)
//        
//        let sighash = getSighash(tx: base_tx, txid: txids[0],input_index: input_indexs[0], agg_pubkey: "", sigversion: 0, proto: "");
//        
//        print("current sighash:", sighash);
//        print("unsignedTx:", unsignedTx);
        
        // Create partial signatures
//        let messageHashBytes = try sighash.bytes
//        let messageDigest = HashDigest(messageHashBytes)
//        
//        // Generate nonces for each signer
//        let firstNonce = try P256K.MuSig.Nonce.generate(
//            secretKey: ourPrivateKey,
//            publicKey: ourPrivateKey.publicKey,
//            msg32: Array(messageDigest)
//        )
//        
//        print("Our nonce: \(firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined())")
//
//        // Hardcoded values for testing
//        let swapID = "9ncXTzLM821K"
//        let ourNonceHex = firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined()
//        let preimage = "bcdfbc02ea3226fb72606979c012247b355768e5a85beb8fee314d54442e519c"
//        
//        // Create claim request
//        let claimRequest = ClaimRequest(
//            index: 0,
//            transaction: unsignedTx,
//            preimage: preimage,
//            pubNonce: ourNonceHex
//        )
//        
//        // Post claim request to Boltz
//        let claimResponse = try await requestClaimAndProcess(swapID: swapID, claimData: claimRequest)
//        
//        if let boltzPubNonce = claimResponse.pubNonce, let boltzPartialSignature = claimResponse.partialSignature {
//            print("Received Boltz pubNonce: \(boltzPubNonce)")
//            print("Received Boltz partialSignature: \(boltzPartialSignature)")
//            
//            // Convert to P256K objects
//            let externalNonce = try P256K.Schnorr.Nonce(hexString: boltzPubNonce)
//            let externalPartialSignature = try P256K.Schnorr.PartialSignature(hexString: boltzPartialSignature)
//            
//            // Aggregate with the external nonce
//            let aggregateWithExternal = try P256K.MuSig.Nonce(aggregating: [externalNonce, firstNonce.pubnonce])
//
//            print("\n=== NONCES ===")
//            print("First Public Nonce: \(firstNonce.hexString)")
//            print("External Nonce: \(externalNonce.hexString)")
//            print("Aggregate with External: \(aggregateWithExternal.hexString)")
//            
//            let firstPartialSignature = try ourPrivateKey.partialSignature(
//                for: messageDigest,
//                pubnonce: firstNonce.pubnonce,
//                secureNonce: firstNonce.secnonce,
//                publicNonceAggregate: aggregateWithExternal,
//                publicKeyAggregate: tweakedKey
//            )
//
//            dump(firstPartialSignature)
//
//            print("\n=== PARTIAL SIGNATURES ===")
//            print("First Partial Signature: \(firstPartialSignature.dataRepresentation.bytes.map { String(format: "%02x", $0) }.joined())")
//            print("External Partial Signature: \(externalPartialSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined())")        
//
//            let aggregateSignature = try P256K.MuSig.aggregateSignatures([externalPartialSignature, firstPartialSignature])
//            
//            let aggregateSignatureHex = aggregateSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined()
//
//            print("Aggregate Signature: \(aggregateSignatureHex)")
//            
//            let final_tx = buildTaprootTx(tx: base_tx, signature: aggregateSignatureHex, txid: txids[0], input_index: input_indexs[0]);
//            
//            print("final_tx: \(final_tx)")
//        } else {
//            print("Failed to get claim response from Boltz")
//        }

        return true
    }

    static func tryBoltzClaim() async throws -> Bool {
        //        {
        //            "id": "7TNAMND8TpBC",
        //            "invoice": "lnbcrt505610n1p5x8hqxsp53cc6umyva3e9vzemfrd679fhyg8u639xe3nt57jqpd72xtst8ypqpp57jmpxtcc9tka0v7pmccq9zmj3yl2r5h6fse4ccznjjspmcyz8ztqdql2djkuepqw3hjqsj5gvsxzerywfjhxucxqyp2xqcqzyl9qyysgq7urq6fed0pkzdwr03t2f02t3pcxgm3w3n9ztqa03qzc9mnfv08u5ywtemjpssecfus5txcw387sn2sya6kzwdx4wnf6cg2fyn0tt5fgpwnwsst",
        //            "swapTree": {
        //                "claimLeaf": {
        //                    "version": 192,
        //                    "output": "82012088a914dc3629a8b0fc948c29b1af03cfe328329156e3b68820b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dcac"
        //                },
        //                "refundLeaf": {
        //                    "version": 192,
        //                    "output": "2016c9a4ebe84573a3a75802f090ddbe2bd9a4a5088503e1fffc83363139ea371ead025601b1"
        //                }
        //            },
        //            "lockupAddress": "bcrt1pw4wlylcfcpm23phm6ptakr7xdxnmjmqf8va4a40f3ywhfwgsf2xsv2f74c",
        //            "refundPublicKey": "0316c9a4ebe84573a3a75802f090ddbe2bd9a4a5088503e1fffc83363139ea371e",
        //            "timeoutBlockHeight": 342
        //        }
        
        let boltzServerPublicKeyBytes = try! "02482a2db89ce575fb8e6cae372abdbba22e3a4d84c4dea7f923486dcb085318ee".bytes
        
        let boltzServerPublicKey = try! P256K.Schnorr.PublicKey(
            dataRepresentation: boltzServerPublicKeyBytes,
            format: .compressed
        )
        
        // When we created the Swap, we used a private/public key pair from our existing wallet (in production, we should use some funny path not to mix keys)
        // hexPrivateKey: c5c8c3cac9b6c5544f0424849b1387d4868925821f2b39599c3396ccef128436
        // hexPublicKey: 02b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dc
        let (hexPrivateKey, _hexPublicKey) = try LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")
        
        // In order to aggregate the keys, I re-initialize the same key using P256K.Schnorr.PrivateKey.init but the public/private key still looks the same
        let ourPrivateKeyBytes = try! hexPrivateKey.bytes
        let ourPrivateKey = try! P256K.Schnorr.PrivateKey.init(dataRepresentation: ourPrivateKeyBytes)
        
        // For some reason, when I want to later on use the getSighash function, that only accepts uncompressed keys, so we're using that as the format here already
        // Aggregate public keys without sorting
        let publicKeys = [boltzServerPublicKey, ourPrivateKey.publicKey]
        let aggregatedPublicKey = try P256K.MuSig.aggregate(publicKeys, sortKeys: false)
        
        print("\n=== AGGREGATED PUBLIC KEY ===")
        print("Aggregated public key: \(aggregatedPublicKey.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
        print("Aggregated x-only public key: \(aggregatedPublicKey.xonly.bytes.map { String(format: "%02x", $0) }.joined())")

        // --- BIP-341 Taproot tweak computation using swapTree ---
        // Based on the swapTree structure from the API response:
        //        "swapTree": {
        //        "claimLeaf": {
        //            "version": 192,
        //            "output": "82012088a914dc3629a8b0fc948c29b1af03cfe328329156e3b68820b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dcac"
        //        },
        //        "refundLeaf": {
        //            "version": 192,
        //            "output": "2016c9a4ebe84573a3a75802f090ddbe2bd9a4a5088503e1fffc83363139ea371ead025601b1"
        //        }
        //    }
        
        // Create the claim leaf hash
        let claimLeafOutput = try "82012088a914ace17abaa30c5fb54a9481ea883e9d46c79d15778820b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dcac".bytes
        let claimLeafHash = try SHA256.taggedHash(
            tag: "TapLeaf".data(using: .utf8)!,
            data: Data([0xC0]) + Data(claimLeafOutput).compactSizePrefix
        )
        
        // Create the refund leaf hash
        let refundLeafOutput = try "20482a2db89ce575fb8e6cae372abdbba22e3a4d84c4dea7f923486dcb085318eead025701b1".bytes
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
        
        print("\n=== TAPROOT TWEAK COMPUTATION ===")
        print("X-only public key for tweak: \(xOnlyPubKey.map { String(format: "%02x", $0) }.joined())")
        print("Claim leaf hash: \(Data(claimLeafHash).map { String(format: "%02x", $0) }.joined())")
        print("Refund leaf hash: \(Data(refundLeafHash).map { String(format: "%02x", $0) }.joined())")
        print("Merkle root: \(Data(merkleRoot).map { String(format: "%02x", $0) }.joined())")
        print("Tap tweak hash: \(Data(tapTweakHash).map { String(format: "%02x", $0) }.joined())")
        
        // Apply the x-only tweak to the aggregated public key's x-only key
        // For Taproot, we need to use x-only tweaking which properly updates the key aggregation cache
        let tweakedXonlyKey = try aggregatedPublicKey.xonly.add(Array(Data(tapTweakHash)))
        
        // Create a new MuSig public key from the tweaked x-only key (preserves the cache)
        let tweakedKey = try aggregatedPublicKey.add(Array(Data(tapTweakHash)))
        print("Sharon's key: \(tweakedKey.dataRepresentation.map { String(format: "%02x", $0) }.joined())")

        
        print("\n=== TWEAKED PUBLIC KEY ===")
        print("Tweaked x-only public key: \(tweakedXonlyKey.bytes.map { String(format: "%02x", $0) }.joined())")
        print("Expected result: 9c1ff67571dcf338b4d417e53afeb7fe20d59b7327481a4e8f9f6504b150ec3b")
        
        // Create partial signatures
        let messageHashHex = "c4fd25b751240bc1bb29cbb1d69359c77fe83de39570b8ce2aafd1330054ae00"
        let messageHashBytes = try messageHashHex.bytes
        let messageDigest = HashDigest(messageHashBytes)
        
        // Generate nonces for each signer
        let firstNonce = try P256K.MuSig.Nonce.generate(
            secretKey: ourPrivateKey,
            publicKey: ourPrivateKey.publicKey,
            msg32: Array(messageDigest)
        )
        
        print("Our nonce: \(firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined())")

        // Hardcoded values for testing
        let swapID = "bLEk6F6YHuzm"
        let claimTransaction = "0100000000010130bad0d33b440dd6bdc0e81d182d6eed6b1a8eb095c804306f9762dc16b5d3160000000000fdffffff017295040000000000160014a8b9b13db16d176496faed039b76a96913d624ed014000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b1040000"
        let preimage = "cdbc1b54efe3f3c546045983d470f951676f92b94f2bb0627119869b60f946fc"
        let ourNonceHex = firstNonce.pubnonce.map { String(format: "%02x", $0) }.joined()
        
        // Create claim request
        let claimRequest = ClaimRequest(
            index: 0,
            transaction: claimTransaction,
            preimage: preimage,
            pubNonce: ourNonceHex
        )
        
        // Post claim request to Boltz
        let claimResponse = try await requestClaimAndProcess(swapID: swapID, claimData: claimRequest)
        
        if let boltzPubNonce = claimResponse.pubNonce, let boltzPartialSignature = claimResponse.partialSignature {
            print("Received Boltz pubNonce: \(boltzPubNonce)")
            print("Received Boltz partialSignature: \(boltzPartialSignature)")
            
            // Convert to P256K objects
            let externalNonce = try P256K.Schnorr.Nonce(hexString: boltzPubNonce)
            let externalPartialSignature = try P256K.Schnorr.PartialSignature(hexString: boltzPartialSignature)
            
            // Aggregate with the external nonce
            let aggregateWithExternal = try P256K.MuSig.Nonce(aggregating: [externalNonce, firstNonce.pubnonce])

            print("\n=== NONCES ===")
            print("First Public Nonce: \(firstNonce.hexString)")
            print("External Nonce: \(externalNonce.hexString)")
            print("Aggregate with External: \(aggregateWithExternal.hexString)")
            
            let firstPartialSignature = try ourPrivateKey.partialSignature(
                for: messageDigest,
                pubnonce: firstNonce.pubnonce,
                secureNonce: firstNonce.secnonce,
                publicNonceAggregate: aggregateWithExternal,
                publicKeyAggregate: tweakedKey
            )

            dump(firstPartialSignature)

            print("\n=== PARTIAL SIGNATURES ===")
            print("First Partial Signature: \(firstPartialSignature.dataRepresentation.bytes.map { String(format: "%02x", $0) }.joined())")
            print("External Partial Signature: \(externalPartialSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined())")        

            let aggregateSignature = try P256K.MuSig.aggregateSignatures([externalPartialSignature, firstPartialSignature])

            print("Aggregate Signature: \(aggregateSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
        } else {
            print("Failed to get claim response from Boltz")
        }

        return true
    }

    static func tryBoltzRefund() async throws -> Bool {
        // This is the public key we got when we made the API call:
    //    {
    //        acceptZeroConf = 0;
    //        address = bcrt1pfg8wrml5hsaudu854jwc6l0celvtj9mfp5xfe7gsfulc2mgldm0s4mskdr;
    //        bip21 = "bitcoin:bcrt1pfg8wrml5hsaudu854jwc6l0celvtj9mfp5xfe7gsfulc2mgldm0s4mskdr?amount=0.00300602&label=Send%20to%20BTC%20lightning";
    //        claimPublicKey = 03defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5;
    //        expectedAmount = 300602;
    //        id = Hxy9F38Isz8k;
    //        swapTree =     {
    //            claimLeaf =         {
    //                output = a9147c8787575fd2190816e4559d15d17be83d6413478820defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5ac;
    //                version = 192;
    //            };
    //            refundLeaf =         {
    //                output = 20b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dcad02b104b1;
    //                version = 192;
    //            };
    //        };
    //        timeoutBlockHeight = 1201;
    //    }
        let boltzServerPublicKeyBytes = try! "03defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5".bytes
        
        let boltzServerPublicKey = try! P256K.Schnorr.PublicKey(
            dataRepresentation: boltzServerPublicKeyBytes,
            format: .compressed
        )
        
        // When we created the Swap, we used a private/public key pair from our existing wallet (in production, we should use some funny path not to mix keys)
        // hexPrivateKey: c5c8c3cac9b6c5544f0424849b1387d4868925821f2b39599c3396ccef128436
        // hexPublicKey: 02b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dc
        let (hexPrivateKey, _hexPublicKey) = try LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")
        
        // In order to aggregate the keys, I re-initialize the same key using P256K.Schnorr.PrivateKey.init but the public/private key still looks the same
        let ourPrivateKeyBytes = try! hexPrivateKey.bytes
        let ourPrivateKey = try! P256K.Schnorr.PrivateKey.init(dataRepresentation: ourPrivateKeyBytes)
        
        // For some reason, when I want to later on use the getSighash function, that only accepts uncompressed keys, so we're using that as the format here already
        // Aggregate public keys without sorting
        let publicKeys = [boltzServerPublicKey, ourPrivateKey.publicKey]
        let aggregatedPublicKey = try P256K.MuSig.aggregate(publicKeys, sortKeys: false)
        
        print("\n=== AGGREGATED PUBLIC KEY ===")
        print("Aggregated public key: \(aggregatedPublicKey.dataRepresentation.map { String(format: "%02x", $0) }.joined())")
        print("Aggregated x-only public key: \(aggregatedPublicKey.xonly.bytes.map { String(format: "%02x", $0) }.joined())")

        // --- BIP-341 Taproot tweak computation using swapTree ---
        // Based on the swapTree structure from the API response:
        //        "swapTree": {
        //        "claimLeaf": {
        //            "version": 192,
        //            "output": "a9147c8787575fd2190816e4559d15d17be83d6413478820defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5ac"
        //        },
        //        "refundLeaf": {
        //            "version": 192,
        //            "output": "20b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dcad02b104b1"
        //        }
        //    }
        
        // Create the claim leaf hash
        let claimLeafOutput = try "a9147c8787575fd2190816e4559d15d17be83d6413478820defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5ac".bytes
        let claimLeafHash = try SHA256.taggedHash(
            tag: "TapLeaf".data(using: .utf8)!,
            data: Data([0xC0]) + Data(claimLeafOutput).compactSizePrefix
        )
        
        // Create the refund leaf hash
        let refundLeafOutput = try "20b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dcad02b104b1".bytes
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
        
        print("\n=== TAPROOT TWEAK COMPUTATION ===")
        print("X-only public key for tweak: \(xOnlyPubKey.map { String(format: "%02x", $0) }.joined())")
        print("Claim leaf hash: \(Data(claimLeafHash).map { String(format: "%02x", $0) }.joined())")
        print("Refund leaf hash: \(Data(refundLeafHash).map { String(format: "%02x", $0) }.joined())")
        print("Merkle root: \(Data(merkleRoot).map { String(format: "%02x", $0) }.joined())")
        print("Tap tweak hash: \(Data(tapTweakHash).map { String(format: "%02x", $0) }.joined())")
        
        // Apply the x-only tweak to the aggregated public key's x-only key
        // For Taproot, we need to use x-only tweaking which properly updates the key aggregation cache
        let tweakedXonlyKey = try aggregatedPublicKey.xonly.add(Array(Data(tapTweakHash)))
        
        // Create a new MuSig public key from the tweaked x-only key (preserves the cache)
        let tweakedKey = try aggregatedPublicKey.add(Array(Data(tapTweakHash)))
        print("Sharon's key: \(tweakedKey.dataRepresentation.map { String(format: "%02x", $0) }.joined())")

        
        print("\n=== TWEAKED PUBLIC KEY ===")
        print("Tweaked x-only public key: \(tweakedXonlyKey.bytes.map { String(format: "%02x", $0) }.joined())")
        print("Expected result: 4a0ee1eff4bc3bc6f0f4ac9d8d7df8cfd8b917690d0c9cf9104f3f856d1f6edf")
        
        // Create partial signatures
        let messageHashHex = "bb4b24f4586b8f2bb32b19a2197234b6d8b471b7740324e3239f44bdd18e2a32"
        let messageHashBytes = try messageHashHex.bytes
        let messageDigest = HashDigest(messageHashBytes)
        
        // Generate nonces for each signer
        let ourBoltzNonce = try P256K.MuSig.Nonce.generate(
            secretKey: ourPrivateKey,
            publicKey: ourPrivateKey.publicKey,
            msg32: Array(messageDigest)
        )
        
        // I created this .serliazed().hex thing, maybe it's wrong? But at least it looks similar in style as what I get back from the boltz server:
        let ourBoltzNonceHex = ourBoltzNonce.pubnonce.hexString
        // ourBoltzNonce: 02cdc4c5b143eb3c575772bf9ac9bac76295188d16c5790306afe5bf4805f0709202bc21c2995ce18c1c8434e4ebc244cecf6cc22515859dc6e9f35d9023df0f33b6
        print("ourBoltzNonce: \(ourBoltzNonceHex)")
        
        let unsignedTx = "0100000000010130bad0d33b440dd6bdc0e81d182d6eed6b1a8eb095c804306f9762dc16b5d3160000000000fdffffff017295040000000000160014a8b9b13db16d176496faed039b76a96913d624ed01400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        
        print("unsignedTx: \(unsignedTx)")
        
        let refundData = RefundRequest(
            pubNonce: ourBoltzNonceHex,
            transaction: unsignedTx,
            index: 0
        )
        
        // Now await for the refund data from the API
        let (pubNonce, partialSignature) = try await requestRefundAndProcess(swapID: "Hxy9F38Isz8k", refundData: refundData)
        
        if let pubNonce = pubNonce, let partialSignature = partialSignature {
            print("Received PubNonce from the Boltz API: \(pubNonce)")
            // Received PubNonce from the Boltz API: 037c7db25d52a5e8873abdc2068ac33dfb1ea264fee2ff0b021579aac1b14aaea903b5817bcd7e1a9c39aa2a2b126c62cddef37b8ccb42107d55d409ca4ad50dc334
            print("Received Partial Signature from the Boltz API: \(partialSignature)")
            // Received Partial Signature from the Boltz API: b1483b65daabeff9fcb7add2ccd81e6d935f7203fae374be2759364b04d13209
            do {                
                // Convert to P256K objects
                let externalNonce = try P256K.Schnorr.Nonce(hexString: pubNonce)
                let externalPartialSignature = try P256K.Schnorr.PartialSignature(hexString: partialSignature)
                
                // Aggregate with the external nonce
                let aggregateWithExternal = try P256K.MuSig.Nonce(aggregating: [externalNonce, ourBoltzNonce.pubnonce])

                print("\n=== NONCES ===")
                print("First Public Nonce: \(ourBoltzNonce.hexString)")
                print("External Nonce: \(externalNonce.hexString)")
                print("Aggregate with External: \(aggregateWithExternal.hexString)")
                
                let firstPartialSignature = try ourPrivateKey.partialSignature(
                    for: messageDigest,
                    pubnonce: ourBoltzNonce.pubnonce,
                    secureNonce: ourBoltzNonce.secnonce,
                    publicNonceAggregate: aggregateWithExternal,
                    publicKeyAggregate: tweakedKey
                )

                print("\n=== PARTIAL SIGNATURES ===")
                print("First Partial Signature: \(firstPartialSignature.dataRepresentation.bytes.map { String(format: "%02x", $0) }.joined())")
                print("External Partial Signature: \(externalPartialSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined())")        

                let aggregateSignature = try P256K.MuSig.aggregateSignatures([externalPartialSignature, firstPartialSignature])

                print("Aggregate Signature: \(aggregateSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined())")

            } catch {
                print("Error during nonce aggregation or signature creation: \(error)")
            }
        } else {
            print("Failed to get the data.")
        }
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
    
    static func requestClaimAndProcess(swapID: String, claimData: ClaimRequest) async throws -> ClaimResponse {
        try await withCheckedThrowingContinuation { continuation in
            BoltzAPI.requestClaim(swapID: swapID, claimData: claimData) { result in
                switch result {
                case .success(let response):
                    if let error = response.error {
                        continuation.resume(throwing: APIError.requestFailed(error))
                    } else {
                        continuation.resume(returning: response)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
