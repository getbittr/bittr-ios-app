//
//  HomeViewController.swift
//  bittr
//
//  Created by Tom Melters on 12/04/2023.
//

import UIKit
import LDKNode
import UserNotifications
import Sentry

class HomeViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UNUserNotificationCenterDelegate {
    
    // Home table view
    @IBOutlet weak var homeTableView: UITableView!
    @IBOutlet weak var noTransactionsLabel: UILabel!
    
    // Table view header elements
    @IBOutlet weak var backgroundColorView: UIView!
    @IBOutlet weak var backgroundColorTopView: UIView!
    @IBOutlet weak var bottomCurve: BottomCurveView!
    
    // Header: Balance card
    @IBOutlet weak var balanceCard: UIView!
    @IBOutlet weak var balanceCardTop: NSLayoutConstraint!
    @IBOutlet weak var balanceLabelInvisible: UILabel!
    @IBOutlet weak var bitcoinSign: UIImageView!
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var conversionLabel: UILabel!
    @IBOutlet weak var balanceCardButton: UIButton!
    var balanceText = "<center><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(201, 154, 0); line-height: 0.5\">0.00 000 00</span><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(0, 0, 0); line-height: 0.5\">0</span></center>"
    
    // Balance card profit views
    @IBOutlet weak var balanceCardProfitView: UIView!
    @IBOutlet weak var balanceCardArrowImage: UIImageView!
    @IBOutlet weak var balanceCardGainLabel: UILabel!
    
    // Header: Balance card header view
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerSpinner: UIActivityIndicatorView!
    @IBOutlet weak var headerProblemImage: UIImageView!
    @IBOutlet weak var headerPiggyImage: UIImageView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var headerViewButton: UIButton!
    @IBOutlet weak var headerDetailsImage: UIImageView!
    @IBOutlet weak var headerCurrencyImage: UIImageView!
    @IBOutlet weak var currencyButton: UIButton!
    @IBOutlet weak var headerMapImage: UIImageView!
    @IBOutlet weak var mapButton: UIButton!
    
    // Header: Lower buttons
    @IBOutlet weak var sendButtonView: UIView!
    @IBOutlet weak var receiveButtonView: UIView!
    @IBOutlet weak var buyButtonView: UIView!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var buyButton: UIButton!
    @IBOutlet weak var profitButton: UIButton!
    @IBOutlet weak var sendLabel: UILabel!
    @IBOutlet weak var receiveLabel: UILabel!
    @IBOutlet weak var buyLabel: UILabel!
    
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
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.headerLabel.accessibilityIdentifier = TestID.Home.headerLabel
        self.headerSpinner.accessibilityIdentifier = TestID.Home.headerSpinner
        self.sendButton.accessibilityIdentifier = TestID.Home.sendButton
        self.sendButton.accessibilityLabel = Language.getWord(withID: "send")
        self.receiveButton.accessibilityIdentifier = TestID.Home.receiveButton
        self.receiveButton.accessibilityLabel = Language.getWord(withID: "receive")
        self.buyButton.accessibilityIdentifier = TestID.Home.buyButton
        self.buyButton.accessibilityLabel = Language.getWord(withID: "buy")
        self.balanceCardButton.accessibilityIdentifier = TestID.Home.balanceCardButton
        self.balanceCardButton.accessibilityLabel = "Balance details"
        self.balanceLabel.accessibilityIdentifier = TestID.Home.balanceLabel

        // Table view
        self.homeTableView.delegate = self
        self.homeTableView.dataSource = self
        
        // Check if dark mode is on.
        self.changeColors()
        self.setWords()
        self.setBasicStyling()
        
