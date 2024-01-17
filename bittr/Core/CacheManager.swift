//
//  CacheManager.swift
//  bittr
//
//  Created by Tom Melters on 24/06/2023.
//

import UIKit

class CacheManager: NSObject {
    
    
    static func deleteClientInfo() {
        
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "device")
        defaults.removeObject(forKey: "cache")
        defaults.removeObject(forKey: "pin")
        defaults.removeObject(forKey: "mnemonic")
    }
    
    static func deleteCache() {
        
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "cache")
    }
    
    
    static func parseDevice(deviceDict:NSDictionary) -> [Client] {
        
        var allClients = [Client]()
        
        for (clientid, clientdata) in deviceDict {
            
            let client = Client()
            
            if let actualClientDict = clientdata as? NSDictionary {
                
                if let actualClientID = clientid as? String {
                    client.id = actualClientID
                }
                if let actualClientOrder = actualClientDict["order"] as? Int {
                    client.order = actualClientOrder
                }
                var ibansInClient = [IbanEntity]()
                if let actualIbansDict = actualClientDict["ibans"] as? NSDictionary {
                    
                    for (ibanid, ibandata) in actualIbansDict {
                        
                        let iban = IbanEntity()
                        
                        if let ibanDataDict = ibandata as? NSDictionary {
                            
                            if let actualIbanID = ibanid as? String {
                                iban.id = actualIbanID
                            }
                            if let actualYourIban = ibanDataDict["youriban"] as? String {
                                iban.yourIbanNumber = actualYourIban
                            }
                            if let actualYourEmail = ibanDataDict["youremail"] as? String {
                                iban.yourEmail = actualYourEmail
                            }
                            if let actualYourCode = ibanDataDict["yourcode"] as? String {
                                iban.yourUniqueCode = actualYourCode
                            }
                            if let actualOurIban = ibanDataDict["ouriban"] as? String {
                                iban.ourIbanNumber = actualOurIban
                            }
                            if let actualOurName = ibanDataDict["ourname"] as? String {
                                iban.ourName = actualOurName
                            }
                            if let actualIbanOrder = ibanDataDict["order"] as? Int {
                                iban.order = actualIbanOrder
                            }
                            if let actualIbanToken = ibanDataDict["token"] as? String {
                                iban.emailToken = actualIbanToken
                            }
                            
                            ibansInClient += [iban]
                        }
                    }
                    
                    client.ibanEntities = ibansInClient
                    client.ibanEntities.sort { iban1, iban2 in
                        iban1.order < iban2.order
                    }
                }
            }
            
            allClients += [client]
        }
        
        allClients.sort { client1, client2 in
            client1.order < client2.order
        }
        
        return allClients
    }
    
    
    static func addIban(clientID:String,iban:IbanEntity) {
        
        let clientsDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
        
        if let actualClientsDict = clientsDict {
            // At least one client already exists.
            let clients = self.parseDevice(deviceDict: actualClientsDict)
            for client in clients {
                if client.id == clientID {
                    var ibanExists = false
                    for existingIban in client.ibanEntities {
                        if existingIban.id == iban.id {
                            ibanExists = true
                            existingIban.yourIbanNumber = iban.yourIbanNumber
                            existingIban.yourEmail = iban.yourEmail
                        }
                    }
                    if ibanExists == false {
                        // This is a new IBAN entity.
                        client.ibanEntities += [iban]
                    }
                }
            }
            
            var updatedClientsDict = NSMutableDictionary()
            for client in clients {
                var ibansDict = NSMutableDictionary()
                for existingIban in client.ibanEntities {
                    ibansDict.setObject(["order":existingIban.order,"youriban":existingIban.yourIbanNumber, "youremail":existingIban.yourEmail, "yourcode":existingIban.yourUniqueCode, "ouriban":existingIban.ourIbanNumber, "ourname":existingIban.ourName, "token":existingIban.emailToken, "ourswift":existingIban.ourSwift], forKey: existingIban.id as NSCopying)
                }
                updatedClientsDict.setObject(["order":client.order, "ibans":ibansDict], forKey: client.id as NSCopying)
            }
            UserDefaults.standard.set(updatedClientsDict, forKey: "device")
            UserDefaults.standard.synchronize()
        } else {
            // No clients have been added yet.
            let client = Client()
            client.id = clientID
            client.order = 0
            client.ibanEntities += [iban]
            
            let clientsDict:NSDictionary = [client.id:["order":client.order,"ibans":[iban.id:["order":iban.order,"youriban":iban.yourIbanNumber, "youremail":iban.yourEmail, "yourcode":iban.yourUniqueCode, "ouriban":iban.ourIbanNumber, "ourname":iban.ourName, "token":iban.emailToken]]]]
            UserDefaults.standard.set(clientsDict, forKey: "device")
            UserDefaults.standard.synchronize()
        }
    }
    
    static func addEmailToken(clientID:String, ibanID:String, emailToken:String) {
        
        let clientsDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
        if let actualClientsDict = clientsDict {
            
            let clients = self.parseDevice(deviceDict: actualClientsDict)
            
            for client in clients {
                if client.id == clientID {
                    for iban in client.ibanEntities {
                        if iban.id == ibanID {
                            iban.emailToken = emailToken
                        }
                    }
                }
            }
            
            var updatedClientsDict = NSMutableDictionary()
            for client in clients {
                var ibansDict = NSMutableDictionary()
                for iban in client.ibanEntities {
                    ibansDict.setObject(["order":iban.order,"youriban":iban.yourIbanNumber, "youremail":iban.yourEmail, "yourcode":iban.yourUniqueCode, "ouriban":iban.ourIbanNumber, "ourname":iban.ourName, "token":iban.emailToken, "ourswift":iban.ourSwift], forKey: iban.id as NSCopying)
                }
                updatedClientsDict.setObject(["order":client.order, "ibans":ibansDict], forKey: client.id as NSCopying)
            }
            UserDefaults.standard.set(updatedClientsDict, forKey: "device")
            UserDefaults.standard.synchronize()
        }
    }
    
    static func addBittrIban(clientID:String, ibanID:String, ourIban:String, ourSwift:String, yourCode:String) {
        
        let clientsDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
        if let actualClientsDict = clientsDict {
            
            let clients = self.parseDevice(deviceDict: actualClientsDict)
            
            for client in clients {
                if client.id == clientID {
                    for iban in client.ibanEntities {
                        if iban.id == ibanID {
                            iban.ourIbanNumber = ourIban
                            iban.yourUniqueCode = yourCode
                            iban.ourSwift = ourSwift
                        }
                    }
                }
            }
            
            var updatedClientsDict = NSMutableDictionary()
            for client in clients {
                var ibansDict = NSMutableDictionary()
                for iban in client.ibanEntities {
                    ibansDict.setObject(["order":iban.order,"youriban":iban.yourIbanNumber, "youremail":iban.yourEmail, "yourcode":iban.yourUniqueCode, "ouriban":iban.ourIbanNumber, "ourname":iban.ourName, "token":iban.emailToken, "ourswift":iban.ourSwift], forKey: iban.id as NSCopying)
                }
                updatedClientsDict.setObject(["order":client.order, "ibans":ibansDict], forKey: client.id as NSCopying)
            }
            UserDefaults.standard.set(updatedClientsDict, forKey: "device")
            UserDefaults.standard.synchronize()
        }
    }
    
    
    static func storeImageInCache(key:String, data:Data) {
        let defaults = UserDefaults.standard
        var existingImages = defaults.value(forKey: "articleimages") as? [String:Data]
        if var actualExistingImages = existingImages {
            // Images have already been stored.
            actualExistingImages.updateValue(data, forKey: key)
            defaults.set(actualExistingImages, forKey: "articleimages")
        } else {
            // No images have been stored yet.
            var newExistingImages = [String:Data]()
            newExistingImages.updateValue(data, forKey: key)
            defaults.set(newExistingImages, forKey: "articleimages")
        }
    }
    
    
    static func getImage(key:String) -> Data {
        
        let defaults = UserDefaults.standard
        var existingImages = defaults.value(forKey: "articleimages") as? [String:Data]
        
        if let actualExistingImages = existingImages {
            if let actualImage = actualExistingImages[key] {
                return actualImage
            }
        }
        
        return Data()
    }
    
    
    static func parseTransactions(transactions:[Transaction]) -> [NSDictionary] {
        
        var transactionsDict = [NSDictionary()]
        
        for eachTransaction in transactions {
            
            let oneTransaction = NSMutableDictionary()
            oneTransaction.setObject(eachTransaction.id, forKey: "id" as NSCopying)
            oneTransaction.setObject(eachTransaction.purchaseAmount, forKey: "purchaseAmount" as NSCopying)
            oneTransaction.setObject(eachTransaction.received, forKey: "received" as NSCopying)
            oneTransaction.setObject(eachTransaction.sent, forKey: "sent" as NSCopying)
            oneTransaction.setObject(eachTransaction.isBittr, forKey: "isBittr" as NSCopying)
            oneTransaction.setObject(eachTransaction.timestamp, forKey: "timestamp" as NSCopying)
            oneTransaction.setObject(eachTransaction.currency, forKey: "currency" as NSCopying)
            oneTransaction.setObject(eachTransaction.height, forKey: "height" as NSCopying)
            oneTransaction.setObject(eachTransaction.isLightning, forKey: "isLightning" as NSCopying)
            oneTransaction.setObject(eachTransaction.fee, forKey: "fee" as NSCopying)
            
            transactionsDict += [oneTransaction]
        }
        
        return transactionsDict
    }
    
    static func getTransactions(transactionsDict:[NSDictionary]) -> [Transaction] {
        
        var allTransactions = [Transaction]()
        
        for eachTransaction in transactionsDict {
            
            let thisTransaction = Transaction()
            if let transactionID = eachTransaction["id"] as? String {
                thisTransaction.id = transactionID
            }
            if let transactionPurchase = eachTransaction["purchaseAmount"] as? Int {
                thisTransaction.purchaseAmount = transactionPurchase
            }
            if let transactionReceived = eachTransaction["received"] as? Int {
                thisTransaction.received = transactionReceived
            }
            if let transactionSent = eachTransaction["sent"] as? Int {
                thisTransaction.sent = transactionSent
            }
            if let transactionBittr = eachTransaction["isBittr"] as? Bool {
                thisTransaction.isBittr = transactionBittr
            }
            if let transactionTimestamp = eachTransaction["timestamp"] as? Int {
                thisTransaction.timestamp = transactionTimestamp
            }
            if let transactionCurrency = eachTransaction["currency"] as? String {
                thisTransaction.currency = transactionCurrency
            }
            if let transactionHeight = eachTransaction["height"] as? Int {
                thisTransaction.height = transactionHeight
            }
            if let transactionLightning = eachTransaction["isLightning"] as? Bool {
                thisTransaction.isLightning = transactionLightning
            }
            if let transactionFee = eachTransaction["fee"] as? Int {
                thisTransaction.fee = transactionFee
            }
            
            allTransactions += [thisTransaction]
        }
        
        return allTransactions
    }
    
    
    static func updateCachedData(data:Any, key:String) {
        
        let defaults = UserDefaults.standard
        let existingCache = defaults.value(forKey: "cache") as? NSDictionary
        
        if let actualExistingCache = existingCache {
            // Cache is available.
            
            if let actualMutableCache = actualExistingCache.mutableCopy() as? NSMutableDictionary {
                if key == "balance" {
                    if let actualData = data as? String {
                        actualMutableCache.setObject(actualData, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: "cache")
                    }
                } else if key == "transactions" {
                    if let actualData = data as? [Transaction] {
                        let actualDataDict = self.parseTransactions(transactions: actualData)
                        actualMutableCache.setObject(actualDataDict, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: "cache")
                    }
                } else if key == "conversion" {
                    if let actualData = data as? String {
                        actualMutableCache.setObject(actualData, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: "cache")
                    }
                } else if key == "eurvalue" {
                    if let actualData = data as? CGFloat {
                        actualMutableCache.setObject(actualData, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: "cache")
                    }
                } else if key == "chfvalue" {
                    if let actualData = data as? CGFloat {
                        actualMutableCache.setObject(actualData, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: "cache")
                    }
                }
            }
        } else {
            // No cache exista yet.
            
            if key == "balance" {
                if let actualData = data as? String {
                    let newCache = NSMutableDictionary()
                    newCache.setObject(actualData, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: "cache")
                }
            } else if key == "transactions" {
                if let actualData = data as? [Transaction] {
                    let newCache = NSMutableDictionary()
                    let actualDataDict = self.parseTransactions(transactions: actualData)
                    newCache.setObject(actualDataDict, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: "cache")
                }
            } else if key == "conversion" {
                if let actualData = data as? String {
                    let newCache = NSMutableDictionary()
                    newCache.setObject(actualData, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: "cache")
                }
            } else if key == "eurvalue" {
                if let actualData = data as? CGFloat {
                    let newCache = NSMutableDictionary()
                    newCache.setObject(actualData, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: "cache")
                }
            } else if key == "chfvalue" {
                if let actualData = data as? CGFloat {
                    let newCache = NSMutableDictionary()
                    newCache.setObject(actualData, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: "cache")
                }
            }
        }
        
        
    }
    
    static func getCachedData(key:String) -> Any {
        
        let defaults = UserDefaults.standard
        let cachedData = defaults.value(forKey: "cache") as? NSDictionary
        
        if let actualCachedData = cachedData {
            
            if key == "balance" {
                if let cachedBalance = actualCachedData[key] as? String {
                    return cachedBalance
                } else {
                    return "empty"
                }
            } else if key == "transactions" {
                if let cachedTransactions = actualCachedData[key] as? [NSDictionary] {
                    
                    let parsedTransactions = self.getTransactions(transactionsDict: cachedTransactions)
                    
                    return parsedTransactions
                } else {
                    return "empty"
                }
            } else if key == "conversion" {
                if let cachedConversion = actualCachedData[key] as? String {
                    return cachedConversion
                } else {
                    return "empty"
                }
            } else if key == "eurvalue" {
                if let cachedEurValue = actualCachedData[key] as? CGFloat {
                    return cachedEurValue
                } else {
                    return "empty"
                }
            } else if key == "chfvalue" {
                if let cachedChfValue = actualCachedData[key] as? CGFloat {
                    return cachedChfValue
                } else {
                    return "empty"
                }
            } else {
                return "empty"
            }
        } else {
            // No data has been cached yet.
            return "empty"
        }
    }
    
    
    static func storeNotificationsToken(token:String) {
        
        let defaults = UserDefaults.standard
        defaults.set(token, forKey: "notificationstoken")
    }
    
    static func getRegistrationToken() -> String {
        
        let defaults = UserDefaults.standard
        let cachedToken = defaults.value(forKey: "notificationstoken") as? String
        
        if let actualCachedToken = cachedToken {
            return actualCachedToken
        } else {
            return "empty"
        }
    }
    
    static func storeInvoiceTimestamp(hash:String, timestamp:Int) {
        
        let defaults = UserDefaults.standard
        let cachedHashes = defaults.value(forKey: "hashes") as? NSDictionary
        if let actualCachedHashes = cachedHashes {
            // Hashes have been cached.
            if let actualMutableHashes = actualCachedHashes.mutableCopy() as? NSMutableDictionary {
                actualMutableHashes.setObject(timestamp, forKey: hash as NSCopying)
                defaults.set(actualMutableHashes, forKey: "hashes")
                print("Timestamp cached.")
            }
        } else {
            // No hashes have been cached.
            let actualMutableHashes = NSMutableDictionary()
            actualMutableHashes.setObject(timestamp, forKey: hash as NSCopying)
            defaults.set(actualMutableHashes, forKey: "hashes")
            print("Timestamp cached.")
        }
    }
    
    static func getInvoiceTimestamp(hash:String) -> Int {
        
        let defaults = UserDefaults.standard
        let cachedHashes = defaults.value(forKey: "hashes") as? NSDictionary
        if let actualCachedHashes = cachedHashes {
            // Hashes have been cached.
            if let foundTimestamp = actualCachedHashes[hash] as? Int {
                return foundTimestamp
            } else {
                self.storeInvoiceTimestamp(hash: hash, timestamp: Int(Date().timeIntervalSince1970))
                return Int(Date().timeIntervalSince1970)
            }
        } else {
            // No hashes have been cached.
            self.storeInvoiceTimestamp(hash: hash, timestamp: Int(Date().timeIntervalSince1970))
            return Int(Date().timeIntervalSince1970)
        }
    }
    
    static func storeMnemonic(mnemonic:String) {
        let defaults = UserDefaults.standard
        defaults.set(mnemonic, forKey: "mnemonic")
    }
    
    static func getMnemonic() -> String {
        
        let defaults = UserDefaults.standard
        let cachedMnemonic = defaults.value(forKey: "mnemonic") as? String
        
        if let actualCachedMnemonic = cachedMnemonic {
            return actualCachedMnemonic
        } else {
            return "empty"
        }
    }
    
    static func storePin(pin:String) {
        let defaults = UserDefaults.standard
        defaults.set(pin, forKey: "pin")
    }
    
    static func getPin() -> String {
        
        let defaults = UserDefaults.standard
        let cachedPin = defaults.value(forKey: "pin") as? String
        
        if let actualCachedPin = cachedPin {
            return actualCachedPin
        } else {
            return "empty"
        }
    }
    
}
