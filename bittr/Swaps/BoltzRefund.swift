//
//  BoltzRefund.swift
//  bittr
//
//  Created by Ruben Waterman on 20/03/2025.
//
import Musig2Bitcoin
import P256K

class BoltzRefund {
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
        let messageHashHex = "cf948211a1070a16c322befbb629c3129bbbe5d001982bfea94a580a6d02cc52"
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
        let claimTransaction = "010000000001011898e20b40a8001a992319d72f3333d95dcaace0917ec5120277f8bad64d95230100000000fdffffff0188c2000000000000160014a8b9b13db16d176496faed039b76a96913d624ed01400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
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
        //{
        //    acceptZeroConf = 0;
        //    address = bcrt1pfg8wrml5hsaudu854jwc6l0celvtj9mfp5xfe7gsfulc2mgldm0s4mskdr;
        //    bip21 = "bitcoin:bcrt1pfg8wrml5hsaudu854jwc6l0celvtj9mfp5xfe7gsfulc2mgldm0s4mskdr?amount=0.00300602&label=Send%20to%20BTC%20lightning";
        //    claimPublicKey = 03defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5;
        //    expectedAmount = 300602;
        //    id = Hxy9F38Isz8k;
        //    swapTree =     {
        //        claimLeaf =         {
        //            output = a9147c8787575fd2190816e4559d15d17be83d6413478820defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5ac;
        //            version = 192;
        //        };
        //        refundLeaf =         {
        //            output = 20b45641876412357b35600c5aa6df1d8f598842b6f1f39b5d7f25928aed7374dcad02b104b1;
        //            version = 192;
        //        };
        //    };
        //    timeoutBlockHeight = 1201;
        //}
        let boltzServerPublicKeyBytes = try! "03defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5".bytes
        
        let boltzServerPublicKey = try! P256K.Schnorr.PublicKey(
            dataRepresentation: boltzServerPublicKeyBytes,
            format: .compressed
        )
        
        // When we created the Swap, we used a private/public key pair from our existing wallet (in production, we should use some funny path not to mix keys)
        // hexPrivateKey: 1fcb7f3c8219bbd48e0a1baf33f7c4f331373f87d27ced7c83e84dfa087fcf85
        // hexPublicKey: 03ef07ea4cacba6709d43a74278a7b6c792cbcef10a035f04d2f196c9069876876
        let (hexPrivateKey, _hexPublicKey) = try LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")
        
        // In order to aggregate the keys, I re-initialize the same key using P256K.Schnorr.PrivateKey.init but the public/private key still looks the same
        let ourPrivateKeyBytes = try! hexPrivateKey.bytes
        let ourPrivateKey = try! P256K.Schnorr.PrivateKey.init(dataRepresentation: ourPrivateKeyBytes)
        
        // For some reason, when I want to later on use the getSighash function, that only accepts uncompressed keys, so we're using that as the format here already
        let boltzAggregateKey = try P256K.MuSig.aggregate([boltzServerPublicKey, ourPrivateKey.publicKey])
        
        // The boltzAggregateKey looks like this: 04499bcea8f3dbf842f347c30b08ae4e3e29141e689c8f1de82c9fd6f37b57d5c4f2712db01543c5d9226b6629294f95958efd2994ae071cd20e5f151e02004a8a
        let hexString = String(bytes: boltzAggregateKey.dataRepresentation)
        // hexString: 04499bcea8f3dbf842f347c30b08ae4e3e29141e689c8f1de82c9fd6f37b57d5c4f2712db01543c5d9226b6629294f95958efd2994ae071cd20e5f151e02004a8a
        print("hexString: \(hexString)")
        
        // Now, we take the refundLeaf.output from our Swap and tweak the key, again because we need an uncompressed key later on to create the sigHash, we put format .uncompressed
        let tweak = try! "20f8b2dfc86aa1f5c6df0d3089c74088eaf0527216b61472113e8839e4e4bbb69fad02c004b1".bytes
        let tweakedKey = try! boltzAggregateKey.add(tweak, format: P256K.Format.compressed)
        
        let hexTweakedString = String(bytes: tweakedKey.dataRepresentation)
        // hexTweakedString: 0496c1b570134b244bc1c6d09ecc288678bd14fe94a17b78cfb204a28f7945bf4c80f3f2fd19055791c97bf605558873bbcc04f6fc584a7c7ec56fb892051ca7b4
        print("hexTweakedString: \(hexTweakedString)")
        
        // Not sure if this is correct but to generate the nonce I used the example of the package, I think in the boltz TS code just random 32 bytes is used?
        let boltzMessage = "Vires in Numeris.".data(using: .utf8)!
        let boltzMessageHash = SHA256.hash(data: boltzMessage)
        
        // Mostly following the example https://github.com/21-DOT-DEV/swift-P256K?tab=readme-ov-file#musig2
        let ourBoltzNonce = try P256K.MuSig.Nonce.generate(
            secretKey: ourPrivateKey,
            publicKey: ourPrivateKey.publicKey,
            msg32: Array(boltzMessageHash)
        )
        
