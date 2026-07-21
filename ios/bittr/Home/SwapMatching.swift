//
//  SwapMatching.swift
//  bittr
//
//  Created by Tom Melters on 7/21/26.
//

import UIKit

extension [Transaction] {
    
    func performSwapMatching() -> [Transaction] {
        
        // Gather all transactions.
        var currentTransactions = self
        
        // Create pairs of swap transactions.
        var swapGroups: [String: [Transaction]] = [:]
        for eachTransaction in currentTransactions where eachTransaction.lnDescription.contains("Swap") {
            swapGroups[eachTransaction.lnDescription, default: []].append(eachTransaction)
        }
        
        for (swapID, pairedTransactions) in swapGroups {
            if pairedTransactions.count == 2 {
                handleCompletedSwap(swapID: swapID, first: pairedTransactions[0], second: pairedTransactions[1], in: &currentTransactions)
            } else if pairedTransactions.count == 1, !pairedTransactions[0].isSwap {
                handlePendingSwap(swapID: swapID, leg: pairedTransactions[0], in: &currentTransactions)
            }
        }
        
        return currentTransactions
    }
    
    private func handleCompletedSwap(swapID: String, first: Transaction, second: Transaction, in currentTransactions: inout [Transaction]) {
        Log.info("Found completed swap.")
        print("Swap ID: \(swapID)")
        
        if swapID.contains(first.id), first.swapStatus == .succeeded {
            // `first` is already the completed swap transaction; drop the other leg.
            currentTransactions.removeAll { $0.id == second.id }
            CacheManager.storeLightningTransaction(first)
            return
        }
        if swapID.contains(second.id), second.swapStatus == .succeeded {
            // `second` is already the completed swap transaction; drop the other leg.
            currentTransactions.removeAll { $0.id == first.id }
            CacheManager.storeLightningTransaction(second)
            return
        }
        
        let swapTransaction = makeCompletedSwapTransaction(swapID: swapID, first: first, second: second)
        
        // Replace the two individual legs with the combined swap transaction.
        let legIDs = [first.id, second.id]
        currentTransactions.removeAll { legIDs.contains($0.id) }
        currentTransactions.append(swapTransaction)
        CacheManager.storeLightningTransaction(swapTransaction)
    }
    
    private func makeCompletedSwapTransaction(swapID: String, first: Transaction, second: Transaction) -> Transaction {
        
        let swapTransaction = Transaction()
        swapTransaction.id = swapID.replacingOccurrences(of: "Swap lightning to onchain ", with: "").replacingOccurrences(of: "Swap onchain to lightning ", with: "")
        swapTransaction.isSwap = true
        swapTransaction.boltzSwapId = CacheManager.getSwapID(dateID: swapID) ?? "Unavailable"
        swapTransaction.lnDescription = swapID
        
        // Amount and fees.
        swapTransaction.sent = first.received + second.received - first.sent - second.sent
        swapTransaction.fee = first.fee + second.fee
        
        // Direction.
        swapTransaction.swapDirection = swapID.contains("onchain to lightning") ? .onchainToLightning : .lightningToOnchain
        swapTransaction.isLightning = swapID.contains("lightning to onchain")
        
        for leg in [first, second] {
            if leg.isLightning {
                // Lightning payment
                swapTransaction.lightningID = leg.isSwap ? leg.lightningID : leg.id
                swapTransaction.channelId = leg.channelId
                if swapTransaction.swapDirection == .onchainToLightning {
                    swapTransaction.timestamp = leg.timestamp
                    swapTransaction.received = leg.received
                } else {
                    swapTransaction.sent = leg.sent
                }
            } else {
                // Onchain transaction
                swapTransaction.onchainID = leg.isSwap ? leg.onchainID : leg.id
                swapTransaction.height = leg.height
                if swapTransaction.swapDirection == .lightningToOnchain {
                    swapTransaction.timestamp = leg.timestamp
                    swapTransaction.received = leg.received - leg.sent
                } else {
                    swapTransaction.sent = leg.sent - leg.received
                }
            }
        }
        
        if !first.isLightning, !second.isLightning {
            // Both transactions are onchain. This is a failed normal swap.
            swapTransaction.timestamp = first.timestamp
            swapTransaction.sent = first.sent + second.sent
            swapTransaction.received = first.received + second.received
            swapTransaction.swapStatus = .failed
            
            if (first.received - first.sent) < (second.received - second.sent) {
                // The 2nd transaction is the refund.
                swapTransaction.onchainID = first.id
                swapTransaction.lightningID = second.id
            } else {
                // The 1st transaction is the refund.
                swapTransaction.onchainID = second.id
                swapTransaction.lightningID = first.id
            }
        }
        
        return swapTransaction
    }
    
    private func handlePendingSwap(swapID: String, leg: Transaction, in currentTransactions: inout [Transaction]) {
        Log.info("Found pending swap.")
        print("Swap ID: \(swapID)")
        
        if let suggestedSwapStatus = CacheManager.getSuggestedSwapStatus(dateID: swapID) {
            leg.isSuggestedSwap = true
            leg.swapStatus = suggestedSwapStatus
            leg.swapDirection = swapID.contains("onchain to lightning") ? .onchainToLightning : .lightningToOnchain
            leg.boltzSwapId = CacheManager.getSwapID(dateID: swapID) ?? "Unavailable"
            return
        }
        
        let swapTransaction = Transaction()
        swapTransaction.isSwap = true
        swapTransaction.swapStatus = .pending
        swapTransaction.boltzSwapId = CacheManager.getSwapID(dateID: swapID) ?? "Unavailable"
        swapTransaction.lnDescription = swapID
        
        swapTransaction.timestamp = leg.timestamp
        swapTransaction.sent = leg.sent
        swapTransaction.received = leg.received
        swapTransaction.isLightning = leg.isLightning
        swapTransaction.id = swapID.replacingOccurrences(of: "Swap lightning to onchain ", with: "").replacingOccurrences(of: "Swap onchain to lightning ", with: "")
        
        swapTransaction.swapDirection = swapID.contains("onchain to lightning") ? .onchainToLightning : .lightningToOnchain
        
        if swapTransaction.isLightning {
            swapTransaction.lightningID = leg.id
            swapTransaction.channelId = leg.channelId
        } else {
            swapTransaction.onchainID = leg.id
            swapTransaction.height = leg.height
        }
        
        // Replace the individual leg with the combined swap transaction.
        currentTransactions.removeAll { $0.id == leg.id }
        currentTransactions.append(swapTransaction)
    }
}
