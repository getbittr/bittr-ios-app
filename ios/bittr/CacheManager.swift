//
//  CacheManager.swift
//  bittr
//
//  Created by Tom Melters on 24/06/2023.
//

import UIKit
import Sentry
import CryptoKit

class CacheManager: NSObject {
    
    
    static func deleteClientInfo() {
        
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "device"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "cache"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "pin"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "mnemonic"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "lastaddress"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "lightning"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "bittraddress"))
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "onchainaddresses"))

        // Remove the secrets from the Keychain too — they no longer live in
        // UserDefaults, so the UserDefaults removals above wouldn't clear them.
        SecureStore.remove(account: EnvironmentConfig.cacheKey(for: "mnemonic"))
        SecureStore.remove(account: EnvironmentConfig.cacheKey(for: "pin"))

        // A wiped wallet's pending swap is meaningless (its documents are
        // deleted with the wallet): clear the ongoing-swap record and sweep
        // the per-swap refund keys out of the Keychain.
        defaults.removeObject(forKey: "ongoingswap")
        SecureStore.removeAll(accountPrefix: "swapkey_")

        self.resetFailedPinAttempts()
    }
    
    // MARK: - Bittr signup details
    
    static func parseDevice() -> BittrWallet {
        
        // Create Bittr wallet.
        let bittrWallet = BittrWallet()
        
        // Get device cache.
        let envKey = EnvironmentConfig.deviceCacheKey
        guard let deviceDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary else {
            return bittrWallet
        }
        
        // Parse IBAN entities.
        for (_, clientdata) in deviceDict {
            guard
                let actualClientDict = clientdata as? NSDictionary,
                let actualIbansDict = actualClientDict["ibans"] as? NSDictionary
            else { continue }
                
            var ibansInClient = [IbanEntity]()
            
            for (ibanid, ibandata) in actualIbansDict {
                guard let ibanDataDict = ibandata as? NSDictionary else { continue }
                
                let iban = IbanEntity()
                
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
                if let actualLightningAddressUsername = ibanDataDict["lightningaddressusername"] as? String {
                    iban.lightningAddressUsername = actualLightningAddressUsername
                }
                if let actualOurSwift = ibanDataDict["ourswift"] as? String {
                    iban.ourSwift = actualOurSwift
                }
                if let actualPaymentMode = ibanDataDict["paymentmode"] as? String {
                    iban.paymentMode = actualPaymentMode
                }
                
                ibansInClient += [iban]
            }
            
            bittrWallet.ibanEntities = ibansInClient
            bittrWallet.ibanEntities.sort { iban1, iban2 in
                iban1.order < iban2.order
            }
        }
        
        return bittrWallet
    }
    
    
    static func addIban(iban:IbanEntity) {
        
        let envKey = EnvironmentConfig.deviceCacheKey
        guard let _ = UserDefaults.standard.value(forKey: envKey) as? NSDictionary else {
            // No client exists yet.
            let clientsDict:NSDictionary = ["bittrwallet":["ibans":[iban.id:["order":iban.order,"youriban":iban.yourIbanNumber, "youremail":iban.yourEmail, "yourcode":iban.yourUniqueCode, "ouriban":iban.ourIbanNumber, "ourname":iban.ourName, "token":iban.emailToken]]]]
            UserDefaults.standard.set(clientsDict, forKey: envKey)
            UserDefaults.standard.synchronize()
            return
        }
        
        // Client already exists.
        let bittrWallet = self.parseDevice()
        
        var ibanExists = false
        for existingIban in bittrWallet.ibanEntities where existingIban.id == iban.id {
            ibanExists = true
            existingIban.yourIbanNumber = iban.yourIbanNumber
            existingIban.yourEmail = iban.yourEmail
        }
        if ibanExists == false {
            // This is a new IBAN entity.
            bittrWallet.ibanEntities += [iban]
        }
        
        let ibansDict = NSMutableDictionary()
        for existingIban in bittrWallet.ibanEntities {
            ibansDict.setObject(["order":existingIban.order,"youriban":existingIban.yourIbanNumber, "youremail":existingIban.yourEmail, "yourcode":existingIban.yourUniqueCode, "ouriban":existingIban.ourIbanNumber, "ourname":existingIban.ourName, "token":existingIban.emailToken, "ourswift":existingIban.ourSwift, "paymentmode":existingIban.paymentMode], forKey: existingIban.id as NSCopying)
        }
        let updatedClientsDict = NSMutableDictionary()
        updatedClientsDict.setObject(["ibans":ibansDict], forKey: "bittrwallet" as NSCopying)
        UserDefaults.standard.set(updatedClientsDict, forKey: envKey)
        UserDefaults.standard.synchronize()
    }
    
    static func addEmailToken(ibanID:String, emailToken:String) {
        
        let envKey = EnvironmentConfig.deviceCacheKey
        guard let _ = UserDefaults.standard.value(forKey: envKey) as? NSDictionary else { return }
            
        let bittrWallet = self.parseDevice()
        
        for eachIbanEntity in bittrWallet.ibanEntities where eachIbanEntity.id == ibanID {
            eachIbanEntity.emailToken = emailToken
        }
        
        let ibansDict = NSMutableDictionary()
        for eachIbanEntity in bittrWallet.ibanEntities {
            ibansDict.setObject(["order":eachIbanEntity.order,"youriban":eachIbanEntity.yourIbanNumber, "youremail":eachIbanEntity.yourEmail, "yourcode":eachIbanEntity.yourUniqueCode, "ouriban":eachIbanEntity.ourIbanNumber, "ourname":eachIbanEntity.ourName, "token":eachIbanEntity.emailToken, "ourswift":eachIbanEntity.ourSwift, "lightningaddressusername":eachIbanEntity.lightningAddressUsername, "paymentmode":eachIbanEntity.paymentMode], forKey: eachIbanEntity.id as NSCopying)
        }
        let updatedClientsDict = NSMutableDictionary()
        updatedClientsDict.setObject(["ibans":ibansDict], forKey: "bittrwallet" as NSCopying)
        UserDefaults.standard.set(updatedClientsDict, forKey: envKey)
        UserDefaults.standard.synchronize()
    }
    
    static func setPaymentMode(ibanID:String, paymentMode:String) {

        let envKey = EnvironmentConfig.deviceCacheKey
        guard let _ = UserDefaults.standard.value(forKey: envKey) as? NSDictionary else { return }

        let bittrWallet = self.parseDevice()

        for eachIbanEntity in bittrWallet.ibanEntities where eachIbanEntity.id == ibanID {
            eachIbanEntity.paymentMode = paymentMode
        }
        
        let ibansDict = NSMutableDictionary()
        for eachIbanEntity in bittrWallet.ibanEntities {
            ibansDict.setObject(["order":eachIbanEntity.order,"youriban":eachIbanEntity.yourIbanNumber, "youremail":eachIbanEntity.yourEmail, "yourcode":eachIbanEntity.yourUniqueCode, "ouriban":eachIbanEntity.ourIbanNumber, "ourname":eachIbanEntity.ourName, "token":eachIbanEntity.emailToken, "ourswift":eachIbanEntity.ourSwift, "lightningaddressusername":eachIbanEntity.lightningAddressUsername, "paymentmode":eachIbanEntity.paymentMode], forKey: eachIbanEntity.id as NSCopying)
        }
        let updatedClientsDict = NSMutableDictionary()
        updatedClientsDict.setObject(["ibans":ibansDict], forKey: "bittrwallet" as NSCopying)
        UserDefaults.standard.set(updatedClientsDict, forKey: envKey)
        UserDefaults.standard.synchronize()
    }

    static func addBittrIban(ibanID:String, ourIban:String, ourSwift:String, yourCode:String, lightningAddressUsername:String?) {
        
        let envKey = EnvironmentConfig.deviceCacheKey
        guard let _ = UserDefaults.standard.value(forKey: envKey) as? NSDictionary else { return }
        
        let bittrWallet = self.parseDevice()
        
        for eachIbanEntity in bittrWallet.ibanEntities {
            if eachIbanEntity.id == ibanID {
                eachIbanEntity.ourIbanNumber = ourIban
                eachIbanEntity.yourUniqueCode = yourCode
                eachIbanEntity.ourSwift = ourSwift
                eachIbanEntity.lightningAddressUsername = lightningAddressUsername ?? eachIbanEntity.lightningAddressUsername
            }
        }
        
        let ibansDict = NSMutableDictionary()
        for eachIbanEntity in bittrWallet.ibanEntities {
            ibansDict.setObject(["order":eachIbanEntity.order,"youriban":eachIbanEntity.yourIbanNumber, "youremail":eachIbanEntity.yourEmail, "yourcode":eachIbanEntity.yourUniqueCode, "ouriban":eachIbanEntity.ourIbanNumber, "ourname":eachIbanEntity.ourName, "token":eachIbanEntity.emailToken, "ourswift":eachIbanEntity.ourSwift, "lightningaddressusername":eachIbanEntity.lightningAddressUsername, "paymentmode":eachIbanEntity.paymentMode], forKey: eachIbanEntity.id as NSCopying)
        }
        let updatedClientsDict = NSMutableDictionary()
        updatedClientsDict.setObject(["ibans":ibansDict], forKey: "bittrwallet" as NSCopying)
        UserDefaults.standard.set(updatedClientsDict, forKey: envKey)
        UserDefaults.standard.synchronize()
    }
    
    // MARK: - Images cache
    
    static func storeImageInCache(key:String, data:Data) {
        
        // Get the documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent("images/" + key)
        
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            // Write the data to file
            try data.write(to: fileURL)
            Log.info("Did save image to file.")
        } catch {
            Log.info("Could not save image to file. \(error.localizedDescription)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "CacheManager row 232", key: "context")
                }
            }
        }
    }
    
    static func emptyImage() {
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesDirectory = documentsPath.appendingPathComponent("images")
        
        do {
            if FileManager.default.fileExists(atPath: imagesDirectory.path) {
                try FileManager.default.removeItem(at: imagesDirectory)
                Log.info("Successfully deleted images folder and its contents.")
            } else {
                Log.info("Images folder does not exist.")
            }
        } catch {
            Log.info("Could not delete images folder. \(error.localizedDescription)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "CacheManager row 53", key: "context")
                }
            }
        }
    }
    
    static func getImage(key:String) -> Data? {
        
        do {
            // Get the documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("images/" + key)
            
            // Read the JSON data from file
            let imageData = try Data(contentsOf: fileURL)
            
            return imageData
        } catch {
            Log.info("Image not found in cache. \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Transactions
    
    static func parseTransactions(transactions:[Transaction]) -> [NSDictionary] {
        
        var transactionsDict = [NSDictionary]()
        
        for eachTransaction in transactions {
            
            let oneTransaction = NSMutableDictionary()
            oneTransaction.setObject(eachTransaction.id, forKey: "id" as NSCopying)
            oneTransaction.setObject(eachTransaction.fiatNetAmount, forKey: "fiatNetAmount" as NSCopying)
            oneTransaction.setObject(eachTransaction.fiatGrossAmount, forKey: "fiatGrossAmount" as NSCopying)
            oneTransaction.setObject(eachTransaction.transferFee, forKey: "transferFee" as NSCopying)
            oneTransaction.setObject(eachTransaction.surcharge, forKey: "surcharge" as NSCopying)
            oneTransaction.setObject(eachTransaction.bittrFee, forKey: "bittrFee" as NSCopying)
            oneTransaction.setObject(eachTransaction.historicalExchangeRate, forKey: "historicalExchangeRate" as NSCopying)
            oneTransaction.setObject(eachTransaction.received, forKey: "received" as NSCopying)
            oneTransaction.setObject(eachTransaction.sent, forKey: "sent" as NSCopying)
            oneTransaction.setObject(eachTransaction.isBittr, forKey: "isBittr" as NSCopying)
            oneTransaction.setObject(eachTransaction.timestamp, forKey: "timestamp" as NSCopying)
            oneTransaction.setObject(eachTransaction.currency, forKey: "currency" as NSCopying)
            if eachTransaction.height != nil {
                oneTransaction.setObject(eachTransaction.height!, forKey: "height" as NSCopying)
            }
            oneTransaction.setObject(eachTransaction.isLightning, forKey: "isLightning" as NSCopying)
            oneTransaction.setObject(eachTransaction.fee, forKey: "fee" as NSCopying)
            oneTransaction.setObject(eachTransaction.channelId, forKey: "channelId" as NSCopying)
            oneTransaction.setObject(eachTransaction.isFundingTransaction, forKey: "isFundingTransaction" as NSCopying)
            oneTransaction.setObject(eachTransaction.lnDescription, forKey: "lnDescription" as NSCopying)
            oneTransaction.setObject(eachTransaction.isSwap, forKey: "isswap" as NSCopying)
            var swapStatus = ""
            switch eachTransaction.swapStatus {
            case .pending: swapStatus = "pending"
            case .succeeded: swapStatus = "succeeded"
            case .failed: swapStatus = "failed"
            }
            oneTransaction.setObject(swapStatus, forKey: "swapstatus" as NSCopying)
            oneTransaction.setObject(eachTransaction.onchainID, forKey: "onchainid" as NSCopying)
            oneTransaction.setObject(eachTransaction.lightningID, forKey: "lightningid" as NSCopying)
            oneTransaction.setObject(eachTransaction.boltzSwapId, forKey: "boltzSwapId" as NSCopying)
            if eachTransaction.swapDirection == .onchainToLightning {
                oneTransaction.setObject(0, forKey: "swapdirection" as NSCopying)
            } else {
                oneTransaction.setObject(1, forKey: "swapdirection" as NSCopying)
            }
            
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
            if let transactionFiatNetAmount = eachTransaction["fiatNetAmount"] as? CGFloat {
                thisTransaction.fiatNetAmount = transactionFiatNetAmount
            }
            if let transactionFiatGrossAmount = eachTransaction["fiatGrossAmount"] as? CGFloat {
                thisTransaction.fiatGrossAmount = transactionFiatGrossAmount
            }
            if let historicalExchangeRate = eachTransaction["historicalExchangeRate"] as? CGFloat {
                thisTransaction.historicalExchangeRate = historicalExchangeRate
            }
            if let transactionTransferFee = eachTransaction["transferFee"] as? CGFloat {
                thisTransaction.transferFee = transactionTransferFee
            }
            if let transactionSurcharge = eachTransaction["surcharge"] as? CGFloat {
                thisTransaction.surcharge = transactionSurcharge
            }
            if let transactionBittrFee = eachTransaction["bittrFee"] as? CGFloat {
                thisTransaction.bittrFee = transactionBittrFee
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
            if let swapStatus = eachTransaction["swapstatus"] as? String {
                if swapStatus == "pending" { thisTransaction.swapStatus = .pending } else
                if swapStatus == "failed" { thisTransaction.swapStatus = .failed } else
                { thisTransaction.swapStatus = .succeeded }
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
                if swapDirection == 0 {
                    thisTransaction.swapDirection = .onchainToLightning
                } else {
                    thisTransaction.swapDirection = .lightningToOnchain
                }
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
    
    static func getLightningTransactions() -> [Transaction] {
        
        if let cachedData = UserDefaults.standard.value(forKey: EnvironmentConfig.cacheKey(for: "lightning")) as? NSDictionary {
            var allTransactions = [NSMutableDictionary]()
            for (transactionId, transactionData) in cachedData {
                allTransactions.append((transactionData as! NSDictionary).mutableCopy() as! NSMutableDictionary)
            }
            let parsedTransactions = self.getTransactions(transactionsDict: allTransactions)
            return parsedTransactions
        } else {
            return [Transaction]()
        }
    }
    
    // MARK: - General cache
    
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
                } else if key == "height" {
                    if let actualData = data as? Int {
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
            } else if key == "height" {
                if let actualData = data as? Int {
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
            } else if key == "height" {
                if let cachedHeight = actualCachedData[key] as? Int {
                    return cachedHeight
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
    
    // MARK: - Notifications token
    
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
    
    // MARK: - Invoice timestamp
    
    static func storeInvoiceTimestamp(preimage:String, timestamp:Int) {
        
        let envKey = EnvironmentConfig.cacheKey(for: "hashes")
        
        let defaults = UserDefaults.standard
        let cachedHashes = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedHashes = cachedHashes {
            // Hashes have been cached.
            if let actualMutableHashes = actualCachedHashes.mutableCopy() as? NSMutableDictionary {
                actualMutableHashes.setObject(timestamp, forKey: preimage as NSCopying)
                defaults.set(actualMutableHashes, forKey: envKey)
                Log.info("Timestamp cached.")
            }
        } else {
            // No hashes have been cached.
            let actualMutableHashes = NSMutableDictionary()
            actualMutableHashes.setObject(timestamp, forKey: preimage as NSCopying)
            defaults.set(actualMutableHashes, forKey: envKey)
            Log.info("Timestamp cached.")
        }
    }
    
    static func getInvoiceTimestamp(preimage:String) -> Int {
        
        let envKey = EnvironmentConfig.cacheKey(for: "hashes")
        
        let defaults = UserDefaults.standard
        let cachedHashes = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedHashes = cachedHashes {
            // Hashes have been cached.
            if let foundTimestamp = actualCachedHashes[hash] as? Int {
                return foundTimestamp
            } else {
                self.storeInvoiceTimestamp(preimage: preimage, timestamp: Int(Date().timeIntervalSince1970))
                return Int(Date().timeIntervalSince1970)
            }
        } else {
            // No hashes have been cached.
            self.storeInvoiceTimestamp(preimage: preimage, timestamp: Int(Date().timeIntervalSince1970))
            return Int(Date().timeIntervalSince1970)
        }
    }
    
    // MARK: - Swap ID
    
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
    
    // MARK: - Suggested swaps

    // Each entry holds the swap's last observed status ("pending" until the
    // recipient is actually paid, then "succeeded" or "failed"), so the Home
    // table never shows a suggested swap as succeeded before it completes.
    static func storeSuggestedSwap(dateID:String, status:SwapStatus = .pending) {
        let statusString:String
        switch status {
        case .succeeded: statusString = "succeeded"
        case .failed: statusString = "failed"
        case .pending: statusString = "pending"
        }
        let defaults = UserDefaults.standard
        if let cached = defaults.value(forKey: "suggestedswaps") as? NSDictionary, let actual = cached.mutableCopy() as? NSMutableDictionary {
            actual.setObject(statusString, forKey: dateID as NSCopying)
            defaults.set(actual, forKey: "suggestedswaps")
        } else {
            let suggested = NSMutableDictionary()
            suggested.setObject(statusString, forKey: dateID as NSCopying)
            defaults.set(suggested, forKey: "suggestedswaps")
        }
    }

    static func getSuggestedSwapStatus(dateID:String) -> SwapStatus? {
        let defaults = UserDefaults.standard
        guard let suggested = defaults.value(forKey: "suggestedswaps") as? NSDictionary, let value = suggested[dateID] else {
            return nil
        }
        switch value as? String {
        case "succeeded": return .succeeded
        case "failed": return .failed
        case "pending": return .pending
        default:
            // Entries written before status tracking stored a Bool.
            return (value as? Bool) == true ? .succeeded : nil
        }
    }
    
    // MARK: - Invoice description
    
    static func storeInvoiceDescription(preimage:String, desc:String) {
        
        let envKey = EnvironmentConfig.cacheKey(for: "descriptions")
        
        let defaults = UserDefaults.standard
        let cachedDescriptions = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedDescriptions = cachedDescriptions {
            // Descriptions have been cached.
            if let actualMutableDescriptions = actualCachedDescriptions.mutableCopy() as? NSMutableDictionary {
                actualMutableDescriptions.setObject(desc, forKey: preimage as NSCopying)
                defaults.set(actualMutableDescriptions, forKey: envKey)
            }
        } else {
            // No descriptions have been cached.
            let actualMutableDescriptions = NSMutableDictionary()
            actualMutableDescriptions.setObject(desc, forKey: preimage as NSCopying)
            defaults.set(actualMutableDescriptions, forKey: envKey)
        }
    }
    
    static func getInvoiceDescription(preimage:String) -> String {
        
        let envKey = EnvironmentConfig.cacheKey(for: "descriptions")
        
        let defaults = UserDefaults.standard
        let cachedDescriptions = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedDescriptions = cachedDescriptions {
            // Descriptions have been cached.
            if let foundDescription = actualCachedDescriptions[preimage] as? String {
                return foundDescription
            } else {
                return ""
            }
        } else {
            // No descriptions have been cached.
            return ""
        }
    }
    
    // MARK: - Transaction note
    
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
    
    // MARK: - Payment fees
    
    static func storePaymentFees(preimage:String, fees:Int) {
        
        let envKey = EnvironmentConfig.cacheKey(for: "lightningfees")
        
        let defaults = UserDefaults.standard
        let cachedHashes = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedHashes = cachedHashes {
            // Hashes have been cached.
            if let actualMutableHashes = actualCachedHashes.mutableCopy() as? NSMutableDictionary {
                actualMutableHashes.setObject(fees, forKey: preimage as NSCopying)
                defaults.set(actualMutableHashes, forKey: envKey)
                Log.info("Lightning fees cached.")
            }
        } else {
            // No hashes have been cached.
            let actualMutableHashes = NSMutableDictionary()
            actualMutableHashes.setObject(fees, forKey: preimage as NSCopying)
            defaults.set(actualMutableHashes, forKey: envKey)
            Log.info("Lightning fees cached.")
        }
    }
    
    static func getLightningFees(preimage:String) -> Int {
        
        let envKey = EnvironmentConfig.cacheKey(for: "lightningfees")
        
        let defaults = UserDefaults.standard
        let cachedFees = defaults.value(forKey: envKey) as? NSDictionary
        if let actualCachedFees = cachedFees {
            // Descriptions have been cached.
            if let foundFees = actualCachedFees[preimage] as? Int {
                return foundFees
            } else {
                return 0
            }
        } else {
            // No fees have been cached.
            return 0
        }
    }
    
    // MARK: - Mnemonic
    
    static func storeMnemonic(_ mnemonic:String) throws {
        try persistSecret(mnemonic, account: EnvironmentConfig.cacheKey(for: "mnemonic"), label: "mnemonic", accessibility: .afterFirstUnlockThisDeviceOnly)
    }
    
    static func getMnemonic() -> String? {
        readSecret(account: EnvironmentConfig.cacheKey(for: "mnemonic"))
    }
    
    // MARK: - Pin

    // The PIN is stored as a salted SHA-256 record ("v1$<salt>$<digest>",
    // base64) so its raw value never sits anywhere at rest — people reuse
    // bank-card PINs, so disclosure matters beyond this app. Honest scope:
    // hashing cannot make a 4-8 digit PIN resistant to offline brute force
    // (the keyspace is tiny); the wipe-after-10 attempt counter is the real
    // guard, and the mnemonic — not the PIN — is the actual key material.
    // Legacy raw values (UserDefaults, or early Keychain builds) are
    // re-hashed by the launch migration; verifyPin also upgrades any
    // straggler on its next successful entry.
    static func storePin(pin:String) {
        writeSecret(hashedPinRecord(for: pin), account: EnvironmentConfig.cacheKey(for: "pin"), label: "pin", accessibility: .whenUnlockedThisDeviceOnly)
    }

    /// Whether a PIN is stored (hashed or legacy raw).
    static func hasPin() -> Bool {
        readSecret(account: EnvironmentConfig.cacheKey(for: "pin")) != nil
    }

    /// Check an entered PIN against the stored record.
    static func verifyPin(_ entered: String) -> Bool {
        guard let stored = readSecret(account: EnvironmentConfig.cacheKey(for: "pin")) else { return false }
        if let record = parseHashedPinRecord(stored) {
            return pinDigest(entered, salt: record.salt) == record.digest
        }
        // Legacy raw value — compare directly, and upgrade to the hashed form
        // now that the correct PIN is known.
        guard stored == entered else { return false }
        storePin(pin: entered)
        return true
    }

    private static func hashedPinRecord(for pin: String) -> String {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        return "v1$\(salt.base64EncodedString())$\(pinDigest(pin, salt: salt).base64EncodedString())"
    }

    private static func parseHashedPinRecord(_ record: String) -> (salt: Data, digest: Data)? {
        let parts = record.split(separator: "$")
        guard parts.count == 3, parts[0] == "v1",
              let salt = Data(base64Encoded: String(parts[1])),
              let digest = Data(base64Encoded: String(parts[2])) else { return nil }
        return (salt, digest)
    }

    private static func pinDigest(_ pin: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }
    
    // MARK: - Secure storage (Keychain)
    
    // Check whether PIN and mnemonic are available.
    enum WalletSecretsPresence {
        case present
        case absent
        case unavailable
    }
    
    static func walletSecretsPresence() -> WalletSecretsPresence {
        // While the device is locked the WhenUnlockedThisDeviceOnly items are
        // unreadable, so we can't decide anything.
        guard UIApplication.shared.isProtectedDataAvailable else { return .unavailable }
        do {
            let mnemonic = try readSecretOrThrow(account: EnvironmentConfig.cacheKey(for: "mnemonic"))
            let pin = try readSecretOrThrow(account: EnvironmentConfig.cacheKey(for: "pin"))
            return (mnemonic != nil && pin != nil) ? .present : .absent
        } catch {
            // A Keychain read failed (not a genuine absence). Report it and treat
            // as unavailable so nothing destructive happens.
            SentrySDK.capture(error: error) { scope in
                scope.setExtra(value: "reading wallet secrets for presence check", key: "context")
            }
            return .unavailable
        }
    }

    /// Eagerly migrate any legacy UserDefaults-stored secrets (mnemonic, PIN,
    /// and an in-flight swap's refund key) into the Keychain. Safe to call on
    /// every launch; a no-op once migrated.
    static func migrateSecretsToKeychainIfNeeded() {
        migrateLegacyValue(account: EnvironmentConfig.cacheKey(for: "mnemonic"), accessibility: .afterFirstUnlockThisDeviceOnly)
        migrateLegacyValue(account: EnvironmentConfig.cacheKey(for: "pin"), accessibility: .whenUnlockedThisDeviceOnly)
        migrateLegacyOngoingSwapKey()
        applyProtectionToExistingSwapFiles()
        // Items keep the accessibility class they were written with; the
        // mnemonic's intended class changed (WhenUnlocked -> AfterFirstUnlock,
        // so background node starts work) after the first Keychain builds.
        // Rewriting in place re-applies the intended class; idempotent.
        refreshAccessibility(account: EnvironmentConfig.cacheKey(for: "mnemonic"), accessibility: .afterFirstUnlockThisDeviceOnly)
        refreshAccessibility(account: EnvironmentConfig.cacheKey(for: "pin"), accessibility: .whenUnlockedThisDeviceOnly)
        // Re-hash a legacy raw PIN (from UserDefaults, or an early Keychain
        // build that stored the raw value).
        if let storedPin = (try? SecureStore.getString(account: EnvironmentConfig.cacheKey(for: "pin"))) ?? nil, parseHashedPinRecord(storedPin) == nil {
            storePin(pin: storedPin)
        }
    }

    /// Re-apply the intended accessibility class to an already-stored secret
    /// by rewriting it in place. No-op when nothing is stored.
    private static func refreshAccessibility(account: String, accessibility: SecureStore.Accessibility) {
        guard let value = (try? SecureStore.getString(account: account)) ?? nil else { return }
        try? SecureStore.setString(value, account: account, accessibility: accessibility)
    }

    /// Stamp existing swap JSON files with the at-rest protection class that
    /// new writes get explicitly (saveSwapDetailsToFile). Files are only ever
    /// rewritten while a swap is in flight, so completed swaps' files would
    /// otherwise keep whatever class they were created with. Idempotent and
    /// content-preserving: this sets a file attribute — the file's deliberate
    /// plain-text content (the Boltz rescue artifact) is untouched.
    private static func applyProtectionToExistingSwapFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: file.path
            )
        }
    }

    /// Move a legacy ongoingswap dictionary's inline Boltz refund key into the
    /// Keychain. Same contract as migrateLegacyValue: the UserDefaults copy is
    /// only stripped once the Keychain copy is confirmed readable, so access
    /// is never lost. Idempotent.
    private static func migrateLegacyOngoingSwapKey() {
        guard let storedSwap = UserDefaults.standard.value(forKey: "ongoingswap") as? NSDictionary,
              let privateKey = storedSwap["privateKey"] as? String,
              let boltzID = storedSwap["boltzID"] as? String else {
            return
        }
        if storeSwapPrivateKey(privateKey, boltzID: boltzID), let stripped = storedSwap.mutableCopy() as? NSMutableDictionary {
            stripped.removeObject(forKey: "privateKey")
            UserDefaults.standard.set(stripped, forKey: "ongoingswap")
        }
    }

    /// Write a secret to the Keychain and confirm it by reading it back. Throws
    /// if the write fails or the read-back doesn't match, so callers that must
    /// not proceed without the secret persisted (wallet creation/restore) can
    /// fail loudly instead of stranding a wallet whose seed was never saved.
    private static func persistSecret(_ value: String, account: String, label: String, accessibility: SecureStore.Accessibility) throws {
        do {
            try SecureStore.setString(value, account: account, accessibility: accessibility)
            let readBack = (try? SecureStore.getString(account: account)) ?? nil
            guard readBack == value else {
                throw SecureStore.SecureStoreError.writeVerificationFailed
            }
        } catch {
            SentrySDK.capture(error: error) { scope in
                scope.setExtra(value: "storing \(label) in keychain", key: "context")
            }
            throw error
        }
    }

    /// Non-throwing convenience for secrets where a failed write is recoverable
    /// (e.g. the PIN, which can be reset via the mnemonic). Failures are logged.
    private static func writeSecret(_ value: String, account: String, label: String, accessibility: SecureStore.Accessibility) {
        try? persistSecret(value, account: account, label: label, accessibility: accessibility)
    }

    /// Non-throwing read used by getMnemonic()/getPin(). A Keychain read failure
    /// yields nil here (existing callers guard on nil and handle it gracefully);
    /// it never drives a destructive decision — the launch presence check uses
    /// walletSecretsPresence() instead, which separates failure from absence.
    /// The intended accessibility class for a secret, by account. The
    /// mnemonic (and swap keys) must be readable in background wakes; the PIN
    /// is foreground-only. See SecureStore's header.
    private static func accessibilityForAccount(_ account: String) -> SecureStore.Accessibility {
        return account == EnvironmentConfig.cacheKey(for: "pin") ? .whenUnlockedThisDeviceOnly : .afterFirstUnlockThisDeviceOnly
    }

    private static func readSecret(account: String) -> String? {
        do {
            return try readSecretOrThrow(account: account)
        } catch {
            // Keychain read failed — still honour a legacy UserDefaults copy if one exists.
            return migrateLegacyValue(account: account, accessibility: accessibilityForAccount(account))
        }
    }

    /// Read a secret, throwing on a Keychain read failure and returning nil only
    /// when the value is genuinely absent (checked in the Keychain and in a
    /// legacy UserDefaults copy). Migrates a legacy value on the way.
    private static func readSecretOrThrow(account: String) throws -> String? {
        if let value = try SecureStore.getString(account: account) {
            UserDefaults.standard.removeObject(forKey: account)   // clean up any legacy leftover
            return value
        }
        return migrateLegacyValue(account: account, accessibility: accessibilityForAccount(account))
    }

    /// Move a legacy UserDefaults value into the Keychain (if one exists). Returns
    /// the value so a read still works even if the Keychain write can't complete
    /// right now; the UserDefaults copy is removed only once the Keychain copy is
    /// confirmed readable, so access is never lost. Idempotent.
    @discardableResult
    private static func migrateLegacyValue(account: String, accessibility: SecureStore.Accessibility) -> String? {
        guard let legacy = UserDefaults.standard.value(forKey: account) as? String else {
            return nil
        }
        do {
            try SecureStore.setString(legacy, account: account, accessibility: accessibility)
            let confirmed = (try? SecureStore.getString(account: account)) ?? nil
            if confirmed == legacy {
                UserDefaults.standard.removeObject(forKey: account)   // safe: verified in Keychain
            }
        } catch {
            // Keychain write failed — keep the UserDefaults copy so access isn't lost.
            SentrySDK.capture(error: error) { scope in
                scope.setExtra(value: "migrating secret to keychain", key: "context")
            }
        }
        return legacy
    }
    
    // MARK: - Txo ID
    
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
    
    // MARK: - Sent to Bittr
    
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
    
    static func getSentToBittr() -> [String] {
        
        let envKey = EnvironmentConfig.cacheKey(for: "senttobittr")
        
        let defaults = UserDefaults.standard
        let cachedSentToBittr = defaults.value(forKey: envKey) as? [String]
        
        if let actualSentToBittr = cachedSentToBittr {
            return actualSentToBittr
        } else {
            return [String]()
        }
    }
    
    // MARK: - Last address
    
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
    
    // MARK: - Failed pin attempts
    
    // The wipe-after-10 counter lives in the Keychain, not UserDefaults:
    // backups restore UserDefaults but a live device's Keychain kept the PIN,
    // so a backup-restore cycle used to reset the counter while the PIN
    // survived — unlimited attempts for anyone with backup access. Honest
    // scope: a full same-device erase-and-restore replays ThisDeviceOnly
    // items too and buys another 9 attempts per multi-minute cycle; the
    // Keychain counter turns a seconds-long plist edit into that, it does
    // not eliminate it. Reads fail open (0): wiping wallets on a transient
    // Keychain error would be worse than granting extra attempts.
    private static var failedAttemptsAccount: String {
        EnvironmentConfig.cacheKey(for: "failedattempts")
    }

    static func getFailedPinAttempts() -> Int {
        migrateLegacyFailedAttemptsIfNeeded()
        guard let stored = (try? SecureStore.getString(account: failedAttemptsAccount)) ?? nil else { return 0 }
        return Int(stored) ?? 0
    }

    static func increaseFailedPinAttempts() {
        let next = getFailedPinAttempts() + 1
        try? SecureStore.setString("\(next)", account: failedAttemptsAccount, accessibility: .whenUnlockedThisDeviceOnly)
    }

    static func resetFailedPinAttempts() {
        SecureStore.remove(account: failedAttemptsAccount)
        UserDefaults.standard.removeObject(forKey: failedAttemptsAccount)
    }

    /// Move a legacy UserDefaults counter into the Keychain. Keeps the higher
    /// of the two values so a restored (older) count can never lower a live
    /// one. Idempotent; the UserDefaults copy is removed once read.
    private static func migrateLegacyFailedAttemptsIfNeeded() {
        guard let legacy = UserDefaults.standard.value(forKey: failedAttemptsAccount) as? Int else { return }
        let current = Int(((try? SecureStore.getString(account: failedAttemptsAccount)) ?? nil) ?? "0") ?? 0
        if legacy > current {
            try? SecureStore.setString("\(legacy)", account: failedAttemptsAccount, accessibility: .whenUnlockedThisDeviceOnly)
        }
        UserDefaults.standard.removeObject(forKey: failedAttemptsAccount)
    }

    // MARK: - Wallet removal in progress

    static func setWalletRemovalInProgress(_ inProgress: Bool) {

        let envKey = EnvironmentConfig.cacheKey(for: "walletremovalinprogress")

        let defaults = UserDefaults.standard
        defaults.set(inProgress, forKey: envKey)
    }

    static func walletRemovalIsInProgress() -> Bool {

        let envKey = EnvironmentConfig.cacheKey(for: "walletremovalinprogress")

        let defaults = UserDefaults.standard
        return defaults.bool(forKey: envKey)
    }

    // MARK: - Event handling
    
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
    
    // MARK: - Dark mode
    
    static func setCurrentDarkMode(darkModeIsOn:Bool) {
        var currentSetting = "light"
        if darkModeIsOn {
            currentSetting = "dark"
        }
        UserDefaults.standard.set(currentSetting, forKey: "currentdarkmode")
    }
    
    static func darkModeIsOn() -> Bool {
        if let darkModeStatus = UserDefaults.standard.value(forKey: "currentdarkmode") as? String {
            if darkModeStatus == "dark" {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }
    
    static func updateDarkMode(_ setting:DarkMode) {
        
        var newSetting = "light"
        switch setting {
        case .light:
            newSetting = "light"
        case .dark:
            newSetting = "dark"
        case .device:
            newSetting = "device"
        }
        UserDefaults.standard.set(newSetting, forKey: "darkmode")
    }
    
    static func darkMode() -> DarkMode {
        
        if let darkModeStatus = UserDefaults.standard.value(forKey: "darkmode") as? String {
            var setDarkMode:DarkMode = .device
            if darkModeStatus == "light" {
                setDarkMode = .light
            } else if darkModeStatus == "dark" {
                setDarkMode = .dark
            }
            return setDarkMode
        } else {
            return .device
        }
    }
    
    // MARK: - Language settings
    
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
    
    // MARK: - Swaps
    
    static func saveLatestSwap(_ latestSwap:Swap?) {

        if let swap = latestSwap, let swapDictionary = swap.toDictionary().mutableCopy() as? NSMutableDictionary {
            // Keep the Boltz refund key out of UserDefaults: store it in the
            // Keychain (keyed per swap) and strip it from the persisted
            // dictionary — but only once the Keychain copy is confirmed
            // readable. If the write fails, the key stays inline: for an
            // in-flight swap, a plaintext key beats a lost refund key.
            // (The per-swap JSON file DELIBERATELY keeps the key in plain
            // text — it is the user-facing emergency artifact for Boltz's
            // rescue flow and must not depend on a working app or Keychain.)
            if let privateKey = swap.privateKey, let boltzID = swap.boltzID, storeSwapPrivateKey(privateKey, boltzID: boltzID) {
                swapDictionary.removeObject(forKey: "privateKey")
            }
            UserDefaults.standard.set(swapDictionary, forKey: "ongoingswap")
        } else {
            if let storedSwap = UserDefaults.standard.value(forKey: "ongoingswap") as? NSDictionary, let boltzID = storedSwap["boltzID"] as? String {
                SecureStore.remove(account: "swapkey_\(boltzID)")
            }
            UserDefaults.standard.removeObject(forKey: "ongoingswap")
        }
    }

    static func getLatestSwap() -> Swap? {
        if let storedSwap = UserDefaults.standard.value(forKey: "ongoingswap") as? NSDictionary {
            let thisSwap = storedSwap.toSwap()
            // New saves strip the refund key from the dictionary — read it
            // back from the Keychain. A legacy dictionary still carries it
            // inline (toSwap picks that up), and
            // migrateSecretsToKeychainIfNeeded moves it across on launch.
            if thisSwap.privateKey == nil, let boltzID = thisSwap.boltzID {
                thisSwap.privateKey = (try? SecureStore.getString(account: "swapkey_\(boltzID)")) ?? nil
            }
            return thisSwap
        } else {
            return nil
        }
    }

    /// Store an in-flight swap's Boltz refund key in the Keychain, verified by
    /// read-back. Returns true only when the Keychain copy is confirmed, so
    /// callers only strip the inline copy on certainty.
    private static func storeSwapPrivateKey(_ privateKey: String, boltzID: String) -> Bool {
        do {
            try SecureStore.setString(privateKey, account: "swapkey_\(boltzID)", accessibility: .afterFirstUnlockThisDeviceOnly)
            guard ((try? SecureStore.getString(account: "swapkey_\(boltzID)")) ?? nil) == privateKey else {
                throw SecureStore.SecureStoreError.writeVerificationFailed
            }
            return true
        } catch {
            SentrySDK.capture(error: error) { scope in
                scope.setExtra(value: "storing swap private key in keychain", key: "context")
            }
            return false
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
    
    // MARK: - Academy cache
    
    static func addCompletedLesson(_ lessonId:String) {
        
        let defaults = UserDefaults.standard
        
        if var completedLessons = defaults.value(forKey: "completedlessons") as? [String] {
            if !completedLessons.contains(lessonId) {
                completedLessons += [lessonId]
                defaults.set(completedLessons, forKey: "completedlessons")
            }
        } else {
            let completedLessons = [lessonId]
            defaults.set(completedLessons, forKey: "completedlessons")
        }
    }
    
    static func getCompletedLessons() -> [String] {
        
        if let completedLessons =  UserDefaults.standard.value(forKey: "completedlessons") as? [String] {
            return completedLessons
        } else {
            return [String]()
        }
    }
    
    // MARK: - Onchain addresses
    
    static func getOnchainAddresses() -> [OnchainAddress] {
        
        if let cachedOnchainAddresses = UserDefaults.standard.value(forKey: EnvironmentConfig.cacheKey(for: "onchainaddresses")) as? [NSDictionary] {
            
            var addresses = cachedOnchainAddresses.toAddresses()
            addresses.sort { address1, address2 in
                address1.addressIndex < address2.addressIndex
            }
            return addresses
        } else {
            return [OnchainAddress]()
        }
    }
    
    static func storeOnchainAddresses(_ theseAddresses:[OnchainAddress]) {
        
        UserDefaults.standard.set(theseAddresses.toDict(), forKey: EnvironmentConfig.cacheKey(for: "onchainaddresses"))
    }
    
}
