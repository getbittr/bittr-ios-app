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
    
    // How far to search for LDK's latest address in our own derivation before giving up.
    static let maxOnchainAddressSearchIndex = 2500
    
    func manageOnchainAddresses() {
        
        if CacheManager.getOnchainAddresses().count == 0 {
            Log.info("Onchain addresses need to be cached.")
            self.revealOnchainAddresses()
        } else {
            Log.info("Onchain addresses have been found in cache.")
            BitcoinManager.shared.bittrWallet.onchainAddresses = CacheManager.getOnchainAddresses()
            Task { await self.checkOnchainAddressesWithBittr() }
        }
    }
    
    func finishOnchainAddressManagement(for wallet:BittrWallet? = nil) {
        DispatchQueue.main.async {
            if let wallet, BitcoinManager.shared.bittrWallet !== wallet {
                Log.info("Wallet was replaced during address management; leaving its successor's gate closed.")
                return
            }
            // Mark that onchain address verification has completed.
            BitcoinManager.shared.bittrWallet.onchainAddressesVerified = true
            // In case the user has opened the ReceiveVC, make the onchain address spinner stop animating.
            self.receiveVC?.onchainAddressesReady()
        }
    }
    
    func revealOnchainAddresses() {
        Log.info("Reveal onchain addresses.")
        guard let lastRevealedOnchainAddress = self.getNewOnchainAddress() else {
            Log.info("Could not derive an address (e.g. LDKNode is unavailable).")
            self.finishOnchainAddressManagement()
            return
        }
        
        // Walk up from index 0 until we meet the address LDK just handed us.
        var peekedAddresses = [String]()
        var lastRevealedIndex:Int?
        var searchIndex = 0
        while searchIndex <= CoreViewController.maxOnchainAddressSearchIndex {
            guard let peekedAddress = BitcoinManager.shared.getAddress(atIndex: searchIndex, doReveal: false) else {
                Log.info("BDK wallet went away while identifying revealed onchain addresses.")
                self.finishOnchainAddressManagement()
                return
            }
            peekedAddresses += [peekedAddress]
            if peekedAddress == lastRevealedOnchainAddress {
                lastRevealedIndex = searchIndex
                break
            }
            searchIndex += 1
        }
        
        guard let lastRevealedIndex else {
            // BDK and LDK are deriving different addresses from the same seed. Bail.
            Log.info("Could not match LDK's address within \(CoreViewController.maxOnchainAddressSearchIndex) derived addresses.")
            DispatchQueue.main.async {
                SentrySDK.capture(message: "BDK could not derive the address LDK reports as latest. Descriptors may have diverged.") { scope in
                    scope.setExtra(value: CoreViewController.maxOnchainAddressSearchIndex, key: "searchedToIndex")
                }
            }
            self.finishOnchainAddressManagement()
            return
        }
        
        // Now reveal the whole range in one write, so these addresses are picked up by any lightSync.
        BitcoinManager.shared.revealAddresses(toIndex: lastRevealedIndex)
        
        var revealedAddresses = [OnchainAddress]()
        for (index, peekedAddress) in peekedAddresses.enumerated() {
            let newAddress = OnchainAddress()
            newAddress.onchainAddress = peekedAddress
            newAddress.addressIndex = index
            revealedAddresses += [newAddress]
        }
        
        Log.info("All revealed onchain addresses have been identified.")
        
        // Update cache.
        BitcoinManager.shared.bittrWallet.onchainAddresses = revealedAddresses
        CacheManager.storeOnchainAddresses(revealedAddresses)
        
        // Check which onchain addresses Bittr has already used.
        Task { await self.checkOnchainAddressesWithBittr() }
    }
    
    func checkOnchainAddressesWithBittr() async {
        let walletAtStart = BitcoinManager.shared.bittrWallet
        guard var onchainAddresses = walletAtStart.onchainAddresses, !onchainAddresses.isEmpty else {
            Log.info("No onchain addresses to check (pool empty or wallet resetting).")
            self.finishOnchainAddressManagement(for: walletAtStart)
            return
        }

        var hasFoundUsedAddress = false
        var checkIndex = onchainAddresses.count - 1
        var latestIndexUsedByBittr = 0

        while !hasFoundUsedAddress && checkIndex >= 0 {
            let thisAddress = onchainAddresses[checkIndex]

            if !thisAddress.hasBeenUsedByBittr {
                // Address needs to be checked with Bittr.

                let checkResult = await thisAddress.checkHasBeenUsed()

                // The wallet may have been reset while we were suspended.
                guard BitcoinManager.shared.bittrWallet === walletAtStart else {
                    Log.info("Wallet was reset during the address check — abandoning.")
                    self.finishOnchainAddressManagement(for: walletAtStart)
                    return
                }

                if checkResult == nil {
                    Log.info("Could not verify onchain address at index \(checkIndex); stopping the check and keeping the cached pool.")
                    self.finishOnchainAddressManagement(for: walletAtStart)
                    return
                } else if checkResult! == true {
                    // Did find used address. Update cache. (OnchainAddress is
                    // a class, so this mark also lands on the live pool.)
                    onchainAddresses[checkIndex].hasBeenUsedByBittr = true
                    CacheManager.storeOnchainAddresses(onchainAddresses)
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
            guard BitcoinManager.shared.bittrWallet === walletAtStart else {
                Log.info("Wallet was reset during the address check — abandoning.")
                self.finishOnchainAddressManagement(for: walletAtStart)
                return
            }

            // Check whether any additional addresses need to be revealed.
            var numberOfUnusedAddresses = onchainAddresses.count - (latestIndexUsedByBittr+1)
            if numberOfUnusedAddresses < 10 {
                // Not enough addresses available.
                Log.info("Reveal more addresses.")

                var addressIndex = onchainAddresses.count
                while numberOfUnusedAddresses < 10 {
                    guard let derivedAddress = BitcoinManager.shared.getAddress(atIndex: addressIndex) else {
                        Log.info("BDK wallet went away while revealing more onchain addresses.")
                        self.finishOnchainAddressManagement(for: walletAtStart)
                        return
                    }
                    let newAddress = OnchainAddress()
                    newAddress.onchainAddress = derivedAddress
                    newAddress.addressIndex = addressIndex
                    onchainAddresses += [newAddress]
                    // Also reveal address in LDKNode.
                    let newLDKAddress = self.getNewOnchainAddress() ?? ""
                    print("BDK and LDK match: \(newAddress.onchainAddress == newLDKAddress)")
                    addressIndex += 1
                    numberOfUnusedAddresses += 1
                }
                onchainAddresses.sort { address1, address2 in
                    address1.addressIndex < address2.addressIndex
                }

                // Publish the grown pool — unless the wallet was reset while
                // we revealed, in which case it belongs to a discarded wallet.
                guard BitcoinManager.shared.bittrWallet === walletAtStart else {
                    Log.info("Wallet was reset during address reveal — abandoning.")
                    self.finishOnchainAddressManagement(for: walletAtStart)
                    return
                }
                BitcoinManager.shared.bittrWallet.onchainAddresses = onchainAddresses
                CacheManager.storeOnchainAddresses(onchainAddresses)

                // Check new addresses with Bittr.
                Task { await self.checkOnchainAddressesWithBittr() }
            } else {
                // Enough addresses available.
                Log.info("Onchain address management successful.")

                // Reveal a little beyond the pool.
                // This is to anticipate any channel closure, which reveals the next address in LDKNode.
                BitcoinManager.shared.revealAddresses(toIndex: onchainAddresses.count + 4)
                
                // Verify the currently cached address.
                let unusedAddresses = onchainAddresses.filter { !$0.hasBeenUsedByBittr }
                let cached = CacheManager.getLastAddress()
                let cachedIsValidUnused = cached != nil && unusedAddresses.contains { $0.onchainAddress == cached }
                if !cachedIsValidUnused, let firstUnused = unusedAddresses.first {
                    CacheManager.storeLastAddress(newAddress: firstUnused.onchainAddress)
                }

                // Alert ReceiveVC that address management has completed.
                self.finishOnchainAddressManagement(for: walletAtStart)
            }
        }
    }
}

extension OnchainAddress {
    
    func checkHasBeenUsed() async -> Bool? {
        
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
        
        guard let chainStats = receivedDict["chain_stats"] as? NSDictionary, let txCount = chainStats["tx_count"] as? Int else {
            // Expected data missing.
            return nil
        }
        return txCount > 0
    }
}
