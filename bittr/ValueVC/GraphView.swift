//
//  GraphView.swift
//  bittr
//
//  Created by Tom Melters on 11/01/2025.
//

import UIKit

class GraphView: UIView, UIGestureRecognizerDelegate {
    
    var valueVC:ValueViewController?

    var data:[CGFloat] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    
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
        let location = recognizer.location(in: self)
        let horizontalTouchPosition = location.x
        self.showGraphValue(x: horizontalTouchPosition, recognizer: recognizer)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for eachSubview in self.subviews {
            if eachSubview.accessibilityIdentifier == "valuecard" {
                eachSubview.removeFromSuperview()
            }
        }
    }
    
    func showGraphValue(x:CGFloat, recognizer:UIPanGestureRecognizer) {
        
        for eachSubview in self.subviews {
            if eachSubview.accessibilityIdentifier == "valuecard" {
                eachSubview.removeFromSuperview()
            }
        }
        
        let totalWidth = self.bounds.width - 60
        var actualX = x - 30
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
            let thisDataPoint = self.valueVC!.allDataPoints[selectedIndex]
            
            let highestNumber = self.data.max() ?? 0
            let lowestNumber = self.data.min() ?? 0
            let dataSpan = highestNumber - lowestNumber
            let thisPrice = thisDataPoint["price"] as! CGFloat
            let priceRelativeToSpan = (thisPrice - lowestNumber)/dataSpan
            let yConstraint = 30 + (priceRelativeToSpan * (self.bounds.height - 30))
            
            let thisCard = UIView()
            thisCard.translatesAutoresizingMaskIntoConstraints = false
            thisCard.backgroundColor = .white
            thisCard.layer.zPosition = 10
            thisCard.layer.cornerRadius = 8
            thisCard.alpha = 1
            thisCard.accessibilityIdentifier = "valuecard"
            self.addSubview(thisCard)
            
            let thisCardHeight = NSLayoutConstraint(item: thisCard, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
            let thisCardWidth = NSLayoutConstraint(item: thisCard, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 80)
            let thisCardCenterX = NSLayoutConstraint(item: thisCard, attribute: .centerX, relatedBy: .equal, toItem: self, attribute: .leading, multiplier: 1, constant: (actualX + 30))
            let thisCardBottom = NSLayoutConstraint(item: thisCard, attribute: .bottom, relatedBy: .equal, toItem: self, attribute: .bottom, multiplier: 1, constant: -yConstraint)
            self.addConstraints([thisCardBottom, thisCardCenterX])
            thisCard.addConstraints([thisCardHeight, thisCardWidth])
            
            let dateLabel = UILabel()
            dateLabel.translatesAutoresizingMaskIntoConstraints = false
            dateLabel.font = UIFont(name: "Gilroy-Regular", size: 10)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd MMM yyyy"
            dateLabel.text = dateFormatter.string(from: thisDataPoint["date"] as! Date)
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
            priceLabel.font = UIFont(name: "Gilroy-Bold", size: 12)
            var currency = "€"
            if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                currency = "CHF"
            }
            priceLabel.text = currency + " " + self.valueVC!.formatEuroValue("\(Int(thisDataPoint["price"] as! CGFloat))")
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

    func coordYFor(index: Int) -> CGFloat {
        
        //var correction:CGFloat = 0
        //if data[index] == (data.max() ?? 0) { correction = 3 }
        let differenceValueAndMin = data[index] - (data.min() ?? 0)
        let differenceMaxAndMin = (data.max() ?? 0) - (data.min() ?? 0)
        /*if bounds.height - (bounds.height * ((differenceValueAndMin) / (differenceMaxAndMin))) < 3 {
            correction = 3
        } else if bounds.height - (bounds.height * ((differenceValueAndMin) / (differenceMaxAndMin))) > bounds.height - 13 {
            correction = -13
        }*/
        return (bounds.height - 25) - ((bounds.height - 30) * ((differenceValueAndMin) / (differenceMaxAndMin)))
    }

    override func draw(_ rect: CGRect) {
        
        if data.count == 0 {return}
        
        let context = UIGraphicsGetCurrentContext()
        let path:UIBezierPath = quadCurvedPath()
        context!.saveGState()
        context!.setShadow(offset: CGSize(width: 0, height: 9), blur: 15, color: UIColor.black.cgColor)
        context!.setAlpha(0.4)
        UIColor.white.setStroke()
        path.lineWidth = 4
        path.stroke()
        context!.restoreGState()
        
        let path2:UIBezierPath = quadCurvedPath()
        UIColor.white.setStroke()
        path2.lineWidth = 4
        path2.stroke()
    }

    func quadCurvedPath() -> UIBezierPath {
        
        let path = UIBezierPath()
        let step = (bounds.width - 60) / CGFloat(data.count - 1)
        
        var p1 = CGPoint(x: 30, y: coordYFor(index: 0))
        path.move(to: p1)
        
        drawPoint(point: p1, color: UIColor.white, radius: 2)
        
        if (data.count == 2) {
            path.addLine(to: CGPoint(x: step + 30, y: coordYFor(index: 1)))
            return path
        }
        
        var oldControlP:CGPoint?
        
        for i in 1..<data.count {
            
            let p2 = CGPoint(x: step * CGFloat(i) + 30, y: coordYFor(index: i))
            drawPoint(point: p2, color: UIColor.white, radius: 2)
            var p3: CGPoint?
            if i < data.count - 1 {
                p3 = CGPoint(x: step * CGFloat(i + 1) + 30, y: coordYFor(index: i + 1))
            }
            
            let newControlP = controlPointForPoints(p1: p1, p2: p2, next: p3)
            
            path.addCurve(to: p2, controlPoint1: oldControlP ?? p1, controlPoint2: newControlP ?? p2)
            
            p1 = p2
            oldControlP = antipodalFor(point: newControlP, center: p2)
        }
        
        return path;
    }
    
    func antipodalFor(point: CGPoint?, center: CGPoint?) -> CGPoint? {
        guard let p1 = point, let center = center else {
            return nil
        }
        let newX = 2 * center.x - p1.x
        let diffY = abs(p1.y - center.y)
        let newY = center.y + diffY * (p1.y < center.y ? 1 : -1)

        return CGPoint(x: newX, y: newY)
    }

    func midPointForPoints(p1: CGPoint, p2: CGPoint) -> CGPoint {
        return CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2);
    }

    func controlPointForPoints(p1: CGPoint, p2: CGPoint, next p3: CGPoint?) -> CGPoint? {
        guard let p3 = p3 else {
            return nil
        }

        let leftMidPoint  = midPointForPoints(p1: p1, p2: p2)
        let rightMidPoint = midPointForPoints(p1: p2, p2: p3)

        var controlPoint = midPointForPoints(p1: leftMidPoint, p2: antipodalFor(point: rightMidPoint, center: p2)!)

        if p1.y.between(a: p2.y, b: controlPoint.y) {
            controlPoint.y = p1.y
        } else if p2.y.between(a: p1.y, b: controlPoint.y) {
            controlPoint.y = p2.y
        }


        let imaginContol = antipodalFor(point: controlPoint, center: p2)!
        if p2.y.between(a: p3.y, b: imaginContol.y) {
            controlPoint.y = p2.y
        }
        if p3.y.between(a: p2.y, b: imaginContol.y) {
            let diffY = abs(p2.y - p3.y)
            controlPoint.y = p2.y + diffY * (p3.y < p2.y ? 1 : -1)
        }

        // make lines easier
        controlPoint.x += (p2.x - p1.x) * 0.1

        return controlPoint
    }

    func drawPoint(point: CGPoint, color: UIColor, radius: CGFloat) {
        let ovalPath = UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        color.setFill()
        ovalPath.fill()
    }
    
}

extension CGFloat {
    func between(a: CGFloat, b: CGFloat) -> Bool {
        return self >= Swift.min(a, b) && self <= Swift.max(a, b)
    }
}

