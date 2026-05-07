//
//  BottomCurveView.swift
//  bittr
//
//  Created by Tom Melters on 12/11/25.
//

import UIKit

final class BottomCurveView: UIView {
    
    private let shapeLayer = CAShapeLayer()
    
    public var fillColor: UIColor = .yellow {
        didSet {
            shapeLayer.fillColor = fillColor.cgColor
        }
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
        shapeLayer.fillColor = Colors.getColor("yelloworblue3").cgColor
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

        shapeLayer.frame = bounds
        shapeLayer.path = path.cgPath
    }
}
