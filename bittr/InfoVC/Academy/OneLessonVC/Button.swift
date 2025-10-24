//
//  Button.swift
//  bittr
//
//  Created by Tom Melters on 10/23/25.
//

import UIKit

extension OneLessonViewController {
    
    func addButton(previousComponent:ComponentType?, firstPage:Bool, lastPage:Bool) {
        
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.translatesAutoresizingMaskIntoConstraints = false
        self.centerView.addSubview(containerView)
        
        var topSpacing:CGFloat = 0
        if previousComponent != nil {
            switch previousComponent! {
            case .label:
                topSpacing = 20
            case .image:
                topSpacing = 40
            }
        }
        let buttonHeight:CGFloat = 40
        
        let containerViewTop = NSLayoutConstraint(item: containerView, attribute: .top, relatedBy: .equal, toItem: self.centerView, attribute: .top, multiplier: 1, constant: self.heightFromTop + topSpacing)
        let containerViewCenterX = NSLayoutConstraint(item: containerView, attribute: .centerX, relatedBy: .equal, toItem: self.centerView, attribute: .centerX, multiplier: 1, constant: 0)
        let containerViewBottom = NSLayoutConstraint(item: containerView, attribute: .bottom, relatedBy: .equal, toItem: self.centerView, attribute: .bottom, multiplier: 1, constant: 0)
        let containerViewHeight = NSLayoutConstraint(item: containerView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: buttonHeight)
        let containerViewWidth = NSLayoutConstraint(item: containerView, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        
        containerView.addConstraints([containerViewHeight, containerViewWidth])
        self.centerView.addConstraints([containerViewTop, containerViewCenterX, containerViewBottom])
        
        let backButtonStack = UIView()
        backButtonStack.backgroundColor = .clear
        backButtonStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(backButtonStack)
        
        let backButtonStackLeft = NSLayoutConstraint(item: backButtonStack, attribute: .leading, relatedBy: .equal, toItem: containerView, attribute: .leading, multiplier: 1, constant: 0)
        let backButtonStackTop = NSLayoutConstraint(item: backButtonStack, attribute: .top, relatedBy: .equal, toItem: containerView, attribute: .top, multiplier: 1, constant: 0)
        let backButtonStackBottom = NSLayoutConstraint(item: backButtonStack, attribute: .bottom, relatedBy: .equal, toItem: containerView, attribute: .bottom, multiplier: 1, constant: 0)
        let backButtonStackWidth = NSLayoutConstraint(item: backButtonStack, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: firstPage ? 0 : (buttonHeight + 7))
        
        backButtonStack.addConstraint(backButtonStackWidth)
        containerView.addConstraints([backButtonStackLeft, backButtonStackTop, backButtonStackBottom])
        
        if !firstPage {
            let backButtonView = UIView()
            backButtonView.backgroundColor = .black
            backButtonView.translatesAutoresizingMaskIntoConstraints = false
            backButtonView.layer.cornerRadius = 8
            backButtonStack.addSubview(backButtonView)
            
            let backButtonViewTop = NSLayoutConstraint(item: backButtonView, attribute: .top, relatedBy: .equal, toItem: backButtonStack, attribute: .top, multiplier: 1, constant: 0)
            let backButtonViewLeft = NSLayoutConstraint(item: backButtonView, attribute: .leading, relatedBy: .equal, toItem: backButtonStack, attribute: .leading, multiplier: 1, constant: 0)
            let backButtonViewBottom = NSLayoutConstraint(item: backButtonView, attribute: .bottom, relatedBy: .equal, toItem: backButtonStack, attribute: .bottom, multiplier: 1, constant: 0)
            let backButtonViewWidth = NSLayoutConstraint(item: backButtonView, attribute: .width, relatedBy: .equal, toItem: backButtonStack, attribute: .height, multiplier: 1, constant: 0)
            
            backButtonStack.addConstraints([backButtonViewTop, backButtonViewLeft, backButtonViewBottom, backButtonViewWidth])
            
            
            let previousIcon = UIImageView()
            previousIcon.image = UIImage(named: "arrowleftwhite")
            previousIcon.translatesAutoresizingMaskIntoConstraints = false
            previousIcon.contentMode = .scaleAspectFit
            backButtonView.addSubview(previousIcon)
            
            let previousIconHeight = NSLayoutConstraint(item: previousIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 11)
            let previousIconWidth = NSLayoutConstraint(item: previousIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 11)
            let previousIconCenterX = NSLayoutConstraint(item: previousIcon, attribute: .centerX, relatedBy: .equal, toItem: backButtonView, attribute: .centerX, multiplier: 1, constant: 0)
            let previousIconCenterY = NSLayoutConstraint(item: previousIcon, attribute: .centerY, relatedBy: .equal, toItem: backButtonView, attribute: .centerY, multiplier: 1, constant: 0)
            
            previousIcon.addConstraints([previousIconWidth, previousIconHeight])
            backButtonView.addConstraints([previousIconCenterX, previousIconCenterY])
            
            
            let previousButton = UIButton()
            previousButton.setTitle("", for: .normal)
            previousButton.isUserInteractionEnabled = true
            previousButton.translatesAutoresizingMaskIntoConstraints = false
            previousButton.addTarget(self, action: #selector(self.previousPage), for: .touchUpInside)
            backButtonView.addSubview(previousButton)
            
            let previousButtonTop = NSLayoutConstraint(item: previousButton, attribute: .top, relatedBy: .equal, toItem: backButtonView, attribute: .top, multiplier: 1, constant: 0)
            let previousButtonBottom = NSLayoutConstraint(item: previousButton, attribute: .bottom, relatedBy: .equal, toItem: backButtonView, attribute: .bottom, multiplier: 1, constant: 0)
            let previousButtonLeft = NSLayoutConstraint(item: previousButton, attribute: .leading, relatedBy: .equal, toItem: backButtonView, attribute: .leading, multiplier: 1, constant: 0)
            let previousButtonRight = NSLayoutConstraint(item: previousButton, attribute: .trailing, relatedBy: .equal, toItem: backButtonView, attribute: .trailing, multiplier: 1, constant: 0)
            
            backButtonView.addConstraints([previousButtonTop, previousButtonLeft, previousButtonRight, previousButtonBottom])
        }
        
        let nextButtonView = UIView()
        nextButtonView.backgroundColor = .black
        nextButtonView.translatesAutoresizingMaskIntoConstraints = false
        nextButtonView.layer.cornerRadius = 8
        containerView.addSubview(nextButtonView)
        
        let nextButtonViewTop = NSLayoutConstraint(item: nextButtonView, attribute: .top, relatedBy: .equal, toItem: containerView, attribute: .top, multiplier: 1, constant: 0)
        let nextButtonViewBottom = NSLayoutConstraint(item: nextButtonView, attribute: .bottom, relatedBy: .equal, toItem: containerView, attribute: .bottom, multiplier: 1, constant: 0)
        let nextButtonViewRight = NSLayoutConstraint(item: nextButtonView, attribute: .trailing, relatedBy: .equal, toItem: containerView, attribute: .trailing, multiplier: 1, constant: 0)
        let nextButtonViewLeft = NSLayoutConstraint(item: nextButtonView, attribute: .leading, relatedBy: .equal, toItem: backButtonStack, attribute: .trailing, multiplier: 1, constant: 0)
        let nextButtonViewWidth = NSLayoutConstraint(item: nextButtonView, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        
        nextButtonView.addConstraints([nextButtonViewWidth])
        containerView.addConstraints([nextButtonViewTop, nextButtonViewBottom, nextButtonViewRight, nextButtonViewLeft])
        
        let nextLabel = UILabel()
        nextLabel.font = UIFont(name: "Gilroy-Bold", size: 14)
        nextLabel.text = lastPage ? "Complete" : "Next"
        nextLabel.translatesAutoresizingMaskIntoConstraints = false
        nextLabel.numberOfLines = 1
        nextLabel.textColor = .white
        nextButtonView.addSubview(nextLabel)
        
        let nextLabelCenterY = NSLayoutConstraint(item: nextLabel, attribute: .centerY, relatedBy: .equal, toItem: nextButtonView, attribute: .centerY, multiplier: 1, constant: 1)
        let nextLabelWidth = NSLayoutConstraint(item: nextLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        let nextLabelHeight = NSLayoutConstraint(item: nextLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        let nextLabelLeft = NSLayoutConstraint(item: nextLabel, attribute: .leading, relatedBy: .equal, toItem: nextButtonView, attribute: .leading, multiplier: 1, constant: 17)
        
        nextLabel.addConstraints([nextLabelHeight, nextLabelWidth])
        nextButtonView.addConstraints([nextLabelLeft, nextLabelCenterY])
        
        let nextIcon = UIImageView()
        nextIcon.image = UIImage(named: "arrowrightwhite")
        nextIcon.translatesAutoresizingMaskIntoConstraints = false
        nextIcon.contentMode = .scaleAspectFit
        nextIcon.alpha = lastPage ? 0 : 1
        nextButtonView.addSubview(nextIcon)
        
        let nextIconHeight = NSLayoutConstraint(item: nextIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 11)
        let nextIconWidth = NSLayoutConstraint(item: nextIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: lastPage ? 0 : 11)
        let nextIconCenterY = NSLayoutConstraint(item: nextIcon, attribute: .centerY, relatedBy: .equal, toItem: nextButtonView, attribute: .centerY, multiplier: 1, constant: 0)
        let nextIconRight = NSLayoutConstraint(item: nextIcon, attribute: .trailing, relatedBy: .equal, toItem: nextButtonView, attribute: .trailing, multiplier: 1, constant: -17)
        let nextIconLeft = NSLayoutConstraint(item: nextIcon, attribute: .leading, relatedBy: .equal, toItem: nextLabel, attribute: .trailing, multiplier: 1, constant: lastPage ? 0 : 10)
        
        nextIcon.addConstraints([nextIconWidth, nextIconHeight])
        nextButtonView.addConstraints([nextIconLeft, nextIconRight, nextIconCenterY])
        
        let nextButton = UIButton()
        nextButton.setTitle("", for: .normal)
        nextButton.isUserInteractionEnabled = true
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.addTarget(self, action: #selector(self.nextPage), for: .touchUpInside)
        nextButtonView.addSubview(nextButton)
        
        let nextButtonTop = NSLayoutConstraint(item: nextButton, attribute: .top, relatedBy: .equal, toItem: nextButtonView, attribute: .top, multiplier: 1, constant: 0)
        let nextButtonBottom = NSLayoutConstraint(item: nextButton, attribute: .bottom, relatedBy: .equal, toItem: nextButtonView, attribute: .bottom, multiplier: 1, constant: 0)
        let nextButtonLeft = NSLayoutConstraint(item: nextButton, attribute: .leading, relatedBy: .equal, toItem: nextButtonView, attribute: .leading, multiplier: 1, constant: 0)
        let nextButtonRight = NSLayoutConstraint(item: nextButton, attribute: .trailing, relatedBy: .equal, toItem: nextButtonView, attribute: .trailing, multiplier: 1, constant: 0)
        
        nextButtonView.addConstraints([nextButtonTop, nextButtonLeft, nextButtonRight, nextButtonBottom])
        
        self.centerView.layoutIfNeeded()
    }
}
