//
//  SendLNURL.swift
//  bittr
//
//  Created by Tom Melters on 17/10/2024.
//

import LNURLDecoder
import UIKit

extension SendViewController {
    
    func handleLNURL(code:String) {
        
        do {
            let url = try LNURLDecoder.decode(lnurl: code)
            print("Decoded url: \(url)")
            
            let actualUrl = URL(string: url.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!
            print("Actual URL: \(actualUrl)")
            
            var request = URLRequest(url: actualUrl, timeoutInterval: Double.infinity)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = "GET"
            
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
                                                let alert = UIAlertController(title: Language.getWord(withID: "payrequest"), message: "\(Language.getWord(withID: "payrequest1")) \(minSendable/1000) \(Language.getWord(withID: "payrequest2")) \(maxSendable/1000) \(Language.getWord(withID: "payrequest3"))", preferredStyle: .alert)
                                                alert.addTextField { (textField) in
                                                    textField.keyboardType = .numberPad
                                                }
                                                alert.addAction(UIAlertAction(title: Language.getWord(withID: "confirm"), style: .default, handler: { (save) in
                                                    
                                                    let amountText = Int(CGFloat(truncating: NumberFormatter().number(from: (alert.textFields![0].text ?? "0").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!)) * 1000
                                                    
                                                    self.sendPayRequest(callbackURL: receivedCallback.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters), amount: amountText)
                                                }))
                                                alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
                                                self.present(alert, animated: true)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } catch {
                        print("Error: \(error.localizedDescription)")
                    }
                }
                // {"tag":"withdrawRequest","callback":"https://spiritedlizard2.lnbits.com/withdraw/api/v1/lnurl/cb/eKbrKxF2PAi8wNX65ab4HM","k1":"9YxWRdFQFSQngwM2EmuNoh","minWithdrawable":10000,"maxWithdrawable":10000,"defaultDescription":"vouchers","webhook_url":null,"webhook_headers":null,"webhook_body":null}
                
                // {"tag":"payRequest","callback":"https://spiritedlizard2.lnbits.com/lnurlp/api/v1/lnurl/cb/FRV7Uj","minSendable":10000,"maxSendable":10000,"metadata":"[[\"text/plain\", \"Payment to tom\"], [\"text/identifier\", \"tom@spiritedlizard2.lnbits.com\"]]"}
                
            }
            task.resume()
            
        } catch {
            print("Couldn't decode LNURL. Message: \(error.localizedDescription)")
        }
    }
    
    func sendPayRequest(callbackURL:String, amount:Int) {
        
        let actualUrl = URL(string: "\(callbackURL)?amount=\(amount)".replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!
        print("Actual URL: \(actualUrl)")
        
        var request = URLRequest(url: actualUrl, timeoutInterval: Double.infinity)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        
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
                                self.confirmLightningTransaction(lnurlinvoice: receivedInvoice)
                            }
                        }
                    }
                } catch {
                    print("Error: \(error.localizedDescription)")
                }
            }
            
            // {"pr":"lnbc100n1pn3zxhxpp5fmfnccd92qx5e0dnm5ycavywwzgm956cnv29k6cfcdewazmg9swqhp5rn75jx56ah3q0a5dng3aqguxnyyck9638h7rmu39ce2v2nqpdnhscqzzsxqyz5vqsp52whelmgxqldxgnaj9w6p6fp8pe9excjuel9ddsfy32jy6swly5gq9qxpqysgqxpz5j6x6ypvh32acj905u7sa2sz0xwq7s6rxx96u6g7v4axamuu9qnz8uxrax3g9rt5fcw9km89208p47u9rxq9h9jja8hdvlttchfqq5nf4qv","successAction":null,"routes":[],"verify":null}
        }
        task.resume()
    }
}
