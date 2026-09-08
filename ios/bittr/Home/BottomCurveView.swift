//
//  BottomCurveView.swift
//  bittr
//
//  Created by Tom Melters on 12/11/25.
//

import UIKit

final class BottomCurveView: UIView {
    
    private let shapeLayer = CAShapeLayer()
    
    public var fillColor: UIColor = .clear {
        didSet {
            Self.withoutImplicitAnimation {
                shapeLayer.fillColor = fillColor.cgColor
            }
        }
    }

    // shapeLayer isn't a view's backing layer, so writes to it pick up whatever
    // animation the current transaction carries — including the one a
    // UIView.animate block is running when layoutSubviews lands inside it.
    private static func withoutImplicitAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        backgroundColor = .clear
        shapeLayer.fillColor = fillColor.cgColor
        layer.addSublayer(shapeLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePath()
    }

    private func updatePath() {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }

        // How “deep” the curve dips – tweak these if you want
        let edgeY = h * 0.15      // y-position of the curve at the left/right edges
        let controlY = h * 1.2    // control point below the view for a nice sag

        let path = UIBezierPath()
        // Top straight edge
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w, y: 0))

        // Right side down
        path.addLine(to: CGPoint(x: w, y: edgeY))

        // Bottom curve from right to left
        path.addQuadCurve(
            to: CGPoint(x: 0, y: edgeY),
            controlPoint: CGPoint(x: w / 2, y: controlY)
        )

        // Left side back up
        path.close()

        // Applied straight away: animating a path from nil draws nothing until
        // the animation ends, which is why the curve only turned up once the
        // container had finished sliding.
        Self.withoutImplicitAnimation {
            shapeLayer.frame = bounds
            shapeLayer.path = path.cgPath
        }
    }
}
