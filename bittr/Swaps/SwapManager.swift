//
//  SwapManager.swift
//  bittr
//
//  Created by Tom Melters on 24/01/2025.
//

import UIKit
import LDKNode
import Sentry
import secp256k1
import BitcoinDevKit

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
            
            // Create an invoice for the amount we want to move.
            let invoice = try await LightningNodeService.shared.receivePayment(
                amountMsat: amountMsat,
                description: "Swap onchain to lightning",
                expirySecs: 3600
            )
            
            // Store invoice in cache.
            DispatchQueue.main.async {
                if let swapVC = delegate as? SwapViewController {
                    if let invoiceHash = swapVC.getInvoiceHash(invoiceString: invoice) {
                        let newTimestamp = Int(Date().timeIntervalSince1970)
                        CacheManager.storeInvoiceTimestamp(hash: invoiceHash, timestamp: newTimestamp)
                        CacheManager.storeInvoiceDescription(hash: invoiceHash, desc: "Swap onchain to lightning")
                        print("Did cache invoice data.")
                    }
                }
            }
            
            // Get public key for potential refund.
            //let xpub = LightningNodeService.shared.getXpub()
            //let xpubData = Data(xpub.utf8)
            //let xpubHex = xpub.unicodeScalars.filter { $0.isASCII }.map { String(format: "%X", $0.value) }.joined()
            
            // Create POST API call.
            let parameters: [String: Any] = [
                "from": "BTC",
                "to": "BTC",
                "invoice": invoice,
                "refundPublicKey": "034ea6d0ca3bef8ad17d716c9cea306596e8088b5c03abd1804e9d6c574d737c88" /* Tom "03da4bdf00584f344ffcaf99f954b5d0ead6124a7269ec404f0ee8ceb12866c315"*/
            ]
            // Private key Tom "cQWo7AVPFAR8S33hNNEXqNhDYgQ5U7ZTxEyEnuWZ3tuxZLqHyU1J"
            var apiURL = "https://api.boltz.exchange/v2"
            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                apiURL = "https://api.regtest.getbittr.com/v2"
            }
            let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
            var request = URLRequest(url: URL(string: "\(apiURL)/swap/submarine".replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!,timeoutInterval: Double.infinity)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = "POST"
            request.httpBody = postData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, dataError in
                if let httpResponse = response as? HTTPURLResponse {
                    print("Status code: \(httpResponse.statusCode)")
                    print("Headers: \(httpResponse.allHeaderFields)")
                }
                
                if let error = dataError {
                    print("Error: \(error.localizedDescription)")
                }
                
                guard let data = data else {
                    print("No data received. Error: \(dataError ?? "no error"). Response: \(String(describing: response)).")
                    DispatchQueue.main.async {
                        if let swapVC = delegate as? SwapViewController {
                            swapVC.showAlert(title: Language.getWord(withID: "error"), message: "\(Language.getWord(withID: "nodatareceived")). \(Language.getWord(withID: "error")): " + (dataError?.localizedDescription ?? "No error"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    }
                    return
                }
                
                // Response has been received.
                print("Data received: \(String(data:data, encoding:.utf8)!)")
                // Example error {"error":"10000 is less than minimal of 25000"}
                // Example success {"bip21":"bitcoin:bc1pn47a2c9ymet8qxwpmlcxnyrs4jcewsdj09t464ag6v2d34uppkdq7ef20s?amount=0.00025478&label=Send%20to%20BTC%20lightning","acceptZeroConf":false,"expectedAmount":25478,"id":"PJ3hNAALsNqn","address":"bc1pn47a2c9ymet8qxwpmlcxnyrs4jcewsdj09t464ag6v2d34uppkdq7ef20s","swapTree":{"claimLeaf":{"version":192,"output":"a9147434464e5afb4407a67bb9ecf6b076dd43d1931c88209f3ec13701b1ebebbdbb6f00530ba7357fc63234353088fa4f6ad973c947a8deac"},"refundLeaf":{"version":192,"output":"204ea6d0ca3bef8ad17d716c9cea306596e8088b5c03abd1804e9d6c574d737c88ad0303760db1"}},"claimPublicKey":"039f3ec13701b1ebebbdbb6f00530ba7357fc63234353088fa4f6ad973c947a8de","timeoutBlockHeight":882179}
                
                //{"bip21":"bitcoin:bcrt1p2tkzczfw4y5xqlxngqgt7rx4lv4wwva0k968u0nue2zw03th6zlsvte5zd?amount=0.00055357&label=Send%20to%20BTC%20lightning","acceptZeroConf":false,"expectedAmount":55357,"id":"zRX14hgFtYLY","address":"bcrt1p2tkzczfw4y5xqlxngqgt7rx4lv4wwva0k968u0nue2zw03th6zlsvte5zd","swapTree":{"claimLeaf":{"version":192,"output":"a914df3d48b0e6848a21773b9f08ba0e5fee449853cc882036ab60cdac08b58c176298582076c56a19388f209ca54c5aa6307ef14cdefc93ac"},"refundLeaf":{"version":192,"output":"20da4bdf00584f344ffcaf99f954b5d0ead6124a7269ec404f0ee8ceb12866c315ad021d02b1"}},"claimPublicKey":"0336ab60cdac08b58c176298582076c56a19388f209ca54c5aa6307ef14cdefc93","timeoutBlockHeight":541}
                
                var dataDictionary:NSDictionary?
                if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                    do {
                        dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                        if let actualDataDict = dataDictionary {
                            if let receivedError = actualDataDict["error"] as? String {
                                // Error
                                DispatchQueue.main.async {
                                    if let swapVC = delegate as? SwapViewController {
                                        swapVC.showAlert(title: Language.getWord(withID: "swapfunds2"), message: "\(Language.getWord(withID: "error")): \(receivedError)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                    }
                                }
                            } else {
                                // Successful swap creation.
                                if let expectedAmount = actualDataDict["expectedAmount"] as? Int {
                                    Task {
                                        await self.checkOnchainFees(amountInSatoshis: Int(amountMsat)/1000, createdInvoice: invoice, receivedDictionary: actualDataDict, delegate: delegate)
                                    }
                                    /*let expectedFees:Int = expectedAmount - Int(amountMsat)/1000
                                    DispatchQueue.main.async {
                                        if let swapVC = delegate as? SwapViewController {
                                            swapVC.confirmExpectedFees(expectedFees: expectedFees, swapDictionary: actualDataDict, createdInvoice: invoice)
                                        }
                                    }*/
                                }
                            }
                        }
                    } catch {
                        print("Error 111: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            if let swapVC = delegate as? SwapViewController {
                                swapVC.showAlert(title: Language.getWord(withID: "error"), message: Language.getWord(withID: "nodatareceived") + " 2", buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        }
                    }
                }
            }
            task.resume()
            
        } catch let error as NodeError {
            let errorString = handleNodeError(error)
            DispatchQueue.main.async {
                if let swapVC = delegate as? SwapViewController {
                    swapVC.showAlert(title: Language.getWord(withID: "error"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                SentrySDK.capture(error: error)
            }
        } catch {
            DispatchQueue.main.async {
                if let swapVC = delegate as? SwapViewController {
                    swapVC.showAlert(title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                SentrySDK.capture(error: error)
            }
        }
    }
    
    static func checkOnchainFees(amountInSatoshis:Int, createdInvoice:Bolt11Invoice, receivedDictionary:NSDictionary, delegate:Any?) async {
        
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
                                    swapVC.showAlert(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). \(condensedMessage).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                }
                            } else {
                                if let swapVC = delegate as? SwapViewController {
                                    swapVC.showAlert(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: \(error).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                }
                            }
                            
                            SentrySDK.capture(error: error)
                        }
                    } catch {
                        print("Error: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            if let swapVC = delegate as? SwapViewController {
                                swapVC.showAlert(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: \(error.localizedDescription).", buttons: [Language.getWord(withID: "okay")], actions: nil)
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
                            
                            if let swapVC = delegate as? SwapViewController, let homeVC = swapVC.homeVC {
                                homeVC.setTransactions += [newTransaction]
                                homeVC.setTransactions.sort { transaction1, transaction2 in
                                    transaction1.timestamp > transaction2.timestamp
                                }
                                homeVC.homeTableView.reloadData()
                                
                                swapVC.didCompleteOnchainTransaction(swapDictionary: receivedDictionary)
                            }
                        }
                    } catch {
                        print("Transaction error: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            if let swapVC = delegate as? SwapViewController {
                                swapVC.showAlert(title: Language.getWord(withID: "error"), message: "\(Language.getWord(withID: "transactionerror")): \(error.localizedDescription).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        }
                    }
                }
            }
            
            // Check swapID every 5 seconds against API /swap/swapID to get the status of the swap.
            /*self.checkSwapStatus(swapID) { swapStatus in
                if swapStatus == "transaction.claim.pending" {
                    // When status is transaction.claim.pending, get preimage details from API /swap/submarine/swapID/claim to verify that the Lightning payment has been made.
                    self.checkPreimageDetails(swapID: swapID, delegate: delegate)
                    
                } else if swapStatus == "invoice.failedToPay" || swapStatus == "transaction.lockupFailed" {
                    
                    // Boltz's payment has failed and we want to get a refund our onchain transaction. Get a partial signature through /swap/submarine/swapID/refund. Or a scriptpath refund can be done after the locktime of the swap expires.
                }
            }*/
        }
    }
    
    static func checkSwapStatus(_ swapID:String, completion: @escaping (String?) -> Void) {
        
        /* {
        "status": "transaction.mempool",
        "zeroConfRejected": true,
        "transaction": {
            "id": "522a30e75acd1a40779a15dabe1bbd2f72274d14d0a0d534427328f4d1f0c1d8",
            "hex": "01000000000102f33880892fd099b704c81d8685201499c955204f7badfbcb59daf45c6a59091e0000000000feffffffe34d83119f21b3c155c1105ff0586d95d02b3397e08e7f46d59ad413cde4592c0000000000feffffff027883000000000000160014a22e11bbcc8df14728a05ea773afa1ded4a218dc3dd800000000000022512052ec2c092ea928607cd34010bf0cd5fb2ae733afb1747e3e7cca84e7c577d0bf0247304402202b5965fc00b6f40db1822144ad7041b052573dcc2165106d8672f8de4746461102203f15f2221fae1ba18f3d49af7726d2cdf98765e9d790706ece84b46f1a37dbc7012102b83d4808931d1a36772e286aa7b2743a9c28035dd071d0907a11262f1ccf297a0247304402206b066dcd1e413a1b0e6a7972175fd0e675a751bef2aa23bdd30367ca65b2aa8e022029e2af71ec7373f3d13197492e1f333d3481514aa4ac150a3a7c8235ca7231c60121033d0cbf5876cd5b12871d351e426b9971cd144508067f6860c9772aded274a665fd000000"
        }
    }*/
        
        //do {
            // Create GET API call.
            /*let parameters: [String: Any] = [
                "id": swapID
            ]*/
            var apiURL = "https://api.boltz.exchange/v2"
            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                apiURL = "https://api.regtest.getbittr.com/v2"
            }
            //let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
            var request = URLRequest(url: URL(string: "\(apiURL)/swap/\(swapID)".replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!,timeoutInterval: Double.infinity)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = "GET"
            //request.httpBody = postData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, dataError in
                if let httpResponse = response as? HTTPURLResponse {
                    print("Status code: \(httpResponse.statusCode)")
                    print("Headers: \(httpResponse.allHeaderFields)")
                }
                
                if let error = dataError {
                    print("335 Error: \(error.localizedDescription)")
                }
                
                guard let data = data else {
                    print("339 No data received. Error: \(dataError ?? "no error"). Response: \(String(describing: response)).")
                    completion(nil)
                    return
                }
                
                // Response has been received.
                print("Data received: \(String(data:data, encoding:.utf8)!)")
                // Example error {"error":"10000 is less than minimal of 25000"}
                // Example success
                
                var dataDictionary:NSDictionary?
                if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                    do {
                        dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                        if let actualDataDict = dataDictionary {
                            if let receivedError = actualDataDict["error"] as? String {
                                // Error
                                completion(nil)
                            } else {
                                // Successful swap creation.
                                if let receivedStatus = actualDataDict["status"] as? String {
                                    completion(receivedStatus)
                                }
                            }
                        }
                    } catch {
                        print("Error 360: \(error.localizedDescription)")
                        completion(nil)
                    }
                }
            }
            task.resume()
            
        /*} catch let error as NodeError {
            let errorString = handleNodeError(error)
            print("241: " + errorString.detail)
            completion(nil)
        } catch {
            print("243: " + error.localizedDescription)
            completion(nil)
        }*/
    }
    
    static func checkPreimageDetails(swapID:String, delegate:Any?) {
        // Get preimage details from API /swap/submarine/swapID/claim to verify that the Lightning payment has been made.
        do {
            // Create GET API call.
            let parameters: [String: Any] = [
                "id": swapID
            ]
            var apiURL = "https://api.boltz.exchange/v2"
            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                apiURL = "https://api.regtest.getbittr.com/v2"
            }
            let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
            var request = URLRequest(url: URL(string: "\(apiURL)/swap/submarine/\(swapID)/claim".replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!,timeoutInterval: Double.infinity)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = "GET"
            request.httpBody = postData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, dataError in
                if let httpResponse = response as? HTTPURLResponse {
                    print("Status code: \(httpResponse.statusCode)")
                    print("Headers: \(httpResponse.allHeaderFields)")
                }
                
                if let error = dataError {
                    print("Error: \(error.localizedDescription)")
                }
                
                guard let data = data else {
                    print("No data received. Error: \(dataError ?? "no error"). Response: \(String(describing: response)).")
                    return
                }
                
                // Response has been received.
                print("411 Data received: \(String(data:data, encoding:.utf8)!)")
                // Example error {"error":"10000 is less than minimal of 25000"}
                // Example success
                
                var dataDictionary:NSDictionary?
                if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                    do {
                        dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                        if let actualDataDict = dataDictionary {
                            if let receivedError = actualDataDict["error"] as? String {
                                // Error
                            } else {
                                // Successful swap creation.
                                if let receivedPreimage = actualDataDict["preimage"] as? String, let receivedPublicNonce = actualDataDict["pubNonce"] as? String, let receivedPublicKey = actualDataDict["publicKey"] as? String, let receivedTransactionHash = actualDataDict["transactionHash"] as? String {
                                    
                                    // Verify that the Lightning payment has been made.
                                    if let swapVC = delegate as? SwapViewController {
                                        if let pendingInvoice = swapVC.pendingInvoice {
                                            if let pendingInvoiceHash = swapVC.getInvoiceHash(invoiceString: pendingInvoice) {
                                                if let pendingPreimage = LightningNodeService.shared.getPaymentDetails(paymentHash: pendingInvoiceHash)?.kind.preimageAsString {
                                                    
                                                    if pendingPreimage == receivedPreimage {
                                                        // Correct preimage has been verified.
                                                        
                                                        // Send claim details to API /swap/submarine/swapID/claim so that Boltz can claim the onchain funds. If you don't send these, Boltz will eventually broadcast a scriptpath claim instead of a keypath claim.
                                                        
                                                        
                                                    } else {
                                                        // Preimage incorrect.
                                                    }
                                                } else {
                                                    // Couldn't fetch invoice preimage.
                                                }
                                            } else {
                                                // Couldn't get hash for pending invoice.
                                            }
                                        } else {
                                            // No pending invoice has been saved.
                                        }
                                    } else {
                                        // Swap VC not connected.
                                    }
                                } else {
                                    // Did not receive expected data.
                                }
                            }
                        }
                    } catch {
                        print("Error 293: \(error.localizedDescription)")
                    }
                }
            }
            task.resume()
            
        } catch let error as NodeError {
            let errorString = handleNodeError(error)
            print("301: " + errorString.detail)
        } catch {
            print("303: " + error.localizedDescription)
        }
    }
    
    struct Base58Check {
        static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

        static func decode(_ input: String) -> Data? {
            var value = [UInt8](repeating: 0, count: 1)

            for char in input {
                guard let index = alphabet.firstIndex(of: char)?.utf16Offset(in: alphabet) else {
                    return nil
                }

                var carry = index
                for i in (0..<value.count).reversed() {
                    carry += Int(value[i]) * 58
                    value[i] = UInt8(carry & 0xFF)
                    carry >>= 8
                }

                while carry > 0 {
                    value.insert(UInt8(carry & 0xFF), at: 0)
                    carry >>= 8
                }
            }

            let leadingZeros = input.prefix { $0 == "1" }.count
            value.insert(contentsOf: Array(repeating: 0, count: leadingZeros), at: 0)

            guard value.count >= 4 else { return nil }
            let checksum = value.suffix(4)
            let payload = value.dropLast(4)

            let hash = Data(SHA256.hash(data: SHA256.hash(data: Data(payload)).withUnsafeBytes { Data($0) }).withUnsafeBytes { Data($0) })
            
            guard hash.prefix(4).map({ $0 }) == Array(checksum) else { return nil }

            return Data(payload)
        }
    }

    static func wifToPrivateKey(_ wif: String) -> Data? {
        guard let decoded = Base58Check.decode(wif) else {
            print("Invalid WIF format")
            return nil
        }

        guard decoded.count == 33 || decoded.count == 34 else {
            print("❌ Invalid decoded length: \(decoded.count) bytes")
            return nil
        }

        let privateKey = decoded.dropFirst().dropLast(decoded.count == 34 ? 1 : 0) // Remove prefix & optional compression flag

        guard privateKey.count == 32 else {
            print("❌ Private key is not 32 bytes, got \(privateKey.count) bytes")
            return nil
        }

        return privateKey
    }
    
    static func generatePublicNonce(from privateKeyData:Data) -> Data? {
        
        guard let context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY)) else {
            print("Failed to create secp256k1 context")
            return nil
        }
        
        defer {
            secp256k1_context_destroy(context)
        }
        
        var secretNonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        
        var pubNonce = secp256k1_pubkey()
        let result = secretNonce.withUnsafeBytes { secretNoncePtr in
            secp256k1_ec_pubkey_create(
                context,
                &pubNonce,
                secretNoncePtr.bindMemory(to: UInt8.self).baseAddress!
            )
        }
        
        guard result == 1 else {
            print("Failed to generate public nonce")
            return nil
        }
        
        var serializedPubNonce = Data(repeating: 0, count: 33)
        var outputLength = 33
        let serializationResult = serializedPubNonce.withUnsafeMutableBytes { outputPtr in
            secp256k1_ec_pubkey_serialize(
                context,
                outputPtr.bindMemory(to: UInt8.self).baseAddress!,
                &outputLength,
                &pubNonce,
                UInt32(SECP256K1_EC_COMPRESSED)
            )
        }
        
        guard serializationResult == 1 else {
            print("Failed to serialize public nonce")
            return nil
        }
        
        return serializedPubNonce
    }
    
    static func claimRefund() {
        
        if let privateKey = self.wifToPrivateKey("cQWo7AVPFAR8S33hNNEXqNhDYgQ5U7ZTxEyEnuWZ3tuxZLqHyU1J") {
            print("✅ Private key extracted:", privateKey.map { String(format: "%02x", $0) }.joined())
            
            if let pubNonce = self.generatePublicNonce(from: privateKey) {
                print("Generated pubNonce:", pubNonce.map { String(format: "%02x", $0) }.joined())
                
            }
        } else {
            print("❌ Failed to extract private key")
        }
    }
    
    
    static func lightningToOnchain(amountSat:Int, delegate:Any?) async {
        
        // Call /v2/swap/reverse to receive the Lightning invoice we should pay.
        // Pay the invoice.
        // Claim the onchain transaction.
        // Call /chain/BTC/transaction to broadcast the onchain transaction with Boltz.
        
        
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

