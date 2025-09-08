//
//  SwapManager.swift
//  bittr
//
//  Created by Tom Melters on 24/01/2025.
//

import UIKit
import LDKNode
import Sentry
import P256K
import BitcoinDevKit
import CryptoKit
import LightningDevKit

class SwapManager: NSObject {
    
    // Normal Submarine Swaps states (Chain > Lightning)
    // 1. swap.created or invoice.set > Swap and/or Invoice created
    // 2. transaction.mempool > Onchain transaction received
    // 3. transaction.confirmed > Onchain transaction confirmed
    // 4. invoice.set > Invoice with correct amount created
    // 5. invoice.pending, invoice.paid, invoice.failedToPay > Invoice payment status
    // 6. transaction.claim.pending > Boltz is claiming the onchain transaction
    // 7. transaction.claimed > Boltz has claimed the onchain transaction
    // 8. swap.expired > No onchain transaction was received in time
    
    // Reverse Submarine Swaps states (Lightning > Chain)
    // 1. swap.created
    // 2. minerfee.paid > Optional if Boltz required prepayment of miner fee
    // 3. transaction.mempool > User has paid Lightning invoice, onchain transaction has been paid
    // 4. transaction.confirmed > Onchain transaction has been confirmed
    // 5. invoice.settled > User has claimed the onchain transaction and paid the Lightning invoice
    // 6. invoice.expired or swap.expired > User didn't pay invoice in time
    // 7. transaction.failed > Boltz couldn't send onchain transaction
    // 8. transaction.refunded > User didn't claim onchain transaction in time
    
    
    static func onchainToLightning(amountMsat:UInt64, swapVC:SwapViewController, existingInvoice:String? = nil) async {
        
        do {
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMddHHmmss"
            let idString = dateFormatter.string(from: Date())
            
            var invoice: String
            var actualAmountMsat: UInt64 = amountMsat
            
            if let existingInvoice = existingInvoice {
                // Use the existing invoice (for Lightning payment case)
                invoice = existingInvoice
                
                // Parse the existing invoice to get the actual amount
                if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: existingInvoice).getValue() {
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        actualAmountMsat = invoiceAmountMilli
                    }
                }
            } else {
                // Create an invoice for the amount we want to move.
                invoice = try await LightningNodeService.shared.receivePayment(
                    amountMsat: amountMsat,
                    description: "Swap onchain to lightning \(idString)",
                    expirySecs: 3600
                ).description
            }
            
            // Store invoice in cache.
            DispatchQueue.main.async {
                if let invoiceHash = swapVC.getInvoiceHash(invoiceString: invoice.description) {
                    let newTimestamp = Int(Date().timeIntervalSince1970)
                    CacheManager.storeInvoiceTimestamp(hash: invoiceHash, timestamp: newTimestamp)
                    CacheManager.storeInvoiceDescription(hash: invoiceHash, desc: "Swap onchain to lightning \(idString)")
                    print("Did cache invoice data.")
                }
                
                swapVC.coreVC!.bittrWallet.ongoingSwap!.dateID = "Swap onchain to lightning \(idString)"
                swapVC.coreVC!.bittrWallet.ongoingSwap!.createdInvoice = invoice.description
            }
            
            // Get next swap index and derive key dynamically
            let swapIndex = CacheManager.incrementSwapIndex()
            let dynamicPath = "m/503'/0'/0'/0/\(swapIndex)"
            
            let (privateKey, publicKey) = try! LightningNodeService.shared.getPrivatePublicKeyForPath(path: dynamicPath)
            
            // Get device token for webhook URL
            let deviceToken = CacheManager.getRegistrationToken() ?? ""
            
