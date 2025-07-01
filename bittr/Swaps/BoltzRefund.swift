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
        //            acceptZeroConf = 0;
        //            address = bcrt1p4m0sj58tex70w95y8v25tlqcq7zqn73636r24qyk8s3y249nrd9syvqk2e;
        //            bip21 = "bitcoin:bcrt1p4m0sj58tex70w95y8v25tlqcq7zqn73636r24qyk8s3y249nrd9syvqk2e?amount=0.00200502&label=Send%20to%20BTC%20lightning";
        //            claimPublicKey = 03d0ceae7a2076302b7418fd8ad1c8e6f05cb5e8f24116813074e1fb4e87d3b523;
        //            expectedAmount = 200502;
        //            id = t6qPA5n7IAIQ;
        //            swapTree =     {
        //                claimLeaf =         {
        //                    output = a91439aa8f251488b1a02fc89fe448f9bbf45a3b01f48820d0ceae7a2076302b7418fd8ad1c8e6f05cb5e8f24116813074e1fb4e87d3b523ac;
        //                    version = 192;
        //                };
        //                refundLeaf =         {
        //                    output = 20f8b2dfc86aa1f5c6df0d3089c74088eaf0527216b61472113e8839e4e4bbb69fad02c004b1;
        //                    version = 192;
        //                };
        //            };
        //            timeoutBlockHeight = 1216;
        //        }
        let boltzServerPublicKeyBytes = try! "03d0ceae7a2076302b7418fd8ad1c8e6f05cb5e8f24116813074e1fb4e87d3b523".bytes
        
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
        let prev_txs = ["01000000000102cd2a020100591623e557eb4d19d684ab122daea75a13f3c4995b61b4bdbcb62d0000000000feffffff4bd6aa91b409959e97ab1a2b712ef387e03f5ffc406cd38f5107ef4e9a9b68fa0100000000feffffff0278992a010000000016001472a8ba21fdf7e8fd6a07998160fc9c03828eaf20360f030000000000225120aedf0950ebc9bcf716843b1545fc18078409fa3a8e86aa80963c224554b31b4b02473044022057cd6591b377754c8d84e5a354149f815cb7faa6cff3c981adc033679a80aed902204d6191beda76122d8ae5a316de2a36d4820751d989273aac816dfe80f63881210121038a3f4f936b72abeee2e24c89985ab33e62fd81f784cfcc77edb5312a09aba58a024730440220604c5937be664d2b4cefd8ccc79f00db4bffb7412e5167f345c78f6da4f908ac02206dc37e482d1acaa11513a08d9d3afe983a0cafa511f4ea9e534345fc4cd9345a0121038a3f4f936b72abeee2e24c89985ab33e62fd81f784cfcc77edb5312a09aba58ad0000000"];
        let txids: [String] = ["2927c5ba00bbc5f0c01172bc1f4611215031bad392d0108b0c425ec69c0c23ee"];
        let input_indexs: [UInt32] = [1];
        let addresses: [String]  = ["bcrt1q86yrllp6mzcdxpvgm8rap7cwwpfnrrgvujsqd0"];
        let amounts: [UInt64] = [199_502];
        
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
}

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