        // I created this .serliazed().hex thing, maybe it's wrong? But at least it looks similar in style as what I get back from the boltz server:
        let ourBoltzNonceHex = ourBoltzNonce.pubnonce.hexString
        // ourBoltzNonce: 02cdc4c5b143eb3c575772bf9ac9bac76295188d16c5790306afe5bf4805f0709202bc21c2995ce18c1c8434e4ebc244cecf6cc22515859dc6e9f35d9023df0f33b6
        print("ourBoltzNonce: \(ourBoltzNonceHex)")
        
        // The next few lintes will create the raw transaction of our refund, so that we can send the unsigned transaction to the Boltz API
        // and later on calculate the sighash that we AND the boltz API need to sign
        let prev_txs = ["01000000000101c12e557a5a170d0340398124267b9f35377bba1d682a29e2b342b440c7ff9b720100000000feffffff023a960400000000002251204a0ee1eff4bc3bc6f0f4ac9d8d7df8cfd8b917690d0c9cf9104f3f856d1f6edf2f84f50000000000160014e9330934b52ad5b2b127060db749d216eba627dc02473044022022e51b31270f9835cd6b5191584722c34fce0f4b077cf84a6d28a4cec50e653f02207720f3b636ccba1e91370152137bbf1b8c044f204200d7c486686a6a94916825012102e945b5a40e769105c13c87d72b8b4cf12a5901c6ea3d81f6e09616ccdc44efecc1000000"];
        let txids: [String] = ["16d3b516dc62976f3004c895b08e1a6bed6e2d181de8c0bdd60d443bd3d0ba30"];
        let input_indexs: [UInt32] = [1];
        let addresses: [String]  = ["bcrt1q4zumz0d3d5tkf9h6a5peka4fdyfavf8df04j2q"];
        let amounts: [UInt64] = [299_602];
        
        let base_tx = generateRawTx(prev_txs: prev_txs, txids: txids, input_indexs:input_indexs, addresses:addresses, amounts: amounts);
        
//        let unsignedTx = getUnsignedTx(tx:base_tx)
        
        // unsignedTx: 0200000001a09039771e17f6120713da7a2c298f3651dbde000ee44d161d74592aa94c432a01000000000000000001f04902000000000016001419e0025f607f3e8e6d6a38a7f98a8d269d6fd35500000000
        
        
        let unsignedTx = "0100000001a09039771e17f6120713da7a2c298f3651dbde000ee44d161d74592aa94c432a0100000000ffffffff01f04902000000000016001419e0025f607f3e8e6d6a38a7f98a8d269d6fd35500000000"
        
        print("unsignedTx: \(unsignedTx)")
        
        let refundData = RefundRequest(
            pubNonce: ourBoltzNonceHex,
            transaction: unsignedTx,
            index: 0
        )
        
        // Now await for the refund data from the API
        let (pubNonce, partialSignature) = try await requestRefundAndProcess(swapID: "tgTKex31LpzS", refundData: refundData)
        
