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
        thisLabel.numberOfLines = 0
        thisLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let textColor = CacheManager.darkModeIsOn() ? "255, 255, 255" : "0, 0, 0"
        let htmlText = ("<center><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 18; color: rgb(\(textColor)); line-height: 1.2\">" + withText + "</span></center>").replacingOccurrences(of: "<b>", with: "</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: 18; color: rgb(\(textColor)); line-height: 1.2\">").replacingOccurrences(of: "</b>", with: "</span><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 18; color: rgb(\(textColor)); line-height: 1.2\">")
        
        if let htmlData = htmlText.data(using: .unicode) {
            do {
                let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                thisLabel.attributedText = attributedText
            } catch {
                print("Could not parse HTML text.")
                thisLabel.textColor = Colors.getColor("blackorwhite")
                thisLabel.textAlignment = .center
                thisLabel.font = UIFont(name: "Gilroy-Regular", size: 18)
                thisLabel.text = withText
            }
        } else {
            print("Could not parse HTML text.")
            thisLabel.textColor = Colors.getColor("blackorwhite")
            thisLabel.textAlignment = .center
            thisLabel.font = UIFont(name: "Gilroy-Regular", size: 18)
            thisLabel.text = withText
        }
        
        self.centerView.addSubview(thisLabel)
        
        var topSpacing:CGFloat = 0
        if previousComponent != nil {
            switch previousComponent! {
            case .label:
                topSpacing = 15
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
