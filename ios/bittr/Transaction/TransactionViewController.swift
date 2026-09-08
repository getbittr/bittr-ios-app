//
//  TransactionViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit
import SPConfetti

class TransactionViewController: UIViewController {
    
    // General
    @IBOutlet weak var mainScrollView: UIScrollView!
    @IBOutlet weak var mainContentView: UIView!
    @IBOutlet weak var mainContentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var mainCenterView: UIView!
    
    // Yellow card
    @IBOutlet weak var yellowCard: UIView!
    
    // Date stack
    @IBOutlet weak var labelDate: UILabel!
    
    // Amount stack
    @IBOutlet weak var cardAmount: UIView!
    @IBOutlet weak var titleAmount: UILabel!
    @IBOutlet weak var labelAmount: UILabel!
    
    // Type stack
    @IBOutlet weak var typeStack: UIView!
    @IBOutlet weak var typeStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardType: UIView!
    @IBOutlet weak var titleType: UILabel!
    @IBOutlet weak var labelType: UILabel!
    @IBOutlet weak var typeBoltImage: UIImageView!
    
    // Swap stack
    @IBOutlet weak var swapStack: UIView!
    @IBOutlet weak var swapStackHeight: NSLayoutConstraint! // 0 or 87
    @IBOutlet weak var cardSwapId: UIView!
    @IBOutlet weak var titleSwapId: UILabel!
    @IBOutlet weak var labelSwapId: UILabel!
    @IBOutlet weak var titleSwapStatus: UILabel!
    @IBOutlet weak var labelSwapStatus: UILabel!
    @IBOutlet weak var swapArrowImage: UIImageView!
    @IBOutlet weak var buttonSwapStatus: UIButton!
    
    // Fees stack
    @IBOutlet weak var feesStack: UIView!
    @IBOutlet weak var feesStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardFees: UIView!
    @IBOutlet weak var titleFees: UILabel!
    @IBOutlet weak var labelFees: UILabel!
    
    // Confirmations stack
    @IBOutlet weak var confirmationsStack: UIView!
    @IBOutlet weak var confirmationsStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardConfirmations: UIView!
    @IBOutlet weak var titleConfirmations: UILabel!
    @IBOutlet weak var labelConfirmations: UILabel!
    
    // Description stack
    @IBOutlet weak var descriptionStack: UIView!
    @IBOutlet weak var descriptionStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardDescription: UIView!
    @IBOutlet weak var titleDescription: UILabel!
    @IBOutlet weak var labelDescription: UILabel!
    @IBOutlet weak var buttonDescription: UIButton!
    
    // IDs stack
    @IBOutlet weak var idStack: UIView!
    @IBOutlet weak var idStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardTopId: UIView!
    @IBOutlet weak var titleTopId: UILabel!
    @IBOutlet weak var labelTopId: UILabel!
    @IBOutlet weak var urlStackTopId: UIView!
    @IBOutlet weak var urlStackTopIdWidth: NSLayoutConstraint!
    @IBOutlet weak var urlButtonTopId: UIButton!
    @IBOutlet weak var urlImageTopId: UIImageView!
    @IBOutlet weak var copyButtonTopId: UIButton!
    @IBOutlet weak var bottomIdStack: UIView!
    @IBOutlet weak var bottomIdStackHeight: NSLayoutConstraint!
    @IBOutlet weak var titleBottomId: UILabel!
    @IBOutlet weak var labelBottomId: UILabel!
    @IBOutlet weak var urlStackBottomId: UIView!
    @IBOutlet weak var urlStackBottomIdWidth: NSLayoutConstraint!
    @IBOutlet weak var urlButtonBottomId: UIButton!
    @IBOutlet weak var urlImageBottomId: UIImageView!
    @IBOutlet weak var copyButtonBottomId: UIButton!
    var tappedUrl:String?
    
    // Value stack
    @IBOutlet weak var cardValue: UIView!
    @IBOutlet weak var titleCurrentValue: UILabel!
    @IBOutlet weak var labelCurrentValue: UILabel!
    @IBOutlet weak var valueStack: UIView!
    @IBOutlet weak var valueStackHeight: NSLayoutConstraint!
    
