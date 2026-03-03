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
}