        // Notification observers
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openValueVC), name: NSNotification.Name(rawValue: "openvalue"), object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        // Show cached data upon app startup.
        self.showCachedData()
        self.downloadConversionAndBlockHeight()
    }
    
    
    func changeCurrency() {
        // Update conversion label.
        self.conversionLabel.alpha = 0
        self.setConversion()
        
        // Update table.
        self.reloadTransactionsTable()
        
        // Calculate profits.
        self.calculateProfit()
    }
    
    
    override func viewDidLayoutSubviews() {
        
        // Set correct top constraint and table insets.
        var bottomInset:CGFloat = 80
        var headerViewTopConstant:CGFloat = 85
        if self.coreVC!.view.safeAreaInsets.bottom == 0 {
            bottomInset = 130
            headerViewTopConstant = 110
        }
        self.homeTableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        self.balanceCardTop.constant = headerViewTopConstant
        
        // Set header view.
        if let newHeaderView = homeTableView.tableHeaderView {
            let height = newHeaderView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
            var headerFrame = newHeaderView.frame
            if height != headerFrame.size.height {
                headerFrame.size.height = height
                newHeaderView.frame = headerFrame
                homeTableView.tableHeaderView = newHeaderView
            }
        }
        
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
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        self.performSegue(withIdentifier: "HomeToMove", sender: self)
    }
    
    @IBAction func sendButtonTapped(_ sender: UIButton) {
        
        if !self.coreVC!.walletHasSynced {
            // Wallet isn't ready.
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        guard self.coreVC!.checkInternetConnection() else { return }
        
        self.performSegue(withIdentifier: "HomeToSend", sender: self)
    }
    
    @IBAction func receiveButtonTapped(_ sender: UIButton) {
        
        if !self.coreVC!.walletHasSynced {
            // Wallet isn't ready.
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
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
                
                if let activeChannel = self.coreVC!.bittrWallet.lightningChannels.getActiveChannel() {
                    moveVC.maximumReceivableLNSats = Int((activeChannel.unspendablePunishmentReserve ?? 0)*10)
                }
            }
        } else if segue.identifier == "HomeToSend" {
            if let sendVC = segue.destination as? SendViewController {
                sendVC.coreVC = self.coreVC
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
                if let activeChannel = self.coreVC!.bittrWallet.lightningChannels.getActiveChannel() {
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
        for (index, eachTransaction) in self.visibleTransactions.enumerated().reversed() {
            if eachTransaction.id == thisTransaction.id {
                didFindDuplicateTransaction = true
                self.visibleTransactions.remove(at: index)
            }
        }
        
        // Add new transaction.
        self.visibleTransactions += [thisTransaction]
        self.visibleTransactions = self.visibleTransactions.performSwapMatching()
        
        // Sort transactions array.
        self.visibleTransactions.sort { transaction1, transaction2 in
            transaction1.timestamp > transaction2.timestamp
        }
        
        // Reload table.
        self.homeTableView.reloadData()
        self.noTransactionsLabel.alpha = 0
        
        if !didFindDuplicateTransaction {
            // Update balance and transactions.
            // Skip the += for funding transactions: .channelReady triggers
            // syncLDKnode → loadWalletData, which resets satoshisLightning to
            // 0 and recomputes from listChannels(). Adding received here on
            // top of that double-counts the balance.
            if !thisTransaction.isFundingTransaction {
                self.coreVC!.bittrWallet.satoshisLightning += (thisTransaction.received - thisTransaction.sent)
            }
            self.coreVC!.bittrWallet.lightningChannels = BitcoinManager.shared.listChannels()
            
            if paymentDetails != nil {
                self.coreVC!.bittrWallet.allTransactions += [paymentDetails!]
            }
            
            // Update balance label.
            self.setTotalSats()
            self.moveVC?.updateLabels()
        }
    }
    
    @IBAction func balanceDetailsButtonTapped(_ sender: UIButton) {
        
        if !self.coreVC!.walletHasSynced {
            // Wallet isn't ready.
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        self.performSegue(withIdentifier: "HomeToMove", sender: self)
    }
    
    @IBAction func syncingStatusTapped(_ sender: UIButton) {
        
        if self.coreVC!.walletHasSynced {
            if self.couldNotFetchConversion {
                self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "conversionfail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            } else {
                self.balanceDetailsButtonTapped(self.balanceCardButton)
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
