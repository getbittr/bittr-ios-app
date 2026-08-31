//
//  ValueViewController.swift
//  bittr
//
//  Created by Tom Melters on 04/01/2025.
//

import UIKit

struct PricePoint {
    let date:Date
    let price:CGFloat
}

enum GraphSpan:String, CaseIterable {
    case week
    case month
    case year
    case fiveYears = "5years"

    // Where this span's series sits in the historical API's payload.
    var apiIndex:Int {
        switch self {
        case .week: return 2
        case .month: return 3
        case .year: return 6
        case .fiveYears: return 7
        }
    }
    
    func startDate(from date:Date) -> Date {
        switch self {
        case .week: return Calendar.current.date(byAdding: .day, value: -7, to: date)!
        case .month: return Calendar.current.date(byAdding: .month, value: -1, to: date)!
        case .year: return Calendar.current.date(byAdding: .year, value: -1, to: date)!
        case .fiveYears: return Calendar.current.date(byAdding: .year, value: -5, to: date)!
        }
    }
    
    var sampleEvery:Int {
        // For the five year series, only plot every second point.
        return self == .fiveYears ? 2 : 1
    }
    
    var tick:(every:DateComponents, format:String, onMonthStart:Bool)? {
        switch self {
        case .week: return (DateComponents(day: 2), "dd MMM", false)
        case .month: return (DateComponents(day: 7), "dd MMM", false)
        case .year: return (DateComponents(month: 3), "MMM", true)
        case .fiveYears: return nil
        }
    }
    
    var longTitle:String {
        switch self {
        case .week: return "1 week"
        case .month: return "1 month"
        case .year: return "1 year"
        case .fiveYears: return "5 years"
        }
    }
    
    var shortTitle:String {
        switch self {
        case .week: return "w"
        case .month: return "m"
        case .year: return "y"
        case .fiveYears: return "5y"
        }
    }
}

class ValueViewController: UIViewController {

    // General
    @IBOutlet weak var centerCard: UIView!
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
    var series:[GraphSpan:[PricePoint]] = [:]
    var allDataPoints = [PricePoint]()
    
    // Variables
    var currentValue:CGFloat = 0
    var selectedSpan:GraphSpan = .week
    var isFetchingData = true
    var homeVC:HomeViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.profitView.alpha = 0

        // Tag the span buttons so changeSpan can route the tap.
        // (Was set on accessibilityIdentifier in IB; moved here so that slot
        // stays free for Maestro test IDs.)
        self.weekButton.boundString = GraphSpan.week.rawValue
        self.monthButton.boundString = GraphSpan.month.rawValue
        self.yearButton.boundString = GraphSpan.year.rawValue
        self.fiveYearsButton.boundString = GraphSpan.fiveYears.rawValue

        // Maestro test IDs.
        self.currentValueLabel.accessibilityIdentifier = TestID.Value.currentValueLabel
        self.valueSpinner.accessibilityIdentifier = TestID.Value.valueSpinner
        self.profitLabel.accessibilityIdentifier = TestID.Value.profitLabel
        self.graphView.accessibilityIdentifier = TestID.Value.graphView
        self.weekButton.accessibilityIdentifier = TestID.Value.weekButton
        self.monthButton.accessibilityIdentifier = TestID.Value.monthButton
        self.yearButton.accessibilityIdentifier = TestID.Value.yearButton
        self.fiveYearsButton.accessibilityIdentifier = TestID.Value.fiveYearsButton

        // Button titles
        self.weekButton.setTitle("", for: .normal)
        
        // Card styling
        self.centerCard.layer.cornerRadius = 13
        self.centerCard.setShadow()
        self.graphView.layer.zPosition = 10
        self.profitView.layer.cornerRadius = 13
        
        // Dates styling
        self.weekView.layer.cornerRadius = 8
        self.weekView.setShadow()
        self.weekView.layer.shadowOpacity = 0.1
        self.monthView.layer.cornerRadius = 8
        self.monthView.setShadow()
        self.monthView.layer.shadowOpacity = 0
        self.yearView.layer.cornerRadius = 8
        self.yearView.setShadow()
        self.yearView.layer.shadowOpacity = 0
        self.fiveYearsView.layer.cornerRadius = 8
        self.fiveYearsView.setShadow()
        self.fiveYearsView.layer.shadowOpacity = 0
        
        // Colors and language
        self.changeColors()
        self.addHeader(iconLight: "iconexchange", iconDark: "iconexchangeyellow", title: Language.getWord(withID: "bitcoinvalue"))
        
