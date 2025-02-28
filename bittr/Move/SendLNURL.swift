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
import LDKNodeFFI
import LightningDevKit
import Sentry
import BitcoinDevKit

extension UIViewController {
    
    func handleLNURL(code:String, sendVC:SendViewController?, receiveVC:ReceiveViewController?) {
        
        do {
            
            if sendVC != nil {
                sendVC!.startLNURLSpinner()
            }
            if receiveVC != nil {
                receiveVC!.startLNURLSpinner()
            }
            
            var url = ""
            if self.isValidEmail(code) {
                // This is an LNURL email.
                let urlDomain = String(code.split(separator: "@")[1])
                let urlUsername = String(code.split(separator: "@")[0])
                url = "https://\(urlDomain)/.well-known/lnurlp/\(urlUsername)"
            } else {
                url = try LNURLDecoder.decode(lnurl: code)
            }
            print("Decoded url: \(url)")
            
            let actualUrl = URL(string: url.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!
            print("Actual URL: \(actualUrl)")
            
            var request = URLRequest(url: actualUrl, timeoutInterval: Double.infinity)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = "GET"
            
            let task = URLSession.shared.dataTask(with: request) { data, response, dataError in
                
                if sendVC != nil {
                    sendVC!.stopLNURLSpinner()
                }
                if receiveVC != nil {
                    receiveVC!.stopLNURLSpinner()
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("Status code: \(httpResponse.statusCode)")
                    print("Headers: \(httpResponse.allHeaderFields)")
                }
                
                if let error = dataError {
                    print("Error 50: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.showAlert(title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                }
                
                guard let data = data else {
                    print("No data received. Error: \(dataError ?? "no error"). Response: \(String(describing: response)).")
                    return
                }
                
                // Response has been received.
                print("Data received: \(String(data:data, encoding:.utf8)!)")
                
                var dataDictionary:NSDictionary?
                if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                    do {
                        dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                        if let actualDataDict = dataDictionary {
                            if let receivedTag = actualDataDict["tag"] as? String {
                                
                                print("Tag: \(receivedTag)")
                                if receivedTag == "payRequest" {
                                    if let receivedCallback = actualDataDict["callback"] as? String {
                                        if let minSendable = actualDataDict["minSendable"] as? Int, let maxSendable = actualDataDict["maxSendable"] as? Int {
                                            
                                            DispatchQueue.main.async {
                                                if minSendable == maxSendable {
                                                    // Min and max are the same.
                                                    self.sendPayRequest(callbackURL: receivedCallback.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters), amount: minSendable, sendVC: sendVC, receiveVC: receiveVC)
                                                } else {
                                                    // Min and max are different. Choose amount.
                                                    let alert = UIAlertController(title: Language.getWord(withID: "payrequest"), message: "\(Language.getWord(withID: "payrequest1")) \(minSendable/1000) \(Language.getWord(withID: "payrequest2")) \(maxSendable/1000) \(Language.getWord(withID: "payrequest3"))", preferredStyle: .alert)
                                                    alert.addTextField { (textField) in
                                                        textField.keyboardType = .numberPad
                                                    }
                                                    alert.addAction(UIAlertAction(title: Language.getWord(withID: "confirm"), style: .default, handler: { (save) in
                                                        
                                                        let amountText = Int(self.stringToNumber(alert.textFields![0].text ?? "0")) * 1000
                                                        
                                                        self.sendPayRequest(callbackURL: receivedCallback.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters), amount: amountText, sendVC: sendVC, receiveVC: receiveVC)
                                                    }))
                                                    alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
                                                    self.present(alert, animated: true)
                                                }
                                            }
                                        }
                                    }
                                } else if receivedTag == "withdrawRequest" {
                                    if let receivedCallback = actualDataDict["callback"] as? String, let receivedK1 = actualDataDict["k1"] as? String, let minWithdrawable = actualDataDict["minWithdrawable"] as? Int, let maxWithdrawable = actualDataDict["maxWithdrawable"] as? Int {
                                        
                                        DispatchQueue.main.async {
                                            var alert = UIAlertController(title: Language.getWord(withID: "withdrawrequest"), message: "\(Language.getWord(withID: "withdrawrequest1")) \(minWithdrawable/1000) \(Language.getWord(withID: "payrequest2")) \(maxWithdrawable/1000) \(Language.getWord(withID: "withdrawrequest2"))", preferredStyle: .alert)
                                            if minWithdrawable == maxWithdrawable {
                                                // Min and max are the same.
                                                alert = UIAlertController(title: Language.getWord(withID: "withdrawrequest"), message: "\(Language.getWord(withID: "withdrawrequest3")) \(minWithdrawable/1000) satoshis?", preferredStyle: .alert)
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
                                                    amountText = Int(self.stringToNumber((alert.textFields![0].text ?? "0"))) * 1000
                                                }
                                                self.sendWithdrawRequest(callbackURL: receivedCallback.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters), amount: amountText, k1: receivedK1, sendVC: sendVC, receiveVC: receiveVC)
                                            }))
                                            alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
                                            self.present(alert, animated: true)
                                        }
                                    }
                                } else {
                                    DispatchQueue.main.async {
                                        self.showAlert(title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail4"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                                    }
                                }
                            }
                        }
                    } catch {
                        print("Error 111: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.showAlert(title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    }
                }
                // {"tag":"withdrawRequest","callback":"https://spiritedlizard2.lnbits.com/withdraw/api/v1/lnurl/cb/eKbrKxF2PAi8wNX65ab4HM","k1":"9YxWRdFQFSQngwM2EmuNoh","minWithdrawable":10000,"maxWithdrawable":10000,"defaultDescription":"vouchers","webhook_url":null,"webhook_headers":null,"webhook_body":null}
                
                // {"tag":"payRequest","callback":"https://spiritedlizard2.lnbits.com/lnurlp/api/v1/lnurl/cb/FRV7Uj","minSendable":10000,"maxSendable":10000,"metadata":"[[\"text/plain\", \"Payment to tom\"], [\"text/identifier\", \"tom@spiritedlizard2.lnbits.com\"]]"}
                
            }
            task.resume()
            
        } catch {
            print("Couldn't decode LNURL. Message: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.showAlert(title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
            if sendVC != nil {
                sendVC!.stopLNURLSpinner()
            }
            if receiveVC != nil {
                receiveVC!.stopLNURLSpinner()
            }
        }
    }
    
    func sendPayRequest(callbackURL:String, amount:Int, sendVC:SendViewController?, receiveVC:ReceiveViewController?) {
        
        if sendVC != nil {
            sendVC!.startLNURLSpinner()
        }
        if receiveVC != nil {
            receiveVC!.startLNURLSpinner()
        }
        
        let actualUrl = URL(string: "\(callbackURL)?amount=\(amount)".replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!
        print("Actual URL: \(actualUrl)")
        
        var request = URLRequest(url: actualUrl, timeoutInterval: Double.infinity)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, dataError in
            
            if sendVC != nil {
                sendVC!.stopLNURLSpinner()
            }
            if receiveVC != nil {
                receiveVC!.stopLNURLSpinner()
            }
            
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
            print("Data received: \(String(data:data, encoding:.utf8)!)")
            
            var dataDictionary:NSDictionary?
            if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                do {
                    dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                    if let actualDataDict = dataDictionary {
                        if let receivedInvoice = actualDataDict["pr"] as? String {
                            // Invoice received.
                            print("Invoice: \(receivedInvoice)")
                            DispatchQueue.main.async {
                                if sendVC != nil {
                                    sendVC!.confirmLightningTransaction(lnurlinvoice: receivedInvoice, sendVC: sendVC, receiveVC: receiveVC)
                                } else if receiveVC != nil {
                                    receiveVC!.confirmLightningTransaction(lnurlinvoice: receivedInvoice, sendVC: sendVC, receiveVC: receiveVC)
                                } else {
                                    let alert = UIAlertController(title: Language.getWord(withID: "invoice"), message: "\(Language.getWord(withID:"lnurlpayment"))\n\n\(receivedInvoice)", preferredStyle: .alert)
                                    alert.addAction(UIAlertAction(title: Language.getWord(withID: "copy"), style: .cancel, handler: { _ in
                                        UIPasteboard.general.string = receivedInvoice
                                    }))
                                    self.present(alert, animated: true)
                                }
                            }
                        } else if let receivedStatus = actualDataDict["status"] as? String, let receivedDetail = actualDataDict["detail"] as? String {
                            DispatchQueue.main.async {
                                self.showAlert(title: Language.getWord(withID: "payrequest"), message: "\(Language.getWord(withID: "lnurlfail2")) \(receivedDetail)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        }
                    }
                } catch {
                    print("Error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.showAlert(title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                }
            }
            
            // {"pr":"lnbc100n1pn3zxhxpp5fmfnccd92qx5e0dnm5ycavywwzgm956cnv29k6cfcdewazmg9swqhp5rn75jx56ah3q0a5dng3aqguxnyyck9638h7rmu39ce2v2nqpdnhscqzzsxqyz5vqsp52whelmgxqldxgnaj9w6p6fp8pe9excjuel9ddsfy32jy6swly5gq9qxpqysgqxpz5j6x6ypvh32acj905u7sa2sz0xwq7s6rxx96u6g7v4axamuu9qnz8uxrax3g9rt5fcw9km89208p47u9rxq9h9jja8hdvlttchfqq5nf4qv","successAction":null,"routes":[],"verify":null}
            // {"detail":"Unable to connect to https://api.getalby.com.","status":"pending"}
        }
        task.resume()
    }
    
    func sendWithdrawRequest(callbackURL:String, amount:Int, k1:String, sendVC:SendViewController?, receiveVC:ReceiveViewController?) {
        
        Task {
            do {
                
                if sendVC != nil {
                    sendVC!.startLNURLSpinner()
                }
                if receiveVC != nil {
                    receiveVC!.startLNURLSpinner()
                }
                
                let invoice = try await LightningNodeService.shared.receivePayment(
                    amountMsat: UInt64(amount),
                    description: "",
                    expirySecs: 3600
                )
                
                DispatchQueue.main.async {
                    
                    let invoiceHash = self.getInvoiceHash(invoiceString: invoice)
                    let newTimestamp = Int(Date().timeIntervalSince1970)
                    if let actualInvoiceHash = invoiceHash {
                        CacheManager.storeInvoiceTimestamp(hash: actualInvoiceHash, timestamp: newTimestamp)
                    }
                    
                    let actualUrl = URL(string: "\(callbackURL)?k1=\(k1)&pr=\(invoice)".replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!
                    print("Actual URL: \(actualUrl)")
                    
                    var request = URLRequest(url: actualUrl, timeoutInterval: Double.infinity)
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.httpMethod = "GET"
                    
                    let task = URLSession.shared.dataTask(with: request) { data, response, dataError in
                        
                        if sendVC != nil {
                            sendVC!.stopLNURLSpinner()
                        }
                        if receiveVC != nil {
                            receiveVC!.stopLNURLSpinner()
                        }
                        
                        if let httpResponse = response as? HTTPURLResponse {
                            print("Status code: \(httpResponse.statusCode)")
                            print("Headers: \(httpResponse.allHeaderFields)")
                        }
                        
                        if let error = dataError {
                            print("Error: \(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.showAlert(title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        }
                        
                        guard let data = data else {
                            print("No data received. Error: \(dataError ?? "no error"). Response: \(String(describing: response)).")
                            return
                        }
                        
                        // Response has been received.
                        print("Data received: \(String(data:data, encoding:.utf8)!)")
                        
                        // {"status":"OK"}
                        // {"status":"ERROR","reason":"LNURL already being processed."}
                        
                        var dataDictionary:NSDictionary?
                        if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                            do {
                                dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                                if let actualDataDict = dataDictionary {
                                    if let receivedStatus = actualDataDict["status"] as? String {
                                        // Response received.
                                        if receivedStatus == "OK" {
                                            // Successful withdrawal.
                                        } else if receivedStatus == "ERROR" {
                                            // There was a problem.
                                            if let receivedReason = actualDataDict["reason"] as? String {
                                                DispatchQueue.main.async {
                                                    self.showAlert(title: Language.getWord(withID: "withdrawrequest"), message: "\(Language.getWord(withID: "lnurlfail1")) \(receivedReason)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                                }
                                            }
                                        }
                                    }
                                }
                            } catch {
                                print("Error: \(error.localizedDescription)")
                                DispatchQueue.main.async {
                                    self.showAlert(title: Language.getWord(withID: "lnurl"), message: Language.getWord(withID: "lnurlfail3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                                }
                            }
                        }
                    }
                    task.resume()
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    if sendVC != nil {
                        sendVC!.stopLNURLSpinner()
                    }
                    if receiveVC != nil {
                        receiveVC!.stopLNURLSpinner()
                    }
                    self.showAlert(title: Language.getWord(withID: "error"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    SentrySDK.capture(error: error)
                }
            } catch {
                DispatchQueue.main.async {
                    if sendVC != nil {
                        sendVC!.stopLNURLSpinner()
                    }
                    if receiveVC != nil {
                        receiveVC!.stopLNURLSpinner()
                    }
                    self.showAlert(title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    SentrySDK.capture(error: error)
                }
            }
        }
    }
    
    func getInvoiceHash(invoiceString:String) -> String? {
        let result = Bolt11Invoice.fromStr(s: invoiceString)
        if result.isOk() {
            if let invoice = result.getValue() {
                print("Invoice parsed successfully: \(invoice)")
                let paymentHash:[UInt8] = invoice.paymentHash()!
                let hexString = paymentHash.map { String(format: "%02x", $0) }.joined()
                return hexString
            } else {
                return nil
            }
        } else if let error = result.getError() {
            print("Failed to parse invoice: \(error)")
            return nil
        } else {
            return nil
        }
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

extension ReceiveViewController {
    
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
