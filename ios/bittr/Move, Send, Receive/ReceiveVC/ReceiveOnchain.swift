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
            BitcoinManager.shared.bittrWallet.onchainAddresses = CacheManager.getOnchainAddresses()
            Task { await self.checkOnchainAddressesWithBittr() }
        }
    }
    
    func revealOnchainAddresses() {
        Log.info("Reveal onchain addresses.")

        guard let lastRevealedOnchainAddress = self.getNewOnchainAddress() else {
            // Could not derive an address (e.g. the LDK node is unavailable). The
            // normal completion path (checkOnchainAddressesWithBittr → "enough
            // addresses" branch) is what sets onchainAddressesVerified, and we're
            // bailing before reaching it — so without this, ReceiveVC's onchain
            // gate would wait forever. Mark verification done and notify so the
            // screen shows the best-available (cached) address instead of hanging.
            DispatchQueue.main.async {
                BitcoinManager.shared.bittrWallet.onchainAddressesVerified = true
                self.receiveVC?.onchainAddressesReady()
            }
            return
        }

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
        BitcoinManager.shared.bittrWallet.onchainAddresses = revealedAddresses
        CacheManager.storeOnchainAddresses(revealedAddresses)
        
        // Check which onchain addresses Bittr has already used.
        Task { await self.checkOnchainAddressesWithBittr() }
    }
    
    func checkOnchainAddressesWithBittr() async {

        // Bind the wallet and its address pool ONCE. performWalletReset can
        // replace bittrWallet while this task is suspended in the network
        // await below (e.g. a wallet removal resumed on relaunch), so
        // re-reading the force-unwrapped property mid-run trapped on nil —
        // this crash reproducibly killed the suite's removal flows. The
        // identity guards after each suspension also stop post-reset cache
        // writes: deleteClientInfo deliberately clears the address cache, and
        // a late write-back here would hand the NEXT wallet its predecessor's
        // addresses.
        let walletAtStart = BitcoinManager.shared.bittrWallet
        guard var onchainAddresses = walletAtStart.onchainAddresses, !onchainAddresses.isEmpty else {
            Log.info("No onchain addresses to check (pool empty or wallet resetting).")
            return
        }

        var hasFoundUsedAddress = false
        var checkIndex = onchainAddresses.count - 1
        var latestIndexUsedByBittr = 0

        while !hasFoundUsedAddress && checkIndex >= 0 {
            let thisAddress = onchainAddresses[checkIndex]

            if !thisAddress.hasBeenUsedByBittr {
                // Address needs to be checked with Bittr.

                let checkResult = await thisAddress.checkHasBeenUsedByBittr()

                // The wallet may have been reset while we were suspended.
                guard BitcoinManager.shared.bittrWallet === walletAtStart else {
                    Log.info("Wallet was reset during the address check — abandoning.")
                    return
                }

                if checkResult == nil {
                    Log.info("Did not receive valid API result for onchain address.")
                    // Treat address as unused.
                    CacheManager.storeLastAddress(newAddress: thisAddress.onchainAddress)
                    checkIndex -= 1
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
                return
            }

            // Check whether any additional addresses need to be revealed.
            var numberOfUnusedAddresses = onchainAddresses.count - (latestIndexUsedByBittr+1)
            if numberOfUnusedAddresses < 10 {
                // Not enough addresses available.
                Log.info("Reveal more addresses.")

                var addressIndex = onchainAddresses.count
                while numberOfUnusedAddresses < 10 {
                    let newAddress = OnchainAddress()
                    newAddress.onchainAddress = BitcoinManager.shared.getAddress(atIndex: addressIndex)
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
                    return
                }
                BitcoinManager.shared.bittrWallet.onchainAddresses = onchainAddresses
                CacheManager.storeOnchainAddresses(onchainAddresses)

                // Check new addresses with Bittr.
                Task { await self.checkOnchainAddressesWithBittr() }
            } else {
                // Enough addresses available.
                Log.info("Onchain address management successful.")

                // Verify the currently cached address.
                let unusedAddresses = onchainAddresses.filter { !$0.hasBeenUsedByBittr }
                let cached = CacheManager.getLastAddress()
                let cachedIsValidUnused = cached != nil && unusedAddresses.contains { $0.onchainAddress == cached }
                if !cachedIsValidUnused, let firstUnused = unusedAddresses.first {
                    CacheManager.storeLastAddress(newAddress: firstUnused.onchainAddress)
                }

                // Alert ReceiveVC that address management has completed.
                DispatchQueue.main.async {
                    guard BitcoinManager.shared.bittrWallet === walletAtStart else { return }
                    BitcoinManager.shared.bittrWallet.onchainAddressesVerified = true
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
            if !error.isConnectivityError {
                SentryManager.capture(error, context: "ReceiveOnchain row 133")
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
