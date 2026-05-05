//
//  SendLNURL.swift
//  bittr
//
//  Created by Tom Melters on 17/10/2024.
//

import LNURLDecoder
import UIKit
import CoreImage.CIFilterBuiltins
import CodeScanner
import LDKNode
import Sentry
import P256K
import CryptoKit

extension SendViewController {
    
    func handleLNURLAmountCompletion() {
        
        guard let callback = pendingLNURLCallback,
              let minAmount = pendingLNURLMinAmount,
              let maxAmount = pendingLNURLMaxAmount,
              let amountText = amountTextField.text,
              !amountText.isEmpty else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Convert amount to millisatoshis based on current currency
        var enteredAmount: Int
        if self.selectedCurrency == .satoshis {
            enteredAmount = Int(amountText.toNumber()) * 1000 // Convert satoshis to millisatoshis
        } else if self.selectedCurrency == .bitcoin {
            enteredAmount = amountText.toNumber().inSatoshis() * 1000 // Convert to millisatoshis
        } else { // .currency (fiat)
            let fiatAmount = amountText.toNumber()
            let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
            let btcAmount = fiatAmount / bitcoinValue.currentValue
            
            // Safety check for invalid values
            guard btcAmount.isFinite && !btcAmount.isNaN && bitcoinValue.currentValue > 0 else {
                Log.info("376 Invalid values.")
                print("⚠️ Warning: Invalid values - fiatAmount: \(fiatAmount), bitcoinValue: \(bitcoinValue.currentValue), btcAmount: \(btcAmount)")
                self.showAlert(presentingController: self, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                return
            }
            
            let satoshis = btcAmount.inSatoshis()
            enteredAmount = satoshis * 1000 // Convert to millisatoshis
        }
        
        // Validate amount is within range
        if enteredAmount < minAmount || enteredAmount > maxAmount {
            let minSats = minAmount / 1000
            let maxSats = maxAmount / 1000
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "lnurlbetween").replacingOccurrences(of: "<min>", with: "\(minSats)").replacingOccurrences(of: "<max>", with: "\(maxSats)"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Store description before clearing
        let description = self.pendingLNURLDescription
        
        // Clear pending data
        self.pendingLNURLCallback = nil
        self.pendingLNURLDescription = nil
        self.pendingLNURLMinAmount = nil
        self.pendingLNURLMaxAmount = nil
        
        // Send the LNURL payment request
        self.amountTextField.resignFirstResponder()
        self.sendPayRequest(callbackURL: callback, amount: enteredAmount, receivedDescription: description)
    }
    
    func handleWithdrawAmountCompletion() {
        guard let callback = pendingWithdrawCallback,
              let k1 = pendingWithdrawK1,
              let minAmount = pendingWithdrawMinAmount,
              let maxAmount = pendingWithdrawMaxAmount,
              let amountText = amountTextField.text,
              !amountText.isEmpty else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Convert amount to millisatoshis
        let enteredAmount = Int(amountText.toNumber()) * 1000
        
        // Validate amount is within range
        if enteredAmount < minAmount || enteredAmount > maxAmount {
            let minSats = minAmount / 1000
            let maxSats = maxAmount / 1000
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "lnurlbetween").replacingOccurrences(of: "<min>", with: "\(minSats)").replacingOccurrences(of: "<max>", with: "\(maxSats)"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Clear pending withdraw data
        self.pendingWithdrawCallback = nil
        self.pendingWithdrawK1 = nil
        self.pendingWithdrawMinAmount = nil
        self.pendingWithdrawMaxAmount = nil
        
        // Send the withdraw request
        self.amountTextField.resignFirstResponder()
        self.sendWithdrawRequest(callbackURL: callback, amount: enteredAmount, k1: k1)
    }
    
}

extension UIViewController {
    
    func handleLNURL(code:String) {
        
        let sendVC = self as? SendViewController
        
        sendVC?.startLNURLSpinner()
        
        let url:String
        if code.isValidEmail() {
            // This is an LNURL email.
            let urlDomain = String(code.split(separator: "@")[1])
            let urlUsername = String(code.split(separator: "@")[0])
            url = "https://\(urlDomain)/.well-known/lnurlp/\(urlUsername)"
        } else {
            do {
                url = try LNURLDecoder.decode(lnurl: code)
            } catch {
                Log.info("Couldn't decode LNURL. Message: \(error.localizedDescription)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "SendLNURL row 126", key: "context")
                    }
                    SentrySDK.metrics.count(key: "lnurl.api.failure.2")
                    sendVC?.stopLNURLSpinner()
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                return
            }
        }
        print("Decoded url: \(url)")
        
        Task {
            await CallsManager.makeApiCall(url: url, parameters: nil, getOrPost: .get) { result in
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    sendVC?.stopLNURLSpinner()
                    
                    switch result {
                    case .success(let actualDataDict):
                        SentrySDK.metrics.count(key: "lnurl.api.success")
                        guard let receivedTag = actualDataDict["tag"] as? String else {
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail4"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            return
                        }
                        print("Tag: \(receivedTag)")
                        
                        if receivedTag == "payRequest",
                            let receivedCallback = actualDataDict["callback"] as? String,
                            let minSendable = actualDataDict["minSendable"] as? Int,
                            let maxSendable = actualDataDict["maxSendable"] as? Int {
                                
                            // Check if this LNURL contains a description.
                            var receivedDescription:String?
                            if let receivedMetadata = actualDataDict["metadata"] as? String, let metadataData = receivedMetadata.data(using: .utf8), let parsedMetadata = try? JSONSerialization.jsonObject(with: metadataData, options: []) as? [[String]] {
                                for eachDataPair in parsedMetadata {
                                    if eachDataPair.count == 2, eachDataPair[0] == "text/plain" {
                                        receivedDescription = eachDataPair[1]
                                    }
                                }
                            }
                            
                            if minSendable == maxSendable {
                                // Min and max are the same.
                                self.sendPayRequest(callbackURL: receivedCallback.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters), amount: minSendable, receivedDescription: receivedDescription)
                            } else {
                                // Min and max are different. Update UI to show range and focus amount field.
                                let minSats = minSendable / 1000
                                let maxSats = maxSendable / 1000
                                
                                // Update the label to show the range
                                sendVC?.availableAmount.text = "You can send \(minSats) - \(maxSats) satoshis"
                                
                                // Clear and focus the amount field
                                sendVC?.amountTextField.text = ""
                                sendVC?.amountTextField.becomeFirstResponder()
                                
                                // Store the callback and description for when user enters amount
                                sendVC?.pendingLNURLCallback = receivedCallback.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters)
                                sendVC?.pendingLNURLDescription = receivedDescription
                                sendVC?.pendingLNURLMinAmount = minSendable
                                sendVC?.pendingLNURLMaxAmount = maxSendable
                            }
                        } else if receivedTag == "withdrawRequest",
                            let receivedCallback = actualDataDict["callback"] as? String,
                            let receivedK1 = actualDataDict["k1"] as? String,
                            let minWithdrawable = actualDataDict["minWithdrawable"] as? Int,
                            let maxWithdrawable = actualDataDict["maxWithdrawable"] as? Int {
                                
                            var alert = UIAlertController(title: Language.getWord(withID: "withdrawrequest"), message: "\(Language.getWord(withID: "withdrawrequest1"))".replacingOccurrences(of: "<minwithdrawable>", with: "\(minWithdrawable/1000)").replacingOccurrences(of: "<maxwithdrawable>", with: "\(maxWithdrawable/1000)"), preferredStyle: .alert)
                            if minWithdrawable == maxWithdrawable {
                                // Min and max are the same.
                                alert = UIAlertController(title: Language.getWord(withID: "withdrawrequest"), message: "\(Language.getWord(withID: "withdrawrequest3"))".replacingOccurrences(of: "<withdrawable>", with: "\(minWithdrawable/1000)"), preferredStyle: .alert)
                            } else {
                                // Min and max aren't the same. Choose amount.
                                alert.addTextField { (textField) in
                                    textField.keyboardType = .numberPad
                                }
                            }
                            alert.addAction(UIAlertAction(title: Language.getWord(withID: "confirm"), style: .default, handler: { (save) in
                                
                                var amountText = minWithdrawable
                                if minWithdrawable != maxWithdrawable {
                                    // Min and max aren't the same.
                                    amountText = Int((alert.textFields![0].text ?? "0").toNumber()) * 1000
                                }
                                self.sendWithdrawRequest(callbackURL: receivedCallback.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters), amount: amountText, k1: receivedK1)
                            }))
                            alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
                            self.present(alert, animated: true)
                        } else if receivedTag == "login",
                            let receivedCallback = actualDataDict["callback"] as? String,
                            let receivedK1 = actualDataDict["k1"] as? String {
                            let receivedAction = actualDataDict["action"] as? String
                            
                            guard let callbackURL = URL(string: receivedCallback), let k1Data = Data(hexString: receivedK1) else { return }

                            let request = LNURLAuthRequest(
                                callbackURL: callbackURL,
                                k1: k1Data,
                                action: receivedAction
                            )

                            self.showLNURLAuthConfirmation(request)
                        } else {
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail4"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    case .failure(let error):
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "SendLNURL row 239", key: "context")
                        }
                        SentrySDK.metrics.count(key: "lnurl.api.failure.1")
                        Log.info("Error 111: \(error.localizedDescription)")
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                }
            }
        }
        