        if let pubNonce = pubNonce, let partialSignature = partialSignature {
            print("Received PubNonce from the Boltz API: \(pubNonce)")
            // Received PubNonce from the Boltz API: 037c7db25d52a5e8873abdc2068ac33dfb1ea264fee2ff0b021579aac1b14aaea903b5817bcd7e1a9c39aa2a2b126c62cddef37b8ccb42107d55d409ca4ad50dc334
            print("Received Partial Signature from the Boltz API: \(partialSignature)")
            // Received Partial Signature from the Boltz API: b1483b65daabeff9fcb7add2ccd81e6d935f7203fae374be2759364b04d13209
            
            do {
                // I created this P256K.Schnorr.Nonce(hexString: pubNonce) as I didn't find anything in the package to parse a hex, perhaps it's wrong
                let theirNonce = try P256K.Schnorr.Nonce(hexString: pubNonce)
                
                // Aggregate nonces (I can only aggregate nonce if they are in the swift struct P256K.MuSig.Nonce)
                let aggregatedNonce = try P256K.MuSig.Nonce(aggregating: [ourBoltzNonce.pubnonce, theirNonce])
                
                // Here is the code to get the sighash but I'm not sure if it works correctly
                //                let sighash = getSighash(tx: base_tx, txid: txids[0], input_index: input_indexs[0], agg_pubkey: tweakedKey.dataRepresentation.hex, sigversion: 1, proto: "");
                
                // current sighash: 337179eb31fc94dcfd09d866f77e24e6905c4bb0346affd15a63b763034836a9
//                print("current sighash:", sighash);
                
                // Create our partial signatures (which also creates the session that we can later on use to parse the BoltzAPI signature
                let ourBoltzPartialSignature = try ourPrivateKey.partialSignature(
                    for: "9e3c507f5b27336e3e76548190fc42737c03792cc876fbe181b0749aeb9ee12f".bytes,
                    pubnonce: ourBoltzNonce.pubnonce,
                    secureNonce: ourBoltzNonce.secnonce,
                    publicNonceAggregate: aggregatedNonce,
                    publicKeyAggregate: tweakedKey
                )
                
                print("ourBoltzPartialSignature: \(ourBoltzPartialSignature)")
                // ourBoltzPartialSignature: PartialSignature(dataRepresentation: 36 bytes, session: 133 bytes)
                
                let boltzAPIPartialSignature = try P256K.Schnorr.PartialSignature(
                    dataRepresentation: Data(partialSignature.bytes),
                    session: ourBoltzPartialSignature.session
                )
                
                // boltzAPIPartialSignature: PartialSignature(dataRepresentation: 36 bytes, session: 133 bytes)
                print("boltzAPIPartialSignature: \(boltzAPIPartialSignature)")
                
                // Aggregate partial signatures into a full signature
                let aggregateBoltzSignature = try P256K.MuSig.aggregateSignatures([ourBoltzPartialSignature, boltzAPIPartialSignature])
                
//                let sighashDigest = try! SHA256.hash(data: sighash.bytes)

                // This is an attempt to verify the signature (but I'm not quite convinced it works because whatever we put into ours as "for", it always returns valid
                // For some reason I can't put here the sighash.bytes (which we signed earlier) as I have to put a Digest into the for parameter
//                let isOurSignatureValid = tweakedKey.isValidSignature(
//                    ourBoltzPartialSignature,
//                    publicKey: ourPrivateKey.publicKey,
//                    nonce: ourBoltzNonce.pubnonce,
//                    for: sighashDigest
//                )
                
                // this always returns true no matter what is put in as 'for' parameter, which seems odd to me
                // isOurSignatureValid: true
//                print("isOurSignatureValid: \(isOurSignatureValid)")
                
                // If I understood it correctly we need to put the aggregateSignatureHex in the witness of our transaction
                let aggregateSignatureHex = aggregateBoltzSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined()
                
                // Aggregate Signature Hex: 3a60472813d1effb534a6d95e0e3dfb41e908576de8ef3788fc3a98963258ed41d7195873c734790408b9d8c25b2edb50abe8833fdbdb37e4b068fe23d87e068
                print("Aggregate Signature Hex: \(aggregateSignatureHex)")
                
                // I tried to see if we can verify the signature that we get back but this always returns false so I'm sure we're doing something wrong
//                let isBoltzAPISignatureValid = tweakedKey.isValidSignature(
//                    boltzAPIPartialSignature,
//                    publicKey: boltzServerPublicKey,
//                    nonce: theirNonce,
//                    for: sighashDigest
//                )
                
                // This one always returns false, so I'm sure I'm doing something wrong: isBoltzAPISignatureValid: false
//                print("isBoltzAPISignatureValid: \(isBoltzAPISignatureValid)")
                
                let final_tx = buildTaprootTx(tx: base_tx, signature: aggregateSignatureHex, txid: txids[0], input_index: input_indexs[0]);
                
                
                // final transaction: 02000000000101a09039771e17f6120713da7a2c298f3651dbde000ee44d161d74592aa94c432a01000000000000000001f04902000000000016001419e0025f607f3e8e6d6a38a7f98a8d269d6fd35501403a60472813d1effb534a6d95e0e3dfb41e908576de8ef3788fc3a98963258ed41d7195873c734790408b9d8c25b2edb50abe8833fdbdb37e4b068fe23d87e06800000000
                
                // if we'd decode it would look like this:
                //                {
                //                  "txid": "f98a72bf512370a6a5cea87f134678ef9e5baa76663a27fa3142af063a53f2c5",
                //                  "hash": "a5ed4e3da4f4cbdc0ee5ebc77ba6ae386903c2952bcb3846243b737c196546da",
                //                  "version": 2,
                //                  "size": 150,
                //                  "vsize": 99,
                //                  "weight": 396,
                //                  "locktime": 0,
                //                  "vin": [
                //                    {
                //                      "txid": "2a434ca92a59741d164de40e00dedb51368f292c7ada130712f6171e773990a0",
                //                      "vout": 1,
                //                      "scriptSig": {
                //                        "asm": "",
                //                        "hex": ""
                //                      },
                //                      "txinwitness": [
                //                        "3a60472813d1effb534a6d95e0e3dfb41e908576de8ef3788fc3a98963258ed41d7195873c734790408b9d8c25b2edb50abe8833fdbdb37e4b068fe23d87e068"
                //                      ],
                //                      "sequence": 0
                //                    }
                //                  ],
                //                  "vout": [
                //                    {
                //                      "value": 0.00150000,
                //                      "n": 0,
                //                      "scriptPubKey": {
                //                        "asm": "0 19e0025f607f3e8e6d6a38a7f98a8d269d6fd355",
                //                        "desc": "addr(bcrt1qr8sqyhmq0ulgumt28znlnz5dy6wkl564r65swh)#tzjqrqt4",
                //                        "hex": "001419e0025f607f3e8e6d6a38a7f98a8d269d6fd355",
                //                        "address": "bcrt1qr8sqyhmq0ulgumt28znlnz5dy6wkl564r65swh",
                //                        "type": "witness_v0_keyhash"
                //                      }
                //                    }
                //                  ]
                //                }
                
                print("final transaction:", final_tx);
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
