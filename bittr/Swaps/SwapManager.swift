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
import secp256k1_bindings
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
                "refundPublicKey": "0304cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24"
            ]
            // 15 March private key KxhGnKyk68TyWQphZ7aPYJ6pspeH3oEadRKenBQaK7sgCo8oZUur

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
                // Example success {"bip21":"bitcoin:bcrt1pfalvfpkhtha6qmxmkgvljnajnc2hvl2c828euxh5679e302gk9wsh3e9af?amount=0.00050352&label=Send%20to%20BTC%20lightning","acceptZeroConf":false,"expectedAmount":50352,"id":"ChTExx2srRLT","address":"bcrt1pfalvfpkhtha6qmxmkgvljnajnc2hvl2c828euxh5679e302gk9wsh3e9af","swapTree":{"claimLeaf":{"version":192,"output":"a914ed96f252263cd8cc0a616602875f76bfb0c70fcd8820611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61fac"},"refundLeaf":{"version":192,"output":"2004cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24ad02df01b1"}},"claimPublicKey":"03611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61f","timeoutBlockHeight":479}
                
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
         "status":"transaction.mempool",
         "zeroConfRejected":true,
         "transaction":{
         "id":"2edfaeb630a8de4870c33046483c22ef2dd14f87c9b45e242924138ad0bb50cc",
         "hex":"010000000001010339c27932ed3437e12c2021e1b219aca14ee5af696ae4b2d93b9d406b05f0630000000000feffffff02f1f42b010000000016001432abff3cfd36f4f83fbe2c50534b728254153acab0c40000000000002251204f7ec486d75dfba06cdbb219f94fb29e15767d583a8f9e1af4d78b98bd48b15d024730440220290e6d4bf4c14c9b2a60856e50abb5715fb1646b51f1737dd1ed7a18d343c1c2022060408caa7ea17d3dd1dcd22be3334a3ec65023f841bca48d11c50f4c3cd0a9590121026479e19c5d9c4e162442f802221f1355fc3568f9cca5491c2c621542c209cd43bf000000"}
         } */
        
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
        
        print("Claim refund triggered.")
        
        do {
            /*let boltzPublicKey = try! secp256k1.Signing.PublicKey(pemRepresentation: "03611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61f")
            let myPrivateKey = try! secp256k1.Signing.PrivateKey(pemRepresentation: "KxhGnKyk68TyWQphZ7aPYJ6pspeH3oEadRKenBQaK7sgCo8oZUur").publicKey
            let combinedPublicKey = try! boltzPublicKey.combine([myPrivateKey], format: .uncompressed)*/
            
            /*let combinedKeyString = """
            -----BEGIN EC PRIVATE KEY-----
            03611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61f0304cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24
            -----END EC PRIVATE KEY-----
            """*/
            
            /*let publicKey = try P256.Signing.PublicKey(rawRepresentation: "03611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61f0304cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24".bytes).pemRepresentation
            print("Did generate publicKey")*/
            
            let combinedKey = try secp256k1.Signing.PrivateKey(dataRepresentation: "03611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61f0304cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24".bytes)
            print("Did generate combinedKey")
            let tweak = try "2004cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24ad02df01b1".bytes
            print("Did generate tweak")
            let tweakedCombinedKey = try combinedKey.add(tweak)
            print("Did generate tweakedCombinedKey")
            
            let schnorrKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: tweakedCombinedKey.dataRepresentation)
            print("Did generate schnorrKey")
            
            /*let boltzSchnorrKey = try! secp256k1.Schnorr.PublicKey(dataRepresentation: "03611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61f".bytes, format: .uncompressed)
            let mySchnorrKey = try! secp256k1.Schnorr.PrivateKey(dataRepresentation: "KxhGnKyk68TyWQphZ7aPYJ6pspeH3oEadRKenBQaK7sgCo8oZUur".bytes).publicKey*/
            //let combinedKey = try! secp256k1.Schnorr.
            
            let message = "2004cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24ad02df01b1".data(using: .utf8)!
            print("Did generate message")
            let messageHash = SHA256.hash(data: message)
            print("Did generate messageHash")
            let firstNonce = try secp256k1.MuSig.Nonce.generate(secretKey: schnorrKey, publicKey: schnorrKey.publicKey, msg32: Array(messageHash))
            
            print("Public nonce")
            
        } catch let error as CryptoKit.CryptoKitError {
            print("628 Error: \(error)")
        } catch let error as secp256k1Error {
            print("637 Error: \(error)")
        } catch {
            print("630 Error: \(error.localizedDescription)")
        }
        
        //let aggregateKey = try secp256k1.MuSig.aggregate([])
        
        /*if let privateKey = self.wifToPrivateKey("cQWo7AVPFAR8S33hNNEXqNhDYgQ5U7ZTxEyEnuWZ3tuxZLqHyU1J") {
            print("✅ Private key extracted:", privateKey.map { String(format: "%02x", $0) }.joined())
            
            if let pubNonce = self.generatePublicNonce(from: privateKey) {
                print("Generated pubNonce:", pubNonce.map { String(format: "%02x", $0) }.joined())
                
            }
        } else {
            print("❌ Failed to extract private key")
        }*/
    }
    
    
    static func lightningToOnchain(amountSat:Int, delegate:Any?) async {
        
        // Call /v2/swap/reverse to receive the Lightning invoice we should pay.
        
        // Create random preimage hash
        // Create a random preimage for the swap; has to have a length of 32 bytes
        // crypto.sha256(preimage).toString('hex')
        let randomPreimage = self.generateRandomPreimage()
        let randomPreimageHash = self.sha256Hash(of: randomPreimage)
        let randomPreimageHashHex = randomPreimageHash.hexEncodedString()
        
        let parameters: [String: Any] = [
            "from": "BTC",
            "to": "BTC",
            "claimPublicKey": "0304cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24",
            "preimageHash": randomPreimageHashHex,
            "onchainAmount": amountSat
        ]
        
        var apiURL = "https://api.boltz.exchange/v2"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            apiURL = "https://api.regtest.getbittr.com/v2"
        }
        
        do {
            let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
            var request = URLRequest(url: URL(string: "\(apiURL)/swap/reverse".replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!,timeoutInterval: Double.infinity)
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
                // Example error
                // Example success
                
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
                                /*if let expectedAmount = actualDataDict["expectedAmount"] as? Int {
                                    Task {
                                        await self.checkOnchainFees(amountInSatoshis: Int(amountMsat)/1000, createdInvoice: invoice, receivedDictionary: actualDataDict, delegate: delegate)
                                    }
                                }*/
                                let mutableSwapDictionary:NSMutableDictionary = actualDataDict.mutableCopy() as! NSMutableDictionary
                                mutableSwapDictionary.setValue(amountSat, forKey: "useramount")
                                mutableSwapDictionary.setValue(randomPreimageHashHex, forKey: "preimagehex")
                                self.checkReverseSwapFees(swapDictionary: mutableSwapDictionary, delegate: delegate)
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
                swapVC.showAlert(title: Language.getWord(withID: "error"), message: Language.getWord(withID: "swaperror1"), buttons: [Language.getWord(withID: "okay")], actions: nil)
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
                                delegate.addNewPaymentToTable(paymentHash: paymentHash, invoiceAmount: userAmount, delegate: self)
                                
                                if let swapID = swapDictionary["id"] as? String {
                                    delegate.webSocketManager = WebSocketManager()
                                    delegate.webSocketManager!.delegate = delegate
                                    delegate.webSocketManager!.swapID = swapID
                                    delegate.webSocketManager!.connect()
                                }
                            } else {
                                // Payment came back failed.
                                delegate.confirmStatusLabel.text = Language.getWord(withID: "swapstatusfailedtopay")
                                delegate.showAlert(title: Language.getWord(withID: "paymentfailed"), message: Language.getWord(withID: "paymentfailed2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        } else {
                            // Success alert
                            delegate.confirmStatusLabel.text = Language.getWord(withID: "swapstatusawaitingtransaction")
                            delegate.addNewPaymentToTable(paymentHash: paymentHash, invoiceAmount: userAmount, delegate: self)
                            
                            if let swapID = swapDictionary["id"] as? String {
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
                        delegate.showAlert(title: Language.getWord(withID: "paymentfailed"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                        SentrySDK.capture(error: error)
                    }
                } catch {
                    DispatchQueue.main.async {
                        // General error alert
                        delegate.showAlert(title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                        SentrySDK.capture(error: error)
                    }
                }
            }
        }
    }
    
    static func claimOnchainTransaction(swapDictionary:NSDictionary, delegate:Any?) {
        
        // As soon as the swap status is "transaction.mempool", the onchain transaction can be claimed.
        // Claim the onchain transaction.
        
        if let boltzPublicKey = swapDictionary["refundPublicKey"] as? String, let randomPreimageHex = swapDictionary["preimagehex"] as? String {
            
            // STEPS (see https://docs.boltz.exchange/api/api-v2)
            // 1. Create a musig signing session with boltzPublicKey and our public key.
            // 2. Tweak it with the Taptree of the swap scripts.
            // 3. Get the transactionHex (either already received with the status, or through GET /swap/reverse/{id}/transaction.
            // 4. Create a claim transaction to be signed cooperatively via a key path spend.
            // 5. Get the partial signature from Boltz through POST /swap/reverse/{id}/claim with parameters {index: 0, transaction: transactionHex, preimage: randomPreimageHex, pubNonce: Buffer.from(musig.getPublicNonce()).toString('hex')}. We receive pubNonce and partialSignature.
            // 6. Aggregate the nonces of boltzPublicKey and the received pubNonce.
            // 7. Sign the claim transaction and add Boltz's partialSignature.
            // 8. Broadcast the transaction through POST /chain/BTC/transaction with the "hex" of the transaction.
            
        }
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

