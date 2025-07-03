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
    @IBOutlet weak var tableSpinner: UIActivityIndicatorView!
    @IBOutlet weak var noTransactionsLabel: UILabel!
    
    // Table view header elements
    @IBOutlet weak var balanceView: UIView!
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
    @IBOutlet weak var balanceSpinner: UIActivityIndicatorView!
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
    
    // Articles
    var articles:[String:Article]?
    var allImages:[String:UIImage]?
    
    // Balance calculations
    var balanceWasFetched = false
    
    // Booleans
    var didStartReset = false
    var didFetchConversion = false
    var couldNotFetchConversion = false
    
    // Cove View Controller
    var coreVC:CoreViewController?
    
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
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAllImages), name: NSNotification.Name(rawValue: "updateallimages"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(loadWalletData), name: NSNotification.Name(rawValue: "getwalletdata"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeCurrency), name: NSNotification.Name(rawValue: "changecurrency"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetWallet), name: NSNotification.Name(rawValue: "resetwallet"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(moveButtonTapped), name: NSNotification.Name(rawValue: "openmovevc"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openValueVC), name: NSNotification.Name(rawValue: "openvalue"), object: nil)
        
        // Show cached data upon app startup.
        self.showCachedData()
    }
    
    
    @objc func changeCurrency(notification:NSNotification) {
        
        self.conversionLabel.alpha = 0
        self.balanceSpinner.startAnimating()
        
        self.setConversion(btcValue: CGFloat(self.coreVC!.onchainBalanceInSats + self.coreVC!.lightningBalanceInSats)/100000000, cachedData: false, updateTableAfterConversion: true)
    }
    
    
    @objc func updateAllImages(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualImages = userInfo["images"] as? [String:UIImage] {
                self.allImages = actualImages
            }
        }
    }
    
    @objc func setSignupArticles(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            
            var allArticles = [String:Article]()
            
            for (articleid, articledata) in userInfo {
                if let actualSlug = articleid as? String, let actualArticle = articledata as? Article {
                    allArticles.updateValue(actualArticle, forKey: actualSlug)
                }
            }
            
            if allArticles.count != 0 {
                self.articles = allArticles
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        
        // Set correct top constraint and table insets.
        var bottomInset:CGFloat = 80
        var headerViewTopConstant:CGFloat = 85
        if #available(iOS 13.0, *) {
            if let window = UIApplication.shared.windows.first {
                if window.safeAreaInsets.bottom == 0 {
                    bottomInset = 130
                    headerViewTopConstant = 110
                }
            }
        } else if #available(iOS 11.0, *) {
            if let window = UIApplication.shared.keyWindow {
                if window.safeAreaInsets.bottom == 0 {
                    bottomInset = 130
                    headerViewTopConstant = 110
                }
            }
        }
        homeTableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        balanceCardTop.constant = headerViewTopConstant
        
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
    
    
    func addSpacesToString(balanceValue:String) -> String {
        
        var balanceValue = balanceValue
        
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
    
    
    @IBAction func profitButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "HomeToProfit", sender: self)
    }
    
    @IBAction func buyButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "HomeToGoal", sender: self)
    }
    
    @objc func moveButtonTapped() {
        
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
        
        if segue.identifier == "HomeToGoal" {
            let goalVC = segue.destination as? BuyViewController
            if let actualGoalVC = goalVC {
                actualGoalVC.coreVC = self.coreVC
                if let actualArticles = self.articles {
                    actualGoalVC.articles = actualArticles
                }
                if let actualImages = self.allImages {
                    actualGoalVC.allImages = actualImages
                }
            }
        } else if segue.identifier == "HomeToMove" {
            let moveVC = segue.destination as? MoveViewController
            if let actualMoveVC = moveVC {
                actualMoveVC.fetchedBtcBalance = CGFloat(self.coreVC!.onchainBalanceInSats)
                actualMoveVC.fetchedBtclnBalance = CGFloat(self.coreVC!.lightningBalanceInSats)
                actualMoveVC.eurValue = self.coreVC!.eurValue
                actualMoveVC.chfValue = self.coreVC!.chfValue
                actualMoveVC.homeVC = self
                
                if let actualChannels = self.coreVC?.lightningChannels {
                    if actualChannels.count > 0 {
                        let outboundCapacitySats = Int(actualChannels[0].outboundCapacityMsat/1000)
                        let punishmentReserveSats = Int(actualChannels[0].unspendablePunishmentReserve ?? 0)
                        actualMoveVC.maximumSendableLNSats = outboundCapacitySats
                        if actualMoveVC.maximumSendableLNSats! < 0 {
                            actualMoveVC.maximumSendableLNSats = 0
                        }
                    }
                }
                
                if let actualChannels = self.coreVC?.lightningChannels {
                    if actualChannels.count > 0 {
                        actualMoveVC.maximumReceivableLNSats = Int((actualChannels[0].unspendablePunishmentReserve ?? 0)*10)
                    }
                }
            }
        } else if segue.identifier == "HomeToSend" {
            let sendVC = segue.destination as? SendViewController
            if let actualSendVC = sendVC {
                
                if let actualChannels = self.coreVC?.lightningChannels {
                    if actualChannels.count > 0 {
                        let outboundCapacitySats = Int(actualChannels[0].outboundCapacityMsat/1000)
                        let punishmentReserveSats = Int(actualChannels[0].unspendablePunishmentReserve ?? 0)
                        actualSendVC.maximumSendableLNSats = outboundCapacitySats
                        if actualSendVC.maximumSendableLNSats! < 0 {
                            actualSendVC.maximumSendableLNSats = 0
                        }
                    }
                }
                actualSendVC.btcAmount = CGFloat(self.coreVC!.onchainBalanceInSats).rounded() * 0.00000001
                actualSendVC.btclnAmount = CGFloat(self.coreVC!.lightningBalanceInSats).rounded() * 0.00000001
                actualSendVC.eurValue = self.coreVC!.eurValue
                actualSendVC.chfValue = self.coreVC!.chfValue
                actualSendVC.homeVC = self
            }
        } else if segue.identifier == "HomeToReceive" {
            let receiveVC = segue.destination as? ReceiveViewController
            if let actualReceiveVC = receiveVC {
                actualReceiveVC.homeVC = self
                if let actualChannels = self.coreVC?.lightningChannels {
                    if actualChannels.count > 0 {
                        actualReceiveVC.maximumReceivableLNSats = Int((actualChannels[0].unspendablePunishmentReserve ?? 0)*10)
                    }
                }
            }
        } else if segue.identifier == "HomeToTransaction" {
            let transactionVC = segue.destination as? TransactionViewController
            if let actualTransactionVC = transactionVC {
                actualTransactionVC.tappedTransaction = self.setTransactions[self.tappedTransaction]
                actualTransactionVC.eurValue = self.coreVC!.eurValue
                actualTransactionVC.chfValue = self.coreVC!.chfValue
            }
        } else if segue.identifier == "HomeToProfit" {
            let profitVC = segue.destination as? ProfitViewController
            if let actualProfitVC = profitVC {
                actualProfitVC.totalProfit = self.calculatedProfit
                actualProfitVC.totalValue = self.calculatedCurrentValue
                actualProfitVC.totalInvestments = self.calculatedInvestments
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
        self.coreVC?.onchainBalanceInSats = 0
        self.coreVC?.lightningBalanceInSats = 0
        
        self.noTransactionsLabel.alpha = 0
        self.balanceCardProfitView.alpha = 0
        self.balanceCardGainLabel.alpha = 0
        self.balanceLabel.alpha = 0
        self.bitcoinSign.alpha = 0
        self.satsLabel.alpha = 0
        self.conversionLabel.alpha = 0
        self.balanceSpinner.startAnimating()
        self.homeTableView.reloadData()
        self.tableSpinner.startAnimating()
        
        self.headerSpinner.startAnimating()
        self.headerProblemImage.alpha = 0
        self.couldNotFetchConversion = false
        self.didFetchConversion = false
        
        self.coreVC?.checkmarkSyncing.alpha = 0
        self.coreVC?.spinnerSyncing.startAnimating()
        self.coreVC?.checkmarkFinal.alpha = 0
        
        LightningNodeService.shared.walletReset()
    }
    
    func performSwapMatching() {
        // Manual swap matching for lightning-to-onchain swaps
        print("Performing manual swap matching...")
        
        // Look for lightning and onchain transactions with matching swap descriptions
        var swapTransactions = NSMutableDictionary()
        
        for eachTransaction in self.setTransactions {
            if eachTransaction.lnDescription.contains("Swap") {
                if var existingTransactions = swapTransactions[eachTransaction.lnDescription] as? [Transaction] {
                    existingTransactions += [eachTransaction]
                    swapTransactions.setValue(existingTransactions, forKey: eachTransaction.lnDescription)
                } else {
                    swapTransactions.setValue([eachTransaction], forKey: eachTransaction.lnDescription)
                }
            }
        }
        
        // Process completed swaps
        for (eachSwapID, eachSetOfTransactions) in swapTransactions {
            if (eachSetOfTransactions as! [Transaction]).count == 2 {
                // Completed swap found
                print("Found completed swap: \(eachSwapID)")
                
                let swapTransaction = Transaction()
                swapTransaction.isSwap = true
                swapTransaction.lnDescription = (eachSwapID as! String)
                swapTransaction.sent = (eachSetOfTransactions as! [Transaction])[0].received + (eachSetOfTransactions as! [Transaction])[1].received - (eachSetOfTransactions as! [Transaction])[0].sent - (eachSetOfTransactions as! [Transaction])[1].sent
                
                if (eachSwapID as! String).contains("onchain to lightning") {
                    swapTransaction.swapDirection = 0
                    swapTransaction.isLightning = false
                    swapTransaction.id = (eachSwapID as! String).replacingOccurrences(of: "Swap onchain to lightning ", with: "")
                } else {
                    swapTransaction.swapDirection = 1
                    swapTransaction.isLightning = true
                    swapTransaction.id = (eachSwapID as! String).replacingOccurrences(of: "Swap lightning to onchain ", with: "")
                }
                
                for eachTransaction in (eachSetOfTransactions as! [Transaction]) {
                    if eachTransaction.isLightning {
                        // Lightning payment
                        swapTransaction.lightningID = eachTransaction.id
                        swapTransaction.channelId = eachTransaction.channelId
                        if swapTransaction.swapDirection == 0 {
                            // Onchain to Lightning
                            swapTransaction.timestamp = eachTransaction.timestamp
                            swapTransaction.received = eachTransaction.received
                        } else {
                            swapTransaction.sent = eachTransaction.sent
                        }
                    } else {
                        // Onchain transaction
                        swapTransaction.onchainID = eachTransaction.id
                        swapTransaction.height = eachTransaction.height
                        if let actualCurrentHeight = self.coreVC?.currentHeight {
                            swapTransaction.confirmations = (actualCurrentHeight - eachTransaction.height) + 1
                        }
                        if swapTransaction.swapDirection == 1 {
                            // Lightning to Onchain
                            swapTransaction.timestamp = eachTransaction.timestamp
                            swapTransaction.received = eachTransaction.received - eachTransaction.sent
                        } else {
                            swapTransaction.sent = eachTransaction.sent - eachTransaction.received
                        }
                    }
                }
                
                // Remove the individual transactions and add the combined swap transaction
                for (index, eachTransaction) in self.setTransactions.enumerated().reversed() {
                    if eachTransaction.id == swapTransaction.lightningID || eachTransaction.id == swapTransaction.onchainID {
                        self.setTransactions.remove(at: index)
                    }
                }
                
                self.setTransactions += [swapTransaction]
                self.setTransactions.sort { transaction1, transaction2 in
                    transaction1.timestamp > transaction2.timestamp
                }
                
                // Cache the combined swap transaction
                CacheManager.storeLightningTransaction(thisTransaction: swapTransaction)
                
                print("Successfully combined swap transactions")
                self.homeTableView.reloadData()
                return
            }
        }
        
        print("No completed swaps found for manual matching")
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
            if let actualCoreVC = self.coreVC {
                actualCoreVC.statusView.alpha = 1
                actualCoreVC.blackSignupButton.alpha = 1
                
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                    
                    NSLayoutConstraint.deactivate([actualCoreVC.syncingStatusTop])
                    actualCoreVC.syncingStatusTop = NSLayoutConstraint(item: actualCoreVC.statusView, attribute: .bottom, relatedBy: .equal, toItem: actualCoreVC.view, attribute: .bottom, multiplier: 1, constant: 0)
                    NSLayoutConstraint.activate([actualCoreVC.syncingStatusTop])
                    actualCoreVC.blackSignupBackground.alpha = 0.2
                    actualCoreVC.view.layoutIfNeeded()
                }) { _ in
                    UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                        
                        NSLayoutConstraint.deactivate([actualCoreVC.syncingStatusTop])
                        actualCoreVC.syncingStatusTop = NSLayoutConstraint(item: actualCoreVC.statusView, attribute: .bottom, relatedBy: .equal, toItem: actualCoreVC.view, attribute: .bottom, multiplier: 1, constant: 13)
                        NSLayoutConstraint.activate([actualCoreVC.syncingStatusTop])
                        actualCoreVC.view.layoutIfNeeded()
                    }
                }
            }
        }
    }
    
    @IBAction func currencyTapped(_ sender: UIButton) {
        self.openValueVC()
    }
    
}

extension String {

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
