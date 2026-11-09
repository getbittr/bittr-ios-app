//
//  GraphCurve.swift
//  bittr
//
//  Created by Tom Melters on 21/09/2026.
//

import CoreGraphics

// The smoothed price line, as geometry only. GraphView draws it into a
// UIBezierPath and the widget into a SwiftUI Path, so this hands back control
// points rather than a path of either kind, and the two stay identical.
struct GraphCurve {

    enum Segment {
        case line(to:CGPoint)
        case curve(to:CGPoint, control1:CGPoint, control2:CGPoint)
    }

    // Where the line starts. Nil when there is nothing to draw.
    private(set) var start:CGPoint?

    // Every plotted value, for hosts that mark them.
    private(set) var dots:[CGPoint] = []

    private(set) var segments:[Segment] = []

    init(values:[CGFloat], size:CGSize, horizontalInset:CGFloat, topInset:CGFloat, bottomInset:CGFloat) {

        guard !values.isEmpty else { return }

        let lowest = values.min() ?? 0
        let highest = values.max() ?? 0
        let span = highest - lowest
        let plotHeight = size.height - topInset - bottomInset
        let baseline = size.height - bottomInset

        // A flat series sits halfway up rather than dividing by zero.
        func coordY(_ index:Int) -> CGFloat {
            guard span > 0 else { return baseline - (plotHeight / 2) }
            return baseline - (plotHeight * ((values[index] - lowest) / span))
        }

        guard values.count > 1 else {
            self.dots = [CGPoint(x: horizontalInset, y: coordY(0))]
            return
        }

        let step = (size.width - (horizontalInset * 2)) / CGFloat(values.count - 1)

        func coord(_ index:Int) -> CGPoint {
            return CGPoint(x: step * CGFloat(index) + horizontalInset, y: coordY(index))
        }

        var p1 = coord(0)
        self.start = p1
        self.dots = [p1]

        // Two values are a straight line; there is no curve to shape.
        guard values.count > 2 else {
            self.segments = [.line(to: coord(1))]
            return
        }

        var oldControlP:CGPoint?

        for i in 1..<values.count {

            let p2 = coord(i)
            self.dots += [p2]
            let p3:CGPoint? = i < values.count - 1 ? coord(i + 1) : nil

            let newControlP = GraphCurve.controlPoint(p1: p1, p2: p2, next: p3)
            self.segments += [.curve(to: p2, control1: oldControlP ?? p1, control2: newControlP ?? p2)]

            p1 = p2
            oldControlP = GraphCurve.antipodal(of: newControlP, center: p2)
        }
    }

    static func antipodal(of point:CGPoint?, center:CGPoint?) -> CGPoint? {

        guard let p1 = point, let center = center else {
            return nil
        }
        let newX = 2 * center.x - p1.x
        let diffY = abs(p1.y - center.y)
        let newY = center.y + diffY * (p1.y < center.y ? 1 : -1)

        return CGPoint(x: newX, y: newY)
    }

    static func midPoint(p1:CGPoint, p2:CGPoint) -> CGPoint {
        return CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    }

    static func controlPoint(p1:CGPoint, p2:CGPoint, next p3:CGPoint?) -> CGPoint? {

        guard let p3 = p3 else {
            return nil
        }

        let leftMidPoint  = GraphCurve.midPoint(p1: p1, p2: p2)
        let rightMidPoint = GraphCurve.midPoint(p1: p2, p2: p3)

        var controlPoint = GraphCurve.midPoint(p1: leftMidPoint, p2: GraphCurve.antipodal(of: rightMidPoint, center: p2)!)

        if GraphCurve.isBetween(p1.y, a: p2.y, b: controlPoint.y) {
            controlPoint.y = p1.y
        } else if GraphCurve.isBetween(p2.y, a: p1.y, b: controlPoint.y) {
            controlPoint.y = p2.y
        }

        let imaginContol = GraphCurve.antipodal(of: controlPoint, center: p2)!
        if GraphCurve.isBetween(p2.y, a: p3.y, b: imaginContol.y) {
            controlPoint.y = p2.y
        }
        if GraphCurve.isBetween(p3.y, a: p2.y, b: imaginContol.y) {
            let diffY = abs(p2.y - p3.y)
            controlPoint.y = p2.y + diffY * (p3.y < p2.y ? 1 : -1)
        }

        // make lines easier
        controlPoint.x += (p2.x - p1.x) * 0.1

        return controlPoint
    }

    // Spelled out here rather than using the app's CGFloat.between, which the
    // widget target doesn't compile.
    static func isBetween(_ value:CGFloat, a:CGFloat, b:CGFloat) -> Bool {
        return value >= Swift.min(a, b) && value <= Swift.max(a, b)
    }
}
