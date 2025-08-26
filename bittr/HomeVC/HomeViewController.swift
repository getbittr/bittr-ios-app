//
//  HomeViewController.swift
//  bittr
//
//  Created by Tom Melters on 12/04/2023.
//

import UIKit
import LDKNode
import BitcoinDevKit
import UserNotifications
import LDKNodeFFI

class HomeViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UNUserNotificationCenterDelegate {
    
    // Home table view
    @IBOutlet weak var homeTableView: UITableView!
    @IBOutlet weak var noTransactionsLabel: UILabel!
    
    // Table view header elements
    @IBOutlet weak var backgroundColorView: UIView!
    @IBOutlet weak var backgroundColorTopView: UIView!
    @IBOutlet weak var yellowCurve: UIImageView!
    
    // Header: Balance card
    @IBOutlet weak var balanceCard: UIView!
    @IBOutlet weak var balanceCardTop: NSLayoutConstraint!
    @IBOutlet weak var balanceLabelInvisible: UILabel!
    @IBOutlet weak var bitcoinSign: UIImageView!
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var satsLabel: UILabel!
    @IBOutlet weak var satsLabelLeading: NSLayoutConstraint!
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
    var calculatedProfit = 0
    var calculatedInvestments = 0
    var calculatedCurrentValue = 0
    
    // Transactions
    var setTransactions = [Transaction]()
    var newTransactions = [Transaction]()
    var lastCachedTransactions = [Transaction]()
    var fetchedTransactions = [[String:String]]()
    var bittrTransactions = NSMutableDictionary() // Key is the txID, Value is purchaseAmount and currency.
    var cachedLightningIds = [String]()
    var tappedTransaction = 0
    
    // Balance calculations
    var balanceWasFetched = false
    
    // Booleans
    var didStartReset = false
    var didFetchConversion = false
    var couldNotFetchConversion = false
    
    // Cove View Controller
    var coreVC:CoreViewController?
    var moveVC:MoveViewController?
    
    // Bitcoin historical data
    var eurData:Data?
    var eurDataFetched:Date?
    var chfData:Data?
    var chfDataFetched:Date?
    var currentValue:Data?
    var currentValueFetched:Date?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii
        self.buyButtonView.layer.cornerRadius = 8
        self.sendButtonView.layer.cornerRadius = 8
        self.receiveButtonView.layer.cornerRadius = 8
        self.headerView.layer.cornerRadius = 13
        self.balanceCard.layer.cornerRadius = 13
        self.balanceCardProfitView.layer.cornerRadius = 13
        
        // Button titles
        self.profitButton.setTitle("", for: .normal)
        self.buyButton.setTitle("", for: .normal)
        self.sendButton.setTitle("", for: .normal)
        self.receiveButton.setTitle("", for: .normal)
        self.balanceCardButton.setTitle("", for: .normal)
        self.headerViewButton.setTitle("", for: .normal)
        self.currencyButton.setTitle("", for: .normal)
        
        // Balance card shadow
        self.balanceCard.setShadow()
        self.sendButtonView.setShadow()
        self.receiveButtonView.setShadow()
        self.buyButtonView.setShadow()
        
        // Table view
        self.homeTableView.delegate = self
        self.homeTableView.dataSource = self
        
        // Check if dark mode is on.
        self.changeColors()
        self.setWords()
        