    // Bittr fees stack
    @IBOutlet weak var titleGrossAmount: UILabel!
    @IBOutlet weak var labelGrossAmount: UILabel!
    @IBOutlet weak var bittrFeesStack: UIView!
    @IBOutlet weak var bittrFeesStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardBittrFees: UIView!
    @IBOutlet weak var titleTransferFee: UILabel!
    @IBOutlet weak var labelTransferFee: UILabel!
    @IBOutlet weak var titleBittrFee: UILabel!
    @IBOutlet weak var labelBittrFee: UILabel!
    @IBOutlet weak var surchargeStack: UIView!
    @IBOutlet weak var surchargeStackHeight: NSLayoutConstraint!
    @IBOutlet weak var titleSurcharge: UILabel!
    @IBOutlet weak var labelSurcharge: UILabel!
    @IBOutlet weak var buttonTransferFee: UIButton!
    @IBOutlet weak var buttonBittrFee: UIButton!
    @IBOutlet weak var buttonSurcharge: UIButton!
    @IBOutlet weak var titleNetAmount: UILabel!
    @IBOutlet weak var labelNetAmount: UILabel!
    @IBOutlet weak var titleExchangeRate: UILabel!
    @IBOutlet weak var labelExchangeRate: UILabel!
    @IBOutlet weak var titleBittrCurrentValue: UILabel!
    @IBOutlet weak var labelBittrCurrentValue: UILabel!
    @IBOutlet weak var titleProfit: UILabel!
    @IBOutlet weak var labelProfit: UILabel!
    @IBOutlet weak var sumLine: UIView!
    
    // Note stack
    @IBOutlet weak var noteStack: UIView!
    @IBOutlet weak var noteStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardNote: UIView!
    @IBOutlet weak var titleNote: UILabel!
    @IBOutlet weak var labelNote: UILabel!
    @IBOutlet weak var buttonNote: UIButton!
    
    // Add a note stack
    @IBOutlet weak var addANoteStack: UIView!
    @IBOutlet weak var addANoteStackHeight: NSLayoutConstraint!
    @IBOutlet weak var imageAddANote: UIImageView!
    @IBOutlet weak var titleAddANote: UILabel!
    @IBOutlet weak var buttonAddANote: UIButton!
    
    // Confetti items
    @IBOutlet weak var bittrPayoutStack: UIView!
    @IBOutlet weak var bittrPayoutStackHeight: NSLayoutConstraint!
    @IBOutlet weak var bittrPayoutSubtitle: UILabel!
    @IBOutlet weak var alertStack: UIView!
    @IBOutlet weak var alertStackHeight: NSLayoutConstraint!
    @IBOutlet weak var alertCard: UIView!
    @IBOutlet weak var alertTitle: UILabel!
    @IBOutlet weak var alertLabel: UILabel!
    
    // Variables
    var tappedTransaction = Transaction()
    var coreVC:CoreViewController?
    var showConfetti = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.yellowCard.accessibilityIdentifier = TestID.Transaction.yellowCard
        self.labelDate.accessibilityIdentifier = TestID.Transaction.labelDate
        self.labelAmount.accessibilityIdentifier = TestID.Transaction.labelAmount
        self.buttonSwapStatus.accessibilityIdentifier = TestID.Transaction.swapStatusButton
        self.buttonDescription.accessibilityIdentifier = TestID.Transaction.descriptionButton
        self.labelDescription.accessibilityIdentifier = TestID.Transaction.descriptionLabel
        self.copyButtonTopId.accessibilityIdentifier = TestID.Transaction.copyIdButton
        self.urlButtonTopId.accessibilityIdentifier = TestID.Transaction.urlIdButton
        self.copyButtonBottomId.accessibilityIdentifier = TestID.Transaction.copyBottomIdButton
        self.buttonBittrFee.accessibilityIdentifier = TestID.Transaction.bittrFeeButton
        self.buttonTransferFee.accessibilityIdentifier = TestID.Transaction.transferFeeButton
        self.buttonAddANote.accessibilityIdentifier = TestID.Transaction.addNoteButton
        self.labelNote.accessibilityIdentifier = TestID.Transaction.labelNote

        // Button titles
        self.buttonSwapStatus.setTitle("", for: .normal)
        self.buttonDescription.setTitle("", for: .normal)
        self.copyButtonTopId.setTitle("", for: .normal)
        self.copyButtonBottomId.setTitle("", for: .normal)
        self.urlButtonTopId.setTitle("", for: .normal)
        self.urlButtonBottomId.setTitle("", for: .normal)
        self.buttonNote.setTitle("", for: .normal)
        self.buttonAddANote.setTitle("", for: .normal)
        self.buttonTransferFee.setTitle("", for: .normal)
        self.buttonBittrFee.setTitle("", for: .normal)
        self.buttonSurcharge.setTitle("", for: .normal)
        
