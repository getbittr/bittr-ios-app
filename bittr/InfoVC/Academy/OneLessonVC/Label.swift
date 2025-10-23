//
//  Label.swift
//  bittr
//
//  Created by Tom Melters on 10/23/25.
//

import UIKit

extension OneLessonViewController {
    
    func addLabel(withText:String, previousComponent:ComponentType?) {
        
        let thisLabel = UILabel()
        thisLabel.font = UIFont(name: "Gilroy-Regular", size: 18)
        thisLabel.text = withText
        thisLabel.numberOfLines = 0
        thisLabel.translatesAutoresizingMaskIntoConstraints = false
        thisLabel.textAlignment = .center
        thisLabel.textColor = Colors.getColor("blackorwhite")
        self.centerView.addSubview(thisLabel)
        
        var topSpacing:CGFloat = 0
        if previousComponent != nil {
            switch previousComponent! {
            case .label:
                topSpacing = 30
            }
        }
        
        let labelTop = NSLayoutConstraint(item: thisLabel, attribute: .top, relatedBy: .equal, toItem: self.centerView, attribute: .top, multiplier: 1, constant: self.heightFromTop + topSpacing)
        let labelLeft = NSLayoutConstraint(item: thisLabel, attribute: .leading, relatedBy: .equal, toItem: self.centerView, attribute: .leading, multiplier: 1, constant: 35)
        let labelRight = NSLayoutConstraint(item: thisLabel, attribute: .trailing, relatedBy: .equal, toItem: self.centerView, attribute: .trailing, multiplier: 1, constant: -35)
        let labelHeight = NSLayoutConstraint(item: thisLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        
        thisLabel.addConstraint(labelHeight)
        self.centerView.addConstraints([labelTop, labelLeft, labelRight])
        
        self.centerView.layoutIfNeeded()
        self.heightFromTop += (thisLabel.frame.height + topSpacing)
        
    }
}
