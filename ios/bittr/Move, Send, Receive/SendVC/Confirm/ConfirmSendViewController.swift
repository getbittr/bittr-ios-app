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
    weak var sendVC:SendViewController?
    var coreVC:CoreViewController?
    
    // Confirming values
    var onchainOrLightning:OnchainOrLightning?
    var addressOrInvoice:String?
    var satoshisAmount:Int?
    var lnurlEmail:String?
    var lightningFees:Int?
    var onchainTxSize:Double?
    var feePerVbLow:Double?
    var feePerVbMedium:Double?
    var feePerVbHigh:Double?
    var isSendingMaximum = false
    var drainTotalSats:Int?
    
    // Fee variables
    var selectedFee:SelectedFee = .medium
    var selectedFeeInSats = 0
    var maxAvailableFeePerVb:Double?
    var newTxId = ""
    
    // The sat/vB rate behind the currently selected fee tier.
    func selectedFeeRatePerVb() -> Double {
        guard let feePerVbLow, let feePerVbMedium, let feePerVbHigh else { return 1 }
        switch self.selectedFee {
        case .high: return feePerVbHigh
        case .medium: return feePerVbMedium
        case .low, .custom: return self.maxAvailableFeePerVb ?? feePerVbLow
        }
    }
    
    func setLightningLabels(
        invoice:String,
        satoshisAmount:Int,
        lnurlEmail:String?,
        lightningFees:Int)
    {
        // Confirming values
        self.lnurlEmail = lnurlEmail
        self.lightningFees = lightningFees
        self.lightningFeesLabel.text = "1 - " + "\(lightningFees)".addSpaces() + " sats"
        
        // Show the typed lightning address rather than the invoice it resolved to.
        self.setSharedLabels(onchainOrLightning: .lightning, addressOrInvoice: invoice, satoshisAmount: satoshisAmount, displayedAddress: lnurlEmail ?? invoice)
    }
    
    func setOnchainLabels(
        address:String,
        satoshisAmount:Int,
        onchainTxSize:Double,
        feeEstimates:FeeEstimates,
        isSendingMaximum:Bool,
        drainTotalSats:Int?)
    {
        // Confirming values
        self.feePerVbLow = feeEstimates.economy
        self.feePerVbMedium = feeEstimates.hour
        self.feePerVbHigh = feeEstimates.fastest
        self.onchainTxSize = onchainTxSize
        self.isSendingMaximum = isSendingMaximum
        self.drainTotalSats = drainTotalSats
        
        self.setSharedLabels(onchainOrLightning: .onchain, addressOrInvoice: address, satoshisAmount: satoshisAmount, displayedAddress: address)
        
        // Check fee availability
        let lowestSats = feeEstimates.economy.feeSats(forVsize: onchainTxSize)
        let availableSatsForFee = (BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0) - satoshisAmount
        if lowestSats > availableSatsForFee {
            // There aren't enough sats available to pay for the cheapest fee.
            // Calculate the cheapest possible fee (minimum 1sat/Vbyte).
            let availableSatsPerVb = onchainTxSize > 0 ? Double(availableSatsForFee) / onchainTxSize : 1
            self.maxAvailableFeePerVb = max(availableSatsPerVb, 1)

            self.timeSlow.text = Language.getWord(withID: "slow")
            self.highlightFee(.low)
            self.selectedFee = .low
        }
        
        // Fees
        self.feesFast.text = "\(feeEstimates.fastest.feeSats(forVsize: onchainTxSize)) sats"
        self.feesMedium.text = "\(feeEstimates.hour.feeSats(forVsize: onchainTxSize)) sats"
        self.feesSlow.text = "\(feeEstimates.economy.feeSats(forVsize: onchainTxSize)) sats"
        
        // Set converted fees
        self.feesFiatFast.text = feeEstimates.fastest.feeSats(forVsize: onchainTxSize).formattedFiatAmount()
        self.feesFiatMedium.text = feeEstimates.hour.feeSats(forVsize: onchainTxSize).formattedFiatAmount()
        self.feesFiatSlow.text = feeEstimates.economy.feeSats(forVsize: onchainTxSize).formattedFiatAmount()
        
        // Custom fee
        if let maxAvailableFeePerVb = self.maxAvailableFeePerVb {
            self.feesSlow.text = "\(maxAvailableFeePerVb.feeSats(forVsize: onchainTxSize)) sats"
            self.feesFiatSlow.text = maxAvailableFeePerVb.feeSats(forVsize: onchainTxSize).formattedFiatAmount()
        }
    }
    
    private func setSharedLabels(
        onchainOrLightning:OnchainOrLightning,
        addressOrInvoice:String,
        satoshisAmount:Int,
        displayedAddress:String)
    {
        
        // Confirming values
        self.onchainOrLightning = onchainOrLightning
        self.addressOrInvoice = addressOrInvoice
        self.satoshisAmount = satoshisAmount
        
        // Address
        self.addressTitle.text = Language.getWord(withID: onchainOrLightning == .onchain ? "address" : "invoice")
        self.addressLabel.text = displayedAddress
        
        // Amount
        self.amountLabel.text = satoshisAmount.formattedAmount()
        
        // Fiat amount
        self.amountFiatLabel.text = satoshisAmount.formattedFiatAmount()
        
        // Fees stacks
        NSLayoutConstraint.deactivate([self.lightningFeesStackHeight, self.onchainFeesStackHeight])
        self.lightningFeesStackHeight = NSLayoutConstraint(item: self.lightningFeesStack, attribute: .height, relatedBy: (onchainOrLightning == .lightning) ? .greaterThanOrEqual : .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        self.onchainFeesStackHeight = NSLayoutConstraint(item: self.onchainFeesStack, attribute: .height, relatedBy: (onchainOrLightning == .lightning) ? .equal : .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.lightningFeesStackHeight, self.onchainFeesStackHeight])
        self.lightningFeesStack.alpha = (onchainOrLightning == .lightning) ? 1 : 0
        self.onchainFeesStack.alpha = (onchainOrLightning == .lightning) ? 0 : 1
    }

    @IBAction func feeButtonTapped(_ sender: UIButton) {
        if self.confirmSpinner.isAnimating { return }
        self.switchToFee(sender.boundString.toSelectedFee())
    }
    
    func switchToFee(_ tappedFee:SelectedFee) {
        // Switch selected fee rate.
        self.selectedFee = tappedFee
        self.selectedFeeInSats = self.selectedFeeRatePerVb().feeSats(forVsize: self.onchainTxSize!)
        
        // For a drain, recalculate the satoshis amount after subtracting the fees.
        if self.isSendingMaximum, let drainTotal = self.drainTotalSats {
            self.satoshisAmount = max(drainTotal - self.selectedFeeInSats, 0)
            self.amountLabel.text = self.satoshisAmount!.formattedAmount()
            self.amountFiatLabel.text = self.satoshisAmount!.formattedFiatAmount()
        }
        
        self.highlightFee(tappedFee)
        guard self.canAffordFees() else { return }
        self.checkHighFeeRate()
    }
    
    func canAffordFees() -> Bool {
        
        if self.isSendingMaximum {
            // A balance draining transaction will manage to afford the appropriate fee.
            return true
        }
        
        let spendable = BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0
        if (self.selectedFeeInSats + self.satoshisAmount!) > spendable {
            self.showAlert(title: Language.getWord(withID: "balance2"), message: Language.getWord(withID: "insufficientonchainbalance").replacingOccurrences(of: "<fee>", with: "\(spendable) sats"), buttons: [.action(Language.getWord(withID: "updateamount")) { self.handleAmountChange() }, .dismiss(Language.getWord(withID: "close"))])
            return false
        } else {
            return true
        }
    }
    
    func checkHighFeeRate() {
        // Check if selected fee rate is too high.
        if (CGFloat(self.selectedFeeInSats) / CGFloat(self.satoshisAmount!)) > 0.1 {
            self.showAlert(title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        }
    }
    
    func handleAmountChange() {
        
        // New amount (at least 0 satoshis).
        self.satoshisAmount = max((BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0) - self.selectedFeeInSats, 0)
        
        // Update SendVC amount text field.
        self.sendVC?.amountTextField.text = self.satoshisAmount!.inBTC().formattedBitcoin()
        self.sendVC?.selectCurrency(.bitcoin)
        
        // Update confirmation labels.
        self.amountLabel.text = self.satoshisAmount!.formattedAmount()
        self.amountFiatLabel.text = self.satoshisAmount!.formattedFiatAmount()
        
        // Switch fee selection.
        self.switchToFee(self.selectedFee)
    }
    
    @IBAction func confirmButtonTapped(_ sender: UIButton) {
        if self.confirmSpinner.isAnimating { return }
        guard self.checkInternetConnection() else { return }
        
        if self.onchainOrLightning == .onchain {
            // Send onchain transaction.
            self.confirmSendOnchain()
        } else {
            // Send lightning payment.
            self.performLightningPayment(invoiceText: self.addressOrInvoice!, satoshisAmount: self.satoshisAmount!)
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

extension Int {
    
    // Formats the send amount, e.g. "50 000 sats".
    func formattedAmount() -> String {
        return "\(self)".addSpaces() + " " + Language.getWord(withID: "sats")
    }
    
    // Formats the fiat send amount with two decimals, e.g. "4.99 €" or "4,99 €".
    func formattedFiatAmount() -> String {
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
        let fiatValue = self.inBTC() * bitcoinValue.currentValue
        return "\(fiatValue.twoDecimals().toString()) \(bitcoinValue.chosenCurrency)"
    }
}

extension String? {
    func toSelectedFee() -> SelectedFee {
        switch self {
        case "high": return .high
        case "medium": return .medium
        default: return .low
        }
    }
}
