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
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            defaults.removeObject(forKey: "device")
            defaults.removeObject(forKey: "cache")
            defaults.removeObject(forKey: "pin")
            defaults.removeObject(forKey: "mnemonic")
            defaults.removeObject(forKey: "lastaddress")
            defaults.removeObject(forKey: "lightning")
            self.resetFailedPinAttempts()
        } else {
            defaults.removeObject(forKey: "proddevice")
            defaults.removeObject(forKey: "prodcache")
            defaults.removeObject(forKey: "prodpin")
            defaults.removeObject(forKey: "prodmnemonic")
            defaults.removeObject(forKey: "prodlastaddress")
            defaults.removeObject(forKey: "prodlightning")
            self.resetFailedPinAttempts()
        }
    }
    
    static func deleteCache() {
        
        let defaults = UserDefaults.standard
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            defaults.removeObject(forKey: "cache")
        } else {
            defaults.removeObject(forKey: "prodcache")
        }
    }
    
    static func deleteLightningTransactions() {
        
        let defaults = UserDefaults.standard
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            defaults.removeObject(forKey: "lightning")
        } else {
            defaults.removeObject(forKey: "prodlightning")
        }
    }
    
    static func emptyImage() {
        
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "articleimages")
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
        
        var envKey = "proddevice"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "device"
        }
        let clientsDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
        
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
            UserDefaults.standard.set(updatedClientsDict, forKey: envKey)
            UserDefaults.standard.synchronize()
        } else {
            // No clients have been added yet.
            let client = Client()
            client.id = clientID
            client.order = 0
            client.ibanEntities += [iban]
            
            let clientsDict:NSDictionary = [client.id:["order":client.order,"ibans":[iban.id:["order":iban.order,"youriban":iban.yourIbanNumber, "youremail":iban.yourEmail, "yourcode":iban.yourUniqueCode, "ouriban":iban.ourIbanNumber, "ourname":iban.ourName, "token":iban.emailToken]]]]
            UserDefaults.standard.set(clientsDict, forKey: envKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    static func addEmailToken(clientID:String, ibanID:String, emailToken:String) {
        
        var envKey = "proddevice"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "device"
        }
        
        let clientsDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
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
            UserDefaults.standard.set(updatedClientsDict, forKey: envKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    static func addBittrIban(clientID:String, ibanID:String, ourIban:String, ourSwift:String, yourCode:String) {
        
        var envKey = "proddevice"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "device"
        }
        
        let clientsDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
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
            UserDefaults.standard.set(updatedClientsDict, forKey: envKey)
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
    
    
    static func getImage(key:String) -> Data? {
        
        let defaults = UserDefaults.standard
        var existingImages = defaults.value(forKey: "articleimages") as? [String:Data]
        
        if let actualExistingImages = existingImages {
            if let actualImage = actualExistingImages[key] {
                return actualImage
            }
        }
        
        return nil
    }
    
    
    static func parseTransactions(transactions:[Transaction]) -> [NSDictionary] {
        
        var transactionsDict = [NSDictionary]()
        
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
            oneTransaction.setObject(eachTransaction.channelId, forKey: "channelId" as NSCopying)
            oneTransaction.setObject(eachTransaction.isFundingTransaction, forKey: "isFundingTransaction" as NSCopying)
            oneTransaction.setObject(eachTransaction.lnDescription, forKey: "lnDescription" as NSCopying)
            oneTransaction.setObject(eachTransaction.isSwap, forKey: "isswap" as NSCopying)
            oneTransaction.setObject(eachTransaction.onchainID, forKey: "onchainid" as NSCopying)
            oneTransaction.setObject(eachTransaction.lightningID, forKey: "lightningid" as NSCopying)
            oneTransaction.setObject(eachTransaction.boltzSwapId, forKey: "boltzSwapId" as NSCopying)
            oneTransaction.setObject(eachTransaction.swapDirection, forKey: "swapdirection" as NSCopying)
            oneTransaction.setObject(eachTransaction.confirmations, forKey: "confirmations" as NSCopying)
            
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
            if let transactionChannelId = eachTransaction["channelId"] as? String {
                thisTransaction.channelId = transactionChannelId
            }
            if let transactionIsFundingTransaction = eachTransaction["isFundingTransaction"] as? Bool {
                thisTransaction.isFundingTransaction = transactionIsFundingTransaction
            }
            if let transactionLnDescription = eachTransaction["lnDescription"] as? String {
                thisTransaction.lnDescription = transactionLnDescription
            }
            if let isSwap = eachTransaction["isswap"] as? Bool {
                thisTransaction.isSwap = isSwap
            }
            if let onchainID = eachTransaction["onchainid"] as? String {
                thisTransaction.onchainID = onchainID
            }
            if let lightningID = eachTransaction["lightningid"] as? String {
                thisTransaction.lightningID = lightningID
            }
            if let boltzSwapId = eachTransaction["boltzSwapId"] as? String {
                thisTransaction.boltzSwapId = boltzSwapId
            }
            if let swapDirection = eachTransaction["swapdirection"] as? Int {
                thisTransaction.swapDirection = swapDirection
            }
            if let confirmations = eachTransaction["confirmations"] as? Int {
                thisTransaction.confirmations = confirmations
            }
            
            if thisTransaction.timestamp != 0 {
                allTransactions += [thisTransaction]
            }
        }
        
        return allTransactions
    }
    
    
    static func storeLightningTransaction(thisTransaction:Transaction) {
        
        var envKey = "prodlightning"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "lightning"
        }
        
        let defaults = UserDefaults.standard
        let existingCache = defaults.value(forKey: envKey) as? NSDictionary
        
        if let actualExistingCache = existingCache {
            // A cache already exists.
            if let actualMutableCache = actualExistingCache.mutableCopy() as? NSMutableDictionary {
                let transactionDict = self.parseTransactions(transactions: [thisTransaction])
                actualMutableCache.setObject(transactionDict[0], forKey: thisTransaction.id as NSCopying)
                defaults.set(actualMutableCache, forKey: envKey)
            }
        } else {
            // No cache exists yet.
            let newCache = NSMutableDictionary()
            let transactionDict = self.parseTransactions(transactions: [thisTransaction])
            newCache.setObject(transactionDict[0], forKey: thisTransaction.id as NSCopying)
            defaults.set(newCache, forKey: envKey)
        }
    }
    
    
    static func getLightningTransactions() -> [Transaction]? {
        
        var envKey = "prodlightning"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "lightning"
        }
        
        let defaults = UserDefaults.standard
        let cachedData = defaults.value(forKey: envKey) as? NSDictionary
        
        if let actualExistingCache = cachedData {
            var allTransactions = [NSMutableDictionary]()
            for (transactionId, transactionData) in actualExistingCache {
                allTransactions.append((transactionData as! NSDictionary).mutableCopy() as! NSMutableDictionary)
            }
            let parsedTransactions = self.getTransactions(transactionsDict: allTransactions)
            return parsedTransactions
        } else {
            return nil
        }
    }
    
    
    static func updateCachedData(data:Any, key:String) {
        
        var envKey = "prodcache"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "cache"
        }
        
        let defaults = UserDefaults.standard
        let existingCache = defaults.value(forKey: envKey) as? NSDictionary
        
        if let actualExistingCache = existingCache {
            // Cache is available.
            
            if let actualMutableCache = actualExistingCache.mutableCopy() as? NSMutableDictionary {
                if key == "balance" {
                    if let actualData = data as? String {
                        actualMutableCache.setObject(actualData, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: envKey)
                    }
                } else if key == "transactions" {
                    if let actualData = data as? [Transaction] {
                        let actualDataDict = self.parseTransactions(transactions: actualData)
                        actualMutableCache.setObject(actualDataDict, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: envKey)
                    }
                } else if key == "conversion" {
                    if let actualData = data as? String {
                        actualMutableCache.setObject(actualData, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: envKey)
                    }
                } else if key == "eurvalue" {
                    if let actualData = data as? CGFloat {
                        actualMutableCache.setObject(actualData, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: envKey)
                    }
                } else if key == "chfvalue" {
                    if let actualData = data as? CGFloat {
                        actualMutableCache.setObject(actualData, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: envKey)
                    }
                } else if key == "satsbalance" {
                    if let actualData = data as? String {
                        actualMutableCache.setObject(actualData, forKey: key as NSCopying)
                        defaults.set(actualMutableCache, forKey: envKey)
                    }
                }
            }
        } else {
            // No cache exista yet.
            
            if key == "balance" {
                if let actualData = data as? String {
                    let newCache = NSMutableDictionary()
                    newCache.setObject(actualData, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: envKey)
                }
            } else if key == "transactions" {
                if let actualData = data as? [Transaction] {
                    let newCache = NSMutableDictionary()
                    let actualDataDict = self.parseTransactions(transactions: actualData)
                    newCache.setObject(actualDataDict, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: envKey)
                }
            } else if key == "conversion" {
                if let actualData = data as? String {
                    let newCache = NSMutableDictionary()
                    newCache.setObject(actualData, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: envKey)
                }
            } else if key == "eurvalue" {
                if let actualData = data as? CGFloat {
                    let newCache = NSMutableDictionary()
                    newCache.setObject(actualData, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: envKey)
                }
            } else if key == "chfvalue" {
                if let actualData = data as? CGFloat {
                    let newCache = NSMutableDictionary()
                    newCache.setObject(actualData, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: envKey)
                }
            } else if key == "satsbalance" {
                if let actualData = data as? String {
                    let newCache = NSMutableDictionary()
                    newCache.setObject(actualData, forKey: key as NSCopying)
                    defaults.set(newCache, forKey: envKey)
                }
            }
        }
        
        
    }
    
    static func getCachedData(key:String) -> Any? {
        
        var envKey = "prodcache"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "cache"
        }
        
        let defaults = UserDefaults.standard
        let cachedData = defaults.value(forKey: envKey) as? NSDictionary
        
        if let actualCachedData = cachedData {
            
            if key == "balance" {
                if let cachedBalance = actualCachedData[key] as? String {
                    return cachedBalance
                } else {
                    return nil
                }
            } else if key == "transactions" {
                if let cachedTransactions = actualCachedData[key] as? [NSDictionary] {
                    
                    let parsedTransactions = self.getTransactions(transactionsDict: cachedTransactions)
                    
                    return parsedTransactions
                } else {
                    return nil
                }
            } else if key == "conversion" {
                if let cachedConversion = actualCachedData[key] as? String {
                    return cachedConversion
                } else {
                    return nil
                }
            } else if key == "eurvalue" {
                if let cachedEurValue = actualCachedData[key] as? CGFloat {
                    return cachedEurValue
                } else {
                    return nil
                }
            } else if key == "chfvalue" {
                if let cachedChfValue = actualCachedData[key] as? CGFloat {
                    return cachedChfValue
                } else {
                    return nil
                }
            } else if key == "satsbalance" {
                if let cachedSatsBalance = actualCachedData[key] as? String {
                    return cachedSatsBalance
                } else {
                    return nil
                }
            } else {
                return nil
            }
        } else {
            // No data has been cached yet.
            return nil
        }
    }
    
    
    static func storeNotificationsToken(token:String) {
        
        let defaults = UserDefaults.standard
        defaults.set(token, forKey: "notificationstoken")
    }
    
    static func getRegistrationToken() -> String? {
        
        let defaults = UserDefaults.standard
        let cachedToken = defaults.value(forKey: "notificationstoken") as? String
        
        if let actualCachedToken = cachedToken {
            return actualCachedToken
        } else {
            return nil
        }
    }
    
    static func storeInvoiceTimestamp(hash:String, timestamp:Int) {
        
        var envKey = "prodhashes"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "hashes"
        }
        
        let defaults = UserDefaults.standard
        let cachedHashes = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedHashes = cachedHashes {
            // Hashes have been cached.
            if let actualMutableHashes = actualCachedHashes.mutableCopy() as? NSMutableDictionary {
                actualMutableHashes.setObject(timestamp, forKey: hash as NSCopying)
                defaults.set(actualMutableHashes, forKey: envKey)
                print("Timestamp cached.")
            }
        } else {
            // No hashes have been cached.
            let actualMutableHashes = NSMutableDictionary()
            actualMutableHashes.setObject(timestamp, forKey: hash as NSCopying)
            defaults.set(actualMutableHashes, forKey: envKey)
            print("Timestamp cached.")
        }
    }
    
    static func storeInvoiceDescription(hash:String, desc:String) {
        
        var envKey = "proddescriptions"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "descriptions"
        }
        
        let defaults = UserDefaults.standard
        let cachedDescriptions = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedDescriptions = cachedDescriptions {
            // Descriptions have been cached.
            if let actualMutableDescriptions = actualCachedDescriptions.mutableCopy() as? NSMutableDictionary {
                actualMutableDescriptions.setObject(desc, forKey: hash as NSCopying)
                defaults.set(actualMutableDescriptions, forKey: envKey)
            }
        } else {
            // No descriptions have been cached.
            let actualMutableDescriptions = NSMutableDictionary()
            actualMutableDescriptions.setObject(desc, forKey: hash as NSCopying)
            defaults.set(actualMutableDescriptions, forKey: envKey)
        }
    }
    
    static func storeTransactionNote(txid:String, note:String) {
        
        var envKey = "prodtransactionnotes"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "transactionnotes"
        }
        
        let defaults = UserDefaults.standard
        let cachedTransactionNotes = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedNotes = cachedTransactionNotes {
            // Notes have been cached.
            if let actualMutableNotes = actualCachedNotes.mutableCopy() as? NSMutableDictionary {
                actualMutableNotes.setObject(note, forKey: txid as NSCopying)
                defaults.set(actualMutableNotes, forKey: envKey)
            }
        } else {
            // No notes have been cached.
            let actualMutableNotes = NSMutableDictionary()
            actualMutableNotes.setObject(note, forKey: txid as NSCopying)
            defaults.set(actualMutableNotes, forKey: envKey)
        }
    }
    
    static func storePaymentFees(hash:String, fees:Int) {
        
        var envKey = "prodlightningfees"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "lightningfees"
        }
        
        let defaults = UserDefaults.standard
        let cachedHashes = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedHashes = cachedHashes {
            // Hashes have been cached.
            if let actualMutableHashes = actualCachedHashes.mutableCopy() as? NSMutableDictionary {
                actualMutableHashes.setObject(fees, forKey: hash as NSCopying)
                defaults.set(actualMutableHashes, forKey: envKey)
                print("Lightning fees cached.")
            }
        } else {
            // No hashes have been cached.
            let actualMutableHashes = NSMutableDictionary()
            actualMutableHashes.setObject(fees, forKey: hash as NSCopying)
            defaults.set(actualMutableHashes, forKey: envKey)
            print("Lightning fees cached.")
        }
    }
    
    static func getInvoiceTimestamp(hash:String) -> Int {
        
        var envKey = "prodhashes"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "hashes"
        }
        
        let defaults = UserDefaults.standard
        let cachedHashes = defaults.value(forKey: envKey) as? NSDictionary
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
    
    static func getInvoiceDescription(hash:String) -> String {
        
        var envKey = "proddescriptions"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "descriptions"
        }
        
        let defaults = UserDefaults.standard
        let cachedDescriptions = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedDescriptions = cachedDescriptions {
            // Descriptions have been cached.
            if let foundDescription = actualCachedDescriptions[hash] as? String {
                return foundDescription
            } else {
                return ""
            }
        } else {
            // No descriptions have been cached.
            return ""
        }
    }
    
    static func getLightningFees(hash:String) -> Int {
        
        var envKey = "prodlightningfees"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "lightningfees"
        }
        
        let defaults = UserDefaults.standard
        let cachedFees = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedFees = cachedFees {
            // Descriptions have been cached.
            if let foundFees = actualCachedFees[hash] as? Int {
                return foundFees
            } else {
                return 0
            }
        } else {
            // No fees have been cached.
            return 0
        }
    }
    
    static func getTransactionNote(txid:String) -> String {
        
        var envKey = "prodtransactionnotes"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "transactionnotes"
        }
        
        let defaults = UserDefaults.standard
        let cachedNotes = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedNotes = cachedNotes {
            // Notes have been cached.
            if let foundNote = actualCachedNotes[txid] as? String {
                return foundNote
            } else {
                return ""
            }
        } else {
            // No notes have been cached.
            return ""
        }
    }
    
    static func storeMnemonic(mnemonic:String) {
        
        var envKey = "prodmnemonic"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "mnemonic"
        }
        
        let defaults = UserDefaults.standard
        defaults.set(mnemonic, forKey: envKey)
    }
    
    static func getMnemonic() -> String? {
        
        var envKey = "prodmnemonic"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "mnemonic"
        }
        
        let defaults = UserDefaults.standard
        let cachedMnemonic = defaults.value(forKey: envKey) as? String
        
        if let actualCachedMnemonic = cachedMnemonic {
            return actualCachedMnemonic
        } else {
            return nil
        }
    }
    
    static func storePin(pin:String) {
        
        var envKey = "prodpin"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "pin"
        }
        
        let defaults = UserDefaults.standard
        defaults.set(pin, forKey: envKey)
    }
    
    static func getPin() -> String? {
        
        var envKey = "prodpin"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "pin"
        }
        
        let defaults = UserDefaults.standard
        let cachedPin = defaults.value(forKey: envKey) as? String
        
        if let actualCachedPin = cachedPin {
            return actualCachedPin
        } else {
            return nil
        }
    }
    
    static func storeTxoID(txoID:String) {
        
        var envKey = "prodtxoid"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "txoid"
        }
        
        let defaults = UserDefaults.standard
        defaults.set(txoID, forKey: envKey)
    }
    
    static func getTxoID() -> String? {
        
        var envKey = "prodtxoid"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "txoid"
        }
        
        let defaults = UserDefaults.standard
        let cachedTxoID = defaults.value(forKey: envKey) as? String
        
        if let actualCachedTxoID = cachedTxoID {
            return actualCachedTxoID
        } else {
            return nil
        }
    }
    
    static func updateSentToBittr(txids:[String]) {
        
        var envKey = "prodsenttobittr"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "senttobittr"
        }
        
        let defaults = UserDefaults.standard
        let cachedSentToBittr = defaults.value(forKey: envKey) as? [String]
        
        if var actualSentToBittr = cachedSentToBittr {
            // TxIDs were stored before.
            actualSentToBittr += txids
            defaults.set(actualSentToBittr, forKey: envKey)
        } else {
            // No TxIDs were stored before.
            let newSentToBittr:[String] = txids
            defaults.setValue(newSentToBittr, forKey: envKey)
        }
    }
    
    static func getSentToBittr() -> [String]? {
        
        var envKey = "prodsenttobittr"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "senttobittr"
        }
        
        let defaults = UserDefaults.standard
        let cachedSentToBittr = defaults.value(forKey: envKey) as? [String]
        
        if let actualSentToBittr = cachedSentToBittr {
            return actualSentToBittr
        } else {
            return nil
        }
    }
    
    static func storeLastAddress(newAddress:String) {
        
        var envKey = "prodlastaddress"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "lastaddress"
        }
        
        let defaults = UserDefaults.standard
        defaults.set(newAddress, forKey: envKey)
    }
    
    static func getLastAddress() -> String? {
        
        var envKey = "prodlastaddress"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "lastaddress"
        }
        
        let defaults = UserDefaults.standard
        let cachedLastAddress = defaults.value(forKey: envKey) as? String
        if let actualLastAddress = cachedLastAddress {
            return actualLastAddress
        } else {
            return nil
        }
    }
    
    static func getFailedPinAttempts() -> Int {
        
        var envKey = "prodfailedattempts"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "failedattempts"
        }
        
        let defaults = UserDefaults.standard
        let cachedFailedAttempts = defaults.value(forKey: envKey) as? Int
        if let actualCachedAttempts = cachedFailedAttempts {
            return actualCachedAttempts
        } else {
            return 0
        }
    }
    
    static func increaseFailedPinAttempts() {
        
        var envKey = "prodfailedattempts"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "failedattempts"
        }
        
        let defaults = UserDefaults.standard
        let cachedFailedAttempts = defaults.value(forKey: envKey) as? Int
        if var actualCachedAttempts = cachedFailedAttempts {
            actualCachedAttempts += 1
            defaults.set(actualCachedAttempts, forKey: envKey)
        } else {
            defaults.set(1, forKey: envKey)
        }
    }
    
    static func resetFailedPinAttempts() {
        
        var envKey = "prodfailedattempts"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "failedattempts"
        }
        
        let defaults = UserDefaults.standard
        defaults.set(0, forKey: envKey)
    }
    
    static func didHandleEvent(event:String) {
        
        let defaults = UserDefaults.standard
        let handledEvents = defaults.value(forKey: "handledevents") as? [String]
        
        if var actualHandledEvents = handledEvents {
            // Events were stored before.
            actualHandledEvents += [event]
            defaults.set(actualHandledEvents, forKey: "handledevents")
        } else {
            // No events were stored before.
            let newHandledEvents:[String] = [event]
            defaults.setValue(newHandledEvents, forKey: "handledevents")
        }
    }
    
    static func hasHandledEvent(event:String) -> Bool {
        
        let defaults = UserDefaults.standard
        let handledEvents = defaults.value(forKey: "handledevents") as? [String]
        
        if let actualHandledEvents = handledEvents {
            // Events were stored before.
            if actualHandledEvents.contains(event) {
                // Event was handled before.
                return true
            } else {
                // Event wasn't handled before.
                return false
            }
        } else {
            // No events were stored before.
            return false
        }
    }
    
    static func storeLatestNotification(specialData:[String: Any]) {
        let defaults = UserDefaults.standard
        defaults.set(specialData, forKey: "lastbittrpayoutnotification")
    }
    
    static func getLatestNotification() -> [String: Any]? {
        let defaults = UserDefaults.standard
        let latestNotification = defaults.value(forKey: "lastbittrpayoutnotification") as? [String: Any]
        
        if let actualLatestNotification = latestNotification {
            return actualLatestNotification
        } else {
            return nil
        }
    }
    
    static func updateDarkMode(isOn:Bool) {
        UserDefaults.standard.set(isOn, forKey: "darkmode")
    }
    
    static func darkModeIsOn() -> Bool {
        
        if let darkModeStatus = UserDefaults.standard.value(forKey: "darkmode") as? Bool {
            return darkModeStatus
        } else {
            return false
        }
    }
    
    static func getLanguage() -> String {
        
        if let selectedLanguage = UserDefaults.standard.value(forKey: "language") as? String {
            return selectedLanguage
        } else {
            return "en_US"
        }
    }
    
    static func changeLanguage(_ toLanguage:String) {
        UserDefaults.standard.set(toLanguage, forKey: "language")
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecolors"), object: nil, userInfo: nil) as Notification)
    }
    
    static func saveLatestSwap(_ latestSwap:NSDictionary?) {
        if latestSwap != nil {
            UserDefaults.standard.set(latestSwap!, forKey: "ongoingswap")
        } else {
            if let storedSwap = UserDefaults.standard.value(forKey: "ongoingswap") as? NSDictionary {
                UserDefaults.standard.removeObject(forKey: "ongoingswap")
            }
        }
    }
    
    static func getLatestSwap() -> NSDictionary? {
        if let storedSwap = UserDefaults.standard.value(forKey: "ongoingswap") as? NSDictionary {
            return storedSwap
        } else {
            return nil
        }
    }
    
}
