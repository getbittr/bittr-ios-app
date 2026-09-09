//
//  UIView.swift
//  bittr
//
//  Created by Tom Melters on 2/27/26.
//

import UIKit

extension UIView {
    
    func setShadow() {
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.layer.shadowRadius = 10.0
        self.layer.shadowOpacity = 0.1
    }
    
    func addGradient() {
        
        self.layer.sublayers?.removeAll(where: { $0.name == "verticalGradient" })
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = self.bounds
        gradientLayer.name = "verticalGradient"
        
        let colorVisible = Colors.getColor("yelloworblue1").withAlphaComponent(1).cgColor
        let colorTransparent = Colors.getColor("yelloworblue1").withAlphaComponent(0).cgColor
        
        gradientLayer.colors = [colorVisible, colorTransparent]
        
        // Vertical: top → bottom
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint   = CGPoint(x: 0.5, y: 1.0)
        
        self.layer.insertSublayer(gradientLayer, at: 0)
    }
}
