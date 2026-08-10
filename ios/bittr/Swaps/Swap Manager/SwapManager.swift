//
//  SwapManager.swift
//  bittr
//
//  Created by Tom Melters on 24/01/2025.
//

import UIKit
import BitcoinDevKit
import LDKNode
import P256K
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
            
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let idString = dateFormatter.string(from: Date())
        
        let invoice: String
        var actualAmountMsat: UInt64 = amountMsat
        
        if let existingInvoice = existingInvoice {
            Log.info("Use the existing invoice (for Lightning payment case)")
            invoice = existingInvoice
            
            // Parse the existing invoice to get the actual amount
            if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: existingInvoice).getValue() {
                if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                    actualAmountMsat = invoiceAmountMilli
                }
            }
        } else {
            Log.info("Create an invoice for the amount we want to move.")
            guard let thisInvoice = await BitcoinManager.shared.getInvoice(
                amountMsat: amountMsat,
                description: "Swap onchain to lightning \(idString)",
                expirySecs: 3600)
            else {
                DispatchQueue.main.async {
                    swapVC.nextLabel.alpha = 1
                    swapVC.arrowIcon.alpha = 1
                    swapVC.nextSpinner.stopAnimating()
                    swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "unexpectederror"), message: Language.getWord(withID: "invoicecreatefail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                return
            }
            invoice = thisInvoice.description
        }
        
        // Store invoice in cache.
        DispatchQueue.main.async {
            if let invoiceHash = invoice.description.getInvoiceHash(), let paymentDetails = BitcoinManager.shared.getPaymentDetails(paymentHash: invoiceHash) {
                let newTimestamp = Int(Date().timeIntervalSince1970)
                CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.kind.transactionID ?? paymentDetails.id, timestamp: newTimestamp)
                CacheManager.storeInvoiceDescription(preimage: paymentDetails.kind.transactionID ?? paymentDetails.id, desc: "Swap onchain to lightning \(idString)")
                Log.info("Did cache invoice data.")
            }
            
            swapVC.thisSwap!.dateID = "Swap onchain to lightning \(idString)"
            swapVC.thisSwap!.createdInvoice = invoice.description
            swapVC.thisSwap!.isSuggested = (existingInvoice != nil)
        }
        
        // Get next swap index and derive key dynamically
        let swapIndex = CacheManager.incrementSwapIndex()
        let dynamicPath = "m/503'/0'/0'/0/\(swapIndex)"
        
        let (privateKey, publicKey) = try! BitcoinManager.shared.getPrivatePublicKeyForPath(path: dynamicPath)
        
        // Get device token for webhook URL
        let deviceToken = CacheManager.getRegistrationToken() ?? ""
        
        // Check if we have a registration token (notifications enabled)
        if deviceToken.isEmpty {
            DispatchQueue.main.async {
                swapVC.nextLabel.alpha = 1
                swapVC.arrowIcon.alpha = 1
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
            await CallsManager.makeApiCall(url: "\(apiURL)/swap/submarine", parameters: parameters, getOrPost: .post) { result in
                
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        swapVC.nextLabel.alpha = 1
                        swapVC.arrowIcon.alpha = 1
                        swapVC.nextSpinner.stopAnimating()
                        swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "error"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                case .success(let receivedDictionary):
                    if let errorMessage = receivedDictionary["error"] as? String {
                        DispatchQueue.main.async {
                            swapVC.nextLabel.alpha = 1
                            swapVC.arrowIcon.alpha = 1
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
                            
                            if swapVC.thisSwap == nil {
                                // SwapVC has been closed while awaiting API response.
                                return
                            }
                            
                            swapVC.thisSwap!.privateKey = privateKey
                            swapVC.thisSwap!.boltzID = swapID
                            swapVC.thisSwap!.boltzOnchainAddress = onchainAddress
                            swapVC.thisSwap!.boltzExpectedAmount = expectedAmount
                            swapVC.thisSwap!.claimLeafOutput = claimLeafOutput
                            swapVC.thisSwap!.refundLeafOutput = refundLeafOutput
                            swapVC.thisSwap!.claimPublicKey = claimPublicKey
                            
                            self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: swapVC.thisSwap!.toDictionary())
                            
                            Task {
                                await self.checkOnchainFees(swapVC: swapVC)
                            }
                        } else {
                            // Expected data unavailable.
                            DispatchQueue.main.async {
                                swapVC.nextLabel.alpha = 1
                                swapVC.arrowIcon.alpha = 1
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
    
    static func checkOnchainFees(swapVC:SwapViewController) async {
        guard let ongoingSwap = await swapVC.thisSwap else {return}
        
        // Check what the onchain fees will be for sending this onchain payment.
        Task {
            if swapVC.highestFeePerVbyte == nil {
                guard let feeEstimates = await BitcoinManager.shared.getFeeEstimates() else {
                    Log.info("Could not fetch fee estimates.")
                    DispatchQueue.main.async {
                        swapVC.nextLabel.alpha = 1
                        swapVC.arrowIcon.alpha = 1
                        swapVC.nextSpinner.stopAnimating()
                        swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: Could not get fee estimates.", buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                    return
                }

                // Select highest fee.
                swapVC.highestFeePerVbyte = Float(feeEstimates.fastest)
            }
            
            var size:UInt64
            do {
                // Calculate transaction size.
                size = try BitcoinManager.shared.getSize(address: ongoingSwap.boltzOnchainAddress!, amountSats: ongoingSwap.boltzExpectedAmount!, selectedVbyte: swapVC.highestFeePerVbyte)
            } catch {
                Log.info("Error: \(error.localizedDescription)")

                // Insufficient onchain funds is the common case — show a friendly
                // message instead of leaking the raw BDK error text to the user.
                var isInsufficientFunds = false
                if let bdkError = error as? BitcoinDevKit.CreateTxError {
                    switch bdkError {
                    case .CoinSelection, .InsufficientFunds:
                        isInsufficientFunds = true
                    default:
                        break
                    }
                }

                DispatchQueue.main.async {
                    // Reset the spinner UI so the user can try a different amount.
                    swapVC.nextLabel.alpha = 1
                    swapVC.arrowIcon.alpha = 1
                    swapVC.nextSpinner.stopAnimating()

                    if isInsufficientFunds {
                        let balance = BitcoinManager.shared.bittrWallet.satoshisOnchain ?? 0
                        let message = Language.getWord(withID: "onchaininsufficientfunds")
                            .replacingOccurrences(of: "<amount>", with: "\(balance)")
                        swapVC.showAlert(
                            presentingController: swapVC,
                            title: Language.getWord(withID: "insufficientfunds"),
                            message: message,
                            buttons: [Language.getWord(withID: "okay")],
                            actions: nil
                        )
                    } else {
                        var errorMessage = error.localizedDescription
                        if let bdkError = error as? BitcoinDevKit.CreateTxError {
                            errorMessage = bdkError.getErrorMessage()
                        }
                        swapVC.showAlert(
                            presentingController: swapVC,
                            title: Language.getWord(withID: "oops"),
                            message: "\(Language.getWord(withID: "cannotproceed")). Error: \(errorMessage).",
                            buttons: [Language.getWord(withID: "okay")],
                            actions: nil
                        )
                        SentryManager.capture(error, context: "SwapManager row 249")
                    }
                }
                return
            }
                
            // Calculate fees.
            let feesForOnchainPayment:Int = Int(CGFloat(swapVC.highestFeePerVbyte!*Float(size)))
            let feesForLightningPayment:Int = ongoingSwap.boltzExpectedAmount! - ongoingSwap.satoshisAmount
            print("Fees lightning: \(feesForLightningPayment). Fees onchain: \(feesForOnchainPayment).")
            
            // Confirm fees with user.
            DispatchQueue.main.async {
                swapVC.thisSwap!.feeHigh = swapVC.highestFeePerVbyte!
                swapVC.thisSwap!.onchainFees = feesForOnchainPayment
                swapVC.thisSwap!.lightningFees = feesForLightningPayment
                swapVC.confirmExpectedFees()
            }
        }
    }
    
    static func sendOnchainPayment(swapVC:SwapViewController) {
        guard swapVC.thisSwap != nil else { return }
            
        // Send onchain transaction.
        let txIdAndRawData:[String]
        do {
            txIdAndRawData = try BitcoinManager.shared.sendOnchainTransaction(address: swapVC.thisSwap!.boltzOnchainAddress!, amountSats: swapVC.thisSwap!.boltzExpectedAmount!, selectedVbyte: swapVC.thisSwap!.feeHigh!)
        } catch {
            // Log the exact error for debugging
            Log.info("Transaction error: \(error.localizedDescription)")
            
            DispatchQueue.main.async {
                swapVC.showAlert(
                    presentingController: swapVC,
                    title: Language.getWord(withID: "paymentfailed"),
                    message: Language.getWord(withID: "paymentfailed3"),
                    buttons: [Language.getWord(withID: "okay")],
                    actions: nil
                )
                SentryManager.countMetric("swap.onchaintolightning.failed")
                SentryManager.capture(error, context: "SwapManager row 308")
            }
            return
        }
        let txId = txIdAndRawData[0]
        let rawData = txIdAndRawData[1]
        print("Transaction ID: \(txId)")
    
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Log.info("Successful transaction.")
            
            // Update swap object.
            swapVC.thisSwap!.sentOnchainTransactionID = txId
            swapVC.thisSwap!.lockupTx = rawData
            self.updateSwapFileWithLockupTx(swapID: swapVC.thisSwap!.boltzID!, lockupTx: swapVC.thisSwap!.lockupTx!)
            
            // Create transaction object.
            CacheManager.storeInvoiceDescription(preimage: txId, desc: swapVC.thisSwap!.dateID)
            CacheManager.storeSwapID(dateID: swapVC.thisSwap!.dateID, swapID: swapVC.thisSwap!.boltzID!)
            if swapVC.thisSwap!.isSuggested {
                // Mark so the Home table renders this as an outbound
                // transaction instead of a perpetually pending swap. Stored as
                // pending; SwapStatusVC upgrades it once Boltz pays the invoice.
                CacheManager.storeSuggestedSwap(dateID: swapVC.thisSwap!.dateID)
            }
            
            // Update Home table.
            BitcoinManager.shared.lightSync() { _ in }
            
            // Call didCompleteOnchainTransaction to set up WebSocket monitoring
            swapVC.swapStatusVC?.didCompleteOnchainTransaction()
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
            await CallsManager.makeApiCall(url: "\(apiURL)/swap/\(swapID)", parameters: nil, getOrPost: .get) { result in
                
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
        
        let (privateKey, publicKey) = try! BitcoinManager.shared.getPrivatePublicKeyForPath(path: dynamicPath)
        
        // Use provided payout address if available, otherwise get a new unused address
        let destinationAddress: String?
        if let payoutAddress = payoutAddress {
            print("DEBUG - Using provided payout address: \(payoutAddress)")
            destinationAddress = payoutAddress
        } else {
            Log.info("DEBUG - Getting new unused address for payout")
            destinationAddress = BitcoinManager.shared.bittrWallet.onchainAddresses?.getNextUnusedAddress() ?? BitcoinManager.shared.getAddress(atIndex: 0)
        }
        
        guard let destinationAddress else {
            Log.info("No payout address available; not starting the swap.")
            DispatchQueue.main.async {
                swapVC.nextLabel.alpha = 1
                swapVC.arrowIcon.alpha = 1
                swapVC.nextSpinner.stopAnimating()
                swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "error"), message: Language.getWord(withID: "swaperror2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
            return
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
                swapVC.arrowIcon.alpha = 1
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
            await CallsManager.makeApiCall(url: "\(apiURL)/swap/reverse", parameters: parameters, getOrPost: .post) { result in
                
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        swapVC.nextLabel.alpha = 1
                        swapVC.arrowIcon.alpha = 1
                        swapVC.nextSpinner.stopAnimating()
                        swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "swapfunds2"), message: "\(Language.getWord(withID: "error")): \(error)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                case .success(let receivedDictionary):
                    if let errorMessage = receivedDictionary["error"] as? String {
                        DispatchQueue.main.async {
                            swapVC.nextLabel.alpha = 1
                            swapVC.arrowIcon.alpha = 1
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
                        swapVC.thisSwap!.dateID = "Swap lightning to onchain " + idString
                        swapVC.thisSwap!.privateKey = privateKey
                        swapVC.thisSwap!.preimage = randomPreimage.hexEncodedString()
                        swapVC.thisSwap!.destinationAddress = destinationAddress
                        
                        // Save swap details to file
                        if let swapID = receivedDictionary["id"] as? String,
                           let boltzInvoice = receivedDictionary["invoice"] as? String,
                           let swapTree = receivedDictionary["swapTree"] as? NSDictionary,
                           let claimLeaf = swapTree["claimLeaf"] as? NSDictionary,
                           let claimLeafOutput = claimLeaf["output"] as? String,
                           let refundLeaf = swapTree["refundLeaf"] as? NSDictionary,
                           let refundLeafOutput = refundLeaf["output"] as? String,
                           let refundPublicKey = receivedDictionary["refundPublicKey"] as? String {
                            swapVC.thisSwap!.boltzID = swapID
                            swapVC.thisSwap!.boltzInvoice = boltzInvoice
                            swapVC.thisSwap!.claimLeafOutput = claimLeafOutput
                            swapVC.thisSwap!.refundLeafOutput = refundLeafOutput
                            swapVC.thisSwap!.refundPublicKey = refundPublicKey
                            self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: swapVC.thisSwap!.toDictionary())
                            
                            // Store transaction details in cache.
                            CacheManager.storeSwapID(dateID: swapVC.thisSwap!.dateID, swapID: swapVC.thisSwap!.boltzID!)
                            CacheManager.storeInvoiceDescription(preimage: swapVC.thisSwap!.preimage!, desc: swapVC.thisSwap!.dateID)
                            if swapVC.thisSwap!.isSuggested {
                                CacheManager.storeSuggestedSwap(dateID: swapVC.thisSwap!.dateID)
                            }
                            self.checkReverseSwapFees(swapVC: swapVC)
                        } else {
                            // Expected data unavailable.
                            DispatchQueue.main.async {
                                swapVC.nextLabel.alpha = 1
                                swapVC.arrowIcon.alpha = 1
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

            // Write the JSON data to file. The swap file DELIBERATELY contains
            // the Boltz refund key in plain text: it is the user-facing
            // emergency artifact for Boltz's rescue flow (see the Download
            // button in SwapStatusVC) and must stay usable without a working
            // app or Keychain — do not strip or encrypt its contents. The
            // file-protection option below encrypts it at rest with the
            // device passcode (readable after first unlock, so background
            // swap processing and the user's export both keep working).
            try jsonData.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            
            print("Swap details saved to: \(fileURL.path)")
        } catch {
            Log.info("Error saving swap details to file: \(error)")
            SentryManager.capture(error, context: "SwapManager row 519")
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
            Log.info("Error loading swap details from file: \(error)")
            SentryManager.capture(error, context: "SwapManager row 542")
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
    
    static func addOnchainTransactionToUI(transactionId:String, swapVC:SwapStatusViewController) {
        // Load swap details to get the description and user amount
        guard let ongoingSwap = swapVC.thisSwap else {
            Log.info("Could not load swap details.")
            return
        }
        
        // Store transaction details in cache.
        CacheManager.storeInvoiceDescription(preimage: transactionId, desc: ongoingSwap.dateID)
        CacheManager.storeSwapID(dateID: ongoingSwap.dateID, swapID: ongoingSwap.boltzID!)
        
        // For a suggested swap the onchain payout goes to an external recipient,
        // so it never lands in this wallet as a matchable onchain transaction.
        // Persist the payout txid on the swap file so the TransactionVC can show
        // it as the Onchain ID (a normal reverse swap gets it from the matched
        // claim transaction instead).
        if ongoingSwap.isSuggested {
            if let boltzID = ongoingSwap.boltzID, let existingSwapDetails = self.loadSwapDetailsFromFile(swapID: boltzID), let updatedSwapDetails = existingSwapDetails.mutableCopy() as? NSMutableDictionary {
                updatedSwapDetails.setValue(transactionId, forKey: "sentOnchainTransactionID")
                self.saveSwapDetailsToFile(swapID: boltzID, swapDictionary: updatedSwapDetails)
            }

            // The claim transaction paying the recipient has been broadcast —
            // only now does the suggested swap count as succeeded.
            CacheManager.storeSuggestedSwap(dateID: ongoingSwap.dateID, status: .succeeded)
        }
        
        // Light sync wallet to add transaction to table.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            BitcoinManager.shared.lightSync() { _ in }
        }
    }
    
    static func checkReverseSwapFees(swapVC:SwapViewController) {
        guard swapVC.thisSwap != nil else { return }
        guard swapVC.checkInternetConnection() else { return }
        
        // Check requested invoice amount.
        guard let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: swapVC.thisSwap!.boltzInvoice!).getValue(), let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() else { return }
        
        // Lightning invoice.
        let invoiceAmount = Int(invoiceAmountMilli)/1000
        
        // Calculate onchain fees.
        // For lightning-to-onchain swaps, the user's input is the final amount they want to receive
        // The invoice amount includes Boltz fees, so we need to calculate the actual on-chain amount
        let finalOnchainAmount = swapVC.thisSwap!.satoshisAmount // This is what the user wants to receive
        let onchainFees:Int = invoiceAmount - finalOnchainAmount
        
        // Note: The claim transaction fee is already included in the on-chain amount requested
        // so the user will receive exactly the amount they input
        
        // Calculate maximum total routing fees.
        let lightningFees = swapVC.getLightningFeesInSatoshis(parsedInvoice: parsedInvoice, amountMsat: nil)
        
        // Calculate claim transaction fee
        Task {
            do {
                let claimTransactionFee = try await BoltzRefund.calculateClaimOrRefundTransactionFee()
                
                DispatchQueue.main.async {
                    swapVC.thisSwap!.boltzExpectedAmount = invoiceAmount
                    swapVC.thisSwap!.onchainFees = onchainFees
                    swapVC.thisSwap!.lightningFees = lightningFees
                    swapVC.thisSwap!.claimTransactionFee = claimTransactionFee
                    
                    // Confirm fees with user.
                    swapVC.confirmExpectedFees()
                }
            } catch {
                Log.info("Failed to calculate claim transaction fee: \(error)")
                // Fallback to default fee calculation without claim transaction fee
                DispatchQueue.main.async {
                    swapVC.thisSwap!.boltzExpectedAmount = invoiceAmount
                    swapVC.thisSwap!.onchainFees = onchainFees
                    swapVC.thisSwap!.lightningFees = lightningFees
                    
                    // Confirm fees with user.
                    swapVC.confirmExpectedFees()
                    SentryManager.capture(error, context: "SwapManager row 654")
                }
            }
        }
    }
    
    static func didReceivePaymentHash(_ paymentHash:PaymentHash, swapVC:SwapStatusViewController) {
        Log.info("Did receive payment hash.")
        guard swapVC.thisSwap != nil else {
            Log.info("❌ No ongoing swap found in sendLightningPayment")
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let thisPayment = BitcoinManager.shared.getPaymentDetails(paymentHash: paymentHash)
            
            if (thisPayment != nil && thisPayment!.status == .failed) || (thisPayment == nil) {
                // Payment came back failed.
                swapVC.confirmStatusLabel.text = Language.getWord(withID: "swapstatusfailedtopay")
                swapVC.showAlert(presentingController: swapVC, title: Language.getWord(withID: "paymentfailed"), message: Language.getWord(withID: "paymentfailed2").replacingOccurrences(of: "<reason>", with: ""), buttons: [Language.getWord(withID: "okay")], actions: nil)
                return
            }
            
            // Success payment
            swapVC.confirmStatusLabel.text = Language.getWord(withID: "swapstatusawaitingtransaction")
            
            // Calculate fees
            if Int(thisPayment!.amountMsat ?? 0)/1000 > swapVC.thisSwap!.satoshisAmount {
                let feesIncurred = (Int(thisPayment!.amountMsat ?? 0)/1000) - swapVC.thisSwap!.satoshisAmount
                CacheManager.storePaymentFees(preimage: swapVC.thisSwap!.preimage!, fees: feesIncurred)
            }
            
            swapVC.webSocketManager = WebSocketManager()
            swapVC.webSocketManager!.delegate = swapVC
            swapVC.webSocketManager!.swapID = swapVC.thisSwap!.boltzID!
            swapVC.webSocketManager!.connect()
        }
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

