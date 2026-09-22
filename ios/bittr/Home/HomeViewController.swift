//
//  HomeViewController.swift
//  bittr
//
//  Created by Tom Melters on 12/04/2023.
//

import UIKit
import LDKNode
import UserNotifications

class HomeViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UNUserNotificationCenterDelegate {
    
    // Home table view
    @IBOutlet weak var homeTableView: UITableView!
    var appliedTopSafeArea:CGFloat?
    
    // Profit calculations
    var calculatedProfit = 0
    var calculatedInvestments = 0
    var calculatedCurrentValue = 0
    
    // Transactions
    var visibleTransactions = [Transaction]()
    var newTransactions = [Transaction]()
    var bittrTransactions = [String:BittrTransaction]()
    var cachedLightningIds = [String]()
    var tappedTransaction = Transaction()
    
    // Booleans
    var didStartReset = false
    var didFetchConversion = false
    var couldNotFetchConversion = false
    
    // Other VCs
    var coreVC:CoreViewController?
    var moveVC:MoveViewController?
    var sendVC:SendViewController?
    var swapStatusVC:SwapStatusViewController?
    
    // Pending URI data for seamless segue
    var pendingBitcoinURI: (address: String, amount: String, label: String)?
    var pendingLightningURI: String?
    
    // Bitcoin historical data
    var eurData:Data?
    var eurDataFetched:Date?
    var chfData:Data?
    var chfDataFetched:Date?
    var currentValue:Data?
    var currentValueFetched:Date?
    var graphPoints:[PricePoint]?
    var isLoadingGraph = false
    var graphLoadFailedAt:Date? // When the last attempt failed.
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Table view
        self.homeTableView.delegate = self
        self.homeTableView.dataSource = self
        self.homeTableView.estimatedRowHeight = 430
        self.homeTableView.contentInsetAdjustmentBehavior = .never
        
        // Check if dark mode is on.
        self.changeColors()
        
