//
//  SendableAmount.swift
//  bittr
//
//  Created by Tom Melters on 3/6/26.
//

import Foundation
import LDKNode
import Sentry

extension SwapViewController {
    
    func bdkWalletUnavailable() {
        self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
        self.bdkSpinner.startAnimating()
        self.showAlert(presentingController: self, title: Language.getWord(withID: "syncing"), message: Language.getWord(withID: "awaitingbdksync"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        
        if !BitcoinManager.shared.bdkWalletIsScanning {
            Log.info("BDK wallet isn't scanning. Will start scan.")
            
            BitcoinManager.shared.didStartBDK { success in
                if success {
                    Log.info("Did start BDK.")
                    BitcoinManager.shared.didSyncBdkWallet { hasBeenSynced in
                        if hasBeenSynced {
                            Log.info("Did scan BDK wallet.")
                            self.calculateSendableAmount()
                        } else {
                            Log.info("Could not scan BDK wallet.")
                        }
                    }
                } else {
                    Log.info("Could not start BDK.")
                }
            }
        } else {
            Log.info("Waiting for BDK wallet to finish scanning.")
        }
    }
    
    func calculateSendableAmount() {
        self.bdkSpinner.stopAnimating()
        
        let activeChannel:LDKNode.ChannelDetails? = self.coreVC!.bittrWallet.lightningChannels.getActiveChannel()
        
        if activeChannel == nil {
            // There is no active Lightning channel.
            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
        } else {
            // There is an active Lightning channel.
            
            if self.swapDirection == .lightningToOnchain {
                // We can send our Lightning balance minus the reserve.
                
                self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "\(Int(activeChannel!.outboundCapacityMsat/1000))".addSpaces())
            } else {
                // We can send our available channel space, if we have enough onchain satoshis.
                
                if BitcoinManager.shared.bdkWallet == nil || !BitcoinManager.shared.bdkWalletHasBeenScanned {
                    Log.info("BDK wallet isn't available yet.")
                    self.bdkWalletUnavailable()
                    return
                }
                
                if self.coreVC!.bittrWallet.satoshisOnchain == 0 {
                    // There are no onchain funds.
                    self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
                    return
                }
                
                // Calculate available channel space.
                let availableChannelSpace:Int = Int(activeChannel!.channelValueSats) - Int(activeChannel!.outboundCapacityMsat/1000) - Int(activeChannel!.unspendablePunishmentReserve ?? 0) - Int(activeChannel!.counterpartyUnspendablePunishmentReserve)
                
                // Calculate available onchain satoshis minus fast fee.
                // Calculate maximum sendable onchain amount at lowest fee.
                let maximumSendableOnchainBtc = self.getMaximumSendableSats(coreVC:self.coreVC!) ?? self.coreVC!.bittrWallet.satoshisOnchain.inBTC()
                let maximumSendableOnchainSats = CGFloat(maximumSendableOnchainBtc).inSatoshis()
                
                Task {
                    let feeEstimates = await BitcoinManager.shared.getFeeEstimates()
                    if feeEstimates == nil {
                        Log.info("Could not fetch fee estimates.")
                        DispatchQueue.main.async {
                            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
                        }
                        return
                    }
                    
                    // Select highest fee.
                    self.highestFeePerVbyte = Float(feeEstimates!["fastestFee"] as! Double)
                    
                    // Get own onchain address.
                    let actualAddress:String? = self.getCachedOnchainAddress() ?? BitcoinManager.shared.getNewOnchainAddress()
                    
                    if actualAddress == nil {
                        Log.info("Could not fetch address.")
                        DispatchQueue.main.async {
                            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
                        }
                        return
                    }
                    
                    // Cache address in case no onchain address is currently cached.
                    if self.getCachedOnchainAddress() == nil {
                        CacheManager.storeLastAddress(newAddress: actualAddress!)
                    }
                    
                    var sizeinVbytes:UInt64
                    do {
                        // Calculate transaction size.
                        sizeinVbytes = try BitcoinManager.shared.getSize(address: actualAddress!, amountSats: maximumSendableOnchainSats)
                    } catch {
                        Log.info("Error: \(error.localizedDescription)")
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "SwapVC row 308", key: "context")
                        }
                        DispatchQueue.main.async {
                            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
                        }
                        return
                    }
                    
                    // Calculate highest fee in satoshis.
                    let satoshisFee:Int = Int(self.highestFeePerVbyte! * Float(sizeinVbytes))
                    
                    // Onchain satoshis minus highest fee.
                    let sendableSatoshis = self.coreVC!.bittrWallet.satoshisOnchain - satoshisFee
                    
                    // Set label.
                    DispatchQueue.main.async {
                        if sendableSatoshis > availableChannelSpace {
                            // We have enough onchain satoshis to fill up the entire channel.
                            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "\(availableChannelSpace)".addSpaces())
                        } else {
                            // We don't have enough onchain satoshis to fill up the entire channel.
                            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "\(sendableSatoshis)".addSpaces())
                        }
                    }
                }
            }
        }
    }
}
