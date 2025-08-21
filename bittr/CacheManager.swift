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
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "device"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "cache"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "pin"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "mnemonic"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "lastaddress"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "lightning"))
        self.resetFailedPinAttempts()
    }
    
    static func deleteCache() {
        
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "cache"))
    }
    
    static func deleteLightningTransactions() {
        
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "lightning"))
    }
    
    static func emptyImage() {
        
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "articleimages")
    }
    
    
    static func parseDevice(deviceDict:NSDictionary) -> BittrWallet {
        
        let bittrWallet = BittrWallet()
        
        for (_, clientdata) in deviceDict {
            if let actualClientDict = clientdata as? NSDictionary {
                if let actualIbansDict = actualClientDict["ibans"] as? NSDictionary {
                    
                    var ibansInClient = [IbanEntity]()
                    
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
                    
                    bittrWallet.ibanEntities = ibansInClient
                    bittrWallet.ibanEntities.sort { iban1, iban2 in
                        iban1.order < iban2.order
                    }
                }
            }
        }
        
        return bittrWallet
    }
    
    
    static func addIban(iban:IbanEntity) {
        
        let envKey = EnvironmentConfig.deviceCacheKey
        
        if let clientsDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary {
            // Client already exists.
            
            let bittrWallet = self.parseDevice(deviceDict: clientsDict)
            
            var ibanExists = false
            for existingIban in bittrWallet.ibanEntities {
                if existingIban.id == iban.id {
                    ibanExists = true
                    existingIban.yourIbanNumber = iban.yourIbanNumber
                    existingIban.yourEmail = iban.yourEmail
                }
            }
            if ibanExists == false {
                // This is a new IBAN entity.
                bittrWallet.ibanEntities += [iban]
            }
            
            let ibansDict = NSMutableDictionary()
            for existingIban in bittrWallet.ibanEntities {
                ibansDict.setObject(["order":existingIban.order,"youriban":existingIban.yourIbanNumber, "youremail":existingIban.yourEmail, "yourcode":existingIban.yourUniqueCode, "ouriban":existingIban.ourIbanNumber, "ourname":existingIban.ourName, "token":existingIban.emailToken, "ourswift":existingIban.ourSwift], forKey: existingIban.id as NSCopying)
            }
            let updatedClientsDict = NSMutableDictionary()
            updatedClientsDict.setObject(["ibans":ibansDict], forKey: "bittrwallet" as NSCopying)
            UserDefaults.standard.set(updatedClientsDict, forKey: envKey)
            UserDefaults.standard.synchronize()
        } else {
            // No client exists yet.
            let clientsDict:NSDictionary = ["bittrwallet":["ibans":[iban.id:["order":iban.order,"youriban":iban.yourIbanNumber, "youremail":iban.yourEmail, "yourcode":iban.yourUniqueCode, "ouriban":iban.ourIbanNumber, "ourname":iban.ourName, "token":iban.emailToken]]]]
            UserDefaults.standard.set(clientsDict, forKey: envKey)
            UserDefaults.standard.synchronize()
        }
        
    }
    
    static func addEmailToken(ibanID:String, emailToken:String) {
        
        let envKey = EnvironmentConfig.deviceCacheKey
        
        if let clientsDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary {
            
            let bittrWallet = self.parseDevice(deviceDict: clientsDict)
            
            for eachIbanEntity in bittrWallet.ibanEntities {
                if eachIbanEntity.id == ibanID {
                    eachIbanEntity.emailToken = emailToken
                }
            }
            
            let ibansDict = NSMutableDictionary()
            for eachIbanEntity in bittrWallet.ibanEntities {
                ibansDict.setObject(["order":eachIbanEntity.order,"youriban":eachIbanEntity.yourIbanNumber, "youremail":eachIbanEntity.yourEmail, "yourcode":eachIbanEntity.yourUniqueCode, "ouriban":eachIbanEntity.ourIbanNumber, "ourname":eachIbanEntity.ourName, "token":eachIbanEntity.emailToken, "ourswift":eachIbanEntity.ourSwift], forKey: eachIbanEntity.id as NSCopying)
            }
            let updatedClientsDict = NSMutableDictionary()
            updatedClientsDict.setObject(["ibans":ibansDict], forKey: "bittrwallet" as NSCopying)
            UserDefaults.standard.set(updatedClientsDict, forKey: envKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    static func addBittrIban(ibanID:String, ourIban:String, ourSwift:String, yourCode:String) {
        
        let envKey = EnvironmentConfig.deviceCacheKey
        
        if let clientsDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary {
            
            let bittrWallet = self.parseDevice(deviceDict: clientsDict)
            
            for eachIbanEntity in bittrWallet.ibanEntities {
                if eachIbanEntity.id == ibanID {
                    eachIbanEntity.ourIbanNumber = ourIban
                    eachIbanEntity.yourUniqueCode = yourCode
                    eachIbanEntity.ourSwift = ourSwift
                }
            }
            
            let ibansDict = NSMutableDictionary()
            for eachIbanEntity in bittrWallet.ibanEntities {
                ibansDict.setObject(["order":eachIbanEntity.order,"youriban":eachIbanEntity.yourIbanNumber, "youremail":eachIbanEntity.yourEmail, "yourcode":eachIbanEntity.yourUniqueCode, "ouriban":eachIbanEntity.ourIbanNumber, "ourname":eachIbanEntity.ourName, "token":eachIbanEntity.emailToken, "ourswift":eachIbanEntity.ourSwift], forKey: eachIbanEntity.id as NSCopying)
            }
            let updatedClientsDict = NSMutableDictionary()
            updatedClientsDict.setObject(["ibans":ibansDict], forKey: "bittrwallet" as NSCopying)
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "lightning")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "lightning")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "cache")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "cache")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "hashes")
        
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
    
    static func storeSwapID(dateID:String, swapID:String) {
        let defaults = UserDefaults.standard
        if let cachedSwapIDs = defaults.value(forKey: "swapids") as? NSDictionary {
            if let actualSwapIDs = cachedSwapIDs.mutableCopy() as? NSMutableDictionary {
                actualSwapIDs.setObject(swapID, forKey: dateID as NSCopying)
                defaults.set(actualSwapIDs, forKey: "swapids")
            }
        } else {
            let swapIDs = NSMutableDictionary()
            swapIDs.setObject(swapID, forKey: dateID as NSCopying)
            defaults.set(swapIDs, forKey: "swapids")
        }
    }
    
    static func getSwapID(dateID:String) -> String? {
        let defaults = UserDefaults.standard
        if let swapIDs = defaults.value(forKey: "swapids") as? NSDictionary {
            if let foundSwapID = swapIDs[dateID] as? String {
                return foundSwapID
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    static func storeInvoiceDescription(hash:String, desc:String) {
        
        let envKey = EnvironmentConfig.cacheKey(for: "descriptions")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "transactionnotes")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "lightningfees")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "hashes")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "descriptions")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "lightningfees")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "transactionnotes")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "mnemonic")
        
        let defaults = UserDefaults.standard
        defaults.set(mnemonic, forKey: envKey)
    }
    
    static func getMnemonic() -> String? {
        
        let envKey = EnvironmentConfig.cacheKey(for: "mnemonic")
        
        let defaults = UserDefaults.standard
        let cachedMnemonic = defaults.value(forKey: envKey) as? String
        
        if let actualCachedMnemonic = cachedMnemonic {
            return actualCachedMnemonic
        } else {
            return nil
        }
    }
    
    static func storePin(pin:String) {
        
        let envKey = EnvironmentConfig.cacheKey(for: "pin")
        
        let defaults = UserDefaults.standard
        defaults.set(pin, forKey: envKey)
    }
    
    static func getPin() -> String? {
        
        let envKey = EnvironmentConfig.cacheKey(for: "pin")
        
        let defaults = UserDefaults.standard
        let cachedPin = defaults.value(forKey: envKey) as? String
        
        if let actualCachedPin = cachedPin {
            return actualCachedPin
        } else {
            return nil
        }
    }
    
    static func storeTxoID(txoID:String) {
        
        let envKey = EnvironmentConfig.cacheKey(for: "txoid")
        
        let defaults = UserDefaults.standard
        defaults.set(txoID, forKey: envKey)
    }
    
    static func getTxoID() -> String? {
        
        let envKey = EnvironmentConfig.cacheKey(for: "txoid")
        
        let defaults = UserDefaults.standard
        let cachedTxoID = defaults.value(forKey: envKey) as? String
        
        if let actualCachedTxoID = cachedTxoID {
            return actualCachedTxoID
        } else {
            return nil
        }
    }
    
    static func updateSentToBittr(txids:[String]) {
        
        let envKey = EnvironmentConfig.cacheKey(for: "senttobittr")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "senttobittr")
        
        let defaults = UserDefaults.standard
        let cachedSentToBittr = defaults.value(forKey: envKey) as? [String]
        
        if let actualSentToBittr = cachedSentToBittr {
            return actualSentToBittr
        } else {
            return nil
        }
    }
    
    static func storeLastAddress(newAddress:String) {
        
        let envKey = EnvironmentConfig.cacheKey(for: "lastaddress")
        
        let defaults = UserDefaults.standard
        defaults.set(newAddress, forKey: envKey)
    }
    
    static func getLastAddress() -> String? {
        
        let envKey = EnvironmentConfig.cacheKey(for: "lastaddress")
        
        let defaults = UserDefaults.standard
        let cachedLastAddress = defaults.value(forKey: envKey) as? String
        if let actualLastAddress = cachedLastAddress {
            return actualLastAddress
        } else {
            return nil
        }
    }
    
    static func getFailedPinAttempts() -> Int {
        
        let envKey = EnvironmentConfig.cacheKey(for: "failedattempts")
        
        let defaults = UserDefaults.standard
        let cachedFailedAttempts = defaults.value(forKey: envKey) as? Int
        if let actualCachedAttempts = cachedFailedAttempts {
            return actualCachedAttempts
        } else {
            return 0
        }
    }
    
    static func increaseFailedPinAttempts() {
        
        let envKey = EnvironmentConfig.cacheKey(for: "failedattempts")
        
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
        
        let envKey = EnvironmentConfig.cacheKey(for: "failedattempts")
        
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
    
    static func swapToDictionary(_ thisSwap:Swap) -> NSDictionary {
        
        let swapDictionary:NSMutableDictionary = ["dateID":thisSwap.dateID, "onchainToLightning":thisSwap.onchainToLightning, "satoshisAmount":thisSwap.satoshisAmount]
        if thisSwap.createdInvoice != nil {
            swapDictionary.setValue(thisSwap.createdInvoice!, forKey: "createdInvoice")
        }
        if thisSwap.privateKey != nil {
            swapDictionary.setValue(thisSwap.privateKey!, forKey: "privateKey")
        }
        if thisSwap.boltzID != nil {
            swapDictionary.setValue(thisSwap.boltzID!, forKey: "boltzID")
        }
        if thisSwap.boltzOnchainAddress != nil {
            swapDictionary.setValue(thisSwap.boltzOnchainAddress!, forKey: "boltzOnchainAddress")
        }
        if thisSwap.boltzExpectedAmount != nil {
            swapDictionary.setValue(thisSwap.boltzExpectedAmount!, forKey: "boltzExpectedAmount")
        }
        if thisSwap.onchainFees != nil {
            swapDictionary.setValue(thisSwap.onchainFees!, forKey: "onchainFees")
        }
        if thisSwap.lightningFees != nil {
            swapDictionary.setValue(thisSwap.lightningFees!, forKey: "lightningFees")
        }
        if thisSwap.feeHigh != nil {
            swapDictionary.setValue(thisSwap.feeHigh!, forKey: "feeHigh")
        }
        if thisSwap.claimTransactionFee != nil {
            swapDictionary.setValue(thisSwap.claimTransactionFee!, forKey: "claimTransactionFee")
        }
        if thisSwap.sentOnchainTransactionID != nil {
            swapDictionary.setValue(thisSwap.sentOnchainTransactionID!, forKey: "sentOnchainTransactionID")
        }
        if thisSwap.boltzOnchainAddress != nil {
            swapDictionary.setValue(thisSwap.boltzOnchainAddress!, forKey: "boltzOnchainAddress")
        }
        if thisSwap.refundPublicKey != nil {
            swapDictionary.setValue(thisSwap.refundPublicKey!, forKey: "refundPublicKey")
        }
        if thisSwap.claimLeafOutput != nil {
            swapDictionary.setValue(thisSwap.claimLeafOutput!, forKey: "claimLeafOutput")
        }
        if thisSwap.refundLeafOutput != nil {
            swapDictionary.setValue(thisSwap.refundLeafOutput!, forKey: "refundLeafOutput")
        }
        if thisSwap.claimPublicKey != nil {
            swapDictionary.setValue(thisSwap.claimPublicKey!, forKey: "claimPublicKey")
        }
        if thisSwap.preimage != nil {
            swapDictionary.setValue(thisSwap.preimage!, forKey: "preimage")
        }
        if thisSwap.destinationAddress != nil {
            swapDictionary.setValue(thisSwap.destinationAddress!, forKey: "destinationAddress")
        }
        if thisSwap.boltzInvoice != nil {
            swapDictionary.setValue(thisSwap.boltzInvoice!, forKey: "boltzInvoice")
        }
        if thisSwap.lockupTx != nil {
            swapDictionary.setValue(thisSwap.lockupTx!, forKey: "lockupTx")
        }
        
        return swapDictionary
    }
    
    static func saveLatestSwap(_ latestSwap:Swap?) {
        
        if latestSwap != nil {
            let swapDictionary = CacheManager.swapToDictionary(latestSwap!)
            UserDefaults.standard.set(swapDictionary, forKey: "ongoingswap")
        } else {
            if let storedSwap = UserDefaults.standard.value(forKey: "ongoingswap") as? NSDictionary {
                UserDefaults.standard.removeObject(forKey: "ongoingswap")
            }
        }
    }
    
    static func dictionaryToSwap(_ dictionary:NSDictionary) -> Swap {
        
        let thisSwap = Swap()
        if let dateID = dictionary["dateID"] as? String {
            thisSwap.dateID = dateID
        }
        if let onchainToLightning = dictionary["onchainToLightning"] as? Bool {
            thisSwap.onchainToLightning = onchainToLightning
        }
        if let satoshisAmount = dictionary["satoshisAmount"] as? Int {
            thisSwap.satoshisAmount = satoshisAmount
        }
        if let createdInvoice = dictionary["createdInvoice"] as? String {
            thisSwap.createdInvoice = createdInvoice
        }
        if let privateKey = dictionary["privateKey"] as? String {
            thisSwap.privateKey = privateKey
        }
        if let boltzID = dictionary["boltzID"] as? String {
            thisSwap.boltzID = boltzID
        }
        if let boltzOnchainAddress = dictionary["boltzOnchainAddress"] as? String {
            thisSwap.boltzOnchainAddress = boltzOnchainAddress
        }
        if let boltzExpectedAmount = dictionary["boltzExpectedAmount"] as? Int {
            thisSwap.boltzExpectedAmount = boltzExpectedAmount
        }
        if let onchainFees = dictionary["onchainFees"] as? Int {
            thisSwap.onchainFees = onchainFees
        }
        if let lightningFees = dictionary["lightningFees"] as? Int {
            thisSwap.lightningFees = lightningFees
        }
        if let feeHigh = dictionary["feeHigh"] as? Float {
            thisSwap.feeHigh = feeHigh
        }
        if let claimTransactionFee = dictionary["claimTransactionFee"] as? Int {
            thisSwap.claimTransactionFee = claimTransactionFee
        }
        if let sentOnchainTransactionID = dictionary["sentOnchainTransactionID"] as? String {
            thisSwap.sentOnchainTransactionID = sentOnchainTransactionID
        }
        if let boltzOnchainAddress = dictionary["boltzOnchainAddress"] as? String {
            thisSwap.boltzOnchainAddress = boltzOnchainAddress
        }
        if let refundPublicKey = dictionary["refundPublicKey"] as? String {
            thisSwap.refundPublicKey = refundPublicKey
        }
        if let claimLeafOutput = dictionary["claimLeafOutput"] as? String {
            thisSwap.claimLeafOutput = claimLeafOutput
        }
        if let refundLeafOutput = dictionary["refundLeafOutput"] as? String {
            thisSwap.refundLeafOutput = refundLeafOutput
        }
        if let claimPublicKey = dictionary["claimPublicKey"] as? String {
            thisSwap.claimPublicKey = claimPublicKey
        }
        if let preimage = dictionary["preimage"] as? String {
            thisSwap.preimage = preimage
        }
        if let destinationAddress = dictionary["destinationAddress"] as? String {
            thisSwap.destinationAddress = destinationAddress
        }
        if let boltzInvoice = dictionary["boltzInvoice"] as? String {
            thisSwap.boltzInvoice = boltzInvoice
        }
        if let lockupTx = dictionary["lockupTx"] as? String {
            thisSwap.lockupTx = lockupTx
        }
        return thisSwap
    }
    
    static func getLatestSwap() -> Swap? {
        if let storedSwap = UserDefaults.standard.value(forKey: "ongoingswap") as? NSDictionary {
            
            let thisSwap = self.dictionaryToSwap(storedSwap)
            
            return thisSwap
        } else {
            return nil
        }
    }
    
    // MARK: - Swap Index Cache
    
    static func getSwapIndex() -> Int {
        let envKey = EnvironmentConfig.cacheKey(for: "swapindex")
        
        let defaults = UserDefaults.standard
        let cachedSwapIndex = defaults.value(forKey: envKey) as? Int
        
        if let actualCachedSwapIndex = cachedSwapIndex {
            return actualCachedSwapIndex
        } else {
            // Initialize with 0 if no index exists
            defaults.set(0, forKey: envKey)
            return 0
        }
    }
    
    static func incrementSwapIndex() -> Int {
        let envKey = EnvironmentConfig.cacheKey(for: "swapindex")
        
        let defaults = UserDefaults.standard
        let currentIndex = getSwapIndex()
        let newIndex = currentIndex + 1
        
        defaults.set(newIndex, forKey: envKey)
        return newIndex
    }
    
    static func resetSwapIndex() {
        let envKey = EnvironmentConfig.cacheKey(for: "swapindex")
        
        let defaults = UserDefaults.standard
        defaults.set(0, forKey: envKey)
    }
    
    static func getCurrentSwapIndex() -> Int {
        return getSwapIndex()
    }
    
}