        // Notification observers
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openValueVC), name: NSNotification.Name(rawValue: "openvalue"), object: nil)
        
        // Show cached data upon app startup.
        self.showCachedData()
    }
    
    
    func changeCurrency() {
        
        self.conversionLabel.alpha = 0
        self.setConversion(btcValue: CGFloat(self.coreVC!.bittrWallet.satoshisOnchain + self.coreVC!.bittrWallet.satoshisLightning)/100000000, cachedData: false, updateTableAfterConversion: true)
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
        
        if self.headerSpinner.isAnimating {
            // Wallet isn't ready.
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        if self.balanceWasFetched == true {
            performSegue(withIdentifier: "HomeToMove", sender: self)
        }
    }
    
    @IBAction func sendButtonTapped(_ sender: UIButton) {
        
        if self.headerSpinner.isAnimating {
            // Wallet isn't ready.
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        if self.balanceWasFetched == true {
            performSegue(withIdentifier: "HomeToSend", sender: self)
        }
    }
    
    @IBAction func receiveButtonTapped(_ sender: UIButton) {
        
        if self.headerSpinner.isAnimating {
            // Wallet isn't ready.
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        if self.balanceWasFetched == true {
            performSegue(withIdentifier: "HomeToReceive", sender: self)
        }
    }
    
    @IBAction func transactionButtonTapped(_ sender: UIButton) {
        
        self.tappedTransaction = sender.tag
        
        performSegue(withIdentifier: "HomeToTransaction", sender: self)
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
                
                if let actualChannels = self.coreVC?.bittrWallet.lightningChannels {
                    if actualChannels.count > 0 {
                        let outboundCapacitySats = Int(actualChannels[0].outboundCapacityMsat/1000)
                        let punishmentReserveSats = Int(actualChannels[0].unspendablePunishmentReserve ?? 0)
                        moveVC.maximumSendableLNSats = outboundCapacitySats
                        if moveVC.maximumSendableLNSats! < 0 {
                            moveVC.maximumSendableLNSats = 0
                        }
                    }
                }
                
                if let actualChannels = self.coreVC?.bittrWallet.lightningChannels {
                    if actualChannels.count > 0 {
                        moveVC.maximumReceivableLNSats = Int((actualChannels[0].unspendablePunishmentReserve ?? 0)*10)
                    }
                }
            }
        } else if segue.identifier == "HomeToSend" {
            let sendVC = segue.destination as? SendViewController
            if let actualSendVC = sendVC {
                
                if let actualChannels = self.coreVC?.bittrWallet.lightningChannels {
                    if actualChannels.count > 0 {
                        let outboundCapacitySats = Int(actualChannels[0].outboundCapacityMsat/1000)
                        let punishmentReserveSats = Int(actualChannels[0].unspendablePunishmentReserve ?? 0)
                        actualSendVC.maximumSendableLNSats = outboundCapacitySats
                        if actualSendVC.maximumSendableLNSats! < 0 {
                            actualSendVC.maximumSendableLNSats = 0
                        }
                    }
                }
                actualSendVC.coreVC = self.coreVC
                actualSendVC.homeVC = self
            }
        } else if segue.identifier == "HomeToReceive" {
            let receiveVC = segue.destination as? ReceiveViewController
            if let actualReceiveVC = receiveVC {
                actualReceiveVC.homeVC = self
                actualReceiveVC.coreVC = self.coreVC
                if let actualChannels = self.coreVC?.bittrWallet.lightningChannels {
                    if actualChannels.count > 0 {
                        actualReceiveVC.maximumReceivableLNSats = Int((actualChannels[0].unspendablePunishmentReserve ?? 0)*10)
                    }
                }
            }
        } else if segue.identifier == "HomeToTransaction" {
            let transactionVC = segue.destination as? TransactionViewController
            if let actualTransactionVC = transactionVC {
                actualTransactionVC.tappedTransaction = self.setTransactions[self.tappedTransaction]
                actualTransactionVC.coreVC = self.coreVC
            }
        } else if segue.identifier == "HomeToProfit" {
            let profitVC = segue.destination as? ProfitViewController
            if let actualProfitVC = profitVC {
                actualProfitVC.totalProfit = self.calculatedProfit
                actualProfitVC.totalValue = self.calculatedCurrentValue
                actualProfitVC.totalInvestments = self.calculatedInvestments
                actualProfitVC.coreVC = self.coreVC
            }
        } else if segue.identifier == "HomeToValue" {
            if let valueVC = segue.destination as? ValueViewController {
                valueVC.homeVC = self
            }
        }
    }
    
    @objc func resetWallet() {
        
        print("Reset wallet.")
        
        self.setTransactions.removeAll()
        self.newTransactions.removeAll()
        self.calculatedProfit = 0
        self.calculatedInvestments = 0
        self.calculatedCurrentValue = 0
        self.coreVC?.bittrWallet.satoshisOnchain = 0
        self.coreVC?.bittrWallet.satoshisLightning = 0
        
        self.noTransactionsLabel.alpha = 0
        self.balanceCardProfitView.alpha = 0
        self.balanceCardGainLabel.alpha = 0
        self.balanceLabel.alpha = 0
        self.bitcoinSign.alpha = 0
        self.satsLabel.alpha = 0
        self.conversionLabel.alpha = 0
        self.homeTableView.reloadData()
        
        self.headerSpinner.startAnimating()
        self.headerProblemImage.alpha = 0
        self.couldNotFetchConversion = false
        self.didFetchConversion = false
        
        self.coreVC?.checkmarkSyncing.alpha = 0
        self.coreVC?.spinnerSyncing.startAnimating()
        self.coreVC?.checkmarkFinal.alpha = 0
        
        LightningNodeService.shared.walletReset()
    }
    
    func addTransaction(_ thisTransaction:Transaction) {
        
        // Add new transaction.
        self.setTransactions += [thisTransaction]
        self.setTransactions = self.setTransactions.performSwapMatching(coreVC: self.coreVC!, storeInCache: false)
        
        // Sort transactions array.
        self.setTransactions.sort { transaction1, transaction2 in
            transaction1.timestamp > transaction2.timestamp
        }
        
        // Reload table.
        self.homeTableView.reloadData()
        self.noTransactionsLabel.alpha = 0
        
        // Update balance.
        if thisTransaction.isLightning {
            self.coreVC!.bittrWallet.satoshisLightning += (thisTransaction.received - thisTransaction.sent)
        } else {
            self.coreVC!.bittrWallet.satoshisOnchain += (thisTransaction.received - thisTransaction.sent)
        }
        
        // Update balance label.
        self.setTotalSats(updateTableAfterConversion: false)
        self.moveVC?.updateLabels()
    }
    
    func performSwapMatching() {
        // Manual swap matching for lightning-to-onchain swaps
        print("Performing manual swap matching...")
        
        // Look for lightning and onchain transactions with matching swap descriptions
        self.setTransactions = self.setTransactions.performSwapMatching(coreVC: self.coreVC, storeInCache: false)
        
        // Sort and reload table
        self.setTransactions.sort { transaction1, transaction2 in
            transaction1.timestamp > transaction2.timestamp
        }
        self.homeTableView.reloadData()
        
        // Store transactions in cache.
        CacheManager.updateCachedData(data: self.setTransactions, key: "transactions")
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        
        // Reload wallet when pulling down the view.
        
        if scrollView.contentOffset.y < -200, self.didStartReset == false, !self.headerSpinner.isAnimating {
            
            if !Reachability.isConnectedToNetwork() {
                // User not connected to internet.
                self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                return
            }
            
            self.didStartReset = true
            self.resetWallet()
        }
    }
    
    
    func askForPushNotifications() {
        
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings { (settings) in
            
            if settings.authorizationStatus == .notDetermined {
                // User hasn't set their preference yet.
                
                current.delegate = self
                current.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    
                    print("Permission granted: \(granted)")
                    guard granted else {return}
                    
                    // Double check that the preference is now authorized.
                    current.getNotificationSettings { (settings) in
                        print("Notification settings: \(settings)")
                        guard settings.authorizationStatus == .authorized else {return}
                        DispatchQueue.main.async {
                            // Register for notifications.
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            }
        }
    }
    
    @IBAction func balanceDetailsButtonTapped(_ sender: UIButton) {
        
        if self.headerSpinner.isAnimating {
            // Wallet isn't ready.
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        performSegue(withIdentifier: "HomeToMove", sender: self)
    }
    
    @IBAction func syncingStatusTapped(_ sender: UIButton) {
        
        if !self.headerSpinner.isAnimating {
            if self.couldNotFetchConversion == true {
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
    
}

extension String {
    
    func addSpaces() -> String {
        
        var balanceValue = self
        
        switch balanceValue.count {
        case 4:
            balanceValue = balanceValue[0] + " " + balanceValue[1..<4]
        case 5:
            balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5]
        case 6:
            balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6]
        case 7:
            balanceValue = balanceValue[0] + " " + balanceValue[1..<4] + " " + balanceValue[4..<7]
        case 8:
            balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5] + " " + balanceValue[5..<8]
        case 9:
            balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6] + " " + balanceValue[6..<9]
        default:
            balanceValue = balanceValue[0..<balanceValue.count]
        }
        
        return balanceValue
    }

    var length: Int {
        return count
    }

    subscript (i: Int) -> String {
        return self[i ..< i + 1]
    }

    func substring(fromIndex: Int) -> String {
        return self[min(fromIndex, length) ..< length]
    }

    func substring(toIndex: Int) -> String {
        return self[0 ..< max(0, toIndex)]
    }

    subscript (r: Range<Int>) -> String {
        let range = Range(uncheckedBounds: (lower: max(0, min(length, r.lowerBound)),
                                            upper: min(length, max(0, r.upperBound))))
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(start, offsetBy: range.upperBound - range.lowerBound)
        return String(self[start ..< end])
    }
}

extension UIView {
    
    func setShadow() {
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.layer.shadowRadius = 10.0
        self.layer.shadowOpacity = 0.1
    }
}
