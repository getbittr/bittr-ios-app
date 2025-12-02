//
//  HandleLightningAddressNotification.swift
//  bittr
//
//  Created by Tom Melters on 9/9/25.
//

import UIKit
import Sentry

extension CoreViewController {
    
    @objc func handleLightningAddressNotification(notification: NSNotification) {
        
        if let userInfo = notification.userInfo as? [String: Any] {
            Log.info("Received lightning address notification.")
            print("User info: \(userInfo)")
            
            // Extract the notification data
            guard let amountMsats = userInfo["amount_msats"] as? Int,
                  let metadata = userInfo["metadata"] as? String,
                  let timeSent = userInfo["time_sent"] as? String,
                  let username = userInfo["username"] as? String,
                  let endpoint = userInfo["endpoint"] as? String else {
                Log.info("Missing required data in lightning address notification")
                return
            }
            
            // Calculate SHA256 hash from metadata
            let descriptionHash = metadata.sha256()
            
            // Check if user is signed in
            if self.userDidSignIn {
                // User is signed in, handle notification immediately
                self.handleLightningAddressNotificationImmediately(amountMsats: amountMsats, descriptionHash: descriptionHash, timeSent: timeSent, username: username, endpoint: endpoint)
                
                // Clear the flag after handling
                UserDefaults.standard.set(false, forKey: "receivedNotificationWhileClosed")
            } else {
                // User hasn't signed in yet, store notification for later
                self.needsToHandleNotification = true
                self.wasNotified = true
                self.lightningNotification = notification
                
                self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentrequest"), message: Language.getWord(withID: "paymentrequest2").replacingOccurrences(of: "<amount>", with: String(amountMsats/1000)), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        }
    }
    
    private func handleLightningAddressNotificationImmediately(amountMsats: Int, descriptionHash: String, timeSent: String, username: String, endpoint: String) {
        
        // Show loading UI
        self.pendingLabel.text = Language.getWord(withID: "generatinginvoice")
        self.showPendingView()
        
        Task {
            do {
                let invoice = try await LightningNodeService.shared.receivePaymentWithHash(
                    amountMsat: UInt64(amountMsats),
                    descriptionHash: descriptionHash,
                    expirySecs: 3600
                )
                
                Log.info("Generated invoice for lightning address payment.")
                print("Invoice: \(invoice.description)")
                
                // Post the invoice to the specified endpoint
                let parameters: [String: Any] = [
                    "invoice": invoice.description,
                    "amount_msats": amountMsats,
                    "description_hash": descriptionHash,
                    "time_sent": timeSent,
                    "username": username
                ]
                
                await CallsManager.makeApiCall(url: endpoint, parameters: parameters, getOrPost: .post) { result in
                    
                    DispatchQueue.main.async {
                        self.hidePendingView()
                        
                        switch result {
                        case .success(let receivedDictionary):
                            Log.info("Successfully posted invoice to endpoint.")
                            print("Dictionary: \(receivedDictionary)")
                            // No alert needed - user will receive payment notification soon
                            
                        case .failure(let error):
                            Log.info("Failed to post invoice to endpoint: \(error)")
                            // Show error message with support contact
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentrequestfailed"), message: Language.getWord(withID: "paymentrequestfailed2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    }
                }
                
            } catch {
                Log.info("Failed to generate invoice for lightning address payment: \(error)")
                
                DispatchQueue.main.async {
                    // Hide loading UI
                    self.hidePendingView()
                    
                    // Capture Sentry error.
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "HandleLightningAddressNotification row 98", key: "context")
                    }
                    
                    // Show error message with support contact
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentrequestfailed"), message: Language.getWord(withID: "paymentrequestfailed2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        }
    }
    
}
