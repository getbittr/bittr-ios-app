//
//  BoltzRefund.swift
//  bittr
//
//  Created by Ruben Waterman on 20/03/2025.
//
import Musig2Bitcoin
import P256K

class BoltzRefund {
    static func tryBoltzRefund() async throws -> Bool {
        // This is the public key we got when we made the API call:
        //        {
        //            "bip21": "bitcoin:bcrt1p2tkt6vevjvszzan8sut58p6fjtcsw0cufull5ksxq2ucwcsuusps0djmjz?amount=0.00150452&label=Send%20to%20BTC%20lightning",
        //            "acceptZeroConf": false,
        //            "expectedAmount": 150452,
        //            "id": "EvZHH6byHy5G",
        //            "address": "bcrt1p2tkt6vevjvszzan8sut58p6fjtcsw0cufull5ksxq2ucwcsuusps0djmjz",
        //            "swapTree": {
        //                "claimLeaf": {
        //                    "version": 192,
        //                    "output": "a914b00dc8e4fe065d98aa1c7d2b6324d0ddd3029b538820defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5ac"
        //                },
        //                "refundLeaf": {
        //                    "version": 192,
        //                    "output": "203f0fadc9e61e8655b8b1e4d01c17bb8996d312b8767e2782671d6cac64a92bdfad02ae04b1"
        //                }
        //            },
        //            "claimPublicKey": "03defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5",
        //            "timeoutBlockHeight": 1198
        //        }
        let boltzServerPublicKeyBytes = try! "03defe74e5f8393f9c48d9c9fb0bf49a883adac25269890bb1d2d7c41af619f2d5".bytes
        
        let boltzServerPublicKey = try! P256K.Schnorr.PublicKey(
            dataRepresentation: boltzServerPublicKeyBytes,
            format: .compressed
        )
        
        // When we created the Swap, we used a private/public key pair from our existing wallet (in production, we should use some funny path not to mix keys)
        // hexPrivateKey: 49681c38765dd01b3c22ea5d426b9fb91adf90ee82ff8e4456320cbc9b3c370d
        // hexPublicKey: 033f0fadc9e61e8655b8b1e4d01c17bb8996d312b8767e2782671d6cac64a92bdf
        let (hexPrivateKey, _hexPublicKey) = try LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")
        
        // In order to aggregate the keys, I re-initialize the same key using P256K.Schnorr.PrivateKey.init but the public/private key still looks the same
        let ourPrivateKeyBytes = try! hexPrivateKey.bytes
        let ourPrivateKey = try! P256K.Schnorr.PrivateKey.init(dataRepresentation: ourPrivateKeyBytes)
        
        // For some reason, when I want to later on use the getSighash function, that only accepts uncompressed keys, so we're using that as the format here already
        let boltzAggregateKey = try P256K.MuSig.aggregate([boltzServerPublicKey, ourPrivateKey.publicKey], format: P256K.Format.uncompressed)
        
        // The boltzAggregateKey looks like this: 04499bcea8f3dbf842f347c30b08ae4e3e29141e689c8f1de82c9fd6f37b57d5c4f2712db01543c5d9226b6629294f95958efd2994ae071cd20e5f151e02004a8a
        let hexString = String(bytes: boltzAggregateKey.dataRepresentation)
        // hexString: 04499bcea8f3dbf842f347c30b08ae4e3e29141e689c8f1de82c9fd6f37b57d5c4f2712db01543c5d9226b6629294f95958efd2994ae071cd20e5f151e02004a8a
        print("hexString: \(hexString)")
        
        // Now, we take the refundLeaf.output from our Swap and tweak the key, again because we need an uncompressed key later on to create the sigHash, we put format .uncompressed
        let tweak = try! "203f0fadc9e61e8655b8b1e4d01c17bb8996d312b8767e2782671d6cac64a92bdfad02ae04b1".bytes
        let tweakedKey = try! boltzAggregateKey.add(tweak, format: P256K.Format.uncompressed)
        
        let hexTweakedString = String(bytes: tweakedKey.dataRepresentation)
        // hexTweakedString: 0496c1b570134b244bc1c6d09ecc288678bd14fe94a17b78cfb204a28f7945bf4c80f3f2fd19055791c97bf605558873bbcc04f6fc584a7c7ec56fb892051ca7b4
        print("hexTweakedString: \(hexTweakedString)")
        
        // Not sure if this is correct but to generate the nonce I used the example of the package, I think in the boltz TS code just random 32 bytes is used?
        let boltzMessage = "Vires in Numeris.".data(using: .utf8)!
        let boltzMessageHash = SHA256.hash(data: boltzMessage)
        
        // Mostly following the example https://github.com/21-DOT-DEV/swift-secp256k1?tab=readme-ov-file#musig2
        let ourBoltzNonce = try P256K.MuSig.Nonce.generate(
            secretKey: ourPrivateKey,
            publicKey: ourPrivateKey.publicKey,
            msg32: Array(boltzMessageHash)
        )
        
        // I created this .serliazed().hex thing, maybe it's wrong? But at least it looks similar in style as what I get back from the boltz server:
        let ourBoltzNonceHex = try! ourBoltzNonce.pubnonce.serialized().hex
        // ourBoltzNonce: 02cdc4c5b143eb3c575772bf9ac9bac76295188d16c5790306afe5bf4805f0709202bc21c2995ce18c1c8434e4ebc244cecf6cc22515859dc6e9f35d9023df0f33b6
        print("ourBoltzNonce: \(ourBoltzNonceHex)")
        
        // The next few lintes will create the raw transaction of our refund, so that we can send the unsigned transaction to the Boltz API
        // and later on calculate the sighash that we AND the boltz API need to sign
        let prev_txs = ["010000000001018a60bf20ef3835698664ac5f1bd7babe6981078ae50433ee4e45a4f7d546353e0100000000feffffff02505a2b01000000001600140b2adca010bb166312ef5f904bbcec85f928e6beb44b02000000000022512052ecbd332c9320217667871743874992f1073f1c4f3ffa5a0602b987621ce40302473044022048a493285d7265ce980488d2b4c36b44975c0c65cb7758e44fd273ce30acf73402201b237c5d58c18d8a75303d3f873633463510228f3ddbe797d4c97fb6ba3f6b0c0121029b5348421694ce0dd0c454818211b31e6b5ea7bf7e215ddce4e7a4ed96168641be000000"];
        let txids: [String] = ["621d9aac4d478a66e31978b5447b47c4e2adc3f880b833ee18ed543a4fbccb05"];
        let input_indexs: [UInt32] = [1];
        let addresses: [String]  = ["bcrt1qad39rwqgjeusdmvwq7mn0p4g5x4eec3wxwcz9d"];
        let amounts: [UInt64] = [150_000];
        
        let base_tx = generateRawTx(prev_txs: prev_txs, txids: txids, input_indexs:input_indexs, addresses:addresses, amounts: amounts);
        
        let unsignedTx = getUnsignedTx(tx:base_tx)
        
        // unsignedTx: 020000000105cbbc4f3a54ed18ee33b880f8c3ade2c4477b44b57819e3668a474dac9a1d6201000000000000000001f049020000000000160014eb6251b808967906ed8e07b73786a8a1ab9ce22e00000000
        print("unsignedTx: \(unsignedTx)")
        
        let refundData = RefundRequest(
            pubNonce: ourBoltzNonceHex,
            transaction: unsignedTx,
            index: 0
        )
        
        // Now await for the refund data from the API
        let (pubNonce, partialSignature) = try await requestRefundAndProcess(swapID: "EvZHH6byHy5G", refundData: refundData)
        
        if let pubNonce = pubNonce, let partialSignature = partialSignature {
            print("Received PubNonce from the Boltz API: \(pubNonce)")
            // Received PubNonce from the Boltz API: 035832cde9eccdd4ce32135b64712c92da2437ce8137514a666545e51089ea90bd03f78ef5a63dbe0d47fe13c9c85ad84cd7df5391b17f03b9a370c9afa16eb2f416
            print("Received Partial Signature from the Boltz API: \(partialSignature)")
            // Received Partial Signature from the Boltz API: af01662446959e0a0b9a847fa9caf380e1fbe0a1fd56194e3e722196b90669f2
            
            do {
                // I created this P256K.Schnorr.Nonce(hexString: pubNonce) as I didn't find anything in the package to parse a hex, perhaps it's wrong
                let theirNonce = try P256K.Schnorr.Nonce(hexString: pubNonce)
                
                // Aggregate nonces (I can only aggregate nonce if they are in the swift struct P256K.MuSig.Nonce)
                let aggregatedNonce = try P256K.MuSig.Nonce(aggregating: [ourBoltzNonce.pubnonce, theirNonce])
                
                // Here is the code to get the sighash but I'm not sure if it works correctly
                let sighash = getSighash(tx: base_tx, txid: txids[0], input_index: input_indexs[0], agg_pubkey: tweakedKey.dataRepresentation.hex, sigversion: 1, proto: "");
                
                // current sighash: 47185fe6f35b4712b7fe8a168a7573a0ae10b8c97c936bdabfbfd8daff313ce6
                print("current sighash:", sighash);
                
                // Create our partial signatures (which also creates the session that we can later on use to parse the BoltzAPI signature
                let ourBoltzPartialSignature = try ourPrivateKey.partialSignature(
                    for: sighash.bytes,
                    pubnonce: ourBoltzNonce.pubnonce,
                    secureNonce: ourBoltzNonce.secnonce,
                    publicNonceAggregate: aggregatedNonce,
                    publicKeyAggregate: tweakedKey
                )
                
                print("ourBoltzPartialSignature: \(ourBoltzPartialSignature)")
                // ourBoltzPartialSignature: PartialSignature(dataRepresentation: 36 bytes, session: 133 bytes)
                
                let boltzAPIPartialSignature = try P256K.Schnorr.PartialSignature(
                    hexString: partialSignature,
                    session: ourBoltzPartialSignature.session
                )
                
                // boltzAPIPartialSignature: PartialSignature(dataRepresentation: 36 bytes, session: 133 bytes)
                print("boltzAPIPartialSignature: \(boltzAPIPartialSignature)")
                
                // Aggregate partial signatures into a full signature
                let aggregateBoltzSignature = try P256K.MuSig.aggregateSignatures([ourBoltzPartialSignature, boltzAPIPartialSignature])
                
                let sighashDigest = try! SHA256.hash(data: sighash.bytes)
                
                // This is an attempt to verify the signature (but I'm not quite convinced it works because whatever we put into ours as "for", it always returns valid
                // For some reason I can't put here the sighash.bytes (which we signed earlier) as I have to put a Digest into the for parameter
                let isOurSignatureValid = tweakedKey.isValidSignature(
                    ourBoltzPartialSignature,
                    publicKey: ourPrivateKey.publicKey,
                    nonce: ourBoltzNonce.pubnonce,
                    for: sighashDigest
                )
                
                // this always returns true no matter what is put in as 'for' parameter, which seems odd to me
                // isOurSignatureValid: true
                print("isOurSignatureValid: \(isOurSignatureValid)")
                
                // If I understood it correctly we need to put the aggregateSignatureHex in the witness of our transaction
                let aggregateSignatureHex = aggregateBoltzSignature.dataRepresentation.map { String(format: "%02x", $0) }.joined()
                
                // Aggregate Signature Hex: 3d4bac438dc5308c756c45f280ae749d1bc445aeb32138e5c3cab0774bd10f8819adc4628fc66884174f7c7669af11dfdd7e47189b05c601196eb43cb26b3169
                print("Aggregate Signature Hex: \(aggregateSignatureHex)")
                
                // I tried to see if we can verify the signature that we get back but this always returns false so I'm sure we're doing something wrong
                let isBoltzAPISignatureValid = tweakedKey.isValidSignature(
                    boltzAPIPartialSignature,
                    publicKey: boltzServerPublicKey,
                    nonce: theirNonce,
                    for: sighashDigest
                )
                
                // This one always returns false, so I'm sure I'm doing something wrong: isBoltzAPISignatureValid: false
                print("isBoltzAPISignatureValid: \(isBoltzAPISignatureValid)")
                
                let final_tx = buildTaprootTx(tx: base_tx, signature: aggregateSignatureHex, txid: txids[0], input_index: input_indexs[0]);
                
                
                // final transaction: 0200000000010105cbbc4f3a54ed18ee33b880f8c3ade2c4477b44b57819e3668a474dac9a1d6201000000000000000001f049020000000000160014eb6251b808967906ed8e07b73786a8a1ab9ce22e01403d4bac438dc5308c756c45f280ae749d1bc445aeb32138e5c3cab0774bd10f8819adc4628fc66884174f7c7669af11dfdd7e47189b05c601196eb43cb26b316900000000
                
                // if we'd decode it would look like this:
                //                {
                //                    "version": 2,
                //                    "locktime": 0,
                //                    "ins": [
                //                        {
                //                            "n": 1,
                //                            "script": {
                //                                "asm": "",
                //                                "hex": ""
                //                            },
                //                            "sequence": 0,
                //                            "txid": "621d9aac4d478a66e31978b5447b47c4e2adc3f880b833ee18ed543a4fbccb05",
                //                            "witness": [
                //                                "3d4bac438dc5308c756c45f280ae749d1bc445aeb32138e5c3cab0774bd10f8819adc4628fc66884174f7c7669af11dfdd7e47189b05c601196eb43cb26b3169"
                //                            ]
                //                        }
                //                    ],
                //                    "outs": [
                //                        {
                //                            "n": 0,
                //                            "script": {
                //                                "addresses": [
                //                                    "bc1qad39rwqgjeusdmvwq7mn0p4g5x4eec3wwp6ufh"
                //                                ],
                //                                "asm": "OP_0 eb6251b808967906ed8e07b73786a8a1ab9ce22e",
                //                                "hex": "0014eb6251b808967906ed8e07b73786a8a1ab9ce22e"
                //                            },
                //                            "value": 150000
                //                        }
                //                    ],
                //                    "hash": "7168ea08b893dccb2b5e87146c833206f19d51b80f3d02eebce6a7ba1c36a85a",
                //                    "txid": "7168ea08b893dccb2b5e87146c833206f19d51b80f3d02eebce6a7ba1c36a85a"
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
}

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