        // {"tag":"withdrawRequest","callback":"https://spiritedlizard2.lnbits.com/withdraw/api/v1/lnurl/cb/eKbrKxF2PAi8wNX65ab4HM","k1":"9YxWRdFQFSQngwM2EmuNoh","minWithdrawable":10000,"maxWithdrawable":10000,"defaultDescription":"vouchers","webhook_url":null,"webhook_headers":null,"webhook_body":null}
        
        // {"tag":"payRequest","callback":"https://spiritedlizard2.lnbits.com/lnurlp/api/v1/lnurl/cb/FRV7Uj","minSendable":10000,"maxSendable":10000,"metadata":"[[\"text/plain\", \"Payment to tom\"], [\"text/identifier\", \"tom@spiritedlizard2.lnbits.com\"]]"}
    }
    
    func sendPayRequest(callbackURL:String, amount:Int, receivedDescription:String?) {
        
        let sendVC = self as? SendViewController
        
        sendVC?.startLNURLSpinner()
        
        let actualUrl = "\(callbackURL)?amount=\(amount)"
        
        Task {
            await CallsManager.makeApiCall(url: actualUrl, parameters: nil, getOrPost: .get) { result in
                DispatchQueue.main.async {
                    sendVC?.stopLNURLSpinner()
                    
                    switch result {
                    case .success(let actualDataDict):
                        // Check invoice.
                        guard let receivedInvoice = actualDataDict["pr"] as? String else {
                            SentrySDK.metrics.count(key: "lnurl.pay.failure.2")
                            let errorMessage:String = (actualDataDict["detail"] as? String) ?? "Unexpected error"
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "payrequest"), message: "\(Language.getWord(withID: "lnurlfail2")) \(errorMessage)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                            return
                        }
                        // Invoice received.
                        print("Invoice: \(receivedInvoice)")
                        SentrySDK.metrics.count(key: "lnurl.pay.success")
                        
                        // Pay invoice.
                        sendVC?.confirmLightningTransaction(lnurlinvoice: receivedInvoice, lnurlNote: receivedDescription)
                        
                    case .failure(let error):
                        SentrySDK.metrics.count(key: "lnurl.pay.failure.1")
                        Log.info("Error: \(error.localizedDescription)")
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                }
            }
        }
        
        // {"pr":"lnbc100n1pn3zxhxpp5fmfnccd92qx5e0dnm5ycavywwzgm956cnv29k6cfcdewazmg9swqhp5rn75jx56ah3q0a5dng3aqguxnyyck9638h7rmu39ce2v2nqpdnhscqzzsxqyz5vqsp52whelmgxqldxgnaj9w6p6fp8pe9excjuel9ddsfy32jy6swly5gq9qxpqysgqxpz5j6x6ypvh32acj905u7sa2sz0xwq7s6rxx96u6g7v4axamuu9qnz8uxrax3g9rt5fcw9km89208p47u9rxq9h9jja8hdvlttchfqq5nf4qv","successAction":null,"routes":[],"verify":null}
        // {"detail":"Unable to connect to https://api.getalby.com.","status":"pending"}
    }
    
    func sendWithdrawRequest(callbackURL:String, amount:Int, k1:String) {
        
        let sendVC = self as? SendViewController
        
        sendVC?.startLNURLSpinner()
        
        Task {
            guard let invoice = await BitcoinManager.shared.getInvoice(
                amountMsat: UInt64(amount),
                description: "",
                expirySecs: 3600)
            else {
                DispatchQueue.main.async {
                    sendVC?.stopLNURLSpinner()
                    SentrySDK.metrics.count(key: "lnurl.withdraw.failure.4")
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "unexpectederror"), message: Language.getWord(withID: "invoicecreatefail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                return
            }
                
            DispatchQueue.main.async {
                if let invoiceHash = invoice.description.getInvoiceHash(), let paymentDetails = BitcoinManager.shared.getPaymentDetails(paymentHash: invoiceHash) {
                    CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.kind.transactionID ?? paymentDetails.id, timestamp: Int(Date().timeIntervalSince1970))
                }
            }
            
            let actualUrl = "\(callbackURL)?k1=\(k1)&pr=\(invoice)"
            print("Actual URL: \(actualUrl)")
            
            await CallsManager.makeApiCall(url: actualUrl, parameters: nil, getOrPost: .get) { result in
                DispatchQueue.main.async {
                    sendVC?.stopLNURLSpinner()
                    
                    switch result {
                    case .success(let actualDataDict):
                        guard let receivedStatus = actualDataDict["status"] as? String, receivedStatus == "OK" else {
                            SentrySDK.metrics.count(key: "lnurl.withdraw.failure.1")
                            let errorMessage:String = (actualDataDict["reason"] as? String) ?? "Unexpected error"
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "withdrawrequest"), message: "\(Language.getWord(withID: "lnurlfail1")) \(errorMessage)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                            return
                        }
                        // Successful withdrawal.
                        SentrySDK.metrics.count(key: "lnurl.withdraw.success")
                    case .failure(let error):
                        Log.info("Error: \(error.localizedDescription)")
                        SentrySDK.capture(error: error)  { scope in
                            scope.setExtra(value: "SendLNURL row 342", key: "context")
                        }
                        SentrySDK.metrics.count(key: "lnurl.withdraw.failure.3")
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                }
            }
        }
    }
    
    @objc func confirmWithdrawRequest() {
        guard let sendVC = self as? SendViewController,
              let callback = sendVC.pendingWithdrawCallback,
              let k1 = sendVC.pendingWithdrawK1,
              let minAmount = sendVC.pendingWithdrawMinAmount else {
            return
        }
        
        // Use the fixed amount (min and max are the same)
        sendWithdrawRequest(callbackURL: callback, amount: minAmount, k1: k1)
        
        // Clear pending data
        sendVC.pendingWithdrawCallback = nil
        sendVC.pendingWithdrawK1 = nil
        sendVC.pendingWithdrawMinAmount = nil
        sendVC.pendingWithdrawMaxAmount = nil
    }
    
    func showLNURLAuthConfirmation(_ request: LNURLAuthRequest) {
        guard let sendVC = self as? SendViewController else { return }
        
        let domain = request.callbackURL.host ?? "Unknown website"
        let actionText = request.action?.capitalized ?? "Authenticate"
        sendVC.pendingLnurlAuth = request
        
        sendVC.showAlert(presentingController: sendVC, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnauth1").replacingOccurrences(of: "<action>", with: actionText).replacingOccurrences(of: "<domain>", with: domain), buttons: [Language.getWord(withID: "cancel"), actionText], actions: [#selector(self.cancelLnurlAuth), #selector(self.performLnurlAuth)])
    }
    
    @objc func cancelLnurlAuth() {
        self.hideAlert()
        let sendVC = self as? SendViewController
        sendVC?.pendingLnurlAuth = nil
    }
    
    @objc func performLnurlAuth() {
        self.hideAlert()
        guard let sendVC = self as? SendViewController, let request = sendVC.pendingLnurlAuth else { return }
        sendVC.pendingLnurlAuth = nil
        sendVC.startLNURLSpinner()
        
        Task {
            do {
                guard request.callbackURL.scheme == "https" else { throw LNURLAuthError.insecureURL }
                guard request.k1.count == 32 else { throw LNURLAuthError.invalidK1 }
                guard let domain = request.callbackURL.host?.lowercased() else { throw LNURLAuthError.invalidCallbackURL }
                
                // Derive domain-specific auth private key
                guard let walletAuthSeed = getLNURLAuthSeed() else { throw LNURLAuthError.signingFailed }
                let authPrivateKey = try deriveLNURLAuthKey(forDomain: domain, walletAuthSeed: walletAuthSeed)
                
                let publicKeyHex = authPrivateKey.publicKey.dataRepresentation.hexString
                let signature = try authPrivateKey.signature(for: request.k1)
                let signatureDERHex = try signature.derRepresentation.hexString
                
                let callbackURL = try buildLNURLAuthCallbackURL(
                    baseURL: request.callbackURL,
                    k1Hex: request.k1.hexString,
                    sigHex: signatureDERHex,
                    keyHex: publicKeyHex
                )
                
                let (data, _) = try await URLSession.shared.data(from: callbackURL)
                
                let response = try JSONDecoder().decode(LNURLAuthResponse.self, from: data)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    sendVC.stopLNURLSpinner()
                    if response.status == "OK" {
                        Log.info("Successful signin.")
                        sendVC.showAlert(presentingController: sendVC, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnauth2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    } else {
                        Log.info("LNURL Auth failed: \(response.reason ?? "Unknown reason")")
                        sendVC.showAlert(presentingController: sendVC, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnauth3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                }
            } catch {
                Log.info("Error in LNURL Auth signin.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    sendVC.stopLNURLSpinner()
                    sendVC.showAlert(presentingController: sendVC, title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnauth3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "SendLNURL row 433", key: "context")
                    }
                }
            }
        }
    }
    
    func deriveLNURLAuthKey(forDomain domain: String, walletAuthSeed: Data) throws -> P256K.Signing.PrivateKey {
        let normalizedDomain = domain.lowercased()
        
        let keyMaterial = HMAC<CryptoKit.SHA256>.authenticationCode(
            for: Data(normalizedDomain.utf8),
            using: SymmetricKey(data: walletAuthSeed)
        )
        
        return try P256K.Signing.PrivateKey(dataRepresentation: Data(keyMaterial))
    }
}

extension SendViewController {
    
    func startLNURLSpinner() {
        DispatchQueue.main.async {
            self.spinnerView.alpha = 1
            self.lnurlSpinner.startAnimating()
        }
    }
    
    func stopLNURLSpinner() {
        DispatchQueue.main.async {
            self.spinnerView.alpha = 0
            self.lnurlSpinner.stopAnimating()
        }
    }
}

struct LNURLAuthRequest {
    let callbackURL: URL
    let k1: Data
    let action: String?
}

struct LNURLAuthResponse: Codable {
    let status: String
    let reason: String?
}

enum LNURLAuthError: LocalizedError {
    case invalidCallbackURL
    case insecureURL
    case invalidK1
    case invalidKey
    case signingFailed
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCallbackURL:
            return "The LNURL-auth callback URL is invalid."
        case .insecureURL:
            return "LNURL-auth requires a secure HTTPS callback URL."
        case .invalidK1:
            return "The LNURL-auth challenge is invalid."
        case .invalidKey:
            return "Could not create a valid LNURL-auth key."
        case .signingFailed:
            return "Could not sign the LNURL-auth challenge."
        case .invalidResponse:
            return "The LNURL-auth server returned an invalid response."
        case .serverError(let reason):
            return reason
        }
    }
}

func buildLNURLAuthCallbackURL(
    baseURL: URL,
    k1Hex: String,
    sigHex: String,
    keyHex: String
) throws -> URL {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    var queryItems = components?.queryItems ?? []

    queryItems.append(URLQueryItem(name: "k1", value: k1Hex))
    queryItems.append(URLQueryItem(name: "sig", value: sigHex))
    queryItems.append(URLQueryItem(name: "key", value: keyHex))

    components?.queryItems = queryItems

    guard let url = components?.url else {
        throw LNURLAuthError.invalidCallbackURL
    }

    return url
}

func getLNURLAuthSeed() -> Data? {
    guard let mnemonic = CacheManager.getMnemonic() else { return nil }
    
    let normalizedMnemonic = mnemonic
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    
    let master = SymmetricKey(data: Data(normalizedMnemonic.utf8))
    
    let authSeed = HMAC<CryptoKit.SHA256>.authenticationCode(
        for: Data("bittr-lnurl-auth-seed-v1".utf8), // Don't change this String without using version control.
        using: master
    )
    
    return Data(authSeed)
}
