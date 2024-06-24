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
    @IBOutlet weak var yellowCurve: UIImageView!
    
    // Header: Balance card
    @IBOutlet weak var balanceCard: UIView!
    @IBOutlet weak var balanceCardTop: NSLayoutConstraint!
    @IBOutlet weak var balanceLabelInvisible: UILabel!
    @IBOutlet weak var bitcoinSign: UIImageView!
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var satsLabel: UILabel!
    @IBOutlet weak var conversionLabel: UILabel!
    @IBOutlet weak var balanceSpinner: UIActivityIndicatorView!
    @IBOutlet weak var balanceCardButton: UIButton!
    var balanceText = "<center><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(201, 154, 0); line-height: 0.5\">0.00 000 00</span><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(0, 0, 0); line-height: 0.5\">0</span></center>"
    
    // Header: Balance card header view
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerSpinner: UIActivityIndicatorView!
    @IBOutlet weak var headerProblemImage: UIImageView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var headerLabelLeading: NSLayoutConstraint!
    @IBOutlet weak var headerViewButton: UIButton!
    
    // Header: Lower buttons
    @IBOutlet weak var sendButtonView: UIView!
    @IBOutlet weak var receiveButtonView: UIView!
    @IBOutlet weak var buyButtonView: UIView!
    @IBOutlet weak var profitButtonView: UIView!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var buyButton: UIButton!
    @IBOutlet weak var profitButton: UIButton!
    @IBOutlet weak var bittrProfitLabel: UILabel!
    @IBOutlet weak var bittrProfitSpinner: UIActivityIndicatorView!
    var calculatedProfit = 0
    var calculatedInvestments = 0
    var calculatedCurrentValue = 0
    
    // Transactions
    var setTransactions = [Transaction]()
    var newTransactions = [Transaction]()
    var lastCachedTransactions = [Transaction]()
    var fetchedTransactions = [[String:String]]()
    var bittrTransactions = NSMutableDictionary()
    var cachedLightningIds = [String]()
    var tappedTransaction = 0
    
    // Client details
    var client = Client()
    
    // Articles
    var articles:[String:Article]?
    var allImages:[String:UIImage]?
    
    // Balance calculations
    var bdkBalance:CGFloat = 0.0
    var btcBalance:CGFloat = 0.0
    var btclnBalance:CGFloat = 0.0
    var totalBalanceSats:CGFloat = 0.0
    var balanceWasFetched = false
    var eurValue:CGFloat = 0.0
    var chfValue:CGFloat = 0.0
    var channels:[ChannelDetails]?
    var currentHeight:Int?
    var bittrChannel:Channel?
    
    // Booleans
    var didStartReset = false
    var didFetchConversion = false
    var couldNotFetchConversion = false
    
    // Cove View Controller
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii
        profitButtonView.layer.cornerRadius = 13
        buyButtonView.layer.cornerRadius = 13
        sendButtonView.layer.cornerRadius = 13
        receiveButtonView.layer.cornerRadius = 13
        headerView.layer.cornerRadius = 13
        balanceCard.layer.cornerRadius = 13
        
        // Button titles
        profitButton.setTitle("", for: .normal)
        buyButton.setTitle("", for: .normal)
        sendButton.setTitle("", for: .normal)
        receiveButton.setTitle("", for: .normal)
        balanceCardButton.setTitle("", for: .normal)
        headerViewButton.setTitle("", for: .normal)
        
        // Balance card shadow
        balanceCard.layer.shadowColor = UIColor.black.cgColor
        balanceCard.layer.shadowOffset = CGSize(width: 0, height: 7)
        balanceCard.layer.shadowRadius = 10.0
        balanceCard.layer.shadowOpacity = 0.1
        
        // Table view
        homeTableView.delegate = self
        homeTableView.dataSource = self
        
        // Notification observers
        NotificationCenter.default.addObserver(self, selector: #selector(setClient), name: NSNotification.Name(rawValue: "restorewallet"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setClient), name: NSNotification.Name(rawValue: "setclient"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAllImages), name: NSNotification.Name(rawValue: "updateallimages"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(loadWalletData), name: NSNotification.Name(rawValue: "getwalletdata"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setTotalSats), name: NSNotification.Name(rawValue: "settotalsats"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeCurrency), name: NSNotification.Name(rawValue: "changecurrency"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetWallet), name: NSNotification.Name(rawValue: "resetwallet"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(moveButtonTapped), name: NSNotification.Name(rawValue: "openmovevc"), object: nil)
        
        // Show cached data upon app startup.
        showCachedData()
    }
    
    
    @objc func changeCurrency(notification:NSNotification) {
        
        self.conversionLabel.alpha = 0
        self.balanceSpinner.startAnimating()
        
        self.setConversion(btcValue: self.btcBalance/100000000, cachedData: false)
    }
    
    
    @objc func updateAllImages(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualImages = userInfo["images"] as? [String:UIImage] {
                self.allImages = actualImages
            }
        }
    }
    
    @objc func setClient() {
        
        var envKey = "proddevice"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "device"
        }
        
        let deviceDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
        if let actualDeviceDict = deviceDict {
            // Client exists in cache.
            let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
            
            self.client = clients[0]
            if let actualCoreVC = self.coreVC {
                actualCoreVC.client = clients[0]
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
        var headerViewTopConstant:CGFloat = 90
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
        
        if self.headerLabel.text == "syncing" {
            // Wallet isn't ready.
            let alert = UIAlertController(title: "Syncing wallet", message: "Please wait a moment while we're syncing your wallet.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
            return
        }
        
        if self.balanceWasFetched == true {
            performSegue(withIdentifier: "HomeToMove", sender: self)
        }
    }
    
    @IBAction func sendButtonTapped(_ sender: UIButton) {
        
        if self.headerLabel.text == "syncing" {
            // Wallet isn't ready.
            let alert = UIAlertController(title: "Syncing wallet", message: "Please wait a moment while we're syncing your wallet.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
            return
        }
        
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            let alert = UIAlertController(title: "Check your connection", message: "You don't seem to be connected to the internet. Please try to connect.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
            return
        }
        
        if self.balanceWasFetched == true {
            performSegue(withIdentifier: "HomeToSend", sender: self)
        }
    }
    
    @IBAction func receiveButtonTapped(_ sender: UIButton) {
        
        if self.headerLabel.text == "syncing" {
            // Wallet isn't ready.
            let alert = UIAlertController(title: "Syncing wallet", message: "Please wait a moment while we're syncing your wallet.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
            return
        }
        
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            let alert = UIAlertController(title: "Check your connection", message: "You don't seem to be connected to the internet. Please try to connect.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
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
                actualGoalVC.client = self.client
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
                actualMoveVC.fetchedBtcBalance = self.btcBalance
                actualMoveVC.fetchedBtclnBalance = self.btclnBalance
                actualMoveVC.eurValue = self.eurValue
                actualMoveVC.chfValue = self.chfValue
                actualMoveVC.homeVC = self
                
                if let actualChannels = self.channels {
                    if actualChannels.count > 0 {
                        let outboundCapacitySats = Int(actualChannels[0].outboundCapacityMsat/1000)
                        let punishmentReserveSats = Int(actualChannels[0].unspendablePunishmentReserve ?? 0)
                        actualMoveVC.maximumSendableLNSats = outboundCapacitySats
                        if actualMoveVC.maximumSendableLNSats! < 0 {
                            actualMoveVC.maximumSendableLNSats = 0
                        }
                    }
                }
                
                if let actualChannels = self.channels {
                    if actualChannels.count > 0 {
                        actualMoveVC.maximumReceivableLNSats = Int((actualChannels[0].unspendablePunishmentReserve ?? 0)*10)
                    }
                }
            }
        } else if segue.identifier == "HomeToSend" {
            let sendVC = segue.destination as? SendViewController
            if let actualSendVC = sendVC {
                
                if let actualChannels = self.channels {
                    if actualChannels.count > 0 {
                        let outboundCapacitySats = Int(actualChannels[0].outboundCapacityMsat/1000)
                        let punishmentReserveSats = Int(actualChannels[0].unspendablePunishmentReserve ?? 0)
                        actualSendVC.maximumSendableLNSats = outboundCapacitySats
                        if actualSendVC.maximumSendableLNSats! < 0 {
                            actualSendVC.maximumSendableLNSats = 0
                        }
                    }
                }
                actualSendVC.btcAmount = self.btcBalance.rounded() * 0.00000001
                actualSendVC.btclnAmount = self.btclnBalance.rounded() * 0.00000001
                actualSendVC.eurValue = self.eurValue
                actualSendVC.chfValue = self.chfValue
                actualSendVC.homeVC = self
            }
        } else if segue.identifier == "HomeToReceive" {
            let receiveVC = segue.destination as? ReceiveViewController
            if let actualReceiveVC = receiveVC {
                
                if let actualChannels = self.channels {
                    if actualChannels.count > 0 {
                        actualReceiveVC.maximumReceivableLNSats = Int((actualChannels[0].unspendablePunishmentReserve ?? 0)*10)
                    }
                }
            }
        } else if segue.identifier == "HomeToTransaction" {
            let transactionVC = segue.destination as? TransactionViewController
            if let actualTransactionVC = transactionVC {
                actualTransactionVC.tappedTransaction = self.setTransactions[self.tappedTransaction]
                actualTransactionVC.eurValue = self.eurValue
                actualTransactionVC.chfValue = self.chfValue
            }
        } else if segue.identifier == "HomeToProfit" {
            let profitVC = segue.destination as? ProfitViewController
            if let actualProfitVC = profitVC {
                actualProfitVC.totalProfit = self.calculatedProfit
                actualProfitVC.totalValue = self.calculatedCurrentValue
                actualProfitVC.totalInvestments = self.calculatedInvestments
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
        self.btcBalance = 0.0
        self.btclnBalance = 0.0
        self.totalBalanceSats = 0.0
        
        self.noTransactionsLabel.alpha = 0
        self.bittrProfitLabel.alpha = 0
        self.bittrProfitSpinner.startAnimating()
        self.balanceLabel.alpha = 0
        self.bitcoinSign.alpha = 0
        self.satsLabel.alpha = 0
        self.conversionLabel.alpha = 0
        self.balanceSpinner.startAnimating()
        self.homeTableView.reloadData()
        self.tableSpinner.startAnimating()
        
        self.headerLabel.text = "syncing"
        self.headerLabelLeading.constant = 10
        self.headerSpinner.startAnimating()
        self.headerProblemImage.alpha = 0
        self.couldNotFetchConversion = false
        self.didFetchConversion = false
        
        LightningNodeService.shared.walletReset()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        
        // Reload wallet when pulling down the view.
        
        if scrollView.contentOffset.y < -200, self.didStartReset == false, self.headerLabel.text != "syncing" {
            
            if !Reachability.isConnectedToNetwork() {
                // User not connected to internet.
                let alert = UIAlertController(title: "Check your connection", message: "You don't seem to be connected to the internet. Please try to connect.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                self.present(alert, animated: true)
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
        
        if self.headerLabel.text == "syncing" {
            // Wallet isn't ready.
            let alert = UIAlertController(title: "Syncing wallet", message: "Please wait a moment while we're syncing your wallet.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
            return
        }
        
        performSegue(withIdentifier: "HomeToMove", sender: self)
    }
    
    @IBAction func syncingStatusTapped(_ sender: UIButton) {
        
        if self.headerLabel.text != "syncing" {
            if self.couldNotFetchConversion == true {
                let alert = UIAlertController(title: "Oops!", message: "We're experiencing an issue fetching the latest conversion rates. Temporarily, our calculations - if available - won't reflect bitcoin's current value.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                self.present(alert, animated: true)
            } else {
                self.balanceDetailsButtonTapped(self.balanceCardButton)
            }
        } else {
            if let actualCoreVC = self.coreVC {
                actualCoreVC.blackSignupBackground.alpha = 0.2
                actualCoreVC.statusView.alpha = 1
                actualCoreVC.blackSignupButton.alpha = 1
            }
        }
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
