//
//  HandleLightningAddressNotification.swift
//  bittr
//
//  Created by Tom Melters on 9/9/25.
//

import UIKit
import Sentry
import LDKNode

extension CoreViewController {
    
    func handleLightningAddressNotification(_ notification: BittrNotification) {
        
        Log.info("Did call handleLightningAddressNotification.")
        
        // Extract the notification data
        guard notification.amountMsat != nil,
              notification.metadata != nil,
              notification.timeSent != nil,
              notification.username != nil,
              notification.endpoint != nil else {
            Log.info("Missing required data in lightning address notification")
            self.hidePendingView()
            self.lightningNotification = nil
            return
        }
        
        // Store LNURL notification for handling.
        self.lightningNotification = notification
        
        // Check if user is signed in
        if !self.userHasSignedIn {
            Log.info("User hasn't signed in yet, store notification for later.")
            self.wasNotified = true
            self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentrequest"), message: Language.getWord(withID: "paymentrequest2").replacingOccurrences(of: "<amount>", with: String(notification.amountMsat!/1000)), buttons: [Language.getWord(withID: "okay")], actions: nil)
        } else if !self.walletHasSynced {
            Log.info("Wallet hasn't synced yet.")
            self.pendingLabel.text = Language.getWord(withID: "syncingwallet3")
            self.showPendingView()
        } else {
            self.hidePendingView()
            if !self.wasNotified {
                Log.info("Will notify user of available LNURL notification.")
                self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentrequest"), message: Language.getWord(withID: "paymentrequest3"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "handlenow")], actions: [nil, #selector(self.handleLightningAddressNotificationImmediately)])
            } else {
                Log.info("Will handle LNURL notification now.")
                self.handleLightningAddressNotificationImmediately()
            }
        }
    }
    
    @objc func handleLightningAddressNotificationImmediately() {
        
        guard
            let notification = self.lightningNotification,
            let amountMsats = notification.amountMsat,
            let metadata = notification.metadata,
            let timeSent = notification.timeSent,
            let username = notification.username,
            let endpoint = notification.endpoint
        else {
            Log.info("Missing required data in lightning address notification")
            self.hidePendingView()
            self.lightningNotification = nil
            SentrySDK.capture(message: "Required data unavailable while trying to handle LNURL payout.") { scope in
                scope.setExtra(value: "HandlePaymentNotification row 108", key: "context")
            }
            self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentrequest"), message: Language.getWord(withID: "paymentrequestfailed2"), buttons: [Language.getWord(withID: "close")], actions: nil)
            return
        }
        
        // Show loading UI
        self.pendingLabel.text = Language.getWord(withID: "generatinginvoice")
        self.showPendingView()
        
        // Calculate SHA256 hash from metadata
        let descriptionHash = metadata.sha256()
        
        Task {
            let invoice:Bolt11Invoice
            do {
                invoice = try await BitcoinManager.shared.receivePaymentWithHash(
                    amountMsat: UInt64(amountMsats),
                    descriptionHash: descriptionHash,
                    expirySecs: 3600
                )
                Log.info("Generated invoice for lightning address payment.")
            } catch {
                Log.info("Failed to generate invoice for lightning address payment: \(error)")
                DispatchQueue.main.async {
                    // Hide loading UI
                    self.hidePendingView()
                    self.lightningNotification = nil
                    
                    // Capture Sentry error.
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "HandleLightningAddressNotification row 98", key: "context")
                    }
                    
                    // Show error message with support contact
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentrequestfailed"), message: Language.getWord(withID: "paymentrequestfailed2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                return
            }
            print("Invoice: \(invoice.description)")
            
            // Post the invoice to the specified endpoint
            let parameters: [String: Any] = [
                "invoice": invoice.description,
                "amount_msats": amountMsats,
                "description_hash": descriptionHash,
                "time_sent": timeSent,
                "username": username
            ]
            
            self.lightningNotification = nil
            await CallsManager.makeApiCall(url: endpoint, parameters: parameters, getOrPost: .post) { result in
                
                DispatchQueue.main.async {
                    self.hidePendingView()
                    
                    switch result {
                    case .success(let receivedDictionary):
                        Log.info("Successfully posted invoice to endpoint.")
                        print("Dictionary: \(receivedDictionary)")
                        // No alert needed - user will receive payment notification soon.
                    case .failure(let error):
                        Log.info("Failed to post invoice to endpoint: \(error)")
                        // Show error message with support contact
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentrequestfailed"), message: Language.getWord(withID: "paymentrequestfailed2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                }
            }
        }
    }
    
}