        // Load graph
        self.graphView.valueVC = self
        self.getCurrentValue()
    }
    
    func getCurrentValue() {
        
        self.valueSpinner.startAnimating()
        self.isFetchingData = true
        self.noDataLabel.alpha = 0
        
        // Start from empty arrays.
        self.series = [:]
        
        // Get latest value
        Task {
            do {
                let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
                let eurUrl = URL(string: bitcoinValue.apiUrl)!
                var eurData = Data()
                if bitcoinValue.chosenCurrency == "CHF", self.homeVC?.chfData != nil, (self.homeVC?.chfDataFetched!)! > Calendar.current.date(byAdding: .minute, value: -15, to: Date())! {
                    
                    eurData = self.homeVC!.chfData!
                } else if bitcoinValue.chosenCurrency != "CHF", self.homeVC?.eurData != nil, (self.homeVC?.eurDataFetched!)! > Calendar.current.date(byAdding: .minute, value: -15, to: Date())! {
                    
                    eurData = self.homeVC!.eurData!
                } else {
                    (eurData, _) = try await URLSession.shared.data(from: eurUrl)
                    if bitcoinValue.chosenCurrency == "CHF" {
                        self.homeVC?.chfData = eurData
                        self.homeVC?.chfDataFetched = Date()
                    } else {
                        self.homeVC?.eurData = eurData
                        self.homeVC?.eurDataFetched = Date()
                    }
                }
                
                guard let json = try JSONSerialization.jsonObject(with: eurData) as? [NSDictionary] else { return }
                
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
                
                // Parse each data point once with a single shared formatter.
                let isoFormatter = ISO8601DateFormatter()
                let now = Date()
                
                var parsedSeries = [GraphSpan:[PricePoint]]()
                for eachSpan in GraphSpan.allCases {
                    guard let rawPoints = json[eachSpan.apiIndex]["data"] as? [NSDictionary] else { return }
                    parsedSeries[eachSpan] = self.pricePoints(from: rawPoints, span: eachSpan, formatter: isoFormatter, now: now)
                }
                
                var data = Data()
                
                if self.homeVC!.currentValue != nil, (self.homeVC?.currentValueFetched!)! > Calendar.current.date(byAdding: .minute, value: -15, to: Date())! {
                    data = self.homeVC!.currentValue!
                } else {
                    let envUrl = URL(string: "https://getbittr.com/api/price/btc")!
                    (data, _) = try await URLSession.shared.data(from: envUrl)

                    self.homeVC?.currentValue = data
                    self.homeVC?.currentValueFetched = Date()
                }
                
                guard let currentJson = try JSONSerialization.jsonObject(with: data) as? [String: Any], let actualEurValue = currentJson["btc_eur"] as? String, let actualChfValue = currentJson["btc_chf"] as? String else { return }
                    
                DispatchQueue.main.async {
                    let formattedEurValue = self.formatEuroValue(actualEurValue)
                    let formattedChfValue = self.formatEuroValue(actualChfValue)
                    
                    self.currentValue = actualEurValue.toNumber()
                    var preferredCurrency = "€"
                    var valueToDisplay = formattedEurValue
                    if bitcoinValue.chosenCurrency == "CHF" {
                        preferredCurrency = "CHF"
                        valueToDisplay = formattedChfValue
                        self.currentValue = actualChfValue.toNumber()
                    }
                    
                    Log.debug("EUR value: \(formattedEurValue), CHF value: \(formattedChfValue), currency: \(preferredCurrency)")
                    
                    // Append the current value so each graph ends on the value shown above it.
                    let currentPoint = PricePoint(date: Date(), price: self.currentValue)
                    for eachSpan in GraphSpan.allCases {
                        self.series[eachSpan] = (parsedSeries[eachSpan] ?? []) + [currentPoint]
                    }
                    
                    self.currentValueLabel.text = "\(preferredCurrency) \(valueToDisplay)"
                    
                    self.valueSpinner.stopAnimating()
                    self.drawGraph()
                    self.isFetchingData = false
                }
            } catch {
                Log.info("Error fetching data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.valueSpinner.stopAnimating()
                    self.isFetchingData = false
                    self.noDataLabel.alpha = 1
                    self.homeVC?.eurData = nil
                    self.homeVC?.chfData = nil
                    self.homeVC?.currentValue = nil
                    
                    self.showAlert(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "historicaldata"))", buttons: [.action(Language.getWord(withID: "tryagain")) { self.getCurrentValue() }, .dismiss(Language.getWord(withID: "cancel"))])
                    SentryManager.capture(error, context: "ValueViewController row 264")
                }
            }
        }
    }
    
    func pricePoints(from rawPoints:[NSDictionary], span:GraphSpan, formatter:ISO8601DateFormatter, now:Date) -> [PricePoint] {
        
        let cutoff = span.startDate(from: now)
        var points = [PricePoint]()
        var kept = 0
        
        for eachDataPoint in rawPoints {
            guard let date = formatter.date(from: eachDataPoint["time_iso8601"] as! String), cutoff < date else { continue }
            kept += 1
            guard (kept - 1) % span.sampleEvery == 0 else { continue }
            points += [PricePoint(date: date, price: (eachDataPoint["price"] as! String).toNumber())]
        }
        
        // Drop the API's copy of the latest price.
        if !points.isEmpty { points.removeLast() }
        
        return points
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

        self.selectedSpan = GraphSpan(rawValue: sender.boundString ?? "") ?? .week
        self.drawGraph()
        self.showSelectedSpan()
    }
    
    func showSelectedSpan() {
        
        let spanButtons:[(span:GraphSpan, view:UIView, label:UILabel)] = [
            (.week, self.weekView, self.weekLabel),
            (.month, self.monthView, self.monthLabel),
            (.year, self.yearView, self.yearLabel),
            (.fiveYears, self.fiveYearsView, self.fiveYearsLabel)
        ]
        
        for eachButton in spanButtons {
            let isSelected = (eachButton.span == self.selectedSpan)
            eachButton.view.layer.shadowOpacity = isSelected ? 0.1 : 0
            eachButton.view.backgroundColor = isSelected ? .white : UIColor(white: 1, alpha: 0.7)
            eachButton.label.text = isSelected ? eachButton.span.longTitle : eachButton.span.shortTitle
        }
    }
    
    func drawGraph() {
        
        // Remove existing lines and labels.
        for eachSubview in self.centerCard.subviews {
            if eachSubview != self.graphView, eachSubview != self.currentValueLabel, eachSubview != self.weekView, eachSubview != self.monthView, eachSubview != self.yearView, eachSubview != self.fiveYearsView, eachSubview != self.buttonsView, eachSubview != self.profitView {
                eachSubview.removeFromSuperview()
            }
        }
        
        self.allDataPoints = self.series[self.selectedSpan] ?? []
        let currentArray = self.allDataPoints.map { $0.price }
        
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
        let (totalDataPoints, dataPoints, labels) = self.xAxisTicks()
        
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
    
    // Where the vertical date lines go.
    func xAxisTicks() -> (total:CGFloat, offsets:[CGFloat], labels:[String]) {
        
        let currentDate = Date()
        let startDate = self.selectedSpan.startDate(from: currentDate)
        var offsets = [CGFloat]()
        var labels = [String]()
        
        // Five years is laid out per calendar year: a line on each 1 January.
        guard let tick = self.selectedSpan.tick else {
            
            var totalDataPoints:CGFloat = 0
            let currentYear = Calendar.current.component(.year, from: currentDate)
            let startYear = currentYear - 5
            
            for eachYear in startYear..<currentYear {
                totalDataPoints += self.isLeapYear(year: eachYear) ? 366 : 365
            }
            
            for eachYear in startYear...currentYear {
                let firstOfJanuary = Calendar.current.date(from: DateComponents(year: eachYear, month: 1, day: 1))!
                let dayNumber = Calendar.current.dateComponents([.day], from: startDate, to: firstOfJanuary).day!
                if dayNumber > 0 {
                    offsets += [CGFloat(dayNumber)]
                    labels += ["\(eachYear)"]
                }
            }
            
            return (totalDataPoints, offsets, labels)
        }
        
        let totalDataPoints = CGFloat(Calendar.current.dateComponents([.day], from: startDate, to: currentDate).day!)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = tick.format
        
        var walkedDate = startDate
        while let nextDate = Calendar.current.date(byAdding: tick.every, to: walkedDate), nextDate <= currentDate {
            
            // The year graph names whole months, so its lines sit on the 1st.
            var lineDate = nextDate
            if tick.onMonthStart {
                lineDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: nextDate))!
            }
            offsets += [CGFloat(Calendar.current.dateComponents([.day], from: startDate, to: lineDate).day!)]
            
            var dateString = dateFormatter.string(from: nextDate)
            if dateString.first == "0" {
                dateString = String(dateString.dropFirst())
            }
            labels += [dateString]
            
            walkedDate = nextDate
        }
        
        return (totalDataPoints, offsets, labels)
    }
    
    func isLeapYear(year: Int) -> Bool {
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.centerCard.backgroundColor = Colors.getColor("yelloworblue2")
        self.currentValueLabel.textColor = Colors.getColor("blackorwhite")
        self.valueSpinner.color = Colors.getColor("blackorwhite")
    }
}
