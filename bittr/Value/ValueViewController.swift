//
//  ValueViewController.swift
//  bittr
//
//  Created by Tom Melters on 04/01/2025.
//

import UIKit

class ValueViewController: UIViewController {

    // General
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var centerCard: UIView!
    @IBOutlet weak var iconExchange: UIImageView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var currentValueLabel: UILabel!
    @IBOutlet weak var valueSpinner: UIActivityIndicatorView!
    @IBOutlet weak var changeDateView: UIView!
    @IBOutlet weak var datesLabel: UILabel!
    @IBOutlet weak var datesButton: UIButton!
    
    // Graph view and sample data
    @IBOutlet weak var graphView: GraphView!
    var week:[CGFloat] = []
    var month:[CGFloat] = []
    var year:[CGFloat] = []
    var fiveYears:[CGFloat] = []
    var currentValue:CGFloat = 0
    var selectedSpan = "week"
    var isFetchingData = true

    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.datesButton.setTitle("", for: .normal)
        
        // Card styling
        self.centerCard.layer.cornerRadius = 13
        self.centerCard.layer.shadowColor = UIColor.black.cgColor
        self.centerCard.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.centerCard.layer.shadowRadius = 10.0
        self.centerCard.layer.shadowOpacity = 0.1
        self.graphView.layer.zPosition = 10
        
        // Dates styling
        self.changeDateView.layer.cornerRadius = 8
        self.changeDateView.layer.shadowColor = UIColor.black.cgColor
        self.changeDateView.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.changeDateView.layer.shadowRadius = 10.0
        self.changeDateView.layer.shadowOpacity = 0.1
        
        // Colors
        self.changeColors()
        
