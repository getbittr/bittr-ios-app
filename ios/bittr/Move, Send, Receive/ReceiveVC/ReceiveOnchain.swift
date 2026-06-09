//
//  ReceiveOnchain.swift
//  bittr
//
//  Created by Tom Melters on 14/07/2024.
//

import UIKit
import CoreImage.CIFilterBuiltins
import CodeScanner
import LDKNode
import Sentry

extension UIViewController {
    
    func getCachedOnchainAddress() -> String? {
        if let cachedAddress = CacheManager.getLastAddress() {
            Log.info("Show cached address.")
            return cachedAddress
        } else {
            Log.info("No cached address available.")
            return nil
        }
    }
    
    func getNewOnchainAddress() -> String? {
        if let newAddress = BitcoinManager.shared.getNewOnchainAddress() {
            return newAddress
        } else {
            return nil
        }
    }
}

extension [OnchainAddress] {
    
    func getNextUnusedAddress() -> String? {
        guard self.count != 0 else { return nil }
        
        // Check the index of the current cached address.
        let cachedAddress = CacheManager.getLastAddress()
        
        // Walk down from the top until we hit the current cached address or a
        // used one, then advance to the address above it.
        var checkIndex = self.count - 1
        while checkIndex >= 0 {
            if (self[checkIndex].onchainAddress == cachedAddress) || self[checkIndex].hasBeenUsedByBittr {
                // This is the current address, or this address has been used.
                // Return the next unused address.
                if (checkIndex + 1) < self.count {
                    CacheManager.storeLastAddress(newAddress: self[checkIndex+1].onchainAddress)
                    return self[checkIndex+1].onchainAddress
                } else {
                    return nil
                }
            }
            // Address hasn't been used.
            checkIndex -= 1
        }
        
        // No cached/used address found in the pool.
        return nil
    }
}

extension CoreViewController {
    
    func manageOnchainAddresses() {
        
        if CacheManager.getOnchainAddresses().count == 0 {
            Log.info("Onchain addresses need to be cached.")
            self.revealOnchainAddresses()
        } else {
            Log.info("Onchain addresses have been found in cache.")
            self.bittrWallet.onchainAddresses = CacheManager.getOnchainAddresses()
            Task { await self.checkOnchainAddressesWithBittr() }
        }
    }
    
    func revealOnchainAddresses() {
        Log.info("Reveal onchain addresses.")
        
        guard let lastRevealedOnchainAddress = self.getNewOnchainAddress() else { return }
        
        var revealedAddresses = [OnchainAddress]()
        var revealAddressIndex:Int = 0
        while revealedAddresses.last?.onchainAddress != lastRevealedOnchainAddress {
            let newAddress = OnchainAddress()
            newAddress.onchainAddress = BitcoinManager.shared.getAddress(atIndex: revealAddressIndex)
            newAddress.addressIndex = revealAddressIndex
            revealAddressIndex += 1
            revealedAddresses += [newAddress]
        }
        revealedAddresses.sort { address1, address2 in
            address1.addressIndex < address2.addressIndex
        }
        
        Log.info("All revealed onchain addresses have been identified.")
        
        // Update cache.
        self.bittrWallet.onchainAddresses = revealedAddresses
        CacheManager.storeOnchainAddresses(revealedAddresses)
        
        // Check which onchain addresses Bittr has already used.
        Task { await self.checkOnchainAddressesWithBittr() }
    }
    
