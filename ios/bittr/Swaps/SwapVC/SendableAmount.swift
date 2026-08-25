//
//  SendableAmount.swift
//  bittr
//
//  Created by Tom Melters on 3/6/26.
//

import Foundation
import BitcoinDevKit
import LDKNode

extension SwapViewController {
    
    func bdkWalletUnavailable() {
        self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
        self.bdkSpinner.startAnimating()
        self.showAlert(title: Language.getWord(withID: "syncing"), message: Language.getWord(withID: "awaitingbdksync"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        
        if !BitcoinManager.shared.bdkWalletIsScanning {
            Log.info("BDK wallet isn't scanning. Will start scan.")

            // didStartBDK is synchronous and blocking (descriptor derivation,
            // SQLite connection, electrum client setup), so run it off main
            // and hop back for the UI outcomes. didSyncBdkWallet manages its
            // own threading and completes on main.
            DispatchQueue.global(qos: .userInitiated).async {
                let didStartBDK = BitcoinManager.shared.didStartBDK()
                DispatchQueue.main.async {
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
                }
            }
        } else {
            Log.info("Waiting for BDK wallet to finish scanning.")
        }
    }

    func calculateSendableAmount() {
        self.bdkSpinner.stopAnimating()
        
        // Get active Lightning channel.
        let activeChannel:LDKNode.ChannelDetails? = BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()
        guard let activeChannel else {
            // There is no active Lightning channel.
            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
            return
        }
        
        if self.swapDirection == .lightningToOnchain {
            // Swap direction: lightning-to-onchain.
            // We can send the channel's outbound capacity.
            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "\(Int(activeChannel.outboundCapacityMsat/1000))".addSpaces())
            return
        }
        // Swap direction: onchain-to-lightning.
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
        let availableChannelSpace:Int = Int(activeChannel.channelValueSats) - Int(activeChannel.outboundCapacityMsat/1000) - Int(activeChannel.unspendablePunishmentReserve ?? 0) - Int(activeChannel.counterpartyUnspendablePunishmentReserve)
        
        self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
        self.bdkSpinner.startAnimating()
        
        // Capture intended direction.
        let requestedDirection = self.swapDirection
        
        Task {
            guard let feeEstimates = await BitcoinManager.shared.getFeeEstimates() else {
                Log.info("Could not fetch fee estimates.")
                DispatchQueue.main.async {
                    guard self.swapDirection == requestedDirection else { return }
                    self.bdkSpinner.stopAnimating()
                    self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
                }
                return
            }
            
            // Select highest fee.
            self.highestFeePerVbyte = feeEstimates.fastest
            
            // Calculate maximum sendable onchain satoshis.
            let sendableSatoshis:Int
            do {
                // Go through maximumSendableOnchainDrain rather than
                // previewOnchainDrain: BDK will happily drain the reserve
                // LDK Node holds back for anchor channels, and only the
                // former clamps against LDK's spendable balance. The
                // recipient isn't known yet, so this quotes against the
                // heaviest common output script.
                let preview = try BitcoinManager.shared.maximumSendableOnchainDrain(
                    toAddress: nil,
                    satPerVb: self.highestFeePerVbyte!.wholeSatPerVb
                )
                sendableSatoshis = Int(preview.sendableSats)
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
                        SentryManager.capture(error, context: "SwapVC row 308")
                        self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
                    }
                }
                return
            }
            
            // Set label.
            DispatchQueue.main.async {
                guard self.swapDirection == requestedDirection else { return }
                self.bdkSpinner.stopAnimating()
                self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "\(min(availableChannelSpace, sendableSatoshis))".addSpaces())
            }
        }
    }

    // MARK: - Suggested swap

    func startSuggestedOnchainToLightningSwap() {
        if BitcoinManager.shared.bdkWallet != nil && BitcoinManager.shared.bdkWalletHasBeenScanned {
            // BDK is ready: refresh the label for the new direction and swap.
            self.calculateSendableAmount()
            self.beginSuggestedSwap()
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
            self.beginSuggestedSwap()
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

        // didStartBDK is synchronous and blocking — run it off main (this
        // function is reached via main-queue polling in awaitBdkScan). The
        // completions are already marshalled back to main.
        DispatchQueue.global(qos: .userInitiated).async {
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
    }
    
    private func beginSuggestedSwap() {
        Task {
            await SwapManager.onchainToLightning(swapVC: self, existingInvoice: self.pendingLightningInvoice)
        }
    }
}
