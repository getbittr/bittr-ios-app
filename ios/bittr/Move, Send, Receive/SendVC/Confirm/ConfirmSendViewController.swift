//
//  ConfirmSendViewController.swift
//  bittr
//
//  Created by Tom Melters on 3/9/26.
//

import UIKit

class ConfirmSendViewController: UIViewController {
    
    // Generic
    @IBOutlet weak var yellowCard: UIView!
    @IBOutlet weak var topLabel: UILabel!
    
    // Address
    @IBOutlet weak var addressView: UIView!
    @IBOutlet weak var addressTitle: UILabel!
    @IBOutlet weak var addressLabel: UILabel!
    
    // Amount
    @IBOutlet weak var amountView: UIView!
    @IBOutlet weak var amountTitle: UILabel!
    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var amountFiatLabel: UILabel!
    
    // Lightning fees
    @IBOutlet weak var lightningFeesStack: UIView!
    @IBOutlet weak var lightningFeesStackHeight: NSLayoutConstraint!
    @IBOutlet weak var lightningFeesView: UIView!
    @IBOutlet weak var lightningFeesTitle: UILabel!
    @IBOutlet weak var lightningFeesLabel: UILabel!
    @IBOutlet weak var questionMark: UIImageView!
    @IBOutlet weak var questionMarkButton: UIButton!
    
    // Onchain fees
    @IBOutlet weak var onchainFeesStack: UIView!
    @IBOutlet weak var onchainFeesStackHeight: NSLayoutConstraint!
    @IBOutlet weak var feesTopLabel: UILabel!
    
    // Fee views
    @IBOutlet weak var feesViewFast: UIView!
    @IBOutlet weak var feesViewMedium: UIView!
    @IBOutlet weak var feesViewSlow: UIView!
    
    // Fee times
    @IBOutlet weak var timeFast: UILabel!
    @IBOutlet weak var timeMedium: UILabel!
    @IBOutlet weak var timeSlow: UILabel!
    
    // Fee sats
    @IBOutlet weak var feesFast: UILabel!
    @IBOutlet weak var feesMedium: UILabel!
    @IBOutlet weak var feesSlow: UILabel!
    
    // Fee fiat
    @IBOutlet weak var feesFiatFast: UILabel!
    @IBOutlet weak var feesFiatMedium: UILabel!
    @IBOutlet weak var feesFiatSlow: UILabel!
    
    // Fee buttons
    @IBOutlet weak var buttonFast: UIButton!
    @IBOutlet weak var buttonMedium: UIButton!
    @IBOutlet weak var buttonSlow: UIButton!
    
    // Confirm buttons
    @IBOutlet weak var backView: UIView!
    @IBOutlet weak var confirmView: UIView!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var confirmButton: UIButton!
    @IBOutlet weak var confirmLabel: UILabel!
    @IBOutlet weak var confirmSpinner: UIActivityIndicatorView!
    
    // Variables
    var sendVC:SendViewController?
    var coreVC:CoreViewController?
    
    // Fee variables
    var selectedFee:SelectedFee = .medium
    var selectedFeeInSats = 0
    var maxAvailableFeePerVb:Double?
    var newTxId = ""
    