    func checkOnchainAddressesWithBittr() async {
        
        var hasFoundUsedAddress = false
        var checkIndex = self.bittrWallet.onchainAddresses!.count - 1
        var latestIndexUsedByBittr = 0
        
        while !hasFoundUsedAddress && checkIndex >= 0 {
            let thisAddress = self.bittrWallet.onchainAddresses![checkIndex]
            
            if !thisAddress.hasBeenUsedByBittr {
                // Address needs to be checked with Bittr.
                
                Log.info("Check onchain address with bittr API.")
                let checkResult = await thisAddress.checkHasBeenUsedByBittr()
                
                if checkResult == nil {
                    Log.info("Did not receive valid API result for onchain address.")
                    // Treat address as unused.
                    CacheManager.storeLastAddress(newAddress: thisAddress.onchainAddress)
                    checkIndex -= 1
                } else if checkResult! == true {
                    // Did find used address.
                    // Update cache.
                    self.bittrWallet.onchainAddresses![checkIndex].hasBeenUsedByBittr = true
                    CacheManager.storeOnchainAddresses(self.bittrWallet.onchainAddresses!)
                    latestIndexUsedByBittr = checkIndex
                    hasFoundUsedAddress = true
                } else {
                    // Address hasn't been used.
                    CacheManager.storeLastAddress(newAddress: thisAddress.onchainAddress)
                    checkIndex -= 1
                }
            } else {
                // This address has been used.
                latestIndexUsedByBittr = checkIndex
                hasFoundUsedAddress = true
            }
        }
        
        DispatchQueue.global(qos: .background).async {
            // Check whether any additional addresses need to be revealed.
            var numberOfUnusedAddresses = self.bittrWallet.onchainAddresses!.count - (latestIndexUsedByBittr+1)
            if numberOfUnusedAddresses < 10 {
                // Not enough addresses available.
                Log.info("Reveal more addresses.")
                
                var addressIndex = self.bittrWallet.onchainAddresses!.count
                while numberOfUnusedAddresses < 10 {
                    let newAddress = OnchainAddress()
                    newAddress.onchainAddress = BitcoinManager.shared.getAddress(atIndex: addressIndex)
                    newAddress.addressIndex = addressIndex
                    self.bittrWallet.onchainAddresses! += [newAddress]
                    // Also reveal address in LDKNode.
                    let newLDKAddress = self.getNewOnchainAddress() ?? ""
                    print("BDK and LDK match: \(newAddress.onchainAddress == newLDKAddress)")
                    addressIndex += 1
                    numberOfUnusedAddresses += 1
                }
                self.bittrWallet.onchainAddresses!.sort { address1, address2 in
                    address1.addressIndex < address2.addressIndex
                }
                CacheManager.storeOnchainAddresses(self.bittrWallet.onchainAddresses!)
                
                // Check new addresses with Bittr.
                Task { await self.checkOnchainAddressesWithBittr() }
            } else {
                // Enough addresses available.
                Log.info("Onchain address management successful.")

                // Verify the currently cached address.
                let unusedAddresses = self.bittrWallet.onchainAddresses!.filter { !$0.hasBeenUsedByBittr }
                let cached = CacheManager.getLastAddress()
                let cachedIsValidUnused = cached != nil && unusedAddresses.contains { $0.onchainAddress == cached }
                if !cachedIsValidUnused, let firstUnused = unusedAddresses.first {
                    CacheManager.storeLastAddress(newAddress: firstUnused.onchainAddress)
                }
                
                // Alert ReceiveVC that address management has completed.
                DispatchQueue.main.async {
                    self.bittrWallet.onchainAddressesVerified = true
                    self.receiveVC?.onchainAddressesReady()
                }
            }
        }
    }
}

extension OnchainAddress {
    
    func checkHasBeenUsedByBittr() async -> Bool? {
        
        let url = "\(EnvironmentConfig.esploraURL)/address/\(self.onchainAddress)"
        
        let receivedDict:NSDictionary
        do {
            receivedDict = try await withThrowingTaskGroup(of: NSDictionary.self) { group in
                
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        Task {
                            await CallsManager.makeApiCall(url: url, parameters: nil, getOrPost: .get) { result in
                                switch result {
                                case .success(let json):
                                    continuation.resume(returning: json)
                                case .failure(let error):
                                    continuation.resume(throwing: error)
                                }
                            }
                        }
                    }
                }
                
                group.addTask {
                    try await Task.sleep(nanoseconds: 10 * NSEC_PER_SEC)
                    throw NSError(
                        domain: "Timeout",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Request timed out"]
                    )
                }
                
                let firstResult = try await group.next()!
                group.cancelAll()
                return firstResult
            }
        } catch {
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "ReceiveOnchain row 133", key: "context")
                }
            }
            return nil
        }
        
        if let chainStats = receivedDict["chain_stats"] as? NSDictionary, let txCount = chainStats["tx_count"] as? Int {
            
            if txCount == 0 {
                return false
            } else {
                return true
            }
        } else {
            // Expected data missing.
            return nil
        }
    }
}
