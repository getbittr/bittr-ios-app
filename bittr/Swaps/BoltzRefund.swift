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
        //           acceptZeroConf = 0;
        //           address = bcrt1pnvdn47r9lwwdtv0wax3537j5xtvyg4z9jk2qut7e47vxawxx028s305jsh;
        //           bip21 = "bitcoin:bcrt1pnvdn47r9lwwdtv0wax3537j5xtvyg4z9jk2qut7e47vxawxx028s305jsh?amount=0.00300602&label=Send%20to%20BTC%20lightning";
        //           claimPublicKey = 034d0ec2790580f2f22b2b6e7e56ca30962ea2395f01cb563afe24440e3117fc55;
        //           expectedAmount = 300602;
        //           id = tgTKex31LpzS;
        //           swapTree =     {
        //               claimLeaf =         {
        //                   output = a914227e1df5d85c2eb50e78b2e041bf0c3b8e2f086588204d0ec2790580f2f22b2b6e7e56ca30962ea2395f01cb563afe24440e3117fc55ac;
        //                   version = 192;
        //               };
        //               refundLeaf =         {
        //                   output = 20ef07ea4cacba6709d43a74278a7b6c792cbcef10a035f04d2f196c9069876876ad02b204b1;
        //                   version = 192;
        //               };
        //           };
        //           timeoutBlockHeight = 1202;
        //       }
        let boltzServerPublicKeyBytes = try! "034d0ec2790580f2f22b2b6e7e56ca30962ea2395f01cb563afe24440e3117fc55".bytes
        
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
        let boltzAggregateKey = try P256K.MuSig.aggregate([boltzServerPublicKey, ourPrivateKey.publicKey], format: P256K.Format.uncompressed)
        
        // The boltzAggregateKey looks like this: 04499bcea8f3dbf842f347c30b08ae4e3e29141e689c8f1de82c9fd6f37b57d5c4f2712db01543c5d9226b6629294f95958efd2994ae071cd20e5f151e02004a8a
        let hexString = String(bytes: boltzAggregateKey.dataRepresentation)
        // hexString: 04499bcea8f3dbf842f347c30b08ae4e3e29141e689c8f1de82c9fd6f37b57d5c4f2712db01543c5d9226b6629294f95958efd2994ae071cd20e5f151e02004a8a
        print("hexString: \(hexString)")
        
        // Now, we take the refundLeaf.output from our Swap and tweak the key, again because we need an uncompressed key later on to create the sigHash, we put format .uncompressed
        let tweak = try! "20ef07ea4cacba6709d43a74278a7b6c792cbcef10a035f04d2f196c9069876876ad02b204b1".bytes
        let tweakedKey = try! boltzAggregateKey.add(tweak, format: P256K.Format.uncompressed)
        
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
        let ourBoltzNonceHex = try! ourBoltzNonce.pubnonce.serialized().hex
        // ourBoltzNonce: 02cdc4c5b143eb3c575772bf9ac9bac76295188d16c5790306afe5bf4805f0709202bc21c2995ce18c1c8434e4ebc244cecf6cc22515859dc6e9f35d9023df0f33b6
        print("ourBoltzNonce: \(ourBoltzNonceHex)")
        
        // The next few lintes will create the raw transaction of our refund, so that we can send the unsigned transaction to the Boltz API
        // and later on calculate the sighash that we AND the boltz API need to sign
        let prev_txs = ["0100000000010114ee6d11384b493b84221ae947c29ac97d8905358a011ca7b9eb511631ee20500000000000feffffff02e32a22010000000016001404dee8419071b93a03164ebf7acde824918891653a960400000000002251209b1b3af865fb9cd5b1eee9a348fa5432d844544595940e2fd9af986eb8c67a8f0247304402205d9a5056a83a87433b11a22e46e440e2de6f2752bdb6aa75250a8802799d12a902200690045e74ce21913023a9023d391a4614879dd98e016d52d4e8061ffc3023a90121033ce211fdd9af1d9b4abb5feef0c902f8e6471fd2d6ed0889b25cc20b18a8703ec2000000"];
        let txids: [String] = ["2a434ca92a59741d164de40e00dedb51368f292c7ada130712f6171e773990a0"];
        let input_indexs: [UInt32] = [1];
        let addresses: [String]  = ["bcrt1qr8sqyhmq0ulgumt28znlnz5dy6wkl564r65swh"];
        let amounts: [UInt64] = [150_000];
        
        let base_tx = generateRawTx(prev_txs: prev_txs, txids: txids, input_indexs:input_indexs, addresses:addresses, amounts: amounts);
        
        let unsignedTx = getUnsignedTx(tx:base_tx)
        
        // unsignedTx: 0200000001a09039771e17f6120713da7a2c298f3651dbde000ee44d161d74592aa94c432a01000000000000000001f04902000000000016001419e0025f607f3e8e6d6a38a7f98a8d269d6fd35500000000
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
                let sighash = getSighash(tx: base_tx, txid: txids[0], input_index: input_indexs[0], agg_pubkey: tweakedKey.dataRepresentation.hex, sigversion: 1, proto: "");
                
                // current sighash: 337179eb31fc94dcfd09d866f77e24e6905c4bb0346affd15a63b763034836a9
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
                
                // Aggregate Signature Hex: 3a60472813d1effb534a6d95e0e3dfb41e908576de8ef3788fc3a98963258ed41d7195873c734790408b9d8c25b2edb50abe8833fdbdb37e4b068fe23d87e068
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