            // Check if we have a registration token (notifications enabled)
            if deviceToken.isEmpty {
                DispatchQueue.main.async {
                    swapVC.nextLabel.alpha = 1
                    swapVC.nextSpinner.stopAnimating()
                    swapVC.showAlert(
                        presentingController: swapVC,
                        title: Language.getWord(withID: "notificationsrequired"),
                        message: Language.getWord(withID: "notificationsrequiredmessage"),
                        buttons: [Language.getWord(withID: "okay")],
                        actions: [#selector(swapVC.askForPushNotifications)]
                    )
                }
                return
            }
            
            let webhookURL = "\(EnvironmentConfig.bittrAPIBaseURL)/webhook/boltz/\(deviceToken)"
            
            // Create POST API call.
            let parameters: [String: Any] = [
                "from": "BTC",
                "to": "BTC",
                "invoice": invoice,
                "refundPublicKey": publicKey,
                "webhook": [
                    "url": webhookURL,
                    "hashSwapId": false
                ]
            ]

            let apiURL = EnvironmentConfig.boltzBaseURL
            
            Task {
                await CallsManager.makeApiCall(url: "\(apiURL)/swap/submarine", parameters: parameters, getOrPost: "POST") { result in
                    
                    switch result {
                    case .failure(let error):
                        DispatchQueue.main.async {
                            swapVC.nextLabel.alpha = 1
                            swapVC.nextSpinner.stopAnimating()
                            swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "error"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    case .success(let receivedDictionary):
                        if let errorMessage = receivedDictionary["error"] as? String {
                            DispatchQueue.main.async {
                                swapVC.nextLabel.alpha = 1
                                swapVC.nextSpinner.stopAnimating()
                                swapVC.showAlert(
                                    presentingController: swapVC,
                                    title: Language.getWord(withID: "error"),
                                    message: errorMessage,
                                    buttons: [Language.getWord(withID: "okay")],
                                    actions: nil
                                )
                            }
                            return
                        }
                        
                        // Example success {"bip21":"bitcoin:bcrt1pfalvfpkhtha6qmxmkgvljnajnc2hvl2c828euxh5679e302gk9wsh3e9af?amount=0.00050352&label=Send%20to%20BTC%20lightning","acceptZeroConf":false,"expectedAmount":50352,"id":"ChTExx2srRLT","address":"bcrt1pfalvfpkhtha6qmxmkgvljnajnc2hvl2c828euxh5679e302gk9wsh3e9af","swapTree":{"claimLeaf":{"version":192,"output":"a914ed96f252263cd8cc0a616602875f76bfb0c70fcd8820611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61fac"},"refundLeaf":{"version":192,"output":"2004cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24ad02df01b1"}},"claimPublicKey":"03611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61f","timeoutBlockHeight":479}
                            
                        print(receivedDictionary)
                        
                        DispatchQueue.main.async {
                            if
                                let onchainAddress = receivedDictionary["address"] as? String,
                                let expectedAmount = receivedDictionary["expectedAmount"] as? Int,
                                let swapID = receivedDictionary["id"] as? String,
                                let swapTree = receivedDictionary["swapTree"] as? NSDictionary,
                                let claimLeaf = swapTree["claimLeaf"] as? NSDictionary,
                                let claimLeafOutput = claimLeaf["output"] as? String,
                                let refundLeaf = swapTree["refundLeaf"] as? NSDictionary,
                                let refundLeafOutput = refundLeaf["output"] as? String,
                                let claimPublicKey = receivedDictionary["claimPublicKey"] as? String {
                                
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.privateKey = privateKey
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.boltzID = swapID
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.boltzOnchainAddress = onchainAddress
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.boltzExpectedAmount = expectedAmount
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.claimLeafOutput = claimLeafOutput
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.refundLeafOutput = refundLeafOutput
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.claimPublicKey = claimPublicKey
                                
                                self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: CacheManager.swapToDictionary(swapVC.coreVC!.bittrWallet.ongoingSwap!))
                                
                                Task {
                                    await self.checkOnchainFees(swapVC: swapVC)
                                }
                            } else {
                                // Expected data unavailable.
                                DispatchQueue.main.async {
                                    swapVC.nextLabel.alpha = 1
                                    swapVC.nextSpinner.stopAnimating()
                                    swapVC.showAlert(
                                        presentingController: swapVC,
                                        title: Language.getWord(withID: "error"),
                                        message: Language.getWord(withID: "swaperror2"),
                                        buttons: [Language.getWord(withID: "okay")],
                                        actions: nil
                                    )
                                }
                            }
                        }
                    }
                }
            }
        } catch let error as NodeError {
            let errorString = handleNodeError(error)
            DispatchQueue.main.async {
                swapVC.nextLabel.alpha = 1
                swapVC.nextSpinner.stopAnimating()
                swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "error"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                SentrySDK.capture(error: error)
            }
        } catch {
            DispatchQueue.main.async {
                swapVC.nextLabel.alpha = 1
                swapVC.nextSpinner.stopAnimating()
                swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                SentrySDK.capture(error: error)
            }
        }
    }
    
    static func checkOnchainFees(swapVC:SwapViewController) async {
        
        guard let ongoingSwap = await swapVC.coreVC!.bittrWallet.ongoingSwap else {return}
        
        // Check what the onchain fees will be for sending this onchain payment.
        if let actualWallet = LightningNodeService.shared.getWallet() {
            
            Task {
                do {
                    // Get current fees for fast onchain transaction.
                    let feeEstimates = try LightningNodeService.shared.getEsploraClient()!.getFeeEstimates()
                    let high = feeEstimates[1]!
                    let feeHigh = Float(Int(high*10))/10
                    
                    // Calculate transaction size.
                    let size = try await swapVC.getSize(address: ongoingSwap.boltzOnchainAddress!, amountSats: ongoingSwap.boltzExpectedAmount!, wallet: actualWallet)
                    
                    // Calculate fees.
                    let feesForOnchainPayment:Int = Int(CGFloat(feeHigh*Float(size)))
                    let feesForLightningPayment:Int = ongoingSwap.boltzExpectedAmount! - ongoingSwap.satoshisAmount
                    print("Fees lightning: \(feesForLightningPayment). Fees onchain: \(feesForOnchainPayment).")
                    
                    // Confirm fees with user.
                    DispatchQueue.main.async {
                        swapVC.coreVC!.bittrWallet.ongoingSwap!.feeHigh = feeHigh
                        swapVC.coreVC!.bittrWallet.ongoingSwap!.onchainFees = feesForOnchainPayment
                        swapVC.coreVC!.bittrWallet.ongoingSwap!.lightningFees = feesForLightningPayment
                        swapVC.confirmExpectedFees()
                    }
                } catch {
                    print("Error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: \(error.localizedDescription).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                        SentrySDK.capture(error: error)
                    }
                }
            }
        }
    }
    
    static func sendOnchainPayment(swapVC:SwapViewController) {
        
        guard let ongoingSwap = swapVC.coreVC?.bittrWallet.ongoingSwap else { return }
            
        // Send onchain transaction.
        if let actualWallet = LightningNodeService.shared.getWallet() {
            
            Task {
                do {
                    let tx = try await swapVC.getTx(address: ongoingSwap.boltzOnchainAddress!, amountSats: ongoingSwap.boltzExpectedAmount!, wallet: actualWallet, selectedVbyte: ongoingSwap.feeHigh!)
                    
                    if let client = LightningNodeService.shared.getClient() {
                        
                        let txid = try client.transactionBroadcast(tx: tx)
                        
                        print("Transaction ID: \(txid)")
                    
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            print("Successful transaction.")
                            
                            // Update swap object.
                            ongoingSwap.sentOnchainTransactionID = txid
                            ongoingSwap.lockupTx = tx.serialize().map { String(format: "%02hhx", $0) }.joined()
                            swapVC.coreVC!.bittrWallet.ongoingSwap!.sentOnchainTransactionID = txid
                            swapVC.coreVC!.bittrWallet.ongoingSwap!.lockupTx = tx.serialize().map { String(format: "%02hhx", $0) }.joined()
                            self.updateSwapFileWithLockupTx(swapID: swapVC.coreVC!.bittrWallet.ongoingSwap!.boltzID!, lockupTx: swapVC.coreVC!.bittrWallet.ongoingSwap!.lockupTx!)
                            
                            // Create transaction object.
                            CacheManager.storeInvoiceDescription(hash: txid, desc: ongoingSwap.dateID)
                            CacheManager.storeSwapID(dateID: ongoingSwap.dateID, swapID: ongoingSwap.boltzID!)
                            
                            // Update Home table.
                            LightningNodeService.shared.lightSync() { _ in }
                            
                            // Call didCompleteOnchainTransaction to set up WebSocket monitoring
                            swapVC.didCompleteOnchainTransaction()
                        }
                    }
                } catch {
                    // Log the exact error for debugging
                    print("Transaction error: \(error.localizedDescription)")
                    
                    // Report to Sentry for monitoring
                    SentrySDK.capture(error: error)
                    
                    DispatchQueue.main.async {
                        swapVC.showAlert(
                            presentingController: swapVC,
                            title: Language.getWord(withID: "paymentfailed"),
                            message: Language.getWord(withID: "paymentfailed3"),
                            buttons: [Language.getWord(withID: "okay")],
                            actions: nil
                        )
                    }
                }
            }
        }
    }
    
    static func checkSwapStatus(_ swapID:String, completion: @escaping (NSDictionary?) -> Void) {
        
        /* {
         "status":"transaction.mempool",
         "zeroConfRejected":true,
         "transaction":{
         "id":"2edfaeb630a8de4870c33046483c22ef2dd14f87c9b45e242924138ad0bb50cc",
         "hex":"010000000001010339c27932ed3437e12c2021e1b219aca14ee5af696ae4b2d93b9d406b05f0630000000000feffffff02f1f42b010000000016001432abff3cfd36f4f83fbe2c50534b728254153acab0c40000000000002251204f7ec486d75dfba06cdbb219f94fb29e15767d583a8f9e1af4d78b98bd48b15d024730440220290e6d4bf4c14c9b2a60856e50abb5715fb1646b51f1737dd1ed7a18d343c1c2022060408caa7ea17d3dd1dcd22be3334a3ec65023f841bca48d11c50f4c3cd0a9590121026479e19c5d9c4e162442f802221f1355fc3568f9cca5491c2c621542c209cd43bf000000"}
         } */
        
        // Create GET API call.
        let apiURL = EnvironmentConfig.boltzBaseURL
    
        Task {
            await CallsManager.makeApiCall(url: "\(apiURL)/swap/\(swapID)", parameters: nil, getOrPost: "GET") { result in
                
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                case .success(let receivedDictionary):
                    completion(receivedDictionary)
                }
            }
        }
    }
    
    static func lightningToOnchain(amountSat:Int, swapVC:SwapViewController, payoutAddress:String? = nil) async {
        
        // For lightning-to-onchain swaps, the user's input is the final amount they want to receive
        // We need to add the claim transaction fee to ensure they receive exactly what they input
        let claimTransactionFee = try? await BoltzRefund.calculateClaimOrRefundTransactionFee()
        let onchainAmountWithFee = amountSat + (claimTransactionFee ?? 0)
        
        // Call /v2/swap/reverse to receive the Lightning invoice we should pay.
        let randomPreimage = self.generateRandomPreimage()
        let randomPreimageHash = self.sha256Hash(of: randomPreimage)
        let randomPreimageHashHex = randomPreimageHash.hexEncodedString()

        // Get next swap index and derive key dynamically
        let swapIndex = CacheManager.incrementSwapIndex()
        let dynamicPath = "m/503'/0'/0'/0/\(swapIndex)"
        
        let (privateKey, publicKey) = try! LightningNodeService.shared.getPrivatePublicKeyForPath(path: dynamicPath)

        let wallet = LightningNodeService.shared.getWallet()
        
        // Use provided payout address if available, otherwise get a new unused address
        let destinationAddress: String?
        if let payoutAddress = payoutAddress {
            print("DEBUG - Using provided payout address: \(payoutAddress)")
            destinationAddress = payoutAddress
        } else {
            print("DEBUG - Getting new unused address for payout")
            destinationAddress = wallet?.nextUnusedAddress(keychain: .external).address.description
        }
        
        print("randomPreimage: \(randomPreimage.hexEncodedString())")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let idString = dateFormatter.string(from: Date())
        
        // Get device token for webhook URL
        let deviceToken = CacheManager.getRegistrationToken() ?? ""
        
        // Check if we have a registration token (notifications enabled)
        if deviceToken.isEmpty {
            DispatchQueue.main.async {
                swapVC.nextLabel.alpha = 1
                swapVC.nextSpinner.stopAnimating()
                swapVC.showAlert(
                    presentingController: swapVC,
                    title: Language.getWord(withID: "notificationsrequired"),
                    message: Language.getWord(withID: "notificationsrequiredmessage"),
                    buttons: [Language.getWord(withID: "okay")],
                    actions: [#selector(swapVC.askForPushNotifications)]
                )
            }
            return
        }
        
        
        let webhookURL = "\(EnvironmentConfig.bittrAPIBaseURL)/webhook/boltz/\(deviceToken)"
        
        let parameters: [String: Any] = [
            "from": "BTC",
            "to": "BTC",
            "claimPublicKey": publicKey,
            "preimageHash": randomPreimageHashHex,
            "onchainAmount": onchainAmountWithFee, // Use amount with fee included
            "webhook": [
                "url": webhookURL,
                "hashSwapId": false,
                "status": ["transaction.mempool", "transaction.confirmed", "invoice.settled", "swap.expired", "transaction.failed"]
            ]
        ]
        
        let apiURL = EnvironmentConfig.boltzBaseURL
        
        Task {
            await CallsManager.makeApiCall(url: "\(apiURL)/swap/reverse", parameters: parameters, getOrPost: "POST") { result in
                
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        swapVC.nextLabel.alpha = 1
                        swapVC.nextSpinner.stopAnimating()
                        swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "swapfunds2"), message: "\(Language.getWord(withID: "error")): \(error)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                case .success(let receivedDictionary):
                    if let errorMessage = receivedDictionary["error"] as? String {
                        DispatchQueue.main.async {
                            swapVC.nextLabel.alpha = 1
                            swapVC.nextSpinner.stopAnimating()
                            swapVC.showAlert(
                                presentingController: swapVC,
                                title: Language.getWord(withID: "error"),
                                message: errorMessage,
                                buttons: [Language.getWord(withID: "okay")],
                                actions: nil
                            )
                        }
                        return
                    }
                    
                    // Example success: {id = yes7P5Hn2FD5; invoice = lnbcrt505610n1p58093msp5k4f2jxgmu059lc8awdccdy8ppx9uw0wtxhmwa0ytna48ykpjlu9spp5augg6x7kd2dj2gs0z5lnpj98pvyyf4kpmrtt43sp8vawdrgm7l2qdql2djkuepqw3hjqsj5gvsxzerywfjhxucxqyp2xqcqzyl9qyysgq3glstd77evhlg2qywjku4lj4mffufgc2wy6trxsjar5a2mdzp6e9308z4d4prhjs03vegamm7raw0ln5k94l5lz8vu5yewz7hf6w7yqpjqj2mj; lockupAddress = bcrt1p32hqu3ve32x524994sxpewdvdznfjgd0ya2xh40z6x9tj5s2mmusx273a3; refundPublicKey = 035578a38b772461f2481b2a9c6f6802419b11282fb3719cde6af337c077e3d5f3; swapTree = {claimLeaf = {output = 82012088a91475b687397f92783b38c7381725bfcf27d65eef3f8820036f6171920eec6d2f377e4c0ab88960307c7d9d817ddf65585bc28a8334be1aac; version = 192;}; refundLeaf = {output = 205578a38b772461f2481b2a9c6f6802419b11282fb3719cde6af337c077e3d5f3ad024d01b1; version = 192;};}; timeoutBlockHeight = 333;}
                    
                    DispatchQueue.main.async {
                        swapVC.coreVC!.bittrWallet.ongoingSwap!.dateID = "Swap lightning to onchain " + idString
                        swapVC.coreVC!.bittrWallet.ongoingSwap!.privateKey = privateKey
                        swapVC.coreVC!.bittrWallet.ongoingSwap!.preimage = randomPreimage.hexEncodedString()
                        swapVC.coreVC!.bittrWallet.ongoingSwap!.destinationAddress = destinationAddress
                        
                        // Save swap details to file
                        if let swapID = receivedDictionary["id"] as? String,
                           let boltzInvoice = receivedDictionary["invoice"] as? String,
                           let swapTree = receivedDictionary["swapTree"] as? NSDictionary,
                           let claimLeaf = swapTree["claimLeaf"] as? NSDictionary,
                           let claimLeafOutput = claimLeaf["output"] as? String,
                           let refundLeaf = swapTree["refundLeaf"] as? NSDictionary,
                           let refundLeafOutput = refundLeaf["output"] as? String,
                           let refundPublicKey = receivedDictionary["refundPublicKey"] as? String {
                            swapVC.coreVC!.bittrWallet.ongoingSwap!.boltzID = swapID
                            swapVC.coreVC!.bittrWallet.ongoingSwap!.boltzInvoice = boltzInvoice
                            swapVC.coreVC!.bittrWallet.ongoingSwap!.claimLeafOutput = claimLeafOutput
                            swapVC.coreVC!.bittrWallet.ongoingSwap!.refundLeafOutput = refundLeafOutput
                            swapVC.coreVC!.bittrWallet.ongoingSwap!.refundPublicKey = refundPublicKey
                            swapVC.coreVC!.bittrWallet.ongoingSwap!.sentLightningPaymentID = randomPreimage.hexEncodedString()
                            self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: CacheManager.swapToDictionary(swapVC.coreVC!.bittrWallet.ongoingSwap!))
                            
                            self.checkReverseSwapFees(swapVC: swapVC)
                        } else {
                            // Expected data unavailable.
                            DispatchQueue.main.async {
                                swapVC.nextLabel.alpha = 1
                                swapVC.nextSpinner.stopAnimating()
                                swapVC.showAlert(
                                    presentingController: swapVC,
                                    title: Language.getWord(withID: "error"),
                                    message: Language.getWord(withID: "swaperror2"),
                                    buttons: [Language.getWord(withID: "okay")],
                                    actions: nil
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    static func generateRandomPreimage() -> Data {
        var preimage = Data(count: 32)
        let result = preimage.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard result == errSecSuccess else {
            fatalError("Failed to generate random preimage")
        }
        return preimage
    }
    
    static func sha256Hash(of data: Data) -> Data {
        return Data(SHA256.hash(data: data))
    }
    
    static func saveSwapDetailsToFile(swapID: String, swapDictionary: NSDictionary) {
        do {
            // Convert NSDictionary to JSON Data
            let jsonData = try JSONSerialization.data(withJSONObject: swapDictionary, options: .prettyPrinted)
            
            // Get the documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("\(swapID).json")
            
            // Write the JSON data to file
            try jsonData.write(to: fileURL)
            
            print("Swap details saved to: \(fileURL.path)")
        } catch {
            print("Error saving swap details to file: \(error)")
        }
    }
    
    static func loadSwapDetailsFromFile(swapID: String) -> NSDictionary? {
        do {
            // Get the documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("\(swapID).json")
            
            // Read the JSON data from file
            let jsonData = try Data(contentsOf: fileURL)
            
            // Convert JSON Data to NSDictionary
            if let dictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as? NSDictionary {
                return dictionary
            }
        } catch {
            print("Error loading swap details from file: \(error)")
        }
        return nil
    }
    
    static func updateSwapFileWithLockupTx(swapID: String, lockupTx: String) {
        
        // Load existing swap details
        guard let existingSwapDetails = loadSwapDetailsFromFile(swapID: swapID) else {
            print("Could not load existing swap details for ID: \(swapID)")
            return
        }
        
        // Create a mutable copy and add the lockup transaction
        let updatedSwapDetails = existingSwapDetails.mutableCopy() as! NSMutableDictionary
        updatedSwapDetails.setValue(lockupTx, forKey: "lockupTx")
        
        // Save the updated swap details back to file
        self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: updatedSwapDetails)
        
        print("Updated swap file with lockup transaction for ID: \(swapID)")
            
    }
    
    static func updateSwapFileWithFees(swapID: String, totalFees: Int, userAmount: Int, direction: Int) {
        
        // Load existing swap details
        guard let existingSwapDetails = loadSwapDetailsFromFile(swapID: swapID) else {
            print("Could not load existing swap details for ID: \(swapID)")
            return
        }
        
        // Create a mutable copy and add the fees information
        let updatedSwapDetails = existingSwapDetails.mutableCopy() as! NSMutableDictionary
        updatedSwapDetails.setValue(totalFees, forKey: "totalFees")
        updatedSwapDetails.setValue(userAmount, forKey: "userAmount")
        updatedSwapDetails.setValue(direction, forKey: "direction")
        
        // Save the updated swap details back to file
        self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: updatedSwapDetails)
        
        print("Updated swap file with fees for ID: \(swapID)")
    }
    
    static func addOnchainTransactionToUI(transactionId:String, swapVC:SwapViewController) {
        // Load swap details to get the description and user amount
        guard let ongoingSwap = swapVC.coreVC?.bittrWallet.ongoingSwap else {
            print("Could not load swap details.")
            return
        }
        
        // Store transaction details in cache.
        CacheManager.storeInvoiceDescription(hash: transactionId, desc: ongoingSwap.dateID)
        CacheManager.storeSwapID(dateID: ongoingSwap.dateID, swapID: ongoingSwap.boltzID!)
        
        // Light sync wallet to add transaction to table.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            LightningNodeService.shared.lightSync() { _ in }
        }
    }
    
    static func checkReverseSwapFees(swapVC:SwapViewController) {
        
        guard let ongoingSwap = swapVC.coreVC?.bittrWallet.ongoingSwap else { return }
        
        // Check requested invoice amount.
        if swapVC.checkInternetConnection() {
                
            if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: ongoingSwap.boltzInvoice!).getValue() {
                // Lightning invoice.
                if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                    let invoiceAmount = Int(invoiceAmountMilli)/1000
                    
                    // Calculate onchain fees.
                    // For lightning-to-onchain swaps, the user's input is the final amount they want to receive
                    // The invoice amount includes Boltz fees, so we need to calculate the actual on-chain amount
                    let finalOnchainAmount = ongoingSwap.satoshisAmount // This is what the user wants to receive
                    let onchainFees:Int = invoiceAmount - finalOnchainAmount
                    
                    // Note: The claim transaction fee is already included in the on-chain amount requested
                    // so the user will receive exactly the amount they input
                    
                    // Calculate maximum total routing fees.
                    let invoicePaymentResult = Bindings.paymentParametersFromInvoice(invoice: parsedInvoice)
                    let (_, _, tryRouteParams) = invoicePaymentResult.getValue()!
                    let maximumRoutingFeesMsat:Int = Int(tryRouteParams.getMaxTotalRoutingFeeMsat() ?? 0)
                    let lightningFees:Int = maximumRoutingFeesMsat/1000
                    
                    // Calculate claim transaction fee
                    Task {
                        do {
                            let claimTransactionFee = try await BoltzRefund.calculateClaimOrRefundTransactionFee()
                            
                            DispatchQueue.main.async {
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.boltzExpectedAmount = invoiceAmount
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.onchainFees = onchainFees
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.lightningFees = lightningFees
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.claimTransactionFee = claimTransactionFee
                                
                                // Confirm fees with user.
                                swapVC.confirmExpectedFees()
                            }
                        } catch {
                            print("❌ Failed to calculate claim transaction fee: \(error)")
                            // Fallback to default fee calculation without claim transaction fee
                            DispatchQueue.main.async {
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.boltzExpectedAmount = invoiceAmount
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.onchainFees = onchainFees
                                swapVC.coreVC!.bittrWallet.ongoingSwap!.lightningFees = lightningFees
                                
                                // Confirm fees with user.
                                swapVC.confirmExpectedFees()
                            }
                        }
                    }
                }
            }
        }
    }
    
    static func sendLightningPayment(swapVC:SwapViewController) {
        // Fees confirmed by user, pay Boltz invoice.
        guard let ongoingSwap = swapVC.coreVC?.bittrWallet.ongoingSwap else { 
            print("❌ No ongoing swap found in sendLightningPayment")
            return 
        }
            
        Task {
            do {
                let paymentHash = try await LightningNodeService.shared.sendPayment(invoice: Bolt11Invoice.fromStr(invoiceStr: ongoingSwap.boltzInvoice!))
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash)
                    
                    if thisPayment != nil, thisPayment!.status == .failed {
                        // Payment came back failed.
                        swapVC.confirmStatusLabel.text = Language.getWord(withID: "swapstatusfailedtopay")
                        swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "paymentfailed"), message: Language.getWord(withID: "paymentfailed2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                        return
                    }
                    
                    // Success payment
                    swapVC.confirmStatusLabel.text = Language.getWord(withID: "swapstatusawaitingtransaction")
                    
                    // Store transaction details in cache.
                    CacheManager.storeSwapID(dateID: ongoingSwap.dateID, swapID: ongoingSwap.boltzID!)
                    CacheManager.storeInvoiceDescription(hash: paymentHash, desc: ongoingSwap.dateID)
                    
                    // Create lightning transaction with swap details
                    let newTransaction = swapVC.createTransaction(transactionDetails: nil, paymentDetails: thisPayment!, bittrTransaction: nil, coreVC: swapVC.coreVC, bittrTransactions: nil)
                    
                    // Calculate fees
                    if Int(thisPayment?.amountMsat ?? 0)/1000 > ongoingSwap.satoshisAmount {
                        let feesIncurred = (Int(thisPayment?.amountMsat ?? 0)/1000) - ongoingSwap.satoshisAmount
                        CacheManager.storePaymentFees(hash: paymentHash, fees: feesIncurred)
                        newTransaction.fee = feesIncurred
                    } else {
                        newTransaction.fee = 0
                    }
                    
                    // Add to home view controller
                    swapVC.homeVC?.addLightningTransaction(thisTransaction: newTransaction, paymentDetails: thisPayment!)
                    
                    swapVC.webSocketManager = WebSocketManager()
                    swapVC.webSocketManager!.delegate = swapVC
                    swapVC.webSocketManager!.swapID = ongoingSwap.boltzID!
                    swapVC.webSocketManager!.connect()
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    // Error alert for NodeError
                    swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "paymentfailed"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    SentrySDK.capture(error: error)
                }
            } catch {
                DispatchQueue.main.async {
                    // General error alert
                    swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    SentrySDK.capture(error: error)
                }
            }
        }
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

