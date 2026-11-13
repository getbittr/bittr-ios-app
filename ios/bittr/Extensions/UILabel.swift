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

// Groups its text in fours for its own width, and again whenever that width changes.
class GroupedLabel: UILabel {
    
    private var grouping:(text:String, lines:Int, trailing:Bool)?
    private var groupedWidth:CGFloat = 0
    private var isGrouping = false
    
    // Plain text ends the grouping.
    override var text: String? {
        didSet { if !self.isGrouping { self.grouping = nil } }
    }
    override var attributedText: NSAttributedString? {
        didSet { if !self.isGrouping { self.grouping = nil } }
    }
    
    func setGroupedText(_ text:String, lines:Int = .max, trailing:Bool = false) {
        self.grouping = (text, lines, trailing)
        self.groupedWidth = 0
        self.applyGrouping()
        self.setNeedsLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.applyGrouping()
    }
    
    private func applyGrouping() {
        guard let grouping, self.bounds.width > 0, self.bounds.width != self.groupedWidth else { return }
        self.groupedWidth = self.bounds.width
        self.isGrouping = true
        self.attributedText = grouping.text.inGroupsOfFour(width: self.bounds.width, lines: grouping.lines, font: self.font, color: self.textColor, trailing: grouping.trailing)
        self.isGrouping = false
    }
}