    // The sat/vB rate behind the currently selected fee tier.
    func selectedFeeRatePerVb() -> Double {
        guard let sendVC = self.sendVC else { return 1 }
        switch self.selectedFee {
        case .high: return sendVC.feePerVbHigh
        case .medium: return sendVC.feePerVbMedium
        case .low, .custom: return self.maxAvailableFeePerVb ?? sendVC.feePerVbLow
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Tag the fee buttons so feeButtonTapped can route the tap.
        // (Was set on accessibilityIdentifier in IB; moved here so that slot
        // stays free for Maestro test IDs.)
        self.buttonFast.boundString = "high"
        self.buttonMedium.boundString = "medium"
        self.buttonSlow.boundString = "low"

        self.setBasicStyling()
        self.changeColors()
        self.setLanguage()
        self.setLabels()

        self.addressLabel.accessibilityIdentifier = TestID.Send.Confirm.addressLabel
        self.amountLabel.accessibilityIdentifier = TestID.Send.Confirm.amountLabel
        self.amountFiatLabel.accessibilityIdentifier = TestID.Send.Confirm.amountFiatLabel
        self.buttonFast.accessibilityIdentifier = TestID.Send.Confirm.feeFastButton
        self.buttonSlow.accessibilityIdentifier = TestID.Send.Confirm.feeSlowButton
        self.confirmButton.accessibilityIdentifier = TestID.Send.Confirm.confirmButton
    }
    
    func setLabels() {
        guard self.sendVC != nil else { return }
        
        // Address
        if self.sendVC!.onchainOrLightning == .onchain {
            self.addressTitle.text = Language.getWord(withID: "address")
        } else {
            self.addressTitle.text = Language.getWord(withID: "invoice")
        }
        self.addressLabel.text = self.sendVC!.confirmAddress
        
        // Amount
        self.amountLabel.text = self.sendVC!.confirmSatoshis.inBTC().formattedBitcoin() + " BTC"
        // Fiat amount
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
        self.amountFiatLabel.text = self.formattedFiatAmount()
        
        // Fees
        if self.sendVC!.onchainOrLightning == .lightning {
            // Lightning
            NSLayoutConstraint.deactivate([self.lightningFeesStackHeight, self.onchainFeesStackHeight])
            self.lightningFeesStackHeight = NSLayoutConstraint(item: self.lightningFeesStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            self.onchainFeesStackHeight = NSLayoutConstraint(item: self.onchainFeesStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.lightningFeesStackHeight, self.onchainFeesStackHeight])
            self.lightningFeesStack.alpha = 1
            self.onchainFeesStack.alpha = 0
            
            self.lightningFeesLabel.text = "1 - " + "\(self.sendVC!.confirmLightningFees)".addSpaces() + " sats"
        } else {
            // Onchain
            NSLayoutConstraint.deactivate([self.lightningFeesStackHeight, self.onchainFeesStackHeight])
            self.lightningFeesStackHeight = NSLayoutConstraint(item: self.lightningFeesStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            self.onchainFeesStackHeight = NSLayoutConstraint(item: self.onchainFeesStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.lightningFeesStackHeight, self.onchainFeesStackHeight])
            self.lightningFeesStack.alpha = 0
            self.onchainFeesStack.alpha = 1
            
            // Check fee availability
            let transactionSize = self.sendVC!.confirmTxSize
            let lowestSats = self.sendVC!.feePerVbLow.feeSats(forVsize: transactionSize)
            let availableSatsForFee = (BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0) - self.sendVC!.confirmSatoshis
            if lowestSats > availableSatsForFee {
                // There aren't enough sats available to pay for the cheapest fee.
                // Calculate the cheapest possible fee (minimum 1sat/Vbyte).
                let availableSatsPerVb = transactionSize > 0 ? Double(availableSatsForFee) / transactionSize : 1
                self.maxAvailableFeePerVb = max(availableSatsPerVb, 1)
                
                self.timeSlow.text = Language.getWord(withID: "slow")
                self.highlightFee(.low)
                self.selectedFee = .low
            }
            
            // Fees
            self.feesFast.text = "\(self.sendVC!.feePerVbHigh.feeSats(forVsize: transactionSize)) sats"
            self.feesMedium.text = "\(self.sendVC!.feePerVbMedium.feeSats(forVsize: transactionSize)) sats"
            self.feesSlow.text = "\(self.sendVC!.feePerVbLow.feeSats(forVsize: transactionSize)) sats"
            
            // Set converted fees
            self.feesFiatFast.text = self.convertFees(.high) + " " + bitcoinValue.chosenCurrency
            self.feesFiatMedium.text = self.convertFees(.medium) + " " + bitcoinValue.chosenCurrency
            self.feesFiatSlow.text = self.convertFees(.low) + " " + bitcoinValue.chosenCurrency
            
            // Custom fee
            if let maxAvailableFeePerVb = self.maxAvailableFeePerVb {
                self.feesSlow.text = "\(maxAvailableFeePerVb.feeSats(forVsize: transactionSize)) sats"
                self.feesFiatSlow.text = self.convertFees(.custom, customFees: maxAvailableFeePerVb)  + " " + bitcoinValue.chosenCurrency
            }
        }
        
    }
    
    func convertFees(_ selectedFee: SelectedFee, customFees:Double? = nil) -> String {
        guard self.sendVC != nil else { return "error" }
        let transactionSize = self.sendVC!.confirmTxSize
        let satsPerVbyte:Double
        switch selectedFee {
        case .high: satsPerVbyte = self.sendVC!.feePerVbHigh
        case .medium: satsPerVbyte = self.sendVC!.feePerVbMedium
        case .low: satsPerVbyte = self.sendVC!.feePerVbLow
        case .custom: satsPerVbyte = customFees ?? 0
        }
        let satsValue = CGFloat(satsPerVbyte.feeSats(forVsize: transactionSize))
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
        // Fiat fee, rounded to two decimals and formatted with the device's
        // decimal separator (e.g. "0,50" in comma locales).
        let fiatValue = satsValue.inBTC() * bitcoinValue.currentValue
        return fiatValue.twoDecimals().toString()
    }

    // Formats the fiat send amount with two decimals, e.g. "4.99 €" (or "4,99 €"
    // in comma locales). twoDecimals() rounds to 2 places and toString() formats
    // with the device's decimal separator, padded to two decimals.
    func formattedFiatAmount() -> String {
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
        let fiatValue = self.sendVC!.confirmSatoshis.inBTC() * bitcoinValue.currentValue
        return "\(fiatValue.twoDecimals().toString()) \(bitcoinValue.chosenCurrency)"
    }

    @IBAction func feeButtonTapped(_ sender: UIButton) {
        if sender.boundString == "high" {
            self.switchToFee(.high)
        } else if sender.boundString == "medium" {
            self.switchToFee(.medium)
        } else {
            self.switchToFee(.low)
        }
    }
    
    func switchToFee(_ tappedFee:SelectedFee) {
        // Switch selected fee rate.
        self.selectedFee = tappedFee
        self.selectedFeeInSats = self.selectedFeeRatePerVb().feeSats(forVsize: self.sendVC!.confirmTxSize)
        
        // A drain sends whatever is left after the fee, so its amount moves with
        // the selected rate. Restate it, otherwise picking a higher fee leaves
        // the screen quoting the amount from the rate it was calculated at.
        if self.sendVC!.isSendingMaximum, let drainTotal = self.sendVC!.drainTotalSats {
            self.sendVC!.confirmSatoshis = max(drainTotal - self.selectedFeeInSats, 0)
            self.amountLabel.text = self.sendVC!.confirmSatoshis.inBTC().formattedBitcoin() + " BTC"
            self.amountFiatLabel.text = self.formattedFiatAmount()
        }

        self.highlightFee(tappedFee)
        guard self.canAffordFees() else { return }
        self.checkHighFeeRate()
    }
    
    func highlightFee(_ selectedFee:SelectedFee) {
        self.selectedFee = selectedFee
        switch selectedFee {
        case .medium:
            self.feesViewFast.backgroundColor = Colors.getColor("white0.7orblue1")
            self.feesViewMedium.backgroundColor = Colors.getColor("whiteorblue3")
            self.feesViewSlow.backgroundColor = Colors.getColor("white0.7orblue1")
        case .high:
            self.feesViewFast.backgroundColor = Colors.getColor("whiteorblue3")
            self.feesViewMedium.backgroundColor = Colors.getColor("white0.7orblue1")
            self.feesViewSlow.backgroundColor = Colors.getColor("white0.7orblue1")
        default:
            self.feesViewFast.backgroundColor = Colors.getColor("white0.7orblue1")
            self.feesViewMedium.backgroundColor = Colors.getColor("white0.7orblue1")
            self.feesViewSlow.backgroundColor = Colors.getColor("whiteorblue3")
        }
    }
    
    func canAffordFees() -> Bool {
        
        if self.sendVC!.isSendingMaximum {
            // A balance draining transaction will manage to afford the appropriate fee.
            return true
        }
        
        let spendable = BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0
        if (self.selectedFeeInSats + self.sendVC!.confirmSatoshis) > spendable {
            self.showAlert(title: Language.getWord(withID: "balance2"), message: Language.getWord(withID: "insufficientonchainbalance").replacingOccurrences(of: "<fee>", with: "\(spendable) sats"), buttons: [.action(Language.getWord(withID: "updateamount")) { self.handleAmountChange() }, .dismiss(Language.getWord(withID: "close"))])
            return false
        } else {
            return true
        }
    }
    
    func checkHighFeeRate() {
        // Check if selected fee rate is too high.
        if (CGFloat(self.selectedFeeInSats) / CGFloat(self.sendVC!.confirmSatoshis)) > 0.1 {
            self.showAlert(title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        }
    }
    
    func handleAmountChange() {
        
        // New amount (at least 0 satoshis).
        self.sendVC!.confirmSatoshis = max((BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0) - self.selectedFeeInSats, 0)
        
        // Update SendVC amount text field.
        self.sendVC!.amountTextField.text = self.sendVC!.confirmSatoshis.inBTC().formattedBitcoin()
        self.sendVC!.selectCurrency(.bitcoin)
        
        // Update confirmation labels.
        self.amountLabel.text = self.sendVC!.confirmSatoshis.inBTC().formattedBitcoin() + " BTC"
        self.amountFiatLabel.text = self.formattedFiatAmount()
        
        // Switch fee selection.
        self.switchToFee(self.selectedFee)
    }
    
    @IBAction func confirmButtonTapped(_ sender: UIButton) {
        if self.confirmSpinner.isAnimating { return }
        guard self.checkInternetConnection() else { return }
        
        if self.sendVC!.onchainOrLightning == .onchain {
            // Send onchain transaction.
            self.confirmSendOnchain()
        } else {
            // Send lightning payment.
            self.performLightningPayment()
        }
    }
    
    func confirmSendOnchain() {
        Log.info("Confirm onchain transaction.")
        // Check whether selected fee is appropriate.
        
        if self.maxAvailableFeePerVb != nil && self.selectedFee == .low {
            // Selected fee is very low.
            self.showAlert(title: Language.getWord(withID: "lowfee"), message: Language.getWord(withID: "lowfee2"), buttons: [.dismiss(Language.getWord(withID: "changefee")), .action(Language.getWord(withID: "continue")) { self.proceedWithOnchainConfirmation() }])
        } else {
            self.proceedWithOnchainConfirmation()
        }
    }
    
    @IBAction func lightningFeesTapped(_ sender: UIButton) {
        self.showAlert(title: Language.getWord(withID: "alertlightningfees"), message: Language.getWord(withID: "alertlightningfees2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        // Slide back to leftmost scroll view.
        self.sendVC?.slideFromConfirmToSend()
    }
}

enum SelectedFee {
    case custom
    case low
    case medium
    case high
}