        self.getCurrentValue()
    }
    
    func getCurrentValue() {
        
        self.valueSpinner.startAnimating()
        
        // Get latest value
        Task {
            do {
                var eurUrl = URL(string: "https://getbittr.com/api/price/btc/historical/eur")!
                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                    eurUrl = URL(string: "https://getbittr.com/api/price/btc/historical/chf")!
                }
                let (eurData, _) = try await URLSession.shared.data(from: eurUrl)
                
                print("Data: \(eurData)")
                if let json = try JSONSerialization.jsonObject(with: eurData) as? [NSDictionary], let weekData = json[2]["data"] as? [NSDictionary], let monthData = json[3]["data"] as? [NSDictionary], let yearData = json[6]["data"] as? [NSDictionary], let fiveYearData = json[7]["data"] as? [NSDictionary] {
                    
                    // Data consists of dictionaries:
                    // - [0] Minute intervals
                    // - [1] Hourly intervals
                    // - [2] Daily intervals
                    // - [3] Monthly intervals
                    // - [4] Semi-annually intervals
                    // - [5] YTD
                    // - [6] 1 year
                    // - [7] 5 years
                    // - [8] Max
                    // Each dictionary consists of 5 key-value pairs
                    // - [0] time_retrieved_unix_iso8601 (2025-01-13T05:55:58Z)
                    // - [1] interval (daily)
                    // - [2] time_retrieved_unix (1736747758)
                    // - [3] data (12 dictionaries)
                    // - [4] pair (eur)
                    // The 12 data dictionaries consist of 3 key-value pairs.
                    // - [0] time_iso8601
                    // - [1] price (92189.2)
                    // - [2] time_unix
                    
                    var last7Days = [CGFloat]()
                    for eachDataPoint in weekData {
                        if Calendar.current.date(byAdding: .day, value: -7, to: Date())! < ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))! {
                            last7Days += [self.stringToNumber((eachDataPoint["price"] as! String))]
                        }
                    }
                    print("Week: \(last7Days)")
                    
                    var lastMonth = [CGFloat]()
                    for eachDataPoint in monthData {
                        if Calendar.current.date(byAdding: .month, value: -1, to: Date())! < ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))! {
                            lastMonth += [self.stringToNumber((eachDataPoint["price"] as! String))]
                        }
                    }
                    print("Month: \(lastMonth)")
                    
                    var lastYear = [CGFloat]()
                    for eachDataPoint in yearData {
                        if Calendar.current.date(byAdding: .year, value: -1, to: Date())! < ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))! {
                            lastYear += [self.stringToNumber((eachDataPoint["price"] as! String))]
                        }
                    }
                    print("Year: \(lastYear)")
                    
                    var lastFiveYears = [CGFloat]()
                    for eachDataPoint in fiveYearData {
                        if Calendar.current.date(byAdding: .year, value: -5, to: Date())! < ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))! {
                            lastFiveYears += [self.stringToNumber((eachDataPoint["price"] as! String))]
                        }
                    }
                    print("5 Year: \(lastFiveYears)")
                    
                    let envUrl = URL(string: "https://getbittr.com/api/price/btc")!
                    let (data, _) = try await URLSession.shared.data(from: envUrl)
                    
                    if let currentJson = try JSONSerialization.jsonObject(with: data) as? [String: Any], let actualEurValue = currentJson["btc_eur"] as? String, let actualChfValue = currentJson["btc_chf"] as? String {
                        // Create an entry with the fetched data
                        
                        DispatchQueue.main.async {
                            let formattedEurValue = self.formatEuroValue(actualEurValue)
                            let formattedChfValue = self.formatEuroValue(actualChfValue)
                            
                            self.currentValue = self.stringToNumber(actualEurValue)
                            var preferredCurrency = "€"
                            var valueToDisplay = formattedEurValue
                            if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                                preferredCurrency = "CHF"
                                valueToDisplay = formattedChfValue
                                self.currentValue = self.stringToNumber(actualChfValue)
                            }
                            
                            print("EUR value: \(formattedEurValue), CHF value: \(formattedChfValue), currency: \(preferredCurrency)")
                            
                            // Data arrays
                            self.week = last7Days + [self.currentValue]
                            self.month = lastMonth + [self.currentValue]
                            self.year = lastYear + [self.currentValue]
                            self.fiveYears = lastFiveYears + [self.currentValue]
                            
                            self.currentValueLabel.text = "\(preferredCurrency) \(valueToDisplay)"
                            
                            self.valueSpinner.stopAnimating()
                            self.drawGraph()
                            self.isFetchingData = false
                        }
                    }
                }
            } catch {
                print("Error fetching data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.valueSpinner.stopAnimating()
                    self.isFetchingData = false
                }
            }
        }
    }
    
    func formatEuroValue(_ actualEurValue: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal // Automatically adds separators
        formatter.maximumFractionDigits = 0 // Round to whole numbers
        formatter.locale = Locale.current // Use current locale for separators
        
        // Convert string to number and format it
        if let number = Double(actualEurValue) {
            return formatter.string(from: NSNumber(value: round(number))) ?? "0"
        } else {
            return "0" // Fallback in case of invalid input
        }
    }
    
    @IBAction func changeSpan(_ sender: UIButton) {
        
        if self.isFetchingData { return }
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let weekOption = UIAlertAction(title: "1 week", style: .default) { (action) in
            self.selectedSpan = "week"
            self.datesLabel.text = "1 week"
            self.drawGraph()
        }
        let monthOption = UIAlertAction(title: "1 month", style: .default) { (action) in
            self.selectedSpan = "month"
            self.datesLabel.text = "1 month"
            self.drawGraph()
        }
        let yearOption = UIAlertAction(title: "1 year", style: .default) { (action) in
            self.selectedSpan = "year"
            self.datesLabel.text = "1 year"
            self.drawGraph()
        }
        let fiveYearsOption = UIAlertAction(title: "5 years", style: .default) { (action) in
            self.selectedSpan = "5years"
            self.datesLabel.text = "5 years"
            self.drawGraph()
        }

        let cancelAction = UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil)
        actionSheet.addAction(weekOption)
        actionSheet.addAction(monthOption)
        actionSheet.addAction(yearOption)
        actionSheet.addAction(fiveYearsOption)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true, completion: nil)
    }
    
    func drawGraph() {
        
        // Remove existing lines and labels.
        for eachSubview in self.centerCard.subviews {
            if eachSubview != self.graphView, eachSubview != self.headerLabel, eachSubview != self.iconExchange, eachSubview != self.currentValueLabel, eachSubview != self.changeDateView, eachSubview != self.datesButton {
                eachSubview.removeFromSuperview()
            }
        }
        
        var currentArray = self.month
        if self.selectedSpan == "week" {
            currentArray = self.week
        } else if self.selectedSpan == "year" {
            currentArray = self.year
        } else if self.selectedSpan == "5years" {
            currentArray = self.fiveYears
        }
        if currentArray.count == 0 {
            self.graphView.alpha = 0
            return
        } else {
            self.graphView.alpha = 1
        }
        self.graphView.data = currentArray
        
        if let lowestNumber = currentArray.min(), let highestNumber = currentArray.max() {
            
            let totalSpan = highestNumber - lowestNumber
            
            var differential:CGFloat = 2500
            if totalSpan > 60000 {
                differential = 20000
            } else if totalSpan > 30000 {
                differential = 10000
            } else if totalSpan > 10000 {
                differential = 5000
            }
            
            // Round up the lowest number to the nearest 5000
            var roundedUp = ceil(lowestNumber / differential) * differential
            var allLines:[CGFloat] = [roundedUp]
            
            // Keep adding 5000 until we exceed the maxNumber
            while roundedUp <= highestNumber {
                roundedUp += differential
                if roundedUp < highestNumber {
                    allLines += [roundedUp]
                }
            }
            
            print(allLines)
            
            for eachLine in allLines {
                // Draw a line
                
                let thisLine = UIView()
                thisLine.translatesAutoresizingMaskIntoConstraints = false
                thisLine.backgroundColor = Colors.getColor("blackorwhite")
                thisLine.layer.zPosition = 0
                thisLine.alpha = 0.2
                self.centerCard.addSubview(thisLine)
                
                let thisLineHeight = NSLayoutConstraint(item: thisLine, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 1)
                let thisLineLeft = NSLayoutConstraint(item: thisLine, attribute: .leading, relatedBy: .equal, toItem: self.graphView, attribute: .leading, multiplier: 1, constant: 20)
                let thisLineRight = NSLayoutConstraint(item: thisLine, attribute: .trailing, relatedBy: .equal, toItem: self.graphView, attribute: .trailing, multiplier: 1, constant: -20)
                let thisLineTop = NSLayoutConstraint(item: thisLine, attribute: .top, relatedBy: .equal, toItem: self.graphView, attribute: .top, multiplier: 1, constant: ((highestNumber-eachLine)/totalSpan)*140)
                self.centerCard.addConstraints([thisLineLeft, thisLineRight, thisLineTop])
                thisLine.addConstraint(thisLineHeight)
                
                let thisLabel = UILabel()
                thisLabel.translatesAutoresizingMaskIntoConstraints = false
                thisLabel.font = UIFont(name: "Gilroy-Regular", size: 12)
                thisLabel.text = self.formatEuroValue("\(eachLine)")
                thisLabel.textColor = Colors.getColor("blackorwhite")
                thisLabel.layer.zPosition = 0
                thisLabel.alpha = 0.4
                self.centerCard.addSubview(thisLabel)
                
                let thisLabelHeight = NSLayoutConstraint(item: thisLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                let thisLabelWidth = NSLayoutConstraint(item: thisLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                let thisLabelRight = NSLayoutConstraint(item: thisLabel, attribute: .trailing, relatedBy: .equal, toItem: thisLine, attribute: .leading, multiplier: 1, constant: -10)
                let thisLabelCenter = NSLayoutConstraint(item: thisLabel, attribute: .centerY, relatedBy: .equal, toItem: thisLine, attribute: .centerY, multiplier: 1, constant: 0)
                self.centerCard.addConstraints([thisLabelRight, thisLabelCenter])
                thisLabel.addConstraints([thisLabelHeight, thisLabelWidth])
                
            }
        }
        
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.centerCard.backgroundColor = Colors.getColor("yelloworblue1")
        self.headerLabel.textColor = Colors.getColor("whiteoryellow")
        self.currentValueLabel.textColor = Colors.getColor("blackorwhite")
        self.valueSpinner.color = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.iconExchange.image = UIImage(named: "iconexchangeyellow")
        } else {
            self.iconExchange.image = UIImage(named: "iconexchange")
        }
    }
}
