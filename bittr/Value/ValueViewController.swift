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
    var week:[CGFloat] = [94955, 95441, 95726, 98333, 93356, 89890, 92401]
    var month:[CGFloat] = [92893, 101467, 90638, 94303, 89268, 98333]
    var year:[CGFloat] = [42205, 47832, 66722, 65609, 62666, 49049, 62479, 94760]
    var fiveYears:[CGFloat] = [7213, 15530, 50118, 26714, 56274, 20347, 25416, 25536, 64497, 48547]
    var currentValue:CGFloat = 0
    var selectedSpan = "month"

    
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
                let envUrl = URL(string: "https://getbittr.com/api/price/btc")!
                let (data, _) = try await URLSession.shared.data(from: envUrl)
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let actualEurValue = json["btc_eur"] as? String, let actualChfValue = json["btc_chf"] as? String {
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
                        
                        self.currentValueLabel.text = "\(preferredCurrency) \(valueToDisplay)"
                        
                        self.valueSpinner.stopAnimating()
                        self.drawGraph()
                    }
                }
            } catch {
                print("Error fetching data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.valueSpinner.stopAnimating()
                    self.drawGraph()
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
        
        if self.valueSpinner.isAnimating { return }
        
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
        
        var currentArray = self.month + [self.currentValue]
        if self.selectedSpan == "week" {
            currentArray = self.week + [self.currentValue]
        } else if self.selectedSpan == "year" {
            currentArray = self.year + [self.currentValue]
        } else if self.selectedSpan == "5years" {
            currentArray = self.fiveYears + [self.currentValue]
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
