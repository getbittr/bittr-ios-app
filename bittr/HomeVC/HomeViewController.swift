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

class HomeViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UNUserNotificationCenterDelegate {

    @IBOutlet weak var numberViewLeft: UIView!
    @IBOutlet weak var numberViewMiddle: UIView!
    @IBOutlet weak var numberViewSend: UIView!
    @IBOutlet weak var numberViewReceive: UIView!
    
    @IBOutlet weak var homeTableView: UITableView!
    @IBOutlet weak var balanceView: UIView!
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var balanceSpinner: UIActivityIndicatorView!
    @IBOutlet weak var conversionLabel: UILabel!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerViewTop: NSLayoutConstraint!
    
    @IBOutlet weak var profitButton: UIButton!
    @IBOutlet weak var goalButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var receiveButton: UIButton!
    
    @IBOutlet weak var graphView: GraphView!
    @IBOutlet weak var optionDayView: UIView!
    @IBOutlet weak var optionWeekView: UIView!
    @IBOutlet weak var optionMonthView: UIView!
    @IBOutlet weak var optionYearView: UIView!
    @IBOutlet weak var optionFiveYearsView: UIView!
    @IBOutlet weak var dayButton: UIButton!
    @IBOutlet weak var weekButton: UIButton!
    @IBOutlet weak var monthButton: UIButton!
    @IBOutlet weak var yearButton: UIButton!
    @IBOutlet weak var fiveYearsButton: UIButton!
    @IBOutlet weak var graphViewHeight: NSLayoutConstraint!
    
    @IBOutlet weak var tableSpinner: UIActivityIndicatorView!
    
    var transactions = [["amount":"3 700", "euros":"30", "day":"Apr 17", "gain":"0 %"],["amount":"3 900", "euros":"30", "day":"Apr 10", "gain":"7 %"],["amount":"3 950", "euros":"30", "day":"Apr 3", "gain":"8 %"],["amount":"4 100", "euros":"30", "day":"Mar 27", "gain":"13 %"],["amount":"4 100", "euros":"30", "day":"Mar 20", "gain":"13 %"],["amount":"4 200", "euros":"30", "day":"Mar 13", "gain":"17 %"]]
    var setTransactions = [Transaction]()
    var lastCachedTransactions = [Transaction]()
    var fetchedTransactions = [[String:String]]()
    var bittrTransactions = NSMutableDictionary()
    
    @IBOutlet weak var bittrProfitLabel: UILabel!
    @IBOutlet weak var bittrProfitSpinner: UIActivityIndicatorView!
    var calculatedProfit = 0
    var calculatedInvestments = 0
    var calculatedCurrentValue = 0
    
    var balanceText = "<center><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(201, 154, 0); line-height: 0.5\">0.00 000 00</span><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(0, 0, 0); line-height: 0.5\">0 sats</span></center>"
    
    let day:[CGFloat] = [25777, 26002, 25701, 25779, 25840, 25856, 25797, 25671, 25821, 25927, 25793]
    let week:[CGFloat] = [26563, 25596, 26018, 26234, 26180, 26339, 25791, 25793]
    let month:[CGFloat] = [25418, 27711, 27474, 26938, 25767, 25092, 25710, 26286, 26018, 26339, 25793]
    let year:[CGFloat] = [28468, 28321, 18054, 23712, 19738, 21336, 15726, 16239, 22776, 18960, 27503, 25793]
    let fiveYears:[CGFloat] = [6894, 5352, 3517, 9207, 8033, 8370, 15788, 50193, 29098, 56278, 35614, 20120, 25793]
    
    var client = Client()
    var articles:[String:Article]?
    var allImages:[String:UIImage]?
    
    var bdkBalance:CGFloat = 0.0
    var btcBalance:CGFloat = 0.0
    var btclnBalance:CGFloat = 0.0
    var totalBalanceSats:CGFloat = 0.0
    var balanceWasFetched = false
    var eurValue:CGFloat = 0.0
    var chfValue:CGFloat = 0.0
    
    var tappedTransaction = 0
    
    var lightningNodeService:LightningNodeService?
    
    var didStartReset = false
    
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        numberViewLeft.layer.cornerRadius = 13
        numberViewMiddle.layer.cornerRadius = 13
        numberViewSend.layer.cornerRadius = 13
        numberViewReceive.layer.cornerRadius = 13
        headerView.layer.cornerRadius = 13
        
        profitButton.setTitle("", for: .normal)
        goalButton.setTitle("", for: .normal)
        sendButton.setTitle("", for: .normal)
        receiveButton.setTitle("", for: .normal)
        
        optionDayView.layer.cornerRadius = 13
        optionWeekView.layer.cornerRadius = 13
        optionMonthView.layer.cornerRadius = 13
        optionYearView.layer.cornerRadius = 13
        optionFiveYearsView.layer.cornerRadius = 13
        
        dayButton.setTitle("", for: .normal)
        weekButton.setTitle("", for: .normal)
        monthButton.setTitle("", for: .normal)
        yearButton.setTitle("", for: .normal)
        fiveYearsButton.setTitle("", for: .normal)
        
        homeTableView.delegate = self
        homeTableView.dataSource = self
        
