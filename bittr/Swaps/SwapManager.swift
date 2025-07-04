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
    
    
    static func onchainToLightning(amountMsat:UInt64, delegate:Any?) async {
        
        do {
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMddHHmmss"
            let idString = dateFormatter.string(from: Date())
            
            // Create an invoice for the amount we want to move.
            let invoice = try await LightningNodeService.shared.receivePayment(
                amountMsat: amountMsat,
                description: "Swap onchain to lightning \(idString)",
                expirySecs: 3600
            )
            
            // Store invoice in cache.
            DispatchQueue.main.async {
                if let swapVC = delegate as? SwapViewController {
                    if let invoiceHash = swapVC.getInvoiceHash(invoiceString: invoice) {
                        let newTimestamp = Int(Date().timeIntervalSince1970)
                        CacheManager.storeInvoiceTimestamp(hash: invoiceHash, timestamp: newTimestamp)
                        CacheManager.storeInvoiceDescription(hash: invoiceHash, desc: "Swap onchain to lightning \(idString)")
                        print("Did cache invoice data.")
                    }
                }
            }
            
            let (privateKey, publicKey) = try LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")
            
            // Get device token for webhook URL
            let deviceToken = CacheManager.getRegistrationToken() ?? ""
            
            // Check if we have a registration token (notifications enabled)
            if deviceToken.isEmpty {
                DispatchQueue.main.async {
                    if let swapVC = delegate as? SwapViewController {
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
                }
                return
            }
            
            let webhookURL = "https://model-arachnid-viable.ngrok-free.app/webhook/boltz/\(deviceToken)"
            
            // Create POST API call.
            let parameters: [String: Any] = [
                "from": "BTC",
                "to": "BTC",
                "invoice": invoice,
                "refundPublicKey": publicKey,
                "webhook": [
                    "url": webhookURL,
                    "hashSwapId": false
                    // "status": ["transaction.confirmed"]
                ]
            ]

            var apiURL = "https://api.boltz.exchange/v2"
            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                apiURL = "https://api.regtest.getbittr.com/v2"
            }
            
            Task {
                await CallsManager.makeApiCall(url: "\(apiURL)/swap/submarine", parameters: parameters, getOrPost: "POST") { result in
                    
                    switch result {
                    case .failure(let error):
                        DispatchQueue.main.async {
                            if let swapVC = delegate as? SwapViewController {
                                swapVC.nextLabel.alpha = 1
                                swapVC.nextSpinner.stopAnimating()
                                swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "error"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        }
                    case .success(let receivedDictionary):
                        if let errorMessage = receivedDictionary["error"] as? String {
                            DispatchQueue.main.async {
                                if let swapVC = delegate as? SwapViewController {
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
                            }
                            return
                        }
                        if receivedDictionary["expectedAmount"] is Int {
                            
                            print(receivedDictionary)
                            
                            let mutableDictionary:NSMutableDictionary = receivedDictionary.mutableCopy() as! NSMutableDictionary
                            mutableDictionary.setValue("Swap onchain to lightning \(idString)", forKey: "idstring")
                            mutableDictionary.setValue(Int(amountMsat)/1000, forKey: "useramount")
                            mutableDictionary.setValue(0, forKey: "direction") // 0 for onchain to lightning
                            mutableDictionary.setValue(privateKey, forKey: "privateKey")
                            
                            // Save swap details to file
                            if let swapID = receivedDictionary["id"] as? String {
                                self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: mutableDictionary)
                            }
                            
                            Task {
                                await self.checkOnchainFees(amountInSatoshis: Int(amountMsat)/1000, createdInvoice: invoice, receivedDictionary: mutableDictionary, delegate: delegate)
                            }
                        }
                    }
                    
                }
            }
            
        } catch let error as NodeError {
            let errorString = handleNodeError(error)
            DispatchQueue.main.async {
                if let swapVC = delegate as? SwapViewController {
                    swapVC.nextLabel.alpha = 1
                    swapVC.nextSpinner.stopAnimating()
                    swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "error"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                SentrySDK.capture(error: error)
            }
        } catch {
            DispatchQueue.main.async {
                if let swapVC = delegate as? SwapViewController {
                    swapVC.nextLabel.alpha = 1
                    swapVC.nextSpinner.stopAnimating()
                    swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                SentrySDK.capture(error: error)
            }
        }
    }
    
    static func checkOnchainFees(amountInSatoshis:Int, createdInvoice:LDKNode.Bolt11Invoice, receivedDictionary:NSDictionary, delegate:Any?) async {
        
        if let onchainAddress = receivedDictionary["address"] as? String, let expectedAmount = receivedDictionary["expectedAmount"] as? Int, let swapID = receivedDictionary["id"] as? String {
            
            let feesForLightningPayment = expectedAmount - amountInSatoshis
            
            // Check what the onchain fees will be for sending this onchain payment.
            if let actualBlockchain = LightningNodeService.shared.getBlockchain(), let actualWallet = LightningNodeService.shared.getWallet() {
                
                Task {
                    do {
                        // Get current fees for fast onchain transaction.
                        let high = try actualBlockchain.estimateFee(target: 1)
                        let feeHigh = Float(Int(high.asSatPerVb()*10))/10
                        
                        var network = BitcoinDevKit.Network.bitcoin
                        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                            network = BitcoinDevKit.Network.regtest
                        }
                        let address = try Address(address: onchainAddress, network: network)
                        let script = address.scriptPubkey()
                        let txBuilder = TxBuilder().addRecipient(script: script, amount: UInt64(expectedAmount))
                        let details = try txBuilder.finish(wallet: actualWallet)
                        let _ = try actualWallet.sign(psbt: details.psbt, signOptions: nil)
                        let tx = details.psbt.extractTx()
                        let size = tx.vsize()
                        
                        // Convert fees.
                        let feesForOnchainPayment = CGFloat(feeHigh*Float(size))
                        let totalFees:Int = feesForLightningPayment + Int(feesForOnchainPayment)
                        print("Fees lightning: \(feesForLightningPayment). Fees onchain: \(Int(feesForOnchainPayment)).")
                        
                        // Confirm fees with user.
                        DispatchQueue.main.async {
                            if let swapVC = delegate as? SwapViewController {
                                swapVC.confirmExpectedFees(feeHigh: feeHigh, onchainFees: Int(feesForOnchainPayment), lightningFees: feesForLightningPayment, swapDictionary: receivedDictionary, createdInvoice: createdInvoice)
                            }
                        }
                    } catch let error as BdkError {
                        
                        print("BDK error: \(error)")
                        DispatchQueue.main.async {
                            
                            if "\(error)".contains("InsufficientFunds") {
                                let condensedMessage = "\(error)".replacingOccurrences(of: "InsufficientFunds(message: \"", with: "").replacingOccurrences(of: "\")", with: "")
                                if let swapVC = delegate as? SwapViewController {
                                    swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). \(condensedMessage).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                }
                            } else {
                                if let swapVC = delegate as? SwapViewController {
                                    swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: \(error).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                }
                            }
                            
                            SentrySDK.capture(error: error)
                        }
                    } catch {
                        print("Error: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            if let swapVC = delegate as? SwapViewController {
                                swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: \(error.localizedDescription).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                            SentrySDK.capture(error: error)
                        }
                    }
                }
            }
        }
    }
    
    static func sendOnchainPayment(feeHigh:Float, onchainFees:Int, lightningFees:Int, receivedDictionary:NSDictionary, delegate:Any?) {
        
        if let onchainAddress = receivedDictionary["address"] as? String, let expectedAmount = receivedDictionary["expectedAmount"] as? Int, let swapID = receivedDictionary["id"] as? String {
            
            // Send onchain transaction.
            if let actualWallet = LightningNodeService.shared.getWallet(), let actualBlockchain = LightningNodeService.shared.getBlockchain() {
                
                Task {
                    do {
                        // TODO; remove this, this is just done so the swap will fail
                        // let expectedAmount = expectedAmount - 1000
                        var network = BitcoinDevKit.Network.bitcoin
                        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                            network = BitcoinDevKit.Network.regtest
                        }
                        let address = try Address(address: onchainAddress, network: network)
                        let script = address.scriptPubkey()
                        let txBuilder = TxBuilder().addRecipient(script: script, amount: UInt64(expectedAmount)).feeRate(satPerVbyte: feeHigh)
                        let details = try txBuilder.finish(wallet: actualWallet)
                        let _ = try actualWallet.sign(psbt: details.psbt, signOptions: nil)
                        let tx = details.psbt.extractTx()
                        try actualBlockchain.broadcast(transaction: tx)
                        let txid = details.psbt.txid()
                        print("Transaction ID: \(txid)")
                        
                        // We write the raw transaction to the JSON file of our swap as we need it to potentially claim a refund
                        SwapManager.updateSwapFileWithLockupTx(swapID: swapID, lockupTx: tx.serialize().map { String(format: "%02hhx", $0) }.joined())
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            print("Successful transaction.")
                            
                            let newTransaction = Transaction()
                            newTransaction.id = "\(txid)"
                            newTransaction.confirmations = 0
                            newTransaction.timestamp = Int(Date().timeIntervalSince1970)
                            newTransaction.height = 0
                            newTransaction.received = 0
                            newTransaction.fee = onchainFees
                            newTransaction.sent = expectedAmount + onchainFees
                            newTransaction.isLightning = false
                            newTransaction.isBittr = false
                            
                            
                            
                            if let idString = receivedDictionary["idstring"] as? String {
                                newTransaction.lnDescription = idString
                                CacheManager.storeInvoiceDescription(hash: txid, desc: idString)
                            }
                            
                            if let swapVC = delegate as? SwapViewController, let homeVC = swapVC.homeVC {
                                homeVC.setTransactions += [newTransaction]
                                homeVC.setTransactions.sort { transaction1, transaction2 in
                                    transaction1.timestamp > transaction2.timestamp
                                }
                                homeVC.homeTableView.reloadData()
                                
                                // For onchain-to-lightning swaps, the lightning transaction hasn't been received yet
                                // so we don't call performSwapMatching here. It will be handled when the lightning
                                // payment is received via HandlePaymentNotification.swift
                                
                                // Call didCompleteOnchainTransaction to set up WebSocket monitoring
                                swapVC.didCompleteOnchainTransaction(swapDictionary: receivedDictionary)
                            }
                        }
                    } catch {
                        // Log the exact error for debugging
                        print("Transaction error: \(error.localizedDescription)")
                        
                        // Report to Sentry for monitoring
                        SentrySDK.capture(error: error)
                        
                        DispatchQueue.main.async {
                            if let swapVC = delegate as? SwapViewController {
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
        }
    }
    
    static func checkSwapStatus(_ swapID:String, completion: @escaping (String?) -> Void) {
        
        /* {
         "status":"transaction.mempool",
         "zeroConfRejected":true,
         "transaction":{
         "id":"2edfaeb630a8de4870c33046483c22ef2dd14f87c9b45e242924138ad0bb50cc",
         "hex":"010000000001010339c27932ed3437e12c2021e1b219aca14ee5af696ae4b2d93b9d406b05f0630000000000feffffff02f1f42b010000000016001432abff3cfd36f4f83fbe2c50534b728254153acab0c40000000000002251204f7ec486d75dfba06cdbb219f94fb29e15767d583a8f9e1af4d78b98bd48b15d024730440220290e6d4bf4c14c9b2a60856e50abb5715fb1646b51f1737dd1ed7a18d343c1c2022060408caa7ea17d3dd1dcd22be3334a3ec65023f841bca48d11c50f4c3cd0a9590121026479e19c5d9c4e162442f802221f1355fc3568f9cca5491c2c621542c209cd43bf000000"}
         } */
        
        // Create GET API call.
        var apiURL = "https://api.boltz.exchange/v2"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            apiURL = "https://api.regtest.getbittr.com/v2"
        }
    
        Task {
            await CallsManager.makeApiCall(url: "\(apiURL)/swap/\(swapID)", parameters: nil, getOrPost: "GET") { result in
                
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                case .success(let receivedDictionary):
                    if let receivedStatus = receivedDictionary["status"] as? String {
                        completion(receivedStatus)
                    }
                }
                
            }
        }
    }
    
    static func lightningToOnchain(amountSat:Int, delegate:Any?) async {
        
        // Call /v2/swap/reverse to receive the Lightning invoice we should pay.
        let randomPreimage = self.generateRandomPreimage()
        let randomPreimageHash = self.sha256Hash(of: randomPreimage)
        let randomPreimageHashHex = randomPreimageHash.hexEncodedString()

        let (privateKey, publicKey) = try! LightningNodeService.shared.getPrivatePublicKeyForPath(path: "m/84'/0'/0'/0/0")

        let wallet = LightningNodeService.shared.getWallet()
        let destinationAddress = try! wallet?.getAddress(addressIndex: .lastUnused).address.asString()
        
        print("randomPreimage: \(randomPreimage.hexEncodedString())")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let idString = dateFormatter.string(from: Date())
        
        // Get device token for webhook URL
        let deviceToken = CacheManager.getRegistrationToken() ?? ""
        
        // Check if we have a registration token (notifications enabled)
        if deviceToken.isEmpty {
            DispatchQueue.main.async {
                if let swapVC = delegate as? SwapViewController {
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
            }
            return
        }
        
        let webhookURL = "https://model-arachnid-viable.ngrok-free.app/webhook/boltz/\(deviceToken)"
        
        let parameters: [String: Any] = [
            "from": "BTC",
            "to": "BTC",
            "claimPublicKey": publicKey,
            "preimageHash": randomPreimageHashHex,
            "onchainAmount": amountSat,
            "webhook": [
                "url": webhookURL,
                "hashSwapId": false,
                "status": ["transaction.mempool", "transaction.confirmed", "invoice.settled", "swap.expired", "transaction.failed"]
            ]
        ]
        
        var apiURL = "https://api.boltz.exchange/v2"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            apiURL = "https://api.regtest.getbittr.com/v2"
        }
        
        Task {
            await CallsManager.makeApiCall(url: "\(apiURL)/swap/reverse", parameters: parameters, getOrPost: "POST") { result in
                
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        if let swapVC = delegate as? SwapViewController {
                            swapVC.nextLabel.alpha = 1
                            swapVC.nextSpinner.stopAnimating()
                            swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "swapfunds2"), message: "\(Language.getWord(withID: "error")): \(error)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    }
                case .success(let receivedDictionary):
                    if let errorMessage = receivedDictionary["error"] as? String {
                        DispatchQueue.main.async {
                            if let swapVC = delegate as? SwapViewController {
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
                        }
                        return
                    }
                    let mutableSwapDictionary:NSMutableDictionary = receivedDictionary.mutableCopy() as! NSMutableDictionary
                    mutableSwapDictionary.setValue(amountSat, forKey: "useramount")
                    mutableSwapDictionary.setValue(privateKey, forKey: "privateKey")
                    mutableSwapDictionary.setValue(randomPreimage.hexEncodedString(), forKey: "preimage")
                    mutableSwapDictionary.setValue(destinationAddress, forKey: "destinationAddress")
                    mutableSwapDictionary.setValue("Swap lightning to onchain \(idString)", forKey: "idstring")
                    
                    // Save swap details to file
                    if let swapID = receivedDictionary["id"] as? String {
                        self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: mutableSwapDictionary)
                    }
                    
                    self.checkReverseSwapFees(swapDictionary: mutableSwapDictionary, delegate: delegate)
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
        do {
            // Load existing swap details
            guard let existingSwapDetails = loadSwapDetailsFromFile(swapID: swapID) else {
                print("Could not load existing swap details for ID: \(swapID)")
                return
            }
            
            // Create a mutable copy and add the lockup transaction
            let updatedSwapDetails = existingSwapDetails.mutableCopy() as! NSMutableDictionary
            updatedSwapDetails.setValue(lockupTx, forKey: "lockupTx")
            
            // Save the updated swap details back to file
            saveSwapDetailsToFile(swapID: swapID, swapDictionary: updatedSwapDetails)
            
            print("Updated swap file with lockup transaction for ID: \(swapID)")
        } catch {
            print("Error updating swap file with lockup transaction: \(error)")
        }
    }
    
    static func updateSwapFileWithFees(swapID: String, totalFees: Int, userAmount: Int, direction: Int) {
        do {
            // Load existing swap details
            guard let existingSwapDetails = loadSwapDetailsFromFile(swapID: swapID) else {
                print("Could not load existing swap details for ID: \(swapID)")
                return
            }
            
            // Create a mutable copy and add the fees
            let updatedSwapDetails = existingSwapDetails.mutableCopy() as! NSMutableDictionary
            updatedSwapDetails.setValue(totalFees, forKey: "totalfees")
            updatedSwapDetails.setValue(userAmount, forKey: "useramount")
            updatedSwapDetails.setValue(direction, forKey: "direction")
            
            // Save the updated swap details back to file
            saveSwapDetailsToFile(swapID: swapID, swapDictionary: updatedSwapDetails)
            
            print("Updated swap file with fees for ID: \(swapID)")
        } catch {
            print("Error updating swap file with fees: \(error)")
        }
    }
    
    static func addOnchainTransactionToUI(swapID: String, transactionId: String, delegate: Any?) {
        // Load swap details to get the description and user amount
        guard let swapDetails = loadSwapDetailsFromFile(swapID: swapID) else {
            print("Could not load swap details for ID: \(swapID)")
            return
        }
        
        // Create onchain transaction
        let newTransaction = Transaction()
        newTransaction.id = transactionId
        newTransaction.confirmations = 1
        newTransaction.timestamp = Int(Date().timeIntervalSince1970)
        newTransaction.height = 0 // Will be updated when blockchain syncs
        newTransaction.received = swapDetails["useramount"] as? Int ?? 0
        newTransaction.fee = 0
        newTransaction.sent = 0
        newTransaction.isLightning = false
        newTransaction.isBittr = false
        newTransaction.isSwap = true
        newTransaction.swapDirection = 1 // Lightning to onchain
        newTransaction.onchainID = transactionId // Set onchain ID for swap matching
        newTransaction.boltzSwapId = swapID
        
        // Set swap description
        if let idString = swapDetails["idstring"] as? String {
            newTransaction.lnDescription = idString
            CacheManager.storeInvoiceDescription(hash: transactionId, desc: idString)
        }
        
        // Add to home view controller
        if let swapVC = delegate as? SwapViewController, let homeVC = swapVC.homeVC {
            homeVC.setTransactions += [newTransaction]
            homeVC.setTransactions.sort { transaction1, transaction2 in
                transaction1.timestamp > transaction2.timestamp
            }
            homeVC.homeTableView.reloadData()
            
            // Trigger manual swap matching to combine lightning and onchain transactions
            // For lightning-to-onchain swaps, both transactions should be present now
            homeVC.performSwapMatching()
        }
        
        print("Added onchain transaction to UI: \(transactionId) with amount: \(newTransaction.received)")
    }
    
    static func checkReverseSwapFees(swapDictionary:NSDictionary, delegate:Any?) {
        
        if let receivedInvoice = swapDictionary["invoice"] as? String, let userAmount = swapDictionary["useramount"] as? Int, let delegate = delegate as? SwapViewController {
            // Check requested invoice amount.
            if delegate.checkInternetConnection() {
                    
                if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: receivedInvoice).getValue() {
                    // Lightning invoice.
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        
                        // Calculate onchain fees.
                        let onchainFees:Int = invoiceAmount - userAmount
                        
                        // Calculate maximum total routing fees.
                        let invoicePaymentResult = Bindings.paymentParametersFromInvoice(invoice: parsedInvoice)
                        let (tryPaymentHash, tryRecipientOnion, tryRouteParams) = invoicePaymentResult.getValue()!
                        let maximumRoutingFeesMsat:Int = Int(tryRouteParams.getMaxTotalRoutingFeeMsat() ?? 0)
                        let lightningFees:Int = maximumRoutingFeesMsat/1000
                        
                        // Confirm fees with user.
                        DispatchQueue.main.async {
                            delegate.confirmExpectedFees(feeHigh: 0, onchainFees: onchainFees, lightningFees: lightningFees, swapDictionary: swapDictionary, createdInvoice: receivedInvoice)
                        }
                    }
                }
            }
        } else {
            if let swapVC = delegate as? SwapViewController {
                swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "error"), message: Language.getWord(withID: "swaperror1"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        }
    }
    
    static func sendLightningPayment(swapDictionary:NSDictionary, delegate:Any?) {
        
        // Fees confirmed by user, pay Boltz invoice.
        
        if let delegate = delegate as? SwapViewController, let invoice = swapDictionary["invoice"] as? String, let userAmount = swapDictionary["useramount"] as? Int, let totalFees = swapDictionary["totalfees"] as? Int {
            
            Task {
                do {
                    let paymentHash = try await LightningNodeService.shared.sendPayment(invoice: invoice)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                            
                            if thisPayment.status != .failed {
                                // Success payment
                                delegate.confirmStatusLabel.text = Language.getWord(withID: "swapstatusawaitingtransaction")
                                
                                // Create lightning transaction with swap details
                                let newTransaction = Transaction()
                                newTransaction.id = thisPayment.id
                                newTransaction.sent = Int(thisPayment.amountMsat ?? 0)/1000
                                newTransaction.received = 0
                                newTransaction.isLightning = true
                                newTransaction.isSwap = true
                                newTransaction.swapDirection = 1 // Lightning to onchain
                                newTransaction.lightningID = thisPayment.id // Set lightning ID for swap matching
                                newTransaction.timestamp = Int(Date().timeIntervalSince1970)
                                newTransaction.confirmations = 0
                                newTransaction.height = 0
                                newTransaction.isBittr = false
                                
                                // Set swap description
                                if let idString = swapDictionary["idstring"] as? String {
                                    newTransaction.lnDescription = idString
                                    CacheManager.storeInvoiceDescription(hash: thisPayment.id, desc: idString)
                                }
                                
                                // Calculate fees
                                if Int(thisPayment.amountMsat ?? 0)/1000 > userAmount {
                                    let feesIncurred = (Int(thisPayment.amountMsat ?? 0)/1000) - userAmount
                                    CacheManager.storePaymentFees(hash: thisPayment.id, fees: feesIncurred)
                                    newTransaction.fee = feesIncurred
                                } else {
                                    newTransaction.fee = 0
                                }
                                
                                // Add to home view controller
                                if let homeVC = delegate.homeVC {
                                    homeVC.setTransactions += [newTransaction]
                                    homeVC.setTransactions.sort { transaction1, transaction2 in
                                        transaction1.timestamp > transaction2.timestamp
                                    }
                                    homeVC.homeTableView.reloadData()
                                }
                                
                                if let swapID = swapDictionary["id"] as? String {
                                    newTransaction.boltzSwapId = swapID
                                    delegate.webSocketManager = WebSocketManager()
                                    delegate.webSocketManager!.delegate = delegate
                                    delegate.webSocketManager!.swapID = swapID
                                    delegate.webSocketManager!.connect()
                                }
                            } else {
                                // Payment came back failed.
                                delegate.confirmStatusLabel.text = Language.getWord(withID: "swapstatusfailedtopay")
                                delegate.showAlert(presentingController: delegate, title: Language.getWord(withID: "paymentfailed"), message: Language.getWord(withID: "paymentfailed2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        } else {
                            // Success alert
                            delegate.confirmStatusLabel.text = Language.getWord(withID: "swapstatusawaitingtransaction")
                            
                            // Create lightning transaction with swap details
                            let newTransaction = Transaction()
                            newTransaction.id = paymentHash
                            newTransaction.sent = userAmount
                            newTransaction.received = 0
                            newTransaction.isLightning = true
                            newTransaction.isSwap = true
                            newTransaction.swapDirection = 1 // Lightning to onchain
                            newTransaction.lightningID = paymentHash // Set lightning ID for swap matching
                            newTransaction.timestamp = Int(Date().timeIntervalSince1970)
                            newTransaction.confirmations = 0
                            newTransaction.height = 0
                            newTransaction.isBittr = false
                            newTransaction.fee = 0
                            
                            // Set swap description
                            if let idString = swapDictionary["idstring"] as? String {
                                newTransaction.lnDescription = idString
                                CacheManager.storeInvoiceDescription(hash: paymentHash, desc: idString)
                            }
                            
                            // Add to home view controller
                            if let homeVC = delegate.homeVC {
                                homeVC.setTransactions += [newTransaction]
                                homeVC.setTransactions.sort { transaction1, transaction2 in
                                    transaction1.timestamp > transaction2.timestamp
                                }
                                homeVC.homeTableView.reloadData()
                            }
                            
                            if let swapID = swapDictionary["id"] as? String {
                                newTransaction.boltzSwapId = swapID
                                delegate.webSocketManager = WebSocketManager()
                                delegate.webSocketManager!.delegate = delegate
                                delegate.webSocketManager!.swapID = swapID
                                delegate.webSocketManager!.connect()
                            }
                        }
                    }
                } catch let error as NodeError {
                    let errorString = handleNodeError(error)
                    DispatchQueue.main.async {
                        // Error alert for NodeError
                        delegate.showAlert(presentingController: delegate, title: Language.getWord(withID: "paymentfailed"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                        SentrySDK.capture(error: error)
                    }
                } catch {
                    DispatchQueue.main.async {
                        // General error alert
                        delegate.showAlert(presentingController: delegate, title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                        SentrySDK.capture(error: error)
                    }
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

