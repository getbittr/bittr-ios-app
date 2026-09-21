//
//  GraphView.swift
//  bittr
//
//  Created by Tom Melters on 11/01/2025.
//

import UIKit

class GraphView: UIView, UIGestureRecognizerDelegate {
    
    var points:[PricePoint] = [] {
        didSet {
            self.currency = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue().chosenCurrency
            self.data = self.points.map { $0.price }
            setNeedsDisplay()
        }
    }
    
    private(set) var data:[CGFloat] = []
    
    var horizontalInset:CGFloat = 30
    var topInset:CGFloat = 5
    var bottomInset:CGFloat = 25
    var lineWidth:CGFloat = 4
    var pointRadius:CGFloat = 2
    var isInteractive = true
    var lineColor:UIColor?
    private var strokeColor:UIColor {
        return self.lineColor ?? Colors.getColor("whiteoryellow")
    }
    
    var currency = ""
    
    static let cardDateFormatter:DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupGestureRecognizers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupGestureRecognizers()
    }
    
    private func setupGestureRecognizers() {
        // Add a pan gesture recognizer to track horizontal movements
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        self.addGestureRecognizer(panGesture)
        
        // Ensure the gesture recognizer only triggers on horizontal movement
        panGesture.delegate = self
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // If the touch is inside this view, allow gesture recognition
        if gestureRecognizer.view == self {
            return true
        }
        return false
    }
    
    @objc func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        guard self.isInteractive else { return }
        let location = recognizer.location(in: self)
        let horizontalTouchPosition = location.x
        self.showGraphValue(x: horizontalTouchPosition, recognizer: recognizer)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for eachSubview in self.subviews {
            if eachSubview.boundString == "valuecard" {
                eachSubview.removeFromSuperview()
            }
        }
    }
    
    func showGraphValue(x:CGFloat, recognizer:UIPanGestureRecognizer) {
        
        for eachSubview in self.subviews {
            if eachSubview.boundString == "valuecard" {
                eachSubview.removeFromSuperview()
            }
        }
        
        let totalWidth = self.bounds.width - (self.horizontalInset * 2)
        var actualX = x - self.horizontalInset
        if actualX < 0 {
            actualX = 0
        } else if actualX > totalWidth {
            actualX = totalWidth
        }
        
        if recognizer.state != .ended, self.data.count > 0 {
            
            var relativeLocation = actualX/totalWidth
            if relativeLocation > 1 {
                relativeLocation = 1
            } else if relativeLocation < 0 {
                relativeLocation = 0
            }
            let numberOfDataPoints:CGFloat = CGFloat(self.data.count)
            var selectedIndex = Int(relativeLocation * numberOfDataPoints) - 1
            if selectedIndex < 0 {
                selectedIndex = 0
            } else if selectedIndex > Int(totalWidth) {
                selectedIndex = Int(totalWidth)
            }
            let thisDataPoint = self.points[selectedIndex]
            
            let highestNumber = self.data.max() ?? 0
            let lowestNumber = self.data.min() ?? 0
            let dataSpan = highestNumber - lowestNumber
            let thisPrice = thisDataPoint.price
            let priceRelativeToSpan = dataSpan > 0 ? (thisPrice - lowestNumber)/dataSpan : 0.5
            let yConstraint = (self.bottomInset + 5) + (priceRelativeToSpan * (self.bounds.height - self.topInset - self.bottomInset))
            
            let thisCard = UIView()
            thisCard.translatesAutoresizingMaskIntoConstraints = false
            thisCard.backgroundColor = .white
            thisCard.layer.zPosition = 10
            thisCard.layer.cornerRadius = 8
            thisCard.alpha = 1
            thisCard.boundString = "valuecard"
            self.addSubview(thisCard)
            
            let thisCardHeight = NSLayoutConstraint(item: thisCard, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
            let thisCardWidth = NSLayoutConstraint(item: thisCard, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 80)
            let thisCardCenterX = NSLayoutConstraint(item: thisCard, attribute: .centerX, relatedBy: .equal, toItem: self, attribute: .leading, multiplier: 1, constant: (actualX + self.horizontalInset))
            let thisCardBottom = NSLayoutConstraint(item: thisCard, attribute: .bottom, relatedBy: .equal, toItem: self, attribute: .bottom, multiplier: 1, constant: -yConstraint)
            self.addConstraints([thisCardBottom, thisCardCenterX])
            thisCard.addConstraints([thisCardHeight, thisCardWidth])
            
            let dateLabel = UILabel()
            dateLabel.translatesAutoresizingMaskIntoConstraints = false
            dateLabel.font = UIFont(name: "Gilroy-Regular", size: 10)
            dateLabel.text = GraphView.cardDateFormatter.string(from: thisDataPoint.date)
            dateLabel.textColor = .black
            dateLabel.alpha = 0.4
            thisCard.addSubview(dateLabel)
            
            let dateLabelHeight = NSLayoutConstraint(item: dateLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            let dateLabelWidth = NSLayoutConstraint(item: dateLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            let dateLabelTop = NSLayoutConstraint(item: dateLabel, attribute: .top, relatedBy: .equal, toItem: thisCard, attribute: .top, multiplier: 1, constant: 9)
            let dateLabelCenter = NSLayoutConstraint(item: dateLabel, attribute: .centerX, relatedBy: .equal, toItem: thisCard, attribute: .centerX, multiplier: 1, constant: 0)
            thisCard.addConstraints([dateLabelTop, dateLabelCenter])
            dateLabel.addConstraints([dateLabelHeight, dateLabelWidth])
            
            let priceLabel = UILabel()
            priceLabel.translatesAutoresizingMaskIntoConstraints = false
            priceLabel.accessibilityIdentifier = TestID.Value.graphValueLabel
            priceLabel.font = UIFont(name: "Gilroy-Bold", size: 12)
            priceLabel.text = self.currency + " " + ValueViewController.formatEuroValue("\(Int(thisDataPoint.price))")
            priceLabel.textColor = .black
            thisCard.addSubview(priceLabel)
            
            let priceLabelHeight = NSLayoutConstraint(item: priceLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            let priceLabelWidth = NSLayoutConstraint(item: priceLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            let priceLabelTop = NSLayoutConstraint(item: priceLabel, attribute: .top, relatedBy: .equal, toItem: dateLabel, attribute: .bottom, multiplier: 1, constant: 3)
            let priceLabelCenter = NSLayoutConstraint(item: priceLabel, attribute: .centerX, relatedBy: .equal, toItem: thisCard, attribute: .centerX, multiplier: 1, constant: 0)
            thisCard.addConstraints([priceLabelTop, priceLabelCenter])
            priceLabel.addConstraints([priceLabelHeight, priceLabelWidth])
            
        }
    }

    override func draw(_ rect: CGRect) {
        
        if data.count == 0 {return}
        
        let context = UIGraphicsGetCurrentContext()
        let path:UIBezierPath = quadCurvedPath()
        context!.saveGState()
        context!.setShadow(offset: CGSize(width: 0, height: 9), blur: 15, color: UIColor.black.cgColor)
        context!.setAlpha(0.4)
        self.strokeColor.setStroke()
        path.lineWidth = self.lineWidth
        path.stroke()
        context!.restoreGState()
        
        let path2:UIBezierPath = quadCurvedPath()
        self.strokeColor.setStroke()
        path2.lineWidth = self.lineWidth
        path2.stroke()
    }

    func quadCurvedPath() -> UIBezierPath {
        
        let path = UIBezierPath()
        let curve = GraphCurve(values: self.data, size: self.bounds.size, horizontalInset: self.horizontalInset, topInset: self.topInset, bottomInset: self.bottomInset)
        
        for eachDot in curve.dots {
            drawPoint(point: eachDot, color: self.strokeColor, radius: self.pointRadius)
        }
        
        guard let start = curve.start else { return path }
        path.move(to: start)
        
        for eachSegment in curve.segments {
            switch eachSegment {
            case .line(let to):
                path.addLine(to: to)
            case .curve(let to, let control1, let control2):
                path.addCurve(to: to, controlPoint1: control1, controlPoint2: control2)
            }
        }
        
        return path
    }
    
    func drawPoint(point: CGPoint, color: UIColor, radius: CGFloat) {
        guard radius > 0 else { return }
        let ovalPath = UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        color.setFill()
        ovalPath.fill()
    }
    
}

