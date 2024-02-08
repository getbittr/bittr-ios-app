//
//  GraphView.swift
//  bittr
//
//  Created by Tom Melters on 12/04/2023.
//

import UIKit

class GraphView: UIView {

    var data:[CGFloat] = [25418, 27711, 27474, 26938, 25767, 25092, 25710, 26286, 26018, 26339, 25793] {
        didSet {
            setNeedsDisplay()
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
