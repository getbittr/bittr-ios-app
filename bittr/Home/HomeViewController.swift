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
    @IBOutlet weak var numberViewRight: UIView!
    
    @IBOutlet weak var homeTableView: UITableView!
    @IBOutlet weak var balanceView: UIView!
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var balanceSpinner: UIActivityIndicatorView!
    @IBOutlet weak var conversionLabel: UILabel!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerViewTop: NSLayoutConstraint!
    
    @IBOutlet weak var profitButton: UIButton!
    @IBOutlet weak var goalButton: UIButton!
    @IBOutlet weak var moveButton: UIButton!
    
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
    
    var btcBalance:CGFloat = 0.0
    var btclnBalance:CGFloat = 0.0
    var totalBalanceSats:CGFloat = 0.0
    var balanceWasFetched = false
    var eurValue:CGFloat = 0.0
    var chfValue:CGFloat = 0.0
    
    var tappedTransaction = 0
    
    var lightningNodeService:LightningNodeService?
    
    var didStartReset = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        numberViewLeft.layer.cornerRadius = 13
        numberViewMiddle.layer.cornerRadius = 13
        numberViewRight.layer.cornerRadius = 13
        headerView.layer.cornerRadius = 13
        
        profitButton.setTitle("", for: .normal)
        goalButton.setTitle("", for: .normal)
        moveButton.setTitle("", for: .normal)
        
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(fixGraphViewHeight), name: NSNotification.Name(rawValue: "fixgraph"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setClient), name: NSNotification.Name(rawValue: "restorewallet"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setClient), name: NSNotification.Name(rawValue: "setclient"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAllImages), name: NSNotification.Name(rawValue: "updateallimages"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(loadWalletData), name: NSNotification.Name(rawValue: "getwalletdata"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setTotalSats), name: NSNotification.Name(rawValue: "settotalsats"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeCurrency), name: NSNotification.Name(rawValue: "changecurrency"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetWallet), name: NSNotification.Name(rawValue: "resetwallet"), object: nil)
        
        // TODO: Hide after testing.
        //CacheManager.deleteCache()
        showCachedData()
    }
    
    
    func showCachedData() {
        
        // Set cached balance.
        if let cachedBalance = CacheManager.getCachedData(key: "balance") as? String {
            if cachedBalance != "empty" {
                
                if let htmlData = cachedBalance.data(using: .unicode) {
                    do {
                        let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                        balanceLabel.attributedText = attributedText
                        balanceLabel.alpha = 1
                    } catch let e as NSError {
                        print("Couldn't fetch text: \(e.localizedDescription)")
                    }
                }
            }
        }
        
        // Set cached conversion.
        /*if let cachedConversion = CacheManager.getCachedData(key: "conversion") as? String {
            if cachedConversion != "empty" {
                
                self.conversionLabel.text = cachedConversion
                self.balanceSpinner.stopAnimating()
                self.conversionLabel.alpha = 1
            }
        }*/
        
        // Set cached Eur Value.
        if let cachedEurValue = CacheManager.getCachedData(key: "eurvalue") as? CGFloat {
            self.eurValue = cachedEurValue
        }
        
        // Set cached Chf Value.
        if let cachedChfValue = CacheManager.getCachedData(key: "chfvalue") as? CGFloat {
            self.chfValue = cachedChfValue
        }
        
        // Set cached transactions.
        if let cachedTransactions = CacheManager.getCachedData(key: "transactions") as? [Transaction] {
            
            self.setTransactions = cachedTransactions
            
            self.homeTableView.reloadData()
            self.tableSpinner.stopAnimating()
            self.homeTableView.alpha = 1
            self.homeTableView.isUserInteractionEnabled = false
        }
    }
    
    
    @objc func loadWalletData(notification:NSNotification) {
        
        // Step 10.
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let receivedTransactions = userInfo["transactions"] as? [TransactionDetails] {
                print("Received: \(receivedTransactions)")
                
                self.setTransactions.removeAll()
                
                var txIds = [String]()
                for eachTransaction in receivedTransactions {
                    txIds += [eachTransaction.txid]
                }
                if let receivedPayments = userInfo["payments"] as? [PaymentDetails] {
                    for eachPayment in receivedPayments {
                        if eachPayment.preimage != nil {
                            txIds += [eachPayment.preimage ?? "Lightning transaction"]
                        }
                    }
                }
                
                Task {
                    await fetchTransactionData(txIds:txIds)
                    
                    DispatchQueue.main.async {
                        for eachTransaction in receivedTransactions {
                            
                            let thisTransaction = Transaction()
                            thisTransaction.id = eachTransaction.txid
                            thisTransaction.fee = Int(eachTransaction.fee!)
                            thisTransaction.received = Int(eachTransaction.received)
                            thisTransaction.sent = Int(eachTransaction.sent)
                            thisTransaction.isLightning = false
                            if let confirmationTime = eachTransaction.confirmationTime {
                                thisTransaction.height = Int(confirmationTime.height)
                                thisTransaction.timestamp = Int(confirmationTime.timestamp)
                            } else {
                                // Handle the case where confirmationTime is nil.
                                // For example, set a default value or leave it unassigned.
                                let defaultValue = 0
                                thisTransaction.height = defaultValue // Replace defaultValue with an appropriate value
                                let currentTimestamp = Int(Date().timeIntervalSince1970)
                                thisTransaction.timestamp = currentTimestamp // Replace defaultValue with an appropriate value
                            }
                            if (self.bittrTransactions.allKeys as! [String]).contains(thisTransaction.id) {
                                thisTransaction.isBittr = true
                                thisTransaction.purchaseAmount = Int(CGFloat(truncating: NumberFormatter().number(from: ((self.bittrTransactions[thisTransaction.id] as! [String:Any])["amount"] as! String).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!))
                                thisTransaction.currency = (self.bittrTransactions[thisTransaction.id] as! [String:Any])["currency"] as! String
                                
                                print(thisTransaction.purchaseAmount)
                            }
                            
                            /*Task {
                                if await fetchTransactionData(txIds: [eachTransaction.txid]) == true {
                                    // This is a Bittr transaction.
                                    
                                    thisTransaction.isBittr = true
                                    thisTransaction.purchaseAmount = Int(CGFloat(truncating: NumberFormatter().number(from: ((self.bittrTransactions[thisTransaction.id] as! [String:Any])["amount"] as! String).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!))
                                    thisTransaction.currency = (self.bittrTransactions[thisTransaction.id] as! [String:Any])["currency"] as! String
                                    
                                    print(thisTransaction.purchaseAmount)
                                }
                            }*/
                            
                            self.setTransactions += [thisTransaction]
                        }
                        
                        if let receivedPayments = userInfo["payments"] as? [PaymentDetails] {
                            
                            for eachPayment in receivedPayments {
                                let thisTransaction = Transaction()
                                if eachPayment.direction == .inbound {
                                    thisTransaction.received = Int(eachPayment.amountMsat ?? 0)/1000
                                } else {
                                    thisTransaction.sent = Int(eachPayment.amountMsat ?? 0)/1000
                                }
                                thisTransaction.isLightning = true
                                thisTransaction.timestamp = Int(Date().timeIntervalSince1970)
                                thisTransaction.id = eachPayment.preimage ?? "Lightning transaction"
                                
                                if (self.bittrTransactions.allKeys as! [String]).contains(thisTransaction.id) {
                                    thisTransaction.isBittr = true
                                    thisTransaction.purchaseAmount = Int(CGFloat(truncating: NumberFormatter().number(from: ((self.bittrTransactions[thisTransaction.id] as! [String:Any])["amount"] as! String).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!))
                                    thisTransaction.currency = (self.bittrTransactions[thisTransaction.id] as! [String:Any])["currency"] as! String
                                    
                                    print(thisTransaction.purchaseAmount)
                                }
                                
                                if eachPayment.status == .succeeded {
                                    self.setTransactions += [thisTransaction]
                                }
                            }
                        }
                        
                        self.setTransactions.sort { transaction1, transaction2 in
                            transaction1.timestamp > transaction2.timestamp
                        }
                        
                        CacheManager.updateCachedData(data: self.setTransactions, key: "transactions")
                    }
                }
            }
            
            if let actualLightningNodeService = userInfo["lightningnodeservice"] as? LightningNodeService {
                
                self.lightningNodeService = actualLightningNodeService
            }
            
            if let actualLightningChannels = userInfo["channels"] as? [ChannelDetails] {
                for eachChannel in actualLightningChannels {
                    self.btclnBalance += CGFloat(eachChannel.outboundCapacityMsat / 1000)
                }
            }
        }
        
        // Step 11.
        let bitcoinViewModel = BitcoinViewModel()
        Task {
            await bitcoinViewModel.getTotalOnchainBalanceSats()
        }
    }
    
    
    func calculateProfit() {
        
        self.didStartReset = false
        
        // Step 17.
        
        self.bittrProfitLabel.alpha = 0
        self.bittrProfitSpinner.startAnimating()
        
        let bittrTransactionsCount = self.bittrTransactions.count
        var handledTransactions = 0
        var accumulatedProfit = 0
        var accumulatedInvestments = 0
        var accumulatedCurrentValue = 0
        
        var correctValue:CGFloat = self.eurValue
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.chfValue
            currencySymbol = "CHF"
        }
        
        if self.setTransactions.count == 0 {
            // There are no transactions.
            self.bittrProfitLabel.text = "🌱  \(currencySymbol) \(accumulatedProfit)"
            self.bittrProfitLabel.alpha = 1
            self.bittrProfitSpinner.stopAnimating()
            
            self.calculatedProfit = accumulatedProfit
            self.calculatedInvestments = accumulatedInvestments
            self.calculatedCurrentValue = accumulatedCurrentValue
        } else {
            for eachTransaction in self.setTransactions {
                
                if eachTransaction.isBittr == true {
                    
                    handledTransactions += 1
                    let transactionValue = CGFloat(eachTransaction.received)/100000000
                    let transactionProfit = Int((transactionValue*correctValue).rounded())-eachTransaction.purchaseAmount
                    
                    accumulatedProfit += transactionProfit
                    accumulatedInvestments += eachTransaction.purchaseAmount
                    accumulatedCurrentValue += Int((transactionValue*correctValue).rounded())
                    
                    if bittrTransactionsCount == handledTransactions {
                        // We're done counting.
                        
                        self.bittrProfitLabel.text = "🌱  \(currencySymbol) \(accumulatedProfit)"
                        self.bittrProfitLabel.alpha = 1
                        self.bittrProfitSpinner.stopAnimating()
                        
                        self.calculatedProfit = accumulatedProfit
                        self.calculatedInvestments = accumulatedInvestments
                        self.calculatedCurrentValue = accumulatedCurrentValue
                    }
                } else {
                    
                    if bittrTransactionsCount == handledTransactions {
                        
                        self.bittrProfitLabel.text = "🌱  \(currencySymbol) \(accumulatedProfit)"
                        self.bittrProfitLabel.alpha = 1
                        self.bittrProfitSpinner.stopAnimating()
                        
                        self.calculatedProfit = accumulatedProfit
                        self.calculatedInvestments = accumulatedInvestments
                        self.calculatedCurrentValue = accumulatedCurrentValue
                    }
                }
            }
        }
        
        //self.askForPushNotifications()
    }
    
    
    func fetchTransactionData(txIds:[String]) async -> Bool {
        
        do {
            let bittrApiTransactions = try await BittrService.shared.fetchBittrTransactions(txIds: txIds, depositCodes: ["5GCPDLWU5FVQ"])
            print("Transactions: \(bittrApiTransactions)")
            
            if bittrApiTransactions.count == 0 {
                // This is not a Bittr transaction.
                return false
            } else {
                // There are Bittr transactions.
                for eachTransaction in bittrApiTransactions {
                    self.bittrTransactions.setValue(["amount":eachTransaction.purchaseAmount, "currency":eachTransaction.currency], forKey: eachTransaction.txId)
                }
                return true
            }
        } catch {
            print("Bittr error: \(error.localizedDescription)")
            return false
        }
    }
    
    
    func fetchAndPrintChannels() {
        
        Task {
            do {
                let channels = try await LightningNodeService.shared.listChannels()
                print("Channels: \(channels)")
            } catch {
                print("Error listing channels: \(error.localizedDescription)")
            }
        }
    }
    
    
    func fetchAndPrintPeers() {
        
        Task {
            do {
                let peers = try await LightningNodeService.shared.listPeers()
                print("Peers: \(peers)")
            } catch {
                print("Error listing peers: \(error.localizedDescription)")
            }
        }
    }
    
    
    func fetchAndPrintPayments() {
        
        Task {
            do {
                let payments = try await LightningNodeService.shared.listPayments()
                print("Payments: \(payments)")
            } catch {
                print("Error listing peers: \(error.localizedDescription)")
            }
        }
    }
    
    
    func connectToPeer() {
        let nodeId = "026d74bf2a035b8a14ea7c59f6a0698d019720e812421ec02762fdbf064c3bc326" // Extract this from your peer string
        let address = "109.205.181.232:9735" // Extract this from your peer string
        
        Task {
            do {
                try await LightningNodeService.shared.connect(
                    nodeId: nodeId,
                    address: address,
                    persist: true
                )
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                }
            } catch {
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                }
            }
        }
    }
    
    
    @objc func setTotalSats(notification:NSNotification) {
        
        // Step 13.
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let satsBalance = userInfo["balance"] as? String {
                
                print("Sats " + satsBalance)
                
                var zeros = "0.00 000 00"
                var numbers = satsBalance + " sats"
                
                //satsBalance = "12345"
                
                self.btcBalance = CGFloat(truncating: NumberFormatter().number(from: satsBalance)!)
                self.balanceWasFetched = true
                
                self.totalBalanceSats = self.btcBalance + self.btclnBalance
                let totalBalanceSatsString = "\(Int(self.totalBalanceSats))"
                
                switch totalBalanceSatsString.count {
                case 1:
                    zeros = "0.00 000 00"
                    numbers = totalBalanceSatsString + " sats"
                case 2:
                    zeros = "0.00 000 0"
                    numbers = totalBalanceSatsString + " sats"
                case 3:
                    zeros = "0.00 000 "
                    numbers = totalBalanceSatsString + " sats"
                case 4:
                    zeros = "0.00 00"
                    numbers = totalBalanceSatsString[0] + " " + totalBalanceSatsString[1..<4] + " sats"
                case 5:
                    zeros = "0.00 0"
                    numbers = totalBalanceSatsString[0..<2] + " " + totalBalanceSatsString[2..<5] + " sats"
                case 6:
                    zeros = "0.00 "
                    numbers = totalBalanceSatsString[0..<3] + " " + totalBalanceSatsString[3..<6] + " sats"
                case 7:
                    zeros = "0.0"
                    numbers = totalBalanceSatsString[0] + " " + totalBalanceSatsString[1..<4] + " " + totalBalanceSatsString[4..<7] + " sats"
                case 8:
                    zeros = "0."
                    numbers = totalBalanceSatsString[0..<2] + " " + totalBalanceSatsString[2..<5] + " " + totalBalanceSatsString[5..<8] + " sats"
                default:
                    zeros = ""
                    numbers = "btc \(totalBalanceSats/100000000)"
                }
                
                balanceText = "<center><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(201, 154, 0); line-height: 0.5\">\(zeros)</span><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(0, 0, 0); line-height: 0.5\">\(numbers)</span></center>"
                
                CacheManager.updateCachedData(data: balanceText, key: "balance")
                
                if let htmlData = balanceText.data(using: .unicode) {
                    do {
                        let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                        balanceLabel.attributedText = attributedText
                        balanceLabel.alpha = 1
                        
                        // Step 14.
                        self.setConversion(btcValue: CGFloat(truncating: NumberFormatter().number(from: totalBalanceSatsString)!)/100000000)
                        
                    } catch let e as NSError {
                        print("Couldn't fetch text: \(e.localizedDescription)")
                    }
                }
            }
        }
    }
    
    
    func setConversion(btcValue:CGFloat) {
        
        // Step 15.
        var request = URLRequest(url: URL(string: "https://staging.getbittr.com/api/price/btc")!,timeoutInterval: Double.infinity)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                print(String(describing: error))
                return
            }
            
            //print(String(data: data, encoding: .utf8)!)
            
            var dataDictionary:NSDictionary?
            if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                do {
                    dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                    if let actualDataDict = dataDictionary {
                        if var actualEurValue = actualDataDict["btc_eur"] as? String, var actualChfValue = actualDataDict["btc_chf"] as? String {
                            
                            if actualEurValue.contains("."), Locale.current.decimalSeparator == "," {
                                actualEurValue = actualEurValue.replacingOccurrences(of: ".", with: ",")
                                actualChfValue = actualChfValue.replacingOccurrences(of: ".", with: ",")
                            } else if actualEurValue.contains(","), Locale.current.decimalSeparator == "." {
                                actualEurValue = actualEurValue.replacingOccurrences(of: ",", with: ".")
                                actualChfValue = actualChfValue.replacingOccurrences(of: ",", with: ".")
                            }
                            
                            self.eurValue = CGFloat(truncating: NumberFormatter().number(from: actualEurValue)!)
                            self.chfValue = CGFloat(truncating: NumberFormatter().number(from: actualChfValue)!)
                            
                            CacheManager.updateCachedData(data: self.eurValue, key: "eurvalue")
                            CacheManager.updateCachedData(data: self.chfValue, key: "chfvalue")
                            
                            var correctValue:CGFloat = self.eurValue
                            var currencySymbol = "€"
                            if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                                correctValue = self.chfValue
                                currencySymbol = "CHF"
                            }
                            
                            var balanceValue = String(Int((btcValue*correctValue).rounded()))
                            
                            switch balanceValue.count {
                            case 0..<4:
                                balanceValue = balanceValue
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
                                balanceValue = balanceValue
                            }
                            
                            DispatchQueue.main.async {
                                self.conversionLabel.text = currencySymbol + " " + balanceValue
                                CacheManager.updateCachedData(data: currencySymbol + " " + balanceValue, key: "conversion")
                                self.balanceSpinner.stopAnimating()
                                self.conversionLabel.alpha = 1
                                print(currencySymbol + " " + balanceValue)
                                
                                self.homeTableView.reloadData()
                                self.homeTableView.isUserInteractionEnabled = true
                                self.tableSpinner.stopAnimating()
                                self.homeTableView.alpha = 1
                                
                                // Step 16.
                                self.calculateProfit()
                            }
                        }
                    }
                } catch let error as NSError {
                    print(error)
                }
            }
        }
        task.resume()
    }
    
    
    /*func getTransactions() {
        
        let paymentDetails = LightningNodeService.shared.listPayments()
        
        //BitcoinDevKit.Wallet.listTransactions(Wallet)
        
        /*let db = DatabaseConfig.memory
        do {
            
            
            let descriptorSecretKey = BitcoinDevKit.DescriptorSecretKey(network: .testnet, mnemonic: try! BitcoinDevKit.Mnemonic.fromString(mnemonic: "worry nation success gaze bird shine turtle fiscal shrug echo claw two"), password: nil)
            
            //try Descriptor.init(descriptor: T##String, network: T##Network)
            
        } catch let error {
            print(error.localizedDescription)
        }*/
    }*/
    
    
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
    
    
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath) as? HistoryTableViewCell
        
        if let actualCell = cell {
            
            let thisTransaction = self.setTransactions[indexPath.row]
            
            // Set date.
            let transactionDate = Date(timeIntervalSince1970: Double(thisTransaction.timestamp))
            let dateFormatter = DateFormatter()
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.dateFormat = "MMM dd"
            let transactionDateString = dateFormatter.string(from: transactionDate)
            
            actualCell.dayLabel.text = transactionDateString
            
            // Set sats.
            var plusSymbol = "+"
            if thisTransaction.received - thisTransaction.sent < 0 {
                plusSymbol = "-"
            }
            actualCell.satsLabel.text = "\(plusSymbol) \(addSpacesToString(balanceValue: String(thisTransaction.received - thisTransaction.sent)).replacingOccurrences(of: "-", with: "")) sats"
            /*if thisTransaction.received != 0 {
                actualCell.satsLabel.text = "+ \(addSpacesToString(balanceValue: String(thisTransaction.received))) sats"
            } else {
                actualCell.satsLabel.text = "- \(addSpacesToString(balanceValue: String(thisTransaction.sent))) sats"
            }*/
            
            // Set conversion
            var correctValue:CGFloat = self.eurValue
            var currencySymbol = "€"
            if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                correctValue = self.chfValue
                currencySymbol = "CHF"
            }
            
            var transactionValue = CGFloat(thisTransaction.received - thisTransaction.sent)/100000000
            /*if transactionValue < 0 {
                //transactionValue = CGFloat(thisTransaction.sent)/100000000
                plusSymbol = "-"
            }*/
            
            var balanceValue = String(Int((transactionValue*correctValue).rounded()))
            balanceValue = addSpacesToString(balanceValue: balanceValue).replacingOccurrences(of: "-", with: "")
            
            actualCell.eurosLabel.text = plusSymbol + " " + balanceValue + " " + currencySymbol
            
            // Set gain label
            if thisTransaction.isBittr == true {
                actualCell.gainView.alpha = 1
                let relativeGain:Int = Int((CGFloat(Int((transactionValue*correctValue).rounded()) - thisTransaction.purchaseAmount) / CGFloat(thisTransaction.purchaseAmount)) * 100)
                actualCell.gainLabel.text = "\(relativeGain) %"
            } else {
                actualCell.gainView.alpha = 0
                actualCell.gainLabel.text = ""
            }
            
            // Set button
            actualCell.transactionButton.tag = indexPath.row
            
            actualCell.layer.zPosition = CGFloat(indexPath.row)
            
            return actualCell
        }
        
        return UITableViewCell()
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
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.setTransactions.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        return 75
    }
    
    @IBAction func profitButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "HomeToProfit", sender: self)
    }
    
    @IBAction func goalButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "HomeToGoal", sender: self)
    }
    
    @IBAction func moveButtonTapped(_ sender: UIButton) {
        
        //self.resetWallet()
        
        if self.balanceWasFetched == true {
            performSegue(withIdentifier: "HomeToMove", sender: self)
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
