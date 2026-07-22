//
//  UILabel.swift
//  bittr
//
//  Created by Tom Melters on 7/22/26.
//

import UIKit

extension UILabel {
    
    func adjustedFont()->UIFont {
        guard let txt = text else {
            return self.font
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: self.font]
        let attributedString = NSAttributedString(string: txt, attributes: attributes)
        let drawingContext = NSStringDrawingContext()
        drawingContext.minimumScaleFactor = self.minimumScaleFactor
        attributedString.boundingRect(with: bounds.size,
                                      options: [.usesLineFragmentOrigin,.usesFontLeading],
                                      context: drawingContext)

        let fontSize = font.pointSize * drawingContext.actualScaleFactor
        return font.withSize(CGFloat(floor(Double(fontSize))))
    }
    
}