        // Notification observers
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openValueVC), name: NSNotification.Name(rawValue: "openvalue"), object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        // Show cached data upon app startup.
        self.showCachedData()
        self.downloadConversionAndBlockHeight()
    }
    
    func changeCurrency() {
        // Update value card.
        self.graphPoints = nil
        
        // Update table.
        self.reloadTransactionsTable()
    }
    
    @objc func changeColors() {
        // Update table.
        self.reloadTransactionsTable()
    }
    
    override func viewDidLayoutSubviews() {
        
        // Set table insets.
        let bottomSafeArea = self.coreVC!.view.safeAreaInsets.bottom
        let bottomInset:CGFloat = bottomSafeArea == 0 ? 130 : bottomSafeArea + 80
        self.homeTableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
    }
    
    @IBAction func profitButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "HomeToProfit", sender: self)
    }
    
    @IBAction func buyButtonTapped(_ sender: UIButton) {
        self.performSegue(withIdentifier: "HomeToBuy", sender: self)
    }
    
    func moveButtonTapped() {
        // Balance Card tapped.
        
        if !self.coreVC!.walletHasSynced {
            // Wallet isn't ready.
            self.showAlert(title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        self.performSegue(withIdentifier: "HomeToMove", sender: self)
    }
    
    @IBAction func sendButtonTapped(_ sender: UIButton) {
        
        if !self.coreVC!.walletHasSynced {
            // Wallet isn't ready.
            self.showAlert(title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        guard self.coreVC!.checkInternetConnection() else { return }
        
        self.performSegue(withIdentifier: "HomeToSend", sender: self)
    }
    
    @IBAction func receiveButtonTapped(_ sender: UIButton) {
        
        if !self.coreVC!.walletHasSynced {
            // Wallet isn't ready.
            self.showAlert(title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        guard self.coreVC!.checkInternetConnection() else { return }
        
        self.performSegue(withIdentifier: "HomeToReceive", sender: self)
    }
    
    @IBAction func transactionButtonTapped(_ sender: UIButton) {
        if let thisTransaction = sender.accessibilityElements?.first as? Transaction {
            self.tappedTransaction = thisTransaction
            self.performSegue(withIdentifier: "HomeToTransaction", sender: self)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "HomeToBuy" {
            if let buyVC = segue.destination as? BuyViewController {
                buyVC.coreVC = self.coreVC
                self.coreVC!.buyVC = buyVC
            }
        } else if segue.identifier == "HomeToMove" {
            if let moveVC = segue.destination as? MoveViewController {
                moveVC.coreVC = self.coreVC
                moveVC.homeVC = self
                self.moveVC = moveVC
                
                if let activeChannel = BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel() {
                    moveVC.maximumReceivableLNSats = Int((activeChannel.unspendablePunishmentReserve ?? 0)*10)
                }
            }
        } else if segue.identifier == "HomeToSend" {
            if let sendVC = segue.destination as? SendViewController {
                sendVC.coreVC = self.coreVC
                sendVC.homeVC = self
                self.sendVC = sendVC
                
                // Pass pending URI data if available
                if let bitcoinURI = self.pendingBitcoinURI {
                    sendVC.pendingBitcoinURI = bitcoinURI
                    self.pendingBitcoinURI = nil // Clear after passing
                }
                
                if let lightningURI = self.pendingLightningURI {
                    sendVC.pendingLightningURI = lightningURI
                    self.pendingLightningURI = nil // Clear after passing
                }
            }
        } else if segue.identifier == "HomeToReceive" {
            if let receiveVC = segue.destination as? ReceiveViewController {
                receiveVC.homeVC = self
                receiveVC.coreVC = self.coreVC
                self.coreVC?.receiveVC = receiveVC
                if let activeChannel = BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel() {
                    receiveVC.maximumReceivableLNSats = Int((activeChannel.unspendablePunishmentReserve ?? 0)*10)
                }
            }
        } else if segue.identifier == "HomeToTransaction" {
            if let transactionVC = segue.destination as? TransactionViewController {
                
                transactionVC.coreVC = self.coreVC
                if let newBittrPayout = self.coreVC?.receivedBittrTransaction {
                    transactionVC.showConfetti = true
                    transactionVC.tappedTransaction = newBittrPayout
                    self.coreVC!.receivedBittrTransaction = nil
                } else {
                    transactionVC.tappedTransaction = self.tappedTransaction
                }
            }
        } else if segue.identifier == "HomeToProfit" {
            if let profitVC = segue.destination as? ProfitViewController {
                profitVC.totalProfit = self.calculatedProfit
                profitVC.totalValue = self.calculatedCurrentValue
                profitVC.totalInvestments = self.calculatedInvestments
                profitVC.coreVC = self.coreVC
            }
        } else if segue.identifier == "HomeToValue" {
            if let valueVC = segue.destination as? ValueViewController {
                valueVC.homeVC = self
            }
        } else if segue.identifier == "HomeToSwapStatus" {
            if let swapStatusVC = segue.destination as? SwapStatusViewController, let latestSwap = CacheManager.getLatestSwap() {
                swapStatusVC.coreVC = self.coreVC
                swapStatusVC.thisSwap = latestSwap
                self.swapStatusVC = swapStatusVC
            }
        }
    }
    
    func addLightningTransaction(thisTransaction:Transaction, paymentDetails:PaymentDetails?) {
        
        // Remove any duplicate transactions.
        var didFindDuplicateTransaction = false
        for (index, eachTransaction) in self.visibleTransactions.enumerated().reversed() where eachTransaction.id == thisTransaction.id {
            didFindDuplicateTransaction = true
            self.visibleTransactions.remove(at: index)
        }
        
        // Add new transaction.
        self.visibleTransactions += [thisTransaction]
        self.visibleTransactions = self.visibleTransactions.performSwapMatching()
        
        // Sort transactions array.
        self.visibleTransactions.sort { transaction1, transaction2 in
            transaction1.timestamp > transaction2.timestamp
        }
        
        // Update cache
        CacheManager.cachedHomeTransactions = self.visibleTransactions
        
        guard !didFindDuplicateTransaction else {
            self.reloadTransactionsTable()
            return
        }
        
        // Update balance and transactions.
        // For funding transactions, .channelReady will update the balance.
        if !thisTransaction.isFundingTransaction {
            BitcoinManager.shared.bittrWallet.satoshisLightning += (thisTransaction.received - thisTransaction.sent)
        }
        BitcoinManager.shared.bittrWallet.lightningChannels = BitcoinManager.shared.listChannels()
        
        if paymentDetails != nil {
            BitcoinManager.shared.bittrWallet.allTransactions += [paymentDetails!]
        }
        
        if thisTransaction.isBittr {
            self.bittrTransactions.updateValue(thisTransaction.toBittrTransaction(), forKey: thisTransaction.id)
        }
        
        // Update balance label.
        self.reloadTransactionsTable()
        self.moveVC?.updateLabels()
    }
    
    @IBAction func balanceDetailsButtonTapped(_ sender: UIButton) {
        
        if !self.coreVC!.walletHasSynced {
            // Wallet isn't ready.
            self.showAlert(title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        self.performSegue(withIdentifier: "HomeToMove", sender: self)
    }
    
    @IBAction func syncingStatusTapped(_ sender: UIButton) {
        
        if self.coreVC!.walletHasSynced {
            if self.couldNotFetchConversion {
                self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "conversionfail"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            } else {
                self.balanceDetailsButtonTapped(UIButton())
            }
        } else {
            self.coreVC?.showSyncView()
        }
    }
    
    @IBAction func currencyTapped(_ sender: UIButton) {
        self.openValueVC()
    }
    
    @objc func openValueVC() {
        self.performSegue(withIdentifier: "HomeToValue", sender: self)
    }
    
    @IBAction func mapTapped(_ sender: UIButton) {
        self.performSegue(withIdentifier: "HomeToMap", sender: self)
    }
    
}
