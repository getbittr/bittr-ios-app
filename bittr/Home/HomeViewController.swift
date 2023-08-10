//
//  HomeViewController.swift
//  bittr
//
//  Created by Tom Melters on 12/04/2023.
//

import UIKit

class HomeViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

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
    
    var transactions = [["amount":"3 700", "euros":"30", "day":"Apr 17", "gain":"0 %"],["amount":"3 900", "euros":"30", "day":"Apr 10", "gain":"7 %"],["amount":"3 950", "euros":"30", "day":"Apr 3", "gain":"8 %"],["amount":"4 100", "euros":"30", "day":"Mar 27", "gain":"13 %"],["amount":"4 100", "euros":"30", "day":"Mar 20", "gain":"13 %"],["amount":"4 200", "euros":"30", "day":"Mar 13", "gain":"17 %"]]
    
    var balanceText = "<center><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(201, 154, 0); line-height: 0.5\">0.00 000 00</span><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(0, 0, 0); line-height: 0.5\">0 sats</span></center>"
    
    let day:[CGFloat] = [25777, 26002, 25701, 25779, 25840, 25856, 25797, 25671, 25821, 25927, 25793]
    let week:[CGFloat] = [26563, 25596, 26018, 26234, 26180, 26339, 25791, 25793]
    let month:[CGFloat] = [25418, 27711, 27474, 26938, 25767, 25092, 25710, 26286, 26018, 26339, 25793]
    let year:[CGFloat] = [28468, 28321, 18054, 23712, 19738, 21336, 15726, 16239, 22776, 18960, 27503, 25793]
    let fiveYears:[CGFloat] = [6894, 5352, 3517, 9207, 8033, 8370, 15788, 50193, 29098, 56278, 35614, 20120, 25793]
    
    var client = Client()
    var articles:[String:Article]?
    var allImages:[String:UIImage]?
    
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
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAllImages), name: NSNotification.Name(rawValue: "updateallimages"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(loadWalletData), name: NSNotification.Name(rawValue: "getwalletdata"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setTotalSats), name: NSNotification.Name(rawValue: "settotalsats"), object: nil)
    }
    
    @objc func loadWalletData() {
        let bitcoinViewModel = BitcoinViewModel()
        Task {
            await bitcoinViewModel.getTotalOnchainBalanceSats()
        }
    }
    
    @objc func setTotalSats(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let satsBalance = userInfo["balance"] as? String {
                
                print("Sats " + satsBalance)
                
                var zeros = "0.00 000 00"
                var numbers = satsBalance + " sats"
                
                //satsBalance = "12345"
                
                switch satsBalance.count {
                case 1:
                    zeros = "0.00 000 00"
                    numbers = satsBalance + " sats"
                case 2:
                    zeros = "0.00 000 0"
                    numbers = satsBalance + " sats"
                case 3:
                    zeros = "0.00 000 "
                    numbers = satsBalance + " sats"
                case 4:
                    zeros = "0.00 00"
                    numbers = satsBalance[0] + " " + satsBalance[1..<4] + " sats"
                case 5:
                    zeros = "0.00 0"
                    numbers = satsBalance[0..<2] + " " + satsBalance[2..<5] + " sats"
                case 6:
                    zeros = "0.00 "
                    numbers = satsBalance[0..<3] + " " + satsBalance[3..<6] + " sats"
                case 7:
                    zeros = "0.0"
                    numbers = satsBalance[0] + " " + satsBalance[1..<4] + " " + satsBalance[4..<7] + " sats"
                case 8:
                    zeros = "0."
                    numbers = satsBalance[0..<2] + " " + satsBalance[2..<5] + " " + satsBalance[5..<8] + " sats"
                default:
                    zeros = ""
                    numbers = "btc \(CGFloat(truncating: NumberFormatter().number(from: satsBalance)!)/100000000)"
                }
                
                balanceText = "<center><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(201, 154, 0); line-height: 0.5\">\(zeros)</span><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(0, 0, 0); line-height: 0.5\">\(numbers)</span></center>"
                
                if let htmlData = balanceText.data(using: .unicode) {
                    do {
                        let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                        balanceLabel.attributedText = attributedText
                        balanceSpinner.stopAnimating()
                        balanceLabel.alpha = 1
                        conversionLabel.alpha = 1
                        
                    } catch let e as NSError {
                        print("Couldn't fetch text: \(e.localizedDescription)")
                    }
                }
            }
        }
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
            
            actualCell.dayLabel.text = self.transactions[indexPath.row]["day"]
            actualCell.satsLabel.text = "+ \(self.transactions[indexPath.row]["amount"] ?? "?") sats"
            actualCell.eurosLabel.text = "+ \(self.transactions[indexPath.row]["euros"] ?? "?") €"
            actualCell.gainLabel.text = self.transactions[indexPath.row]["gain"]
            
            actualCell.layer.zPosition = CGFloat(indexPath.row)
            
            return actualCell
        }
        
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.transactions.count
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
        performSegue(withIdentifier: "HomeToMove", sender: self)
    }
    
    @IBAction func transactionButtonTapped(_ sender: UIButton) {
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
