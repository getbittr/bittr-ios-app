//
//  SendableAmount.swift
//  bittr
//
//  Created by Tom Melters on 3/6/26.
//

import Foundation
import BitcoinDevKit
import LDKNode
import Sentry

extension SwapViewController {
    
    func bdkWalletUnavailable() {
        self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
        self.bdkSpinner.startAnimating()
        self.showAlert(presentingController: self, title: Language.getWord(withID: "syncing"), message: Language.getWord(withID: "awaitingbdksync"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        
        if !BitcoinManager.shared.bdkWalletIsScanning {
            Log.info("BDK wallet isn't scanning. Will start scan.")
            
            let didStartBDK = BitcoinManager.shared.didStartBDK()
            if didStartBDK {
                Log.info("Did start BDK.")
                BitcoinManager.shared.didSyncBdkWallet { hasBeenSynced in
                    if hasBeenSynced {
                        Log.info("Did scan BDK wallet.")
                        self.calculateSendableAmount()
                    } else {
                        Log.info("Could not scan BDK wallet.")
                        self.presentOnchainSyncFailedAlert()
                    }
                }
            } else {
                Log.info("Could not start BDK.")
                self.presentOnchainSyncFailedAlert()
            }
        } else {
            Log.info("Waiting for BDK wallet to finish scanning.")
        }
    }

    func calculateSendableAmount() {
        self.bdkSpinner.stopAnimating()
        
        let activeChannel:LDKNode.ChannelDetails? = BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()
        
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
                
                if BitcoinManager.shared.bittrWallet.satoshisOnchain == 0 {
                    // There are no onchain funds.
                    self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
                    return
                }
                
                // Calculate available channel space.
                let availableChannelSpace:Int = Int(activeChannel!.channelValueSats) - Int(activeChannel!.outboundCapacityMsat/1000) - Int(activeChannel!.unspendablePunishmentReserve ?? 0) - Int(activeChannel!.counterpartyUnspendablePunishmentReserve)
                
                // Calculate available onchain satoshis minus fast fee.
                // Calculate maximum sendable onchain amount at lowest fee.
                let maximumSendableOnchainBtc = self.getMaximumSendableSats() ?? BitcoinManager.shared.bittrWallet.satoshisOnchain.inBTC()
                let maximumSendableOnchainSats = CGFloat(maximumSendableOnchainBtc).inSatoshis()
                
                self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
                self.bdkSpinner.startAnimating()
                
                // Capture intended direction.
                let requestedDirection = self.swapDirection

                Task {
                    let feeEstimates = await BitcoinManager.shared.getFeeEstimates()
                    if feeEstimates == nil {
                        Log.info("Could not fetch fee estimates.")
                        DispatchQueue.main.async {
                            guard self.swapDirection == requestedDirection else { return }
                            self.bdkSpinner.stopAnimating()
                            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
                        }
                        return
                    }
                    
                    // Select highest fee.
                    self.highestFeePerVbyte = Float(feeEstimates!["fastestFee"] as! Double)
                    
                    // Get own onchain address.
                    let actualAddress:String = BitcoinManager.shared.getAddress(atIndex: 0)
                    
                    var sizeinVbytes:UInt64
                    do {
                        // Calculate transaction size.
                        sizeinVbytes = try BitcoinManager.shared.getSize(address: actualAddress, amountSats: maximumSendableOnchainSats)
                    } catch {
                        Log.info("Error: \(error.localizedDescription)")

                        // bdkWalletHasBeenScanned is sticky — set once on first
                        // sync and never cleared — so the guard at the top of
                        // this function doesn't catch the case where BDK has
                        // scanned in the past but is now stale (e.g. a swap
                        // claim just landed onchain, so LDK Node sees the new
                        // UTXO but BDK hasn't rescanned). Detect that here:
                        // if BDK rejects with insufficient funds while LDK
                        // Node reports a non-zero balance, force a rescan and
                        // recompute once it finishes.
                        var bdkLooksStale = false
                        if let bdkError = error as? BitcoinDevKit.CreateTxError {
                            switch bdkError {
                            case .CoinSelection, .InsufficientFunds:
                                bdkLooksStale = BitcoinManager.shared.bittrWallet.satoshisOnchain > 0
                            default:
                                break
                            }
                        }

                        DispatchQueue.main.async {
                            guard self.swapDirection == requestedDirection else { return }
                            if bdkLooksStale && !self.didRescanForStaleBdk {
                                Log.info("BDK looks stale (LDK Node onchain balance: \(BitcoinManager.shared.bittrWallet.satoshisOnchain), BDK rejected). Forcing rescan.")
                                self.didRescanForStaleBdk = true
                                // bdkWalletUnavailable keeps the spinner running while it rescans.
                                self.bdkWalletUnavailable()
                            } else {
                                self.bdkSpinner.stopAnimating()
                                SentrySDK.capture(error: error) { scope in
                                    scope.setExtra(value: "SwapVC row 308", key: "context")
                                }
                                self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
                            }
                        }
                        return
                    }
                    
                    // Calculate highest fee in satoshis.
                    let satoshisFee:Int = Int(self.highestFeePerVbyte! * Float(sizeinVbytes))
                    
                    // Onchain satoshis minus highest fee.
                    let sendableSatoshis = BitcoinManager.shared.bittrWallet.satoshisOnchain - satoshisFee
                    
                    // Set label.
                    DispatchQueue.main.async {
                        guard self.swapDirection == requestedDirection else { return }
                        self.bdkSpinner.stopAnimating()
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

    // MARK: - Suggested swap

    func startSuggestedOnchainToLightningSwap(invoiceAmount: Int) {
        if BitcoinManager.shared.bdkWallet != nil && BitcoinManager.shared.bdkWalletHasBeenScanned {
            // BDK is ready: refresh the label for the new direction and swap.
            self.calculateSendableAmount()
            self.beginSuggestedSwap(invoiceAmount: invoiceAmount)
            return
        }
        
        Log.info("BDK wallet isn't available yet; syncing before starting the suggested swap.")
        
        // Reflect the syncing state on the sendable-amount label while we wait.
        self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
        self.bdkSpinner.startAnimating()

        self.awaitBdkScan { [weak self] didScan in
            guard let self = self else { return }
            guard didScan else {
                Log.info("BDK wallet could not be scanned; aborting the suggested swap so the user can retry.")
                // Reset the loading state so the user can retry via Next, which
                // runs its own BDK-availability guard.
                self.nextLabel.alpha = 1
                self.arrowIcon.alpha = 1
                self.nextSpinner.stopAnimating()
                // Let the user know the on-chain sync failed and to retry later
                // (also stops the bdkSpinner).
                self.presentOnchainSyncFailedAlert()
                return
            }
            // BDK is ready now: refresh the label and start the swap.
            self.calculateSendableAmount()
            self.beginSuggestedSwap(invoiceAmount: invoiceAmount)
        }
    }
    
    private func awaitBdkScan(completion: @escaping (Bool) -> Void) {
        // Bound the whole wait so a hung scan can't poll forever; give up after
        // the timeout and let the caller show the sync-failed alert.
        self.awaitBdkScan(deadline: Date().addingTimeInterval(180), completion: completion)
    }

    private func awaitBdkScan(deadline: Date, completion: @escaping (Bool) -> Void) {
        if BitcoinManager.shared.bdkWalletHasBeenScanned {
            DispatchQueue.main.async { completion(true) }
            return
        }

        if BitcoinManager.shared.bdkWalletIsScanning {
            // A scan is already running — poll for it to finish, but stop once we
            // pass the deadline so a stuck scan doesn't loop indefinitely.
            guard Date() < deadline else {
                Log.info("BDK scan didn't finish within the timeout; aborting the suggested swap.")
                DispatchQueue.main.async { completion(false) }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.awaitBdkScan(deadline: deadline, completion: completion)
            }
            return
        }

        let didStartBDK = BitcoinManager.shared.didStartBDK()
        guard didStartBDK else {
            Log.info("Could not start BDK for suggested swap.")
            DispatchQueue.main.async { completion(false) }
            return
        }
        BitcoinManager.shared.didSyncBdkWallet { hasBeenSynced in
            DispatchQueue.main.async { completion(hasBeenSynced) }
        }
    }
    
    private func beginSuggestedSwap(invoiceAmount: Int) {
        Task {
            await SwapManager.onchainToLightning(amountMsat: UInt64(invoiceAmount*1000), swapVC: self, existingInvoice: self.pendingLightningInvoice)
        }
    }
}
