//
//  UILabel.swift
//  bittr
//
//  Created by Tom Melters on 9/23/26.
//

import UIKit
import Foundation

extension UILabel {
    
    func setText(_ text:String) {
        
        let lineHeight = font.pointSize * 1.3
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.alignment = textAlignment
        
        attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font as Any,
                .foregroundColor: textColor as Any,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
    
}
