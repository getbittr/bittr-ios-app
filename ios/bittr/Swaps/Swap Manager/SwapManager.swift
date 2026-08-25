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


    /// The signed webhook URL to hand Boltz on swap create. Bittr's API now
    /// rejects unsigned Boltz callbacks — the URL is a server-minted HMAC. The
    /// returned `url` is used verbatim: its path is the HMAC alone, the app
    /// never puts the APNS device token in it (the server maps the HMAC back to
    /// the device when Boltz POSTs). Minted once via `GET /boltz/webhook-token`
    /// (signed with the LN node key, same stack as `GET /notifications` but with
    /// a `boltz_webhook:` prefix), cached next to the APNS device token, and
    /// reused for every swap. Re-mints when there's no cache yet or the cached
    /// URL's device token no longer matches the current APNS token. Returns nil
    /// when it can't produce a signed URL (no device token, signing failure, or
    /// the mint call failed) — the caller must not create a swap with an
    /// unsigned webhook, which would 404.
    static func boltzWebhookURL() async -> String? {
        guard let deviceToken = CacheManager.getRegistrationToken(), !deviceToken.isEmpty else {
            return nil
        }

        // Reuse the cached URL only while it matches the current APNS token AND
        // is the current URL format. The path was shortened to a bare HMAC with
        // no query; a URL cached before that still carries the device token and a
        // `?token=` query. Treat any `?` as the old (too-long) shape and re-mint,
        // so existing installs self-heal on the next swap without a reinstall
        // (which would lose channel state).
        if let cachedURL = CacheManager.getBoltzWebhookURL(),
           CacheManager.getBoltzWebhookDeviceToken() == deviceToken,
           !cachedURL.contains("?") {
            return cachedURL
        }

        guard let pubkey = BitcoinManager.shared.nodeId() else { return nil }
        let timestamp = Int(Date().timeIntervalSince1970)

        let signature: String
        do {
            signature = try await BitcoinManager.shared.signMessage(message: "boltz_webhook:\(pubkey):\(timestamp)")
        } catch {
            Log.info("Could not sign Boltz webhook-token request: \(error.localizedDescription)")
            return nil
        }

        let mintURL = "\(EnvironmentConfig.bittrAPIBaseURL)/boltz/webhook-token?pubkey=\(pubkey)&timestamp=\(timestamp)&signature=\(signature)"

        let response: NSDictionary? = await withCheckedContinuation { continuation in
            Task {
                await CallsManager.makeApiCall(url: mintURL, parameters: nil, getOrPost: .get) { result in
                    switch result {
                    case .success(let dictionary):
                        continuation.resume(returning: dictionary)
                    case .failure(let error):
                        Log.info("Boltz webhook-token mint failed: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        guard let response,
              response["success"] as? Bool == true,
              let url = response["url"] as? String,
              let hashedDeviceToken = response["device_token"] as? String else {
            if let error = response?["error"] as? String {
                Log.info("Boltz webhook-token mint rejected: \(error)")
            }
            return nil
        }

        if hashedDeviceToken != deviceToken {
            // The server HMACs the token on the customer record, not one we
            // pass. A mismatch means the backend hasn't got our current APNS
            // token yet; cache against the server's value so we re-mint once it
            // catches up (and Boltz pushes reach the right device in between).
            Log.info("Boltz webhook-token minted for a device token that differs from the current APNS token — backend customer record may be stale.")
        }

        CacheManager.storeBoltzWebhook(url: url, deviceToken: hashedDeviceToken)
        return url
    }

    /// Boltz's published fee for a swap direction, from its fee/limits endpoint
    /// (`GET /swap/submarine` | `/swap/reverse`). The create response carries no
    /// fee field, so this is the independent reference the amount check bounds
    /// against. Returns nil if unavailable — the check then falls back to the
    /// loose ratio rather than blocking the swap.
    static func fetchBoltzFeeQuote(reverse: Bool) async -> BoltzFeeQuote? {
        let endpoint = reverse ? "swap/reverse" : "swap/submarine"
        let url = "\(EnvironmentConfig.boltzBaseURL)/\(endpoint)"

        let response: NSDictionary? = await withCheckedContinuation { continuation in
            Task {
                await CallsManager.makeApiCall(url: url, parameters: nil, getOrPost: .get) { result in
                    continuation.resume(returning: try? result.get())
                }
            }
        }

        guard let fees = ((response?["BTC"] as? NSDictionary)?["BTC"] as? NSDictionary)?["fees"] as? NSDictionary,
              let percentage = (fees["percentage"] as? NSNumber)?.doubleValue else {
            Log.info("Boltz fee schedule unavailable (\(endpoint)); amount check will use the fallback bound.")
            return nil
        }

        // Submarine quotes a single miner fee; reverse breaks it into lockup +
        // claim, where the lockup is the Boltz-side cost folded into the invoice.
        let minerFee: Int
        if let single = (fees["minerFees"] as? NSNumber)?.intValue {
            minerFee = single
        } else if let breakdown = fees["minerFees"] as? NSDictionary {
            minerFee = (breakdown["lockup"] as? NSNumber)?.intValue
                ?? (breakdown["claim"] as? NSNumber)?.intValue ?? 0
        } else {
            minerFee = 0
        }

        return BoltzFeeQuote(percentage: percentage, minerFee: minerFee)
    }

    static func onchainToLightning(amountMsat:UInt64? = nil, swapVC:SwapViewController, existingInvoice:String? = nil) async {
        // Get Swap ID.
        let idString = createDateId()
        
        // Get invoice
        let invoice: String
        if let existingInvoice {
            Log.info("Use the existing invoice (for Lightning payment case)")
            invoice = existingInvoice
        } else {
            Log.info("Create an invoice for the amount we want to move.")
            guard let amountMsat, let thisInvoice = await BitcoinManager.shared.getInvoice(
                amountMsat: amountMsat,
                description: "Swap onchain to lightning \(idString)",
                expirySecs: 3600)
            else {
                swapVC.cancelSwap(alertMessage: Language.getWord(withID: "invoicecreatefail"))
                return
            }
            invoice = thisInvoice.description
        }
        
        // Get invoice amount.
        guard let invoiceAmountMsat = Bindings.Bolt11Invoice.fromStr(s: invoice).getValue()?.amountMilliSatoshis() else {
            swapVC.cancelSwap(alertMessage: Language.getWord(withID: "swaperror2"))
            return
        }
        
        // Store invoice in cache.
        DispatchQueue.main.async {
            if let invoiceHash = invoice.description.getInvoiceHash(), let paymentDetails = BitcoinManager.shared.getPaymentDetails(paymentHash: invoiceHash) {
                let newTimestamp = Int(Date().timeIntervalSince1970)
                CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.cacheID, timestamp: newTimestamp)
                CacheManager.storeInvoiceDescription(preimage: paymentDetails.cacheID, desc: "Swap onchain to lightning \(idString)")
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
        
        // The webhook needs both an APNS device token and a server-signed URL:
        // Bittr's API now rejects unsigned Boltz callbacks (they 404, breaking
        // swap-status pushes and payout retry). Mint the signed URL — cached
        // after the first swap and reused for every swap.
        guard CacheManager.getRegistrationToken()?.isEmpty == false else {
            swapVC.cancelSwap(alertTitle: Language.getWord(withID: "notificationsrequired"), alertMessage: Language.getWord(withID: "notificationsrequiredmessage"), alertButtons: [.action(Language.getWord(withID: "okay")) { swapVC.askForPushNotifications() }])
            return
        }

        guard let webhookURL = await SwapManager.boltzWebhookURL() else {
            swapVC.cancelSwap(alertMessage: Language.getWord(withID: "couldntconnect"))
            return
        }
        
        // Create POST API call.
        let parameters: [String: Any] = [
            "from": "BTC",
            "to": "BTC",
            "invoice": invoice,
            "refundPublicKey": publicKey,
            "webhook": [
                "url": webhookURL,
                "hashSwapId": true
            ]
        ]
        
        let feeQuote = await fetchBoltzFeeQuote(reverse: false)
        let apiURL = EnvironmentConfig.boltzBaseURL
        Task {
            await CallsManager.makeApiCall(url: "\(apiURL)/swap/submarine", parameters: parameters, getOrPost: .post) { result in
                
                switch result {
                case .failure(let error):
                    swapVC.cancelSwap(alertMessage: error.localizedDescription)
                case .success(let receivedDictionary):
                    if let errorMessage = receivedDictionary["error"] as? String {
                        swapVC.cancelSwap(alertMessage: errorMessage)
                        return
                    }

                    // EVIL-BOLTZ-INJECTION — SEC-02 test harness (see Helpers/EvilBoltz.swift).
                    // The response handler is wrapped in `processSubmarineResponse` so the
                    // DEBUG-only harness can feed it a tampered response. In Release the call
                    // after this block is a plain passthrough — behavior is identical.
                    let processSubmarineResponse: ([String: Any]) -> Void = { receivedDictionary in

                    // Example success {"bip21":"bitcoin:bcrt1pfalvfpkhtha6qmxmkgvljnajnc2hvl2c828euxh5679e302gk9wsh3e9af?amount=0.00050352&label=Send%20to%20BTC%20lightning","acceptZeroConf":false,"expectedAmount":50352,"id":"ChTExx2srRLT","address":"bcrt1pfalvfpkhtha6qmxmkgvljnajnc2hvl2c828euxh5679e302gk9wsh3e9af","swapTree":{"claimLeaf":{"version":192,"output":"a914ed96f252263cd8cc0a616602875f76bfb0c70fcd8820611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61fac"},"refundLeaf":{"version":192,"output":"2004cac31242618cac8211d342bc733a1d1fdfe063cfe053977eacd9fac9a89d24ad02df01b1"}},"claimPublicKey":"03611b80e6aa832718caae89c59f16576888db6f911f88c2d1fc3533bee7efc61f","timeoutBlockHeight":479}
                    
                    DispatchQueue.main.async {
                        guard
                            let onchainAddress = receivedDictionary["address"] as? String,
                            let expectedAmount = receivedDictionary["expectedAmount"] as? Int,
                            let swapID = receivedDictionary["id"] as? String,
                            let swapTree = receivedDictionary["swapTree"] as? NSDictionary,
                            let claimLeaf = swapTree["claimLeaf"] as? NSDictionary,
                            let claimLeafOutput = claimLeaf["output"] as? String,
                            let refundLeaf = swapTree["refundLeaf"] as? NSDictionary,
                            let refundLeafOutput = refundLeaf["output"] as? String,
                            let claimPublicKey = receivedDictionary["claimPublicKey"] as? String
                        else {
                            Log.info("Expected data unavailable.")
                            swapVC.cancelSwap(alertMessage: Language.getWord(withID: "swaperror2"))
                            return
                        }
                        guard swapVC.thisSwap != nil else {
                            Log.info("SwapVC has been closed while awaiting API response.")
                            return
                        }
                        
                        Log.info("Validate Boltz address and amount.")
                        do {
                            try BoltzSwapValidation.validateSubmarineLockup(
                                address: onchainAddress,
                                claimPublicKeyHex: claimPublicKey,
                                refundPrivateKeyHex: privateKey,
                                ourRefundPublicKeyHex: publicKey,
                                claimLeafOutputHex: claimLeafOutput,
                                refundLeafOutputHex: refundLeafOutput
                            )
                            try BoltzSwapValidation.validateQuotedAmount(
                                requested: Int(invoiceAmountMsat / 1000),
                                quoted: expectedAmount,
                                fee: feeQuote
                            )
                        } catch {
                            Log.info("Refused the submarine swap response: \(error.localizedDescription)")
                            swapVC.cancelSwap(alertMessage: Language.getWord(withID: "swapvalidationfailed"))
                            SentryManager.countMetric("swap.onchaintolightning.responserejected")
                            SentryManager.capture(error, context: "SwapManager submarine response validation")
                            return
                        }
                        
                        swapVC.thisSwap!.privateKey = privateKey
                        swapVC.thisSwap!.boltzID = swapID
                        swapVC.thisSwap!.boltzOnchainAddress = onchainAddress
                        swapVC.thisSwap!.boltzExpectedAmount = expectedAmount
                        swapVC.thisSwap!.claimLeafOutput = claimLeafOutput
                        swapVC.thisSwap!.refundLeafOutput = refundLeafOutput
                        swapVC.thisSwap!.claimPublicKey = claimPublicKey
                        swapVC.thisSwap!.refundPublicKey = publicKey
                        
                        self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: swapVC.thisSwap!.toDictionary())
                        
                        Task {
                            await self.checkOnchainFees(swapVC: swapVC)
                        }
                    }
                    } // processSubmarineResponse
                    EvilBoltz.tamperSubmarineResponse(receivedDictionary as? [String: Any] ?? [:], completion: processSubmarineResponse)
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
                    swapVC.cancelSwap(alertTitle: Language.getWord(withID: "oops"), alertMessage: "\(Language.getWord(withID: "cannotproceed")). Error: Could not get fee estimates.")
                    return
                }
                // Select highest fee.
                swapVC.highestFeePerVbyte = feeEstimates.fastest
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
                    let alertTitle:String
                    let alertMessage:String
                    if isInsufficientFunds {
                        let balance = BitcoinManager.shared.bittrWallet.satoshisOnchain
                        let message = Language.getWord(withID: "onchaininsufficientfunds")
                            .replacingOccurrences(of: "<amount>", with: "\(balance)")
                        alertTitle = Language.getWord(withID: "insufficientfunds")
                        alertMessage = message
                    } else {
                        var errorMessage = error.localizedDescription
                        if let bdkError = error as? BitcoinDevKit.CreateTxError {
                            errorMessage = bdkError.getErrorMessage()
                        }
                        alertTitle = Language.getWord(withID: "oops")
                        alertMessage = "\(Language.getWord(withID: "cannotproceed")). Error: \(errorMessage)."
                        SentryManager.capture(error, context: "SwapManager row 249")
                    }
                    swapVC.cancelSwap(alertTitle: alertTitle, alertMessage: alertMessage)
                }
                return
            }
            
            // Calculate fees.
            let feesForOnchainPayment:Int = swapVC.highestFeePerVbyte!.feeSats(forVsize: Double(size))
            let feesForLightningPayment:Int = ongoingSwap.boltzExpectedAmount! - ongoingSwap.satoshisAmount
            Log.debug("Fees lightning: \(feesForLightningPayment). Fees onchain: \(feesForOnchainPayment).")
            
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
        guard let ongoingSwap = swapVC.thisSwap else { return }
        
        let address = ongoingSwap.boltzOnchainAddress!
        let amountSats = ongoingSwap.boltzExpectedAmount!
        let feeHigh = ongoingSwap.feeHigh!
        
        // Send onchain transaction.
        DispatchQueue.global(qos: .userInitiated).async {
            
            // Send onchain transaction.
            let txIdAndRawData:[String]
            do {
                txIdAndRawData = try BitcoinManager.shared.sendOnchainTransaction(address: address, amountSats: amountSats, selectedVbyte: feeHigh)
            } catch {
                // Log the exact error for debugging
                Log.info("Transaction error: \(error.localizedDescription)")

                DispatchQueue.main.async {
                    swapVC.cancelSwap(alertTitle: Language.getWord(withID: "paymentfailed"), alertMessage: Language.getWord(withID: "paymentfailed3"))
                    SentryManager.countMetric("swap.onchaintolightning.failed")
                    SentryManager.capture(error, context: "SwapManager row 308")
                }
                return
            }
            let txId = txIdAndRawData[0]
            let rawData = txIdAndRawData[1]
            Log.debug("Transaction ID: \(txId)")
            
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
                    CacheManager.storeSuggestedSwap(dateID: swapVC.thisSwap!.dateID)
                }
                
                // Update Home table.
                BitcoinManager.shared.lightSync() { _ in }
                
                // Call didCompleteOnchainTransaction to set up WebSocket monitoring
                swapVC.swapStatusVC?.didCompleteOnchainTransaction()
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
        let claimTransactionFee = await BoltzRefund.calculateClaimOrRefundTransactionFee()
        let onchainAmountWithFee = amountSat + claimTransactionFee
        
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
        if let payoutAddress {
            destinationAddress = payoutAddress
        } else {
            Log.info("DEBUG - Getting new unused address for payout")
            destinationAddress = BitcoinManager.shared.bittrWallet.onchainAddresses?.getNextUnusedAddress() ?? BitcoinManager.shared.getAddress(atIndex: 0)
        }
        
        guard let destinationAddress else {
            Log.info("No payout address available; not starting the swap.")
            swapVC.cancelSwap(alertMessage: Language.getWord(withID: "swaperror2"))
            return
        }
        
        Log.debug("randomPreimage: \(randomPreimage.hexEncodedString())")
        
        // Get Swap ID.
        let idString = createDateId()
        
        // The webhook needs both an APNS device token and a server-signed URL:
        // Bittr's API now rejects unsigned Boltz callbacks (they 404, breaking
        // swap-status pushes and payout retry). Mint the signed URL — cached
        // after the first swap and reused for every swap.
        guard CacheManager.getRegistrationToken()?.isEmpty == false else {
            swapVC.cancelSwap(alertTitle: Language.getWord(withID: "notificationsrequired"), alertMessage: Language.getWord(withID: "notificationsrequiredmessage"), alertButtons: [.action(Language.getWord(withID: "okay")) { swapVC.askForPushNotifications() }])
            return
        }

        guard let webhookURL = await SwapManager.boltzWebhookURL() else {
            swapVC.cancelSwap(alertMessage: Language.getWord(withID: "couldntconnect"))
            return
        }
        
        let parameters: [String: Any] = [
            "from": "BTC",
            "to": "BTC",
            "claimPublicKey": publicKey,
            "preimageHash": randomPreimageHashHex,
            "onchainAmount": onchainAmountWithFee, // Use amount with fee included
            "webhook": [
                "url": webhookURL,
                "hashSwapId": true,
                "status": ["transaction.mempool", "transaction.confirmed", "invoice.settled", "swap.expired", "transaction.failed"]
            ]
        ]
        
        let feeQuote = await fetchBoltzFeeQuote(reverse: true)
        let apiURL = EnvironmentConfig.boltzBaseURL

        Task {
            await CallsManager.makeApiCall(url: "\(apiURL)/swap/reverse", parameters: parameters, getOrPost: .post) { result in
                
                switch result {
                case .failure(let error):
                    swapVC.cancelSwap(alertTitle: Language.getWord(withID: "swapfunds2"), alertMessage: "\(Language.getWord(withID: "error")): \(error)")
                case .success(let receivedDictionary):
                    if let errorMessage = receivedDictionary["error"] as? String {
                        swapVC.cancelSwap(alertMessage: errorMessage)
                        return
                    }

                    // EVIL-BOLTZ-INJECTION — SEC-01 test harness (see Helpers/EvilBoltz.swift).
                    // The response handler is wrapped in `processReverseResponse` so the
                    // DEBUG-only harness can feed it a tampered response. In Release the call
                    // after this block is a plain passthrough — behavior is identical.
                    let processReverseResponse: ([String: Any]) -> Void = { receivedDictionary in

                    // Example success: {id = yes7P5Hn2FD5; invoice = lnbcrt505610n1p58093msp5k4f2jxgmu059lc8awdccdy8ppx9uw0wtxhmwa0ytna48ykpjlu9spp5augg6x7kd2dj2gs0z5lnpj98pvyyf4kpmrtt43sp8vawdrgm7l2qdql2djkuepqw3hjqsj5gvsxzerywfjhxucxqyp2xqcqzyl9qyysgq3glstd77evhlg2qywjku4lj4mffufgc2wy6trxsjar5a2mdzp6e9308z4d4prhjs03vegamm7raw0ln5k94l5lz8vu5yewz7hf6w7yqpjqj2mj; lockupAddress = bcrt1p32hqu3ve32x524994sxpewdvdznfjgd0ya2xh40z6x9tj5s2mmusx273a3; refundPublicKey = 035578a38b772461f2481b2a9c6f6802419b11282fb3719cde6af337c077e3d5f3; swapTree = {claimLeaf = {output = 82012088a91475b687397f92783b38c7381725bfcf27d65eef3f8820036f6171920eec6d2f377e4c0ab88960307c7d9d817ddf65585bc28a8334be1aac; version = 192;}; refundLeaf = {output = 205578a38b772461f2481b2a9c6f6802419b11282fb3719cde6af337c077e3d5f3ad024d01b1; version = 192;};}; timeoutBlockHeight = 333;}
                    
                    DispatchQueue.main.async {
                        swapVC.thisSwap!.dateID = "Swap lightning to onchain " + idString
                        swapVC.thisSwap!.privateKey = privateKey
                        swapVC.thisSwap!.preimage = randomPreimage.hexEncodedString()
                        swapVC.thisSwap!.destinationAddress = destinationAddress
                        
                        // Save swap details to file
                        guard
                            let swapID = receivedDictionary["id"] as? String,
                            let boltzInvoice = receivedDictionary["invoice"] as? String,
                            let swapTree = receivedDictionary["swapTree"] as? NSDictionary,
                            let claimLeaf = swapTree["claimLeaf"] as? NSDictionary,
                            let claimLeafOutput = claimLeaf["output"] as? String,
                            let refundLeaf = swapTree["refundLeaf"] as? NSDictionary,
                            let refundLeafOutput = refundLeaf["output"] as? String,
                            let refundPublicKey = receivedDictionary["refundPublicKey"] as? String,
                            let lockupAddress = receivedDictionary["lockupAddress"] as? String
                        else {
                            // Expected data unavailable.
                            swapVC.cancelSwap(alertMessage: Language.getWord(withID: "swaperror2"))
                            return
                        }
                        
                        // Validate Boltz invoice and lockup address.
                        do {
                            try BoltzSwapValidation.validateReverseInvoice(
                                boltzInvoice,
                                preimageHashHex: randomPreimageHashHex,
                                requestedOnchainAmountSats: onchainAmountWithFee,
                                fee: feeQuote
                            )
                            try BoltzSwapValidation.validateReverseLockup(
                                address: lockupAddress,
                                refundPublicKeyHex: refundPublicKey,
                                claimPrivateKeyHex: privateKey,
                                ourClaimPublicKeyHex: publicKey,
                                preimageHex: randomPreimage.hexEncodedString(),
                                claimLeafOutputHex: claimLeafOutput,
                                refundLeafOutputHex: refundLeafOutput
                            )
                        } catch {
                            Log.info("Refused the reverse swap response: \(error.localizedDescription)")
                            swapVC.cancelSwap(alertMessage: Language.getWord(withID: "swapvalidationfailed"))
                            SentryManager.countMetric("swap.lightningtoonchain.responserejected")
                            SentryManager.capture(error, context: "SwapManager reverse response validation")
                            return
                        }
                        
                        swapVC.thisSwap!.boltzID = swapID
                        swapVC.thisSwap!.boltzInvoice = boltzInvoice
                        swapVC.thisSwap!.claimLeafOutput = claimLeafOutput
                        swapVC.thisSwap!.refundLeafOutput = refundLeafOutput
                        swapVC.thisSwap!.refundPublicKey = refundPublicKey
                        swapVC.thisSwap!.claimPublicKey = publicKey
                        self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: swapVC.thisSwap!.toDictionary())
                        
                        // Store transaction details in cache.
                        CacheManager.storeSwapID(dateID: swapVC.thisSwap!.dateID, swapID: swapVC.thisSwap!.boltzID!)
                        CacheManager.storeInvoiceDescription(preimage: randomPreimageHashHex, desc: swapVC.thisSwap!.dateID)
                        if swapVC.thisSwap!.isSuggested {
                            CacheManager.storeSuggestedSwap(dateID: swapVC.thisSwap!.dateID)
                        }
                        self.checkReverseSwapFees(swapVC: swapVC)
                    }
                    } // processReverseResponse
                    EvilBoltz.tamperReverseResponse(receivedDictionary as? [String: Any] ?? [:], completion: processReverseResponse)
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

    /// The SHA-256 (lowercase hex) of a Boltz swap id — the value Boltz puts in
    /// its webhook when the swap was created with `hashSwapId` on, and the name
    /// its details file is stored under, so a status push resolves to the swap
    /// without the plaintext id ever reaching bittr.
    static func hashedSwapID(_ swapID: String) -> String {
        return sha256Hash(of: Data(swapID.utf8)).hexEncodedString()
    }
    
    static func saveSwapDetailsToFile(swapID: String, swapDictionary: NSDictionary) {
        do {
            // Convert NSDictionary to JSON Data
            let jsonData = try JSONSerialization.data(withJSONObject: swapDictionary, options: .prettyPrinted)

            // Store under sha256(swapID): the filename is the same value Boltz
            // puts in a hashSwapId webhook, so a status push opens the file
            // directly and the plaintext Boltz id never reaches bittr.
            let fileURL = swapFile(named: hashedSwapID(swapID))

            // Write the JSON data to file. The swap file DELIBERATELY contains
            // the Boltz refund key in plain text: it is the user-facing
            // emergency artifact for Boltz's rescue flow (see the Download
            // button in SwapStatusVC) and must stay usable without a working
            // app or Keychain — do not strip or encrypt its contents. The
            // file-protection option below encrypts it at rest with the
            // device passcode (readable after first unlock, so background
            // swap processing and the user's export both keep working).
            try jsonData.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

            Log.debug("Swap details saved to: \(fileURL.path)")
        } catch {
            Log.info("Error saving swap details to file: \(error)")
            SentryManager.capture(error, context: "SwapManager row 519")
        }
    }

    static func loadSwapDetailsFromFile(swapID: String) -> NSDictionary? {
        // New swaps are stored under sha256(id); fall back to the plaintext name
        // for swaps written before that change (they age out as they complete).
        return swapDetails(atFileNamed: hashedSwapID(swapID)) ?? swapDetails(atFileNamed: swapID)
    }

    /// Resolve the swap a status push refers to. The push id is already the file
    /// stem — sha256(boltzID) for hashSwapId swaps, the plaintext id for older
    /// ones — so open it directly.
    static func loadSwapDetails(forPushedID pushedID: String) -> NSDictionary? {
        return swapDetails(atFileNamed: pushedID)
    }

    /// On-disk URL of a swap's JSON, for reading/exporting the file directly.
    /// Prefers the sha256-named file, falling back to a legacy plaintext name.
    static func swapFileURL(for swapID: String) -> URL {
        let hashed = swapFile(named: hashedSwapID(swapID))
        if FileManager.default.fileExists(atPath: hashed.path) { return hashed }
        let legacy = swapFile(named: swapID)
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : hashed
    }

    private static func swapFile(named stem: String) -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(stem).json")
    }

    private static func swapDetails(atFileNamed stem: String) -> NSDictionary? {
        guard let jsonData = try? Data(contentsOf: swapFile(named: stem)),
              let object = try? JSONSerialization.jsonObject(with: jsonData, options: []),
              let dictionary = object as? NSDictionary else {
            return nil
        }
        return dictionary
    }

    static func updateSwapFileWithLockupTx(swapID: String, lockupTx: String) {
        
        // Load existing swap details
        guard let existingSwapDetails = loadSwapDetailsFromFile(swapID: swapID) else {
            Log.debug("Could not load existing swap details for ID: \(swapID)")
            return
        }
        
        // Create a mutable copy and add the lockup transaction
        let updatedSwapDetails = existingSwapDetails.mutableCopy() as! NSMutableDictionary
        updatedSwapDetails.setValue(lockupTx, forKey: "lockupTx")
        
        // Save the updated swap details back to file
        self.saveSwapDetailsToFile(swapID: swapID, swapDictionary: updatedSwapDetails)
        
        Log.debug("Updated swap file with lockup transaction for ID: \(swapID)")
            
    }
    
    private static func swapLegs(dateID:String) -> [Transaction] {
        return BitcoinManager.shared.listPayments()
            .map { $0.createTransaction(bittrTransactions: nil) }
            .filter { $0.lnDescription == dateID }
    }
    
    private static func swapStatusVC(for homeVC:HomeViewController) -> SwapStatusViewController? {
        return homeVC.swapStatusVC ?? homeVC.moveVC?.swapVC?.swapStatusVC
    }
    
    static func openCompletedSwapTransaction(dateID:String, homeVC:HomeViewController?, attemptsLeft:Int = 4) {
        guard dateID != "", let homeVC = homeVC else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Look for the two swap transactions before syncing.
            var legs = self.swapLegs(dateID: dateID)
            if legs.count != 2 {
                // Couldn't find both transactions. Will sync wallet.
                DispatchQueue.main.async {
                    let statusVC = self.swapStatusVC(for: homeVC)
                    if statusVC?.isShowingSwapComplete == true {
                        // Show loading banner while fetching swap details.
                        statusVC?.showLoading(message: Language.getWord(withID: "gatheringdetails"))
                    }
                }
                try? BitcoinManager.shared.syncWallets()
                legs = self.swapLegs(dateID: dateID)
            }
            
            // Make sure both transactions have been found.
            guard legs.count == 2 else {
                guard attemptsLeft > 1 else {
                    Log.info("Complete swap not yet available.")
                    DispatchQueue.main.async { self.swapStatusVC(for: homeVC)?.hideLoading() }
                    return
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5) {
                    Log.info("Will retry finding completed swap.")
                    self.openCompletedSwapTransaction(dateID: dateID, homeVC: homeVC, attemptsLeft: attemptsLeft - 1)
                }
                return
            }
            
            // Combine the two transactions.
            guard let swapTransaction = legs.performSwapMatching().first(where: { $0.isSwap }) else {
                Log.info("Could not combine the two legs of this swap.")
                DispatchQueue.main.async { self.swapStatusVC(for: homeVC)?.hideLoading() }
                return
            }
            
            Log.info("Did find completed swap transaction, will launch TransactionVC.")
            DispatchQueue.main.async {
                // Mark swap complete.
                let statusVC = self.swapStatusVC(for: homeVC)
                statusVC?.hideLoading()
                statusVC?.markSwapComplete()
                
                // Open TransactionVC.
                homeVC.tappedTransaction = swapTransaction
                homeVC.performSegue(withIdentifier: "HomeToTransaction", sender: homeVC)
            }
        }
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
        
        if ongoingSwap.isSuggested {
            if let boltzID = ongoingSwap.boltzID, let existingSwapDetails = self.loadSwapDetailsFromFile(swapID: boltzID), let updatedSwapDetails = existingSwapDetails.mutableCopy() as? NSMutableDictionary {
                updatedSwapDetails.setValue(transactionId, forKey: "sentOnchainTransactionID")
                self.saveSwapDetailsToFile(swapID: boltzID, swapDictionary: updatedSwapDetails)
            }
            // Mark suggested swap as succeeded.
            CacheManager.storeSuggestedSwap(dateID: ongoingSwap.dateID, status: .succeeded)
        }
        
        // Light sync wallet to add transaction to table.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            BitcoinManager.shared.lightSync() { _ in }
        }
        
        // Open TransactionVC.
        if !ongoingSwap.isSuggested {
            self.openCompletedSwapTransaction(dateID: ongoingSwap.dateID, homeVC: swapVC.coreVC?.homeVC)
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
            let claimTransactionFee = await BoltzRefund.calculateClaimOrRefundTransactionFee()
            
            DispatchQueue.main.async {
                swapVC.thisSwap!.boltzExpectedAmount = invoiceAmount
                swapVC.thisSwap!.onchainFees = onchainFees
                swapVC.thisSwap!.lightningFees = lightningFees
                swapVC.thisSwap!.claimTransactionFee = claimTransactionFee
                
                // Confirm fees with user.
                swapVC.confirmExpectedFees()
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
                swapVC.showAlert(title: Language.getWord(withID: "paymentfailed"), message: Language.getWord(withID: "paymentfailed2").replacingOccurrences(of: "<reason>", with: ""), buttons: [.dismiss(Language.getWord(withID: "okay"))])
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

func createDateId() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMddHHmmss"
    return dateFormatter.string(from: Date())
}
