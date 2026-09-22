//
//  GraphLine.swift
//  BittrWidget
//
//  Created by Tom Melters on 21/09/2026.
//

import SwiftUI

// The app's price curve as a SwiftUI shape. WidgetKit can't host a UIView, so
// the widget can't use GraphView itself; both build their path from the same
// GraphCurve geometry, so the line is the one the app draws.
struct GraphLine: Shape {

    let values:[CGFloat]

    // The widget's chart is small, so it sits closer to its edges than the
    // in-app graph does.
    var horizontalInset:CGFloat = 3
    var topInset:CGFloat = 5
    var bottomInset:CGFloat = 5

    func path(in rect: CGRect) -> Path {

        var path = Path()
        let curve = GraphCurve(values: self.values, size: rect.size, horizontalInset: self.horizontalInset, topInset: self.topInset, bottomInset: self.bottomInset)

        guard let start = curve.start else { return path }
        path.move(to: start)

        for eachSegment in curve.segments {
            switch eachSegment {
            case .line(let to):
                path.addLine(to: to)
            case .curve(let to, let control1, let control2):
                path.addCurve(to: to, control1: control1, control2: control2)
            }
        }

        return path
    }
}
