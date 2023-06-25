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
    
    let balanceText = "<center><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(201, 154, 0); line-height: 0.5\">0.00 000 00</span><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(0, 0, 0); line-height: 0.5\">0 sats</span></center>"
    
    let day:[CGFloat] = [25777, 26002, 25701, 25779, 25840, 25856, 25797, 25671, 25821, 25927, 25793]
    let week:[CGFloat] = [26563, 25596, 26018, 26234, 26180, 26339, 25791, 25793]
    let month:[CGFloat] = [25418, 27711, 27474, 26938, 25767, 25092, 25710, 26286, 26018, 26339, 25793]
    let year:[CGFloat] = [28468, 28321, 18054, 23712, 19738, 21336, 15726, 16239, 22776, 18960, 27503, 25793]
    let fiveYears:[CGFloat] = [6894, 5352, 3517, 9207, 8033, 8370, 15788, 50193, 29098, 56278, 35614, 20120, 25793]
    
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
        
        if let htmlData = balanceText.data(using: .unicode) {
            do {
                let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                balanceLabel.attributedText = attributedText
            } catch let e as NSError {
                print("Couldn't fetch text: \(e.localizedDescription)")
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(fixGraphViewHeight), name: NSNotification.Name(rawValue: "fixgraph"), object: nil)
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
    
    @objc func fixGraphViewHeight() {
        
        
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