        // Yellow card styling
        self.yellowCard.setShadow()
        self.alertCard.setShadow()
        
        // Corner radii
        self.yellowCard.layer.cornerRadius = 13
        self.alertCard.layer.cornerRadius = 13
        self.cardAmount.layer.cornerRadius = 8
        self.cardType.layer.cornerRadius = 8
        self.cardSwapId.layer.cornerRadius = 8
        self.cardFees.layer.cornerRadius = 8
        self.cardConfirmations.layer.cornerRadius = 8
        self.cardDescription.layer.cornerRadius = 8
        self.cardTopId.layer.cornerRadius = 8
        self.cardValue.layer.cornerRadius = 8
        self.cardBittrFees.layer.cornerRadius = 8
        self.cardNote.layer.cornerRadius = 8
        self.sumLine.layer.cornerRadius = 1
        
        // Language
        self.setWords()
        self.changeColors()
        self.addHeader(iconLight: "iconpiggywhite", iconDark: "iconpiggyyellow", title: Language.getWord(withID: "transaction"))
        self.setTransactionData()
        
        // Confetti
        if self.showConfetti {
            // Show piggy bank header.
            NSLayoutConstraint.deactivate([self.bittrPayoutStackHeight, self.alertStackHeight])
            self.bittrPayoutStackHeight = NSLayoutConstraint(item: self.bittrPayoutStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            self.alertStackHeight = NSLayoutConstraint(item: self.alertStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.bittrPayoutStackHeight, self.alertStackHeight])
            self.bittrPayoutStack.alpha = 1
            self.alertStack.alpha = 1
        }
    }
    
    func checkContentViewHeight() {
        let centerViewHeight = self.mainCenterView.bounds.height
        if centerViewHeight > self.mainContentView.bounds.height {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
                NSLayoutConstraint.deactivate([self.mainContentViewHeight])
                self.mainContentViewHeight = NSLayoutConstraint(item: self.mainContentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight)
                NSLayoutConstraint.activate([self.mainContentViewHeight])
                self.view.layoutIfNeeded()
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.checkContentViewHeight()
        if self.showConfetti {
            SPConfettiConfiguration.particlesConfig.colors = [.red]
            SPConfetti.startAnimating(.fullWidthToDown, particles: [.heart], duration: 2)
        }
    }
    
    func setTransactionData() {
        
        // Date
        let transactionDate = Date(timeIntervalSince1970: Double(self.tappedTransaction.timestamp))
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "dd MMM yyyy HH:mm"
        var transactionDateString = dateFormatter.string(from: transactionDate)
        if transactionDateString.first == "0" {
            transactionDateString = String(transactionDateString.dropFirst())
        }
        self.labelDate.text = transactionDateString
        
        // Amount
        if self.tappedTransaction.isSwap {
            if self.tappedTransaction.swapStatus == .succeeded {
                self.labelAmount.text = "\(String(self.tappedTransaction.received).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            } else if self.tappedTransaction.swapStatus == .pending {
                if let swapID = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription), let swapDictionary = SwapManager.loadSwapDetailsFromFile(swapID: swapID) {
                    let convertedSwap = swapDictionary.toSwap()
                    self.labelAmount.text = "\(convertedSwap.satoshisAmount)".addSpaces() + " sats"
                } else {
                    self.labelAmount.text = "\(String(self.tappedTransaction.received - self.tappedTransaction.sent).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
                }
            } else if self.tappedTransaction.swapDirection == .onchainToLightning {
                // Normal swap has failed.
                self.labelAmount.text = "0 sats"
            }
        } else if self.tappedTransaction.isSuggestedSwap {
            // Suggested swap: show only the paid invoice amount (from the swap
            // file), not the full onchain outflow which also bundles the swap
            // spread and network fee. Mirrors the SwapStatus screen.
            if let swapID = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription), let swapDictionary = SwapManager.loadSwapDetailsFromFile(swapID: swapID) {
                let convertedSwap = swapDictionary.toSwap()
                self.labelAmount.text = "- " + "\(convertedSwap.satoshisAmount)".addSpaces() + " sats"
            } else {
                // Fall back to the full outflow if the swap file is unavailable.
                self.labelAmount.text = "- \(String(self.tappedTransaction.sent - self.tappedTransaction.received).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            }
        } else {
            var plusSymbol = "+"
            if (self.tappedTransaction.received - self.tappedTransaction.sent) < 0 {
                plusSymbol = "-"
            }
            self.labelAmount.text = "\(plusSymbol) \(String(self.tappedTransaction.received - self.tappedTransaction.sent).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
        }
        
        // Type
        if self.showConfetti {
            self.typeStack.alpha = 0
            self.typeStackHeight.constant = 0
        } else if self.tappedTransaction.isSwap {
            switch self.tappedTransaction.swapDirection {
            case .onchainToLightning:
                self.labelType.text = Language.getWord(withID: "onchaintolightning")
            case .lightningToOnchain:
                self.labelType.text = Language.getWord(withID: "lightningtoonchain")
            }
        } else {
            if self.tappedTransaction.isLightning {
                self.labelType.text = Language.getWord(withID: "instant")
                self.typeBoltImage.alpha = 0.8
            } else {
                self.labelType.text = Language.getWord(withID: "regular")
            }
        }
        
        // Swap ID and status. Suggested (outgoing) swaps aren't full swaps
        // (isSwap == false, rendered as a normal outbound transaction) but still
        // show the Boltz swap ID + status here.
        if self.tappedTransaction.isSwap || self.tappedTransaction.isSuggestedSwap {
            // Show swap stack
            self.swapStack.alpha = 1
            self.swapStackHeight.constant = 87
            
            // Swap ID
            self.labelSwapId.text = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription) ?? "Unavailable"
            
            // Swap status
            switch self.tappedTransaction.swapStatus {
            case .succeeded:
                self.labelSwapStatus.text = Language.getWord(withID: "swapsucceeded")
            case .pending:
                self.labelSwapStatus.text = Language.getWord(withID: "swappending")
            case .failed:
                self.labelSwapStatus.text = Language.getWord(withID: "swapfailed")
            }
        }
        
        // Fees
        if self.tappedTransaction.isSwap {
            self.feesStackHeight.constant = 55
            self.feesStack.alpha = 1
            if self.tappedTransaction.swapStatus != .pending {
                // Completed or failed swap. Total cost = implicit Boltz spread
                // (sent - received) + user-paid network fee (e.g. the onchain
                // fee on an onchain→lightning swap, summed into .fee by
                // performSwapMatching).
                let totalFees = self.tappedTransaction.sent - self.tappedTransaction.received + self.tappedTransaction.fee
                self.labelFees.text = "\(String(totalFees).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            } else {
                // Pending swap.
                if let swapID = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription), let swapDictionary = SwapManager.loadSwapDetailsFromFile(swapID: swapID) {
                    let convertedSwap = swapDictionary.toSwap()
                    self.labelFees.text = "\(self.tappedTransaction.sent - self.tappedTransaction.received - convertedSwap.satoshisAmount)".addSpaces() + " sats"
                } else {
                    self.labelFees.text = "0 sats"
                }
            }
        } else if self.tappedTransaction.isSuggestedSwap {
            // Suggested swap: fees are everything beyond the paid invoice
            // amount — the swap spread (sent - received) plus the onchain
            // network fee. Mirrors the SwapStatus screen.
            self.feesStackHeight.constant = 55
            self.feesStack.alpha = 1
            if let swapID = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription), let swapDictionary = SwapManager.loadSwapDetailsFromFile(swapID: swapID) {
                let convertedSwap = swapDictionary.toSwap()
                let totalFees = self.tappedTransaction.sent - self.tappedTransaction.received + self.tappedTransaction.fee - convertedSwap.satoshisAmount
                self.labelFees.text = "\(String(totalFees).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            } else {
                // Fall back to just the onchain network fee.
                self.labelFees.text = "\(String(self.tappedTransaction.fee).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            }
        } else if (self.tappedTransaction.received-self.tappedTransaction.sent-self.tappedTransaction.fee) < 0 {
            // Outbound transaction.
            self.feesStackHeight.constant = 55
            self.feesStack.alpha = 1
            self.labelFees.text = "\(String(self.tappedTransaction.fee).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
        }
        
        // Confirmations
        if !self.tappedTransaction.isLightning, !self.tappedTransaction.isSwap {
            // Onchain transaction.
            self.confirmationsStackHeight.constant = 55
            self.confirmationsStack.alpha = 1
            
            let currentHeight = BitcoinManager.shared.bittrWallet.currentHeight ?? CacheManager.cachedHeight ?? 0
            
            if self.tappedTransaction.height == nil || (currentHeight - self.tappedTransaction.height! + 1) < 1 {
                // Unconfirmed transaction.
                self.labelConfirmations.text = Language.getWord(withID: "unconfirmed")
            } else {
                // Confirmed transaction.
                self.labelConfirmations.text = "\(currentHeight - self.tappedTransaction.height! + 1)".addSpaces()
            }
        }
        
        // Description
        if self.descriptionText().trimmingCharacters(in: .whitespacesAndNewlines) != "", !self.tappedTransaction.isSwap, !self.tappedTransaction.isSuggestedSwap, !self.showConfetti {
            
            if self.tappedTransaction.isBittr {
                self.labelDescription.numberOfLines = 1
                self.labelDescription.lineBreakMode = .byTruncatingMiddle
            }
            
            self.labelDescription.text = self.descriptionText()
            NSLayoutConstraint.deactivate([self.descriptionStackHeight])
            self.descriptionStackHeight = NSLayoutConstraint(item: self.descriptionStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.descriptionStackHeight])
            self.view.layoutIfNeeded()
            self.descriptionStack.alpha = 1
        }
        
        // IDs
        if self.showConfetti {
            self.idStack.alpha = 0
            NSLayoutConstraint.deactivate([self.idStackHeight])
            self.idStackHeight = NSLayoutConstraint(item: self.idStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.idStackHeight])
        } else if self.tappedTransaction.isSwap {
            self.bottomIdStack.alpha = 1
            self.bottomIdStackHeight.constant = 29
            if self.tappedTransaction.swapDirection == .onchainToLightning {
                // Top ID
                self.titleTopId.text = Language.getWord(withID: "onchainid")
                self.labelTopId.text = self.tappedTransaction.onchainID
                self.copyButtonTopId.boundString = self.tappedTransaction.onchainID
                // Top URL
                self.urlStackTopId.alpha = 1
                self.urlStackTopIdWidth.constant = 22
                self.urlButtonTopId.boundString = self.tappedTransaction.onchainID
                // Bottom ID and URL
                switch self.tappedTransaction.swapStatus {
                case .succeeded:
                    self.titleBottomId.text = Language.getWord(withID: "lightningid")
                    self.labelBottomId.text = self.tappedTransaction.lightningID
                    self.copyButtonBottomId.boundString = self.tappedTransaction.lightningID
                case .pending:
                    self.titleBottomId.text = Language.getWord(withID: "lightningid")
                    self.labelBottomId.text = Language.getWord(withID: "expecting")
                case .failed:
                    self.titleBottomId.text = Language.getWord(withID: "refundid")
                    self.labelBottomId.text = self.tappedTransaction.lightningID
                    self.copyButtonBottomId.boundString = self.tappedTransaction.lightningID
                    self.urlStackBottomId.alpha = 1
                    self.urlStackBottomIdWidth.constant = 22
                    self.urlButtonBottomId.boundString = self.tappedTransaction.lightningID
                }
            } else if self.tappedTransaction.swapDirection == .lightningToOnchain {
                // Top ID
                self.titleTopId.text = Language.getWord(withID: "lightningid")
                self.labelTopId.text = self.tappedTransaction.lightningID
                self.copyButtonTopId.boundString = self.tappedTransaction.lightningID
                // Bottom ID and URL
                switch self.tappedTransaction.swapStatus {
                case .succeeded:
                    self.titleBottomId.text = Language.getWord(withID: "onchainid")
                    self.labelBottomId.text = self.tappedTransaction.onchainID
                    self.copyButtonBottomId.boundString = self.tappedTransaction.onchainID
                    self.urlStackBottomId.alpha = 1
                    self.urlStackBottomIdWidth.constant = 22
                    self.urlButtonBottomId.boundString = self.tappedTransaction.onchainID
                case .pending:
                    self.titleBottomId.text = Language.getWord(withID: "onchainid")
                    self.labelBottomId.text = Language.getWord(withID: "expecting")
                case .failed:
                    self.bottomIdStack.alpha = 0
                    self.bottomIdStackHeight.constant = 0
                }
            }
        } else if self.tappedTransaction.isSuggestedSwap {
            
            self.bottomIdStack.alpha = 1
            self.bottomIdStackHeight.constant = 29
            var convertedSwap:Swap?
            if let swapID = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription),
               let swapDictionary = SwapManager.loadSwapDetailsFromFile(swapID: swapID) {
                convertedSwap = swapDictionary.toSwap()
            }
            if self.tappedTransaction.swapDirection == .onchainToLightning {
                // Onchain lockup transaction on top, payment hash of the paid
                // Lightning invoice below.
                self.titleTopId.text = Language.getWord(withID: "onchainid")
                self.labelTopId.text = self.tappedTransaction.id
                self.copyButtonTopId.boundString = self.tappedTransaction.id
                self.urlStackTopId.alpha = 1
                self.urlStackTopIdWidth.constant = 22
                self.urlButtonTopId.boundString = self.tappedTransaction.id
                self.titleBottomId.text = Language.getWord(withID: "lightningid")
                if let lightningID = convertedSwap?.createdInvoice?.getInvoiceHash() {
                    self.labelBottomId.text = lightningID
                    self.copyButtonBottomId.boundString = lightningID
                } else {
                    self.labelBottomId.text = "Unavailable"
                }
            } else {
                // Lightning payment on top, onchain payout transaction (paying
                // the recipient) below, with an explorer link like a normal
                // reverse swap's onchain leg.
                self.titleTopId.text = Language.getWord(withID: "lightningid")
                self.labelTopId.text = self.tappedTransaction.id
                self.copyButtonTopId.boundString = self.tappedTransaction.id
                self.titleBottomId.text = Language.getWord(withID: "onchainid")
                if let onchainID = convertedSwap?.sentOnchainTransactionID {
                    self.labelBottomId.text = onchainID
                    self.copyButtonBottomId.boundString = onchainID
                    self.urlStackBottomId.alpha = 1
                    self.urlStackBottomIdWidth.constant = 22
                    self.urlButtonBottomId.boundString = onchainID
                } else {
                    self.labelBottomId.text = "Unavailable"
                }
            }
        } else {
            // Onchain or Lightning transaction.
            self.titleTopId.text = Language.getWord(withID: "id")
            self.labelTopId.text = self.tappedTransaction.id
            self.copyButtonTopId.boundString = self.tappedTransaction.id
            if !self.tappedTransaction.isLightning {
                self.urlStackTopId.alpha = 1
                self.urlStackTopIdWidth.constant = 22
                self.urlButtonTopId.boundString = self.tappedTransaction.id
            }
        }
        
        // Value
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
        let transactionValue:CGFloat = {
            if self.tappedTransaction.isSwap {
                return (self.tappedTransaction.sent - self.tappedTransaction.received + self.tappedTransaction.fee).inBTC()
            } else {
                return (self.tappedTransaction.received-self.tappedTransaction.sent-self.tappedTransaction.fee).inBTC()
            }
        }()
        let balanceValue = "\((transactionValue*bitcoinValue.currentValue).twoDecimals())".replacingOccurrences(of: "-", with: "").addSpaces()
        self.labelCurrentValue.text = balanceValue + " " + bitcoinValue.chosenCurrency
        if self.tappedTransaction.isBittr {
            self.valueStack.alpha = 0
            self.valueStackHeight.constant = 0
        }
        
        // Bittr fees
        if self.tappedTransaction.isBittr {
            
            NSLayoutConstraint.deactivate([self.bittrFeesStackHeight])
            self.bittrFeesStackHeight = NSLayoutConstraint(item: self.bittrFeesStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.bittrFeesStackHeight])
            self.bittrFeesStack.alpha = 1
            
            // Currency.
            let currencySymbol:String = {
                if self.tappedTransaction.currency == "EUR" {
                    return "€"
                } else {
                    return "CHF"
                }
            }()
            
            // Gross amount
            self.labelGrossAmount.text = "\(self.tappedTransaction.fiatGrossAmount)\(Locale.current.decimalSeparator!)00".addSpaces() + " \(currencySymbol)"
            
            // Surcharge
            if self.tappedTransaction.surcharge == 0 {
                self.surchargeStackHeight.constant = 0
                self.surchargeStack.alpha = 0
            } else {
                self.labelSurcharge.text = "\(self.tappedTransaction.surcharge.toString()) \(currencySymbol)"
            }
            
            // Bittr fee
            self.labelBittrFee.text = "\(self.tappedTransaction.bittrFee.toString()) \(currencySymbol)"
            
            // Transfer fee
            self.labelTransferFee.text = "\(self.tappedTransaction.transferFee)".addSpaces() + " sats"
            
            // Current value
            self.labelBittrCurrentValue.text = balanceValue + " " + bitcoinValue.chosenCurrency
            
            // Exchange rate
            self.labelExchangeRate.text = "\(self.tappedTransaction.historicalExchangeRate.toString().addSpaces()) \(currencySymbol)/btc"
            
            // Purchase value and profit
            if self.tappedTransaction.fiatNetAmount == 0 {
                // This transaction has not yet been checked with the Bittr API.
                self.labelNetAmount.text = self.labelCurrentValue.text
                self.labelProfit.text = "0" + Locale.current.decimalSeparator! + "00 " + "\(currencySymbol)"
            } else {
                // Fix any discrepancies in net amount displaying.
                if self.tappedTransaction.transferFee == 0 {
                    self.tappedTransaction.fiatNetAmount = self.tappedTransaction.fiatGrossAmount - self.tappedTransaction.surcharge - self.tappedTransaction.bittrFee
                }
                
                self.labelNetAmount.text = "\(self.tappedTransaction.fiatNetAmount)\(Locale.current.decimalSeparator!)00".addSpaces() + " \(currencySymbol)"
                
                var correctConversion = bitcoinValue.currentValue
                if bitcoinValue.chosenCurrency != currencySymbol {
                    if currencySymbol == "€" {
                        correctConversion = BitcoinManager.shared.bittrWallet.valueInEUR ?? 0
                    } else {
                        correctConversion = BitcoinManager.shared.bittrWallet.valueInCHF ?? 0
                    }
                    self.labelBittrCurrentValue.text = "\((transactionValue*correctConversion).twoDecimals())".replacingOccurrences(of: "-", with: "").addSpaces() + " \(currencySymbol)"
                }
                let profitValue = "\((transactionValue*correctConversion - (self.tappedTransaction.fiatNetAmount)).twoDecimals())".addSpaces()
                self.labelProfit.text = "\(profitValue) \(currencySymbol)".replacingOccurrences(of: "-", with: "- ")
                
                if (self.labelProfit.text ?? "").contains("-") {
                    // Loss
                    self.labelProfit.textColor = Colors.getColor("losstext")
                } else {
                    // Profit
                    self.labelProfit.textColor = Colors.getColor("profittext")
                }
            }
            
        }
        
        // Note
        if self.showConfetti {
            // Hide Add a Note for Bittr payout summary.
            self.addANoteStack.alpha = 0
            self.addANoteStackHeight.constant = 0
        } else if CacheManager.getTransactionNote(txid: self.tappedTransaction.id) != "" {
            // There's a note.
            self.labelNote.text = CacheManager.getTransactionNote(txid: self.tappedTransaction.id)
            self.showNoteStack()
        } else {
            // There's no note.
            self.addANoteStack.alpha = 1
            self.addANoteStackHeight.constant = 45
        }
        
        self.view.layoutIfNeeded()
    }
    
    func showNoteStack() {
        self.noteStack.alpha = 1
        NSLayoutConstraint.deactivate([self.noteStackHeight])
        self.noteStackHeight = NSLayoutConstraint(item: self.noteStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.noteStackHeight])
        self.addANoteStack.alpha = 0
        self.addANoteStackHeight.constant = 0
        self.view.layoutIfNeeded()
    }
    
    func hideNoteStack() {
        self.noteStack.alpha = 0
        NSLayoutConstraint.deactivate([self.noteStackHeight])
        self.noteStackHeight = NSLayoutConstraint(item: self.noteStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.noteStackHeight])
        // Keep "Add a note" hidden on the Bittr payout summary, which suppresses
        // it deliberately — reverting to it there would put the button on a
        // screen that never offers one.
        if !self.showConfetti {
            self.addANoteStack.alpha = 1
            self.addANoteStackHeight.constant = 45
        }
        self.view.layoutIfNeeded()
    }
    
    @IBAction func noteButtonTapped(_ sender: UIButton) {

        self.showTextFieldAlert(
            title: Language.getWord(withID: "addanote"),
            initialText: self.labelNote.text ?? "",
            placeholder: Language.getWord(withID: "addanote"),
            cancelTitle: Language.getWord(withID: "cancel"),
            saveTitle: Language.getWord(withID: "save")
        ) { [weak self] noteText in
            guard let self = self else { return }
            let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedNote != "" {
                // Store what the emptiness check was made against, so a note
                // isn't persisted (and redisplayed) with stray padding.
                CacheManager.storeTransactionNote(txid: self.tappedTransaction.id, note: trimmedNote)
                self.labelNote.text = trimmedNote
                self.showNoteStack()
            } else {
                // The user cleared the note: delete it and revert to the "Add a note" button.
                CacheManager.deleteTransactionNote(txid: self.tappedTransaction.id)
                self.labelNote.text = ""
                self.hideNoteStack()
            }
        }
    }
    
    @IBAction func idButtonTapped(_ sender: UIButton) {

        if let thisId = sender.boundString {
            UIPasteboard.general.string = thisId
            self.showAlert(title: Language.getWord(withID: "copied"), message: thisId, buttons: [.dismiss(Language.getWord(withID: "okay"))])
        }
    }
    
    func descriptionText() -> String {
        if self.tappedTransaction.lnDescription == "", self.tappedTransaction.isChannelClosure {
            return Language.getWord(withID: "channelclosuretransaction")
        }
        return self.tappedTransaction.lnDescription
    }
    
    @IBAction func descriptionButtonTapped(_ sender: UIButton) {
        
        let copyingText = self.descriptionText()
        UIPasteboard.general.string = copyingText
        self.showAlert(title: Language.getWord(withID: "copied"), message: copyingText, buttons: [.dismiss(Language.getWord(withID: "okay"))])
    }
    
    @IBAction func lightningIDTapped(_ sender: UIButton) {
        
        UIPasteboard.general.string = self.tappedTransaction.lightningID
        self.showAlert(title: Language.getWord(withID: "copied"), message: self.tappedTransaction.lightningID, buttons: [.dismiss(Language.getWord(withID: "okay"))])
    }
    
    @IBAction func feesQuestionButtonTapped(_ sender: UIButton) {
        let baseMessage = Language.getWord(withID: "lightningchannelfees2")
        let dynamicMessage = baseMessage.replacingOccurrences(of: "This fee", with: "This \(self.tappedTransaction.transferFee) satoshi fee")
        self.coreVC!.launchQuestion(question: Language.getWord(withID: "lightningchannelfees"), answer: dynamicMessage, type: nil)
    }
    
    @IBAction func openUrlButtonTapped(_ sender: UIButton) {
        if let thisUrl = sender.boundString {
            self.tappedUrl = "\(EnvironmentConfig.explorerURL)/tx/\(thisUrl)?mode=details"
            self.performSegue(withIdentifier: "TransactionToWebsite", sender: self)
        }
    }
    
    @IBAction func openSwapTapped(_ sender: UIButton) {
        if CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription) != nil {
            self.performSegue(withIdentifier: "TransactionToSwapStatus", sender: self)
        }
    }
    
    @IBAction func bittrFeesTapped(_ sender: UIButton) {
        Log.info("User tapped bittr fees. \(sender.tag)")
        
        let notificationTitle:String
        let notificationBody:String
        
        switch sender.tag {
        case 0: // Transfer fee
            notificationTitle = Language.getWord(withID: "transferfee")
            if self.tappedTransaction.isFundingTransaction {
                notificationBody = Language.getWord(withID: "transferfee1")
            } else if self.tappedTransaction.isLightning {
                notificationBody = Language.getWord(withID: "transferfee2")
            } else {
                notificationBody = Language.getWord(withID: "transferfee3")
            }
        case 1: // Bittr fee
            notificationTitle = Language.getWord(withID: "bittrfee")
            notificationBody = Language.getWord(withID: "bittrfee1")
        case 2: // Surcharge
            notificationTitle = Language.getWord(withID: "surcharge")
            notificationBody = Language.getWord(withID: "surcharge1")
        default: return
        }
        
        self.showAlert(title: notificationTitle, message: notificationBody, buttons: [.dismiss(Language.getWord(withID: "okay"))])
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "TransactionToWebsite" {
            if let websiteVC = segue.destination as? WebsiteViewController {
                if let actualTappedUrl = self.tappedUrl {
                    websiteVC.tappedUrl = actualTappedUrl
                }
            }
        } else if segue.identifier == "TransactionToSwapStatus" {
            if let swapVC = segue.destination as? SwapStatusViewController {
                swapVC.coreVC = self.coreVC
                self.coreVC?.homeVC?.swapStatusVC = swapVC
                let tappedSwap = Swap()
                tappedSwap.boltzID = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription)!
                tappedSwap.satoshisAmount = self.tappedTransaction.received
                // Total user cost = Boltz spread (sent - received) + user-paid
                // network fee (Transaction.fee, e.g. the onchain fee on an
                // onchain→lightning swap). SwapStatusVC sums onchainFees +
                // lightningFees + claimTransactionFee, so stash the whole
                // amount in onchainFees and leave the other two at 0.
                tappedSwap.onchainFees = (self.tappedTransaction.sent - self.tappedTransaction.received) + self.tappedTransaction.fee
                tappedSwap.lightningFees = 0
                tappedSwap.swapDirection = self.tappedTransaction.swapDirection
                swapVC.thisSwap = tappedSwap
            }
        }
    }
    
}