        //NotificationCenter.default.addObserver(self, selector: #selector(fixGraphViewHeight), name: NSNotification.Name(rawValue: "fixgraph"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setClient), name: NSNotification.Name(rawValue: "restorewallet"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setClient), name: NSNotification.Name(rawValue: "setclient"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAllImages), name: NSNotification.Name(rawValue: "updateallimages"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(loadWalletData), name: NSNotification.Name(rawValue: "getwalletdata"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setTotalSats), name: NSNotification.Name(rawValue: "settotalsats"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeCurrency), name: NSNotification.Name(rawValue: "changecurrency"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetWallet), name: NSNotification.Name(rawValue: "resetwallet"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(moveButtonTapped), name: NSNotification.Name(rawValue: "openmovevc"), object: nil)
        
        showCachedData()
    }
    
    
    @objc func changeCurrency(notification:NSNotification) {
        
        self.conversionLabel.alpha = 0
        self.balanceSpinner.startAnimating()
        
        self.setConversion(btcValue: self.btcBalance/100000000)
    }
    
    
    @objc func updateAllImages(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualImages = userInfo["images"] as? [String:UIImage] {
                self.allImages = actualImages
            }
        }
    }
    
    @objc func setClient() {
        
        let deviceDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
        if let actualDeviceDict = deviceDict {
            // Client exists in cache.
            let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
            
            self.client = clients[0]
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
        headerViewTop.constant = headerViewTopConstant
        
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
    
    @IBAction func goalButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "HomeToGoal", sender: self)
    }
    
    @objc func moveButtonTapped() {
        
        //self.resetWallet()
        
        if self.balanceWasFetched == true {
            performSegue(withIdentifier: "HomeToMove", sender: self)
        }
    }
    
    @IBAction func sendButtonTapped(_ sender: UIButton) {
        if self.balanceWasFetched == true {
            performSegue(withIdentifier: "HomeToSend", sender: self)
        }
    }
    
    @IBAction func receiveButtonTapped(_ sender: UIButton) {
        if self.balanceWasFetched == true {
            performSegue(withIdentifier: "HomeToReceive", sender: self)
        }
    }
    
    @IBAction func transactionButtonTapped(_ sender: UIButton) {
        
        self.tappedTransaction = sender.tag
        
        performSegue(withIdentifier: "HomeToTransaction", sender: self)
    }
    
    @objc func fixGraphViewHeight() {}
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "HomeToGoal" {
            let goalVC = segue.destination as? GoalViewController
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
                
                if let actualLightningNodeService = self.lightningNodeService {
                    actualMoveVC.lightningNodeService = actualLightningNodeService
                }
            }
        } else if segue.identifier == "HomeToSend" {
            let sendVC = segue.destination as? SendViewController
            if let actualSendVC = sendVC {
                
                actualSendVC.btcAmount = self.btcBalance.rounded() * 0.00000001
                actualSendVC.btclnAmount = self.btclnBalance.rounded() * 0.00000001
                if let actualLightningNodeService = self.lightningNodeService {
                    actualSendVC.lightningNodeService = actualLightningNodeService
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
    
    @IBAction func graphButtonTapped(_ sender: UIButton) {
        
        switch sender.accessibilityIdentifier {
        case "d":
            self.graphView.data = self.day;
            self.optionDayView.backgroundColor = .white;
            self.optionWeekView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionMonthView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionYearView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionFiveYearsView.backgroundColor = UIColor(white: 1, alpha: 0.7)
        case "w":
            self.graphView.data = self.week;
            self.optionDayView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionWeekView.backgroundColor = .white;
            self.optionMonthView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionYearView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionFiveYearsView.backgroundColor = UIColor(white: 1, alpha: 0.7)
        case "m":
            self.graphView.data = self.month;
            self.optionDayView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionWeekView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionMonthView.backgroundColor = .white;
            self.optionYearView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionFiveYearsView.backgroundColor = UIColor(white: 1, alpha: 0.7)
        case "y":
            self.graphView.data = self.year;
            self.optionDayView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionWeekView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionMonthView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionYearView.backgroundColor = .white;
            self.optionFiveYearsView.backgroundColor = UIColor(white: 1, alpha: 0.7)
        case "5y":
            self.graphView.data = self.fiveYears;
            self.optionDayView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionWeekView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionMonthView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionYearView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionFiveYearsView.backgroundColor = .white
        default:
            self.graphView.data = self.month;
            self.optionDayView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionWeekView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionMonthView.backgroundColor = .white;
            self.optionYearView.backgroundColor = UIColor(white: 1, alpha: 0.7);
            self.optionFiveYearsView.backgroundColor = UIColor(white: 1, alpha: 0.7)
        }
        
    }
    
    
    @objc func resetWallet() {
        
        print("Reset wallet.")
        
        self.setTransactions.removeAll()
        self.calculatedProfit = 0
        self.calculatedInvestments = 0
        self.calculatedCurrentValue = 0
        self.btcBalance = 0.0
        self.btclnBalance = 0.0
        self.totalBalanceSats = 0.0
        
        self.bittrProfitLabel.alpha = 0
        self.bittrProfitSpinner.startAnimating()
        self.balanceLabel.alpha = 0
        self.conversionLabel.alpha = 0
        self.balanceSpinner.startAnimating()
        self.homeTableView.reloadData()
        self.tableSpinner.startAnimating()
        
        LightningNodeService.shared.walletReset()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        
        if scrollView.contentOffset.y < -200, self.didStartReset == false {
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
