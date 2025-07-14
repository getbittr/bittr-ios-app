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
    @IBOutlet weak var noDataLabel: UILabel!
    
    // Profit
    @IBOutlet weak var profitView: UIView!
    @IBOutlet weak var profitArrowImage: UIImageView!
    @IBOutlet weak var profitLabel: UILabel!
    
    // Dates
    @IBOutlet weak var buttonsView: UIView!
    @IBOutlet weak var weekButton: UIButton!
    @IBOutlet weak var weekView: UIView!
    @IBOutlet weak var weekLabel: UILabel!
    @IBOutlet weak var monthButton: UIButton!
    @IBOutlet weak var monthView: UIView!
    @IBOutlet weak var monthLabel: UILabel!
    @IBOutlet weak var yearButton: UIButton!
    @IBOutlet weak var yearView: UIView!
    @IBOutlet weak var yearLabel: UILabel!
    @IBOutlet weak var fiveYearsButton: UIButton!
    @IBOutlet weak var fiveYearsView: UIView!
    @IBOutlet weak var fiveYearsLabel: UILabel!
    
    // Graph view and sample data
    @IBOutlet weak var graphView: GraphView!
    
    // Data
    var week:[CGFloat] = []
    var month:[CGFloat] = []
    var year:[CGFloat] = []
    var fiveYears:[CGFloat] = []
    var allWeekData = [NSDictionary]()
    var allMonthData = [NSDictionary]()
    var allYearsData = [NSDictionary]()
    var allFiveYearsData = [NSDictionary]()
    var allDataPoints = [NSDictionary]()
    
    // Variables
    var currentValue:CGFloat = 0
    var currentLowestValue:CGFloat = 0
    var currentHighestValue:CGFloat = 0
    var selectedSpan = "week"
    var isFetchingData = true
    var homeVC:HomeViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.profitView.alpha = 0

        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.weekButton.setTitle("", for: .normal)
        
        // Card styling
        self.centerCard.layer.cornerRadius = 13
        self.centerCard.layer.shadowColor = UIColor.black.cgColor
        self.centerCard.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.centerCard.layer.shadowRadius = 10.0
        self.centerCard.layer.shadowOpacity = 0.1
        self.graphView.layer.zPosition = 10
        self.profitView.layer.cornerRadius = 13
        
        // Dates styling
        self.weekView.layer.cornerRadius = 8
        self.weekView.layer.shadowColor = UIColor.black.cgColor
        self.weekView.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.weekView.layer.shadowRadius = 10.0
        self.weekView.layer.shadowOpacity = 0.1
        self.monthView.layer.cornerRadius = 8
        self.monthView.layer.shadowColor = UIColor.black.cgColor
        self.monthView.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.monthView.layer.shadowRadius = 10.0
        self.monthView.layer.shadowOpacity = 0
        self.yearView.layer.cornerRadius = 8
        self.yearView.layer.shadowColor = UIColor.black.cgColor
        self.yearView.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.yearView.layer.shadowRadius = 10.0
        self.yearView.layer.shadowOpacity = 0
        self.fiveYearsView.layer.cornerRadius = 8
        self.fiveYearsView.layer.shadowColor = UIColor.black.cgColor
        self.fiveYearsView.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.fiveYearsView.layer.shadowRadius = 10.0
        self.fiveYearsView.layer.shadowOpacity = 0
        
        // Colors and language
        self.setLanguage()
        self.changeColors()
        
        // Load graph
        self.graphView.valueVC = self
        self.getCurrentValue()
    }
    
    @objc func getCurrentValue() {
        self.hideAlert()
        
        self.valueSpinner.startAnimating()
        self.isFetchingData = true
        self.noDataLabel.alpha = 0
        
        // Get latest value
        Task {
            do {
                var eurUrl = URL(string: "https://getbittr.com/api/price/btc/historical/eur")!
                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                    eurUrl = URL(string: "https://model-arachnid-viable.ngrok-free.app/price/btc/historical/chf")!
                }
                var eurData = Data()
                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF", self.homeVC?.chfData != nil, (self.homeVC?.chfDataFetched!)! > Calendar.current.date(byAdding: .minute, value: -15, to: Date())! {
                    
                    eurData = self.homeVC!.chfData!
                } else if UserDefaults.standard.value(forKey: "currency") as? String != "CHF", self.homeVC?.eurData != nil, (self.homeVC?.eurDataFetched!)! > Calendar.current.date(byAdding: .minute, value: -15, to: Date())! {
                    
                    eurData = self.homeVC!.eurData!
                } else {
                    (eurData, _) = try await URLSession.shared.data(from: eurUrl)
                    if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                        self.homeVC?.chfData = eurData
                        self.homeVC?.chfDataFetched = Date()
                    } else {
                        self.homeVC?.eurData = eurData
                        self.homeVC?.eurDataFetched = Date()
                    }
                }
                
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
                            self.allWeekData += [["price":self.stringToNumber((eachDataPoint["price"] as! String)),"date":ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))!]]
                        }
                    }
                    
                    var lastMonth = [CGFloat]()
                    for eachDataPoint in monthData {
                        if Calendar.current.date(byAdding: .month, value: -1, to: Date())! < ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))! {
                            lastMonth += [self.stringToNumber((eachDataPoint["price"] as! String))]
                            self.allMonthData += [["price":self.stringToNumber((eachDataPoint["price"] as! String)),"date":ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))!]]
                        }
                    }
                    
                    var lastYear = [CGFloat]()
                    for eachDataPoint in yearData {
                        if Calendar.current.date(byAdding: .year, value: -1, to: Date())! < ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))! {
                            lastYear += [self.stringToNumber((eachDataPoint["price"] as! String))]
                            self.allYearsData += [["price":self.stringToNumber((eachDataPoint["price"] as! String)),"date":ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))!]]
                        }
                    }
                    
                    var lastFiveYears = [CGFloat]()
                    var doAdd = true
                    for eachDataPoint in fiveYearData {
                        if Calendar.current.date(byAdding: .year, value: -5, to: Date())! < ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))! {
                            if doAdd {
                                lastFiveYears += [self.stringToNumber((eachDataPoint["price"] as! String))]
                                self.allFiveYearsData += [["price":self.stringToNumber((eachDataPoint["price"] as! String)),"date":ISO8601DateFormatter().date(from: (eachDataPoint["time_iso8601"] as! String))!]]
                                doAdd = false
                            } else {
                                doAdd = true
                            }
                        }
                    }
                    
                    var data = Data()
                    
                    if self.homeVC!.currentValue != nil, (self.homeVC?.currentValueFetched!)! > Calendar.current.date(byAdding: .minute, value: -15, to: Date())! {
                        data = self.homeVC!.currentValue!
                    } else {
                        let envUrl = URL(string: "https://model-arachnid-viable.ngrok-free.app/price/btc")!
                        (data, _) = try await URLSession.shared.data(from: envUrl)
                        
                        self.homeVC?.currentValue = data
                        self.homeVC?.currentValueFetched = Date()
                    }
                    
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
                            self.allWeekData = self.allWeekData + [["price":self.currentValue,"date":Date()]]
                            self.allMonthData = self.allMonthData + [["price":self.currentValue,"date":Date()]]
                            self.allYearsData = self.allYearsData + [["price":self.currentValue,"date":Date()]]
                            self.allFiveYearsData = self.allFiveYearsData + [["price":self.currentValue,"date":Date()]]
                            
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
                    self.noDataLabel.alpha = 1
                    self.homeVC?.eurData = nil
                    self.homeVC?.chfData = nil
                    self.homeVC?.currentValue = nil
                    
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "historicaldata"))", buttons: [Language.getWord(withID: "tryagain"), Language.getWord(withID: "cancel")], actions: [#selector(self.getCurrentValue), nil])
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
        
        self.selectedSpan = sender.accessibilityIdentifier!
        self.drawGraph()
        
        var shadowOpacities = [Float]()
        var backgroundColors = [UIColor]()
        var words = [String]()
        switch sender.accessibilityIdentifier! {
        case "week":
            shadowOpacities = [0.1,0,0,0]
            backgroundColors = [.white, UIColor(white: 1, alpha: 0.7), UIColor(white: 1, alpha: 0.7), UIColor(white: 1, alpha: 0.7)]
            words = ["1 week", "m", "y", "5y"]
        case "month":
            shadowOpacities = [0,0.1,0,0]
            backgroundColors = [UIColor(white: 1, alpha: 0.7), .white, UIColor(white: 1, alpha: 0.7), UIColor(white: 1, alpha: 0.7)]
            words = ["w", "1 month", "y", "5y"]
        case "year":
            shadowOpacities = [0,0,0.1,0]
            backgroundColors = [UIColor(white: 1, alpha: 0.7), UIColor(white: 1, alpha: 0.7), .white, UIColor(white: 1, alpha: 0.7)]
            words = ["w", "m", "1 year", "5y"]
        case "5years":
            shadowOpacities = [0,0,0,0.1]
            backgroundColors = [UIColor(white: 1, alpha: 0.7), UIColor(white: 1, alpha: 0.7), UIColor(white: 1, alpha: 0.7), .white]
            words = ["w", "m", "y", "5 years"]
        default:
            shadowOpacities = [0.1,0,0,0]
            backgroundColors = [.white, UIColor(white: 1, alpha: 0.7), UIColor(white: 1, alpha: 0.7), UIColor(white: 1, alpha: 0.7)]
            words = ["1 week", "m", "y", "5y"]
        }

        self.weekView.layer.shadowOpacity = shadowOpacities[0]
        self.monthView.layer.shadowOpacity = shadowOpacities[1]
        self.yearView.layer.shadowOpacity = shadowOpacities[2]
        self.fiveYearsView.layer.shadowOpacity = shadowOpacities[3]
        self.weekView.backgroundColor = backgroundColors[0]
        self.monthView.backgroundColor = backgroundColors[1]
        self.yearView.backgroundColor = backgroundColors[2]
        self.fiveYearsView.backgroundColor = backgroundColors[3]
        self.weekLabel.text = words[0]
        self.monthLabel.text = words[1]
        self.yearLabel.text = words[2]
        self.fiveYearsLabel.text = words[3]
    }
    
    func drawGraph() {
        
        // Remove existing lines and labels.
        for eachSubview in self.centerCard.subviews {
            if eachSubview != self.graphView, eachSubview != self.headerLabel, eachSubview != self.iconExchange, eachSubview != self.currentValueLabel, eachSubview != self.weekView, eachSubview != self.monthView, eachSubview != self.yearView, eachSubview != self.fiveYearsView, eachSubview != self.buttonsView, eachSubview != self.profitView {
                eachSubview.removeFromSuperview()
            }
        }
        
        var currentArray = self.month
        self.allDataPoints = self.allMonthData
        if self.selectedSpan == "week" {
            currentArray = self.week
            self.allDataPoints = self.allWeekData
        } else if self.selectedSpan == "year" {
            currentArray = self.year
            self.allDataPoints = self.allYearsData
        } else if self.selectedSpan == "5years" {
            currentArray = self.fiveYears
            self.allDataPoints = self.allFiveYearsData
        }
        if currentArray.count == 0 {
            if self.noDataLabel != nil {
                self.noDataLabel.alpha = 1
            }
            self.graphView.alpha = 0
            return
        } else {
            if self.noDataLabel != nil {
                self.noDataLabel.alpha = 0
            }
            self.graphView.alpha = 1
        }
        self.graphView.data = currentArray
        
        // Set Y axis.
        var allLines:[CGFloat] = []
        var thisHighestNumber = CGFloat()
        var totalSpan = CGFloat()
        
        if let lowestNumber = currentArray.min(), let highestNumber = currentArray.max() {
            
            self.currentLowestValue = lowestNumber
            self.currentHighestValue = highestNumber
            thisHighestNumber = highestNumber
            totalSpan = highestNumber - lowestNumber
            
            // Set profit label
            let profitPercentage = "\(Int((currentArray[currentArray.count-1] - currentArray[0])/currentArray[0] * 100)) %"
            self.profitLabel.text = profitPercentage
            if profitPercentage.contains("-") {
                self.profitLabel.textColor = Colors.getColor("losstext")
                self.profitView.backgroundColor = Colors.getColor("lossbackground0.8")
                self.profitArrowImage.tintColor = Colors.getColor("losstext")
                self.profitArrowImage.image = UIImage(systemName: "arrow.down")
            } else {
                self.profitLabel.textColor = Colors.getColor("profittext")
                self.profitView.backgroundColor = Colors.getColor("profitbackground0.8")
                self.profitArrowImage.tintColor = Colors.getColor("profittext")
                self.profitArrowImage.image = UIImage(systemName: "arrow.up")
            }
            self.profitView.alpha = 1
            
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
            allLines = [roundedUp]
            
            // Keep adding 5000 until we exceed the maxNumber
            while roundedUp <= highestNumber {
                roundedUp += differential
                if roundedUp < highestNumber {
                    allLines += [roundedUp]
                }
            }
            
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
        
        // Set X axis.
        var totalDataPoints:CGFloat = 0
        var dataPoints = [CGFloat]()
        var labels = [String]()
        
        if self.selectedSpan == "5years" {
            
            // Get total days
            let currentDate = Date()
            let currentYear = Calendar.current.component(.year, from: currentDate)
            let startYear = currentYear - 5
            let endYear = currentYear
            for year in startYear..<endYear {
                if self.isLeapYear(year: year) {
                    totalDataPoints += 366
                } else {
                    totalDataPoints += 365
                }
            }
            
            // Get 1 Januarys
            let startDate = Calendar.current.date(byAdding: .year, value: -5, to: currentDate)!
            for year in startYear...endYear {
                let firstOfJanuary = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1))!
                let dayNumber = Calendar.current.dateComponents([.day], from: startDate, to: firstOfJanuary).day!
                if dayNumber > 0 {
                    dataPoints += [CGFloat(dayNumber)]
                    labels += ["\(year)"]
                }
            }
        } else if selectedSpan == "year" {
            
            let currentDate = Date()
            var startDate = Calendar.current.date(byAdding: .year, value: -1, to: currentDate)!
            let originalStartDate = startDate
            totalDataPoints = CGFloat(Calendar.current.dateComponents([.day], from: startDate, to: currentDate).day!)
            
            while Calendar.current.date(byAdding: .month, value: 3, to: startDate)! <= currentDate {
                if let newDate = Calendar.current.date(byAdding: .month, value: 3, to: startDate) {
                    
                    let components = Calendar.current.dateComponents([.year, .month], from: newDate)
                    
                    dataPoints += [CGFloat(Calendar.current.dateComponents([.day], from: originalStartDate, to: Calendar.current.date(from: DateComponents(year: components.year, month: components.month, day: 1))!).day!)]
                    
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "MMM"
                    labels += [dateFormatter.string(from: newDate)]
                    
                    startDate = newDate
                }
            }
        } else if selectedSpan == "month" {
            
            let currentDate = Date()
            var startDate = Calendar.current.date(byAdding: .month, value: -1, to: currentDate)!
            let originalStartDate = startDate
            totalDataPoints = CGFloat(Calendar.current.dateComponents([.day], from: startDate, to: currentDate).day!)
            
            while Calendar.current.date(byAdding: .day, value: 7, to: startDate)! <= currentDate {
                if let newDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate) {
                    
                    dataPoints += [CGFloat(Calendar.current.dateComponents([.day], from: originalStartDate, to: newDate).day!)]
                    
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "dd MMM"
                    var dateString = dateFormatter.string(from: newDate)
                    if dateString.first == "0" {
                        dateString = String(dateString.dropFirst())
                    }
                    labels += [dateString]
                    
                    startDate = newDate
                }
            }
        } else if selectedSpan == "week" {
            
            let currentDate = Date()
            var startDate = Calendar.current.date(byAdding: .day, value: -7, to: currentDate)!
            let originalStartDate = startDate
            totalDataPoints = CGFloat(Calendar.current.dateComponents([.day], from: startDate, to: currentDate).day!)
            
            while Calendar.current.date(byAdding: .day, value: 2, to: startDate)! <= currentDate {
                if let newDate = Calendar.current.date(byAdding: .day, value: 2, to: startDate) {
                    
                    dataPoints += [CGFloat(Calendar.current.dateComponents([.day], from: originalStartDate, to: newDate).day!)]
                    
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "dd MMM"
                    var dateString = dateFormatter.string(from: newDate)
                    if dateString.first == "0" {
                        dateString = String(dateString.dropFirst())
                    }
                    labels += [dateString]
                    
                    startDate = newDate
                }
            }
        }
        
        for (index, eachDataPoint) in dataPoints.enumerated() {
            
            let thisLine = UIView()
            thisLine.translatesAutoresizingMaskIntoConstraints = false
            thisLine.backgroundColor = Colors.getColor("blackorwhite")
            thisLine.layer.zPosition = 0
            thisLine.alpha = 0.2
            self.centerCard.addSubview(thisLine)
            
            let thisLineWidth = NSLayoutConstraint(item: thisLine, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 1)
            let thisLineLeft = NSLayoutConstraint(item: thisLine, attribute: .leading, relatedBy: .equal, toItem: self.graphView, attribute: .leading, multiplier: 1, constant: (eachDataPoint/totalDataPoints)*self.graphView.bounds.width*0.75+self.graphView.bounds.width*0.1)
            let thisLineTop = NSLayoutConstraint(item: thisLine, attribute: .top, relatedBy: .equal, toItem: self.graphView, attribute: .top, multiplier: 1, constant: ((thisHighestNumber-allLines[0])/totalSpan)*140)
            let thisLineBottom = NSLayoutConstraint(item: thisLine, attribute: .bottom, relatedBy: .equal, toItem: self.graphView, attribute: .bottom, multiplier: 1, constant: -15)
            self.centerCard.addConstraints([thisLineLeft, thisLineTop, thisLineBottom])
            thisLine.addConstraint(thisLineWidth)
            
            let thisLabel = UILabel()
            thisLabel.translatesAutoresizingMaskIntoConstraints = false
            thisLabel.font = UIFont(name: "Gilroy-Regular", size: 12)
            thisLabel.text = labels[index]
            thisLabel.textColor = Colors.getColor("blackorwhite")
            thisLabel.layer.zPosition = 0
            thisLabel.alpha = 0.4
            self.centerCard.addSubview(thisLabel)
            
            let thisLabelHeight = NSLayoutConstraint(item: thisLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            let thisLabelWidth = NSLayoutConstraint(item: thisLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            let thisLabelTop = NSLayoutConstraint(item: thisLabel, attribute: .top, relatedBy: .equal, toItem: thisLine, attribute: .bottom, multiplier: 1, constant: 10)
            let thisLabelCenter = NSLayoutConstraint(item: thisLabel, attribute: .centerX, relatedBy: .equal, toItem: thisLine, attribute: .centerX, multiplier: 1, constant: 0)
            self.centerCard.addConstraints([thisLabelTop, thisLabelCenter])
            thisLabel.addConstraints([thisLabelHeight, thisLabelWidth])
        }
        
    }
    
    func isLeapYear(year: Int) -> Bool {
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func setLanguage() {
        self.headerLabel.text = Language.getWord(withID: "bitcoinvalue")
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
