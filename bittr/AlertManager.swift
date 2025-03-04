//
//  AlertManager.swift
//  bittr
//
//  Created by Tom Melters on 04/03/2025.
//

import UIKit

extension UIViewController {
    
    func showAlert(title:String, message:String, buttons:[String], actions:[Selector?]?) {
        /*DispatchQueue.main.async {
         let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
         alert.addAction(UIAlertAction(title: alertButton, style: .cancel, handler: nil))
         self.present(alert, animated: true)
         }*/
        
        DispatchQueue.main.async {
            
            // Background
            let darkBackground = UIView()
            darkBackground.translatesAutoresizingMaskIntoConstraints = false
            darkBackground.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
            darkBackground.accessibilityIdentifier = "alertview"
            self.view.addSubview(darkBackground)
            let darkBackgroundTop = NSLayoutConstraint(item: darkBackground, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
            let darkBackgroundBottom = NSLayoutConstraint(item: darkBackground, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            let darkBackgroundLeft = NSLayoutConstraint(item: darkBackground, attribute: .leading, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
            let darkBackgroundRight = NSLayoutConstraint(item: darkBackground, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
            self.view.addConstraints([darkBackgroundTop, darkBackgroundLeft, darkBackgroundRight, darkBackgroundBottom])
            
            // Card
            let yellowCard = UIView()
            yellowCard.translatesAutoresizingMaskIntoConstraints = false
            yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
            yellowCard.layer.cornerRadius = 13
            yellowCard.layer.shadowColor = UIColor.black.cgColor
            yellowCard.layer.shadowOffset = CGSize(width: 0, height: 7)
            yellowCard.layer.shadowRadius = 10.0
            yellowCard.layer.shadowOpacity = 0.1
            yellowCard.clipsToBounds = false
            darkBackground.addSubview(yellowCard)
            let yellowCardCenterY = NSLayoutConstraint(item: yellowCard, attribute: .centerY, relatedBy: .equal, toItem: darkBackground, attribute: .centerY, multiplier: 1, constant: 0)
            let yellowCardLeft = NSLayoutConstraint(item: yellowCard, attribute: .leading, relatedBy: .equal, toItem: darkBackground, attribute: .leading, multiplier: 1, constant: 30)
            let yellowCardRight = NSLayoutConstraint(item: yellowCard, attribute: .trailing, relatedBy: .equal, toItem: darkBackground, attribute: .trailing, multiplier: 1, constant: -30)
            let yellowCardHeight = NSLayoutConstraint(item: yellowCard, attribute: .height, relatedBy: .lessThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: self.view.bounds.height)
            darkBackground.addConstraints([yellowCardCenterY, yellowCardLeft, yellowCardRight])
            yellowCard.addConstraint(yellowCardHeight)
            
            // Icon
            let alertIcon = UIImageView()
            alertIcon.translatesAutoresizingMaskIntoConstraints = false
            alertIcon.contentMode = .scaleAspectFit
            if CacheManager.darkModeIsOn() {
                alertIcon.image = UIImage(named: "iconmailboxyellow")
            } else {
                alertIcon.image = UIImage(named: "iconmailboxwhite")
            }
            yellowCard.addSubview(alertIcon)
            let alertIconTop = NSLayoutConstraint(item: alertIcon, attribute: .top, relatedBy: .equal, toItem: yellowCard, attribute: .top, multiplier: 1, constant: 19)
            let alertIconLeft = NSLayoutConstraint(item: alertIcon, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 20)
            let alertIconHeight = NSLayoutConstraint(item: alertIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 21)
            let alertIconWidth = NSLayoutConstraint(item: alertIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 21)
            yellowCard.addConstraints([alertIconTop, alertIconLeft])
            alertIcon.addConstraints([alertIconHeight, alertIconWidth])
            
            // Header
            let headerLabel = UILabel()
            headerLabel.translatesAutoresizingMaskIntoConstraints = false
            headerLabel.numberOfLines = 1
            headerLabel.font = UIFont(name: "Gilroy-Bold", size: 18)
            headerLabel.text = Language.getWord(withID: "message")
            headerLabel.textColor = Colors.getColor("whiteoryellow")
            yellowCard.addSubview(headerLabel)
            let headerLabelCenterY = NSLayoutConstraint(item: headerLabel, attribute: .centerY, relatedBy: .equal, toItem: alertIcon, attribute: .centerY, multiplier: 1, constant: 0)
            let headerLabelLeft = NSLayoutConstraint(item: headerLabel, attribute: .leading, relatedBy: .equal, toItem: alertIcon, attribute: .trailing, multiplier: 1, constant: 10)
            let headerLabelHeight = NSLayoutConstraint(item: headerLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            let headerLabelWidth = NSLayoutConstraint(item: headerLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            yellowCard.addConstraints([headerLabelCenterY, headerLabelLeft])
            headerLabel.addConstraints([headerLabelHeight, headerLabelWidth])
            
            // Close image
            let closeIcon = UIImageView()
            closeIcon.translatesAutoresizingMaskIntoConstraints = false
            closeIcon.contentMode = .scaleAspectFit
            if CacheManager.darkModeIsOn() {
                closeIcon.image = UIImage(named: "iconcloseyellow")
            } else {
                closeIcon.image = UIImage(named: "iconclosewhite")
            }
            yellowCard.addSubview(closeIcon)
            let closeIconCenterY = NSLayoutConstraint(item: closeIcon, attribute: .centerY, relatedBy: .equal, toItem: alertIcon, attribute: .centerY, multiplier: 1, constant: 0)
            let closeIconRight = NSLayoutConstraint(item: closeIcon, attribute: .trailing, relatedBy: .equal, toItem: yellowCard, attribute: .trailing, multiplier: 1, constant: -20)
            let closeIconHeight = NSLayoutConstraint(item: closeIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 16)
            let closeIconWidth = NSLayoutConstraint(item: closeIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 16)
            yellowCard.addConstraints([closeIconCenterY, closeIconRight])
            closeIcon.addConstraints([closeIconHeight, closeIconWidth])
            
            // Close button
            let closeButton = UIButton()
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            closeButton.setTitle("", for: .normal)
            closeButton.backgroundColor = .clear
            closeButton.addTarget(self, action: #selector(self.hideAlert), for: .touchUpInside)
            if actions == nil {
                closeIcon.alpha = 1
                closeButton.alpha = 1
            } else {
                var theresACancelButton = false
                for eachAction in actions! {
                    if eachAction == nil {
                        theresACancelButton = true
                    }
                }
                // Hide close icon for alerts with a specific function.
                if !theresACancelButton {
                    closeIcon.alpha = 0
                    closeButton.alpha = 0
                }
            }
            yellowCard.addSubview(closeButton)
            let closeButtonCenterX = NSLayoutConstraint(item: closeButton, attribute: .centerX, relatedBy: .equal, toItem: closeIcon, attribute: .centerX, multiplier: 1, constant: 0)
            let closeButtonCenterY = NSLayoutConstraint(item: closeButton, attribute: .centerY, relatedBy: .equal, toItem: closeIcon, attribute: .centerY, multiplier: 1, constant: 0)
            let closeButtonHeight = NSLayoutConstraint(item: closeButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
            let closeButtonWidth = NSLayoutConstraint(item: closeButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
            yellowCard.addConstraints([closeButtonCenterX, closeButtonCenterY])
            closeButton.addConstraints([closeButtonWidth, closeButtonHeight])
            
            // Message title
            let titleLabel = UILabel()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.numberOfLines = 1
            titleLabel.font = UIFont(name: "Gilroy-Bold", size: 16)
            titleLabel.text = title
            titleLabel.textColor = Colors.getColor("blackorwhite")
            titleLabel.textAlignment = .center
            yellowCard.addSubview(titleLabel)
            let titleLabelTop = NSLayoutConstraint(item: titleLabel, attribute: .top, relatedBy: .equal, toItem: alertIcon, attribute: .bottom, multiplier: 1, constant: 25)
            let titleLabelCenterX = NSLayoutConstraint(item: titleLabel, attribute: .centerX, relatedBy: .equal, toItem: yellowCard, attribute: .centerX, multiplier: 1, constant: 0)
            let titleLabelHeight = NSLayoutConstraint(item: titleLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            let titleLabelWidth = NSLayoutConstraint(item: titleLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            yellowCard.addConstraints([titleLabelTop, titleLabelCenterX])
            titleLabel.addConstraints([titleLabelHeight, titleLabelWidth])
            
            // Message
            let messageLabel = UILabel()
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            messageLabel.numberOfLines = 0
            messageLabel.font = UIFont(name: "Gilroy-Regular", size: 16)
            messageLabel.text = message
            messageLabel.textColor = Colors.getColor("blackorwhite")
            messageLabel.textAlignment = .center
            yellowCard.addSubview(messageLabel)
            let messageLabelTop = NSLayoutConstraint(item: messageLabel, attribute: .top, relatedBy: .equal, toItem: titleLabel, attribute: .bottom, multiplier: 1, constant: 8)
            let messageLabelLeft = NSLayoutConstraint(item: messageLabel, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 40)
            let messageLabelRight = NSLayoutConstraint(item: messageLabel, attribute: .trailing, relatedBy: .equal, toItem: yellowCard, attribute: .trailing, multiplier: 1, constant: -40)
            let messageLabelHeight = NSLayoutConstraint(item: messageLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            yellowCard.addConstraints([messageLabelLeft, messageLabelRight, messageLabelTop])
            messageLabel.addConstraints([messageLabelHeight])
            
            // Buttons stack
            let buttonsStack = UIView()
            buttonsStack.translatesAutoresizingMaskIntoConstraints = false
            buttonsStack.clipsToBounds = false
            buttonsStack.backgroundColor = .clear
            yellowCard.addSubview(buttonsStack)
            let buttonsStackHeight = NSLayoutConstraint(item: buttonsStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 50)
            let buttonsStackLeft = NSLayoutConstraint(item: buttonsStack, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 10)
            let buttonsStackRight = NSLayoutConstraint(item: buttonsStack, attribute: .trailing, relatedBy: .equal, toItem: yellowCard, attribute: .trailing, multiplier: 1, constant: -10)
            let buttonsStackBottom = NSLayoutConstraint(item: buttonsStack, attribute: .bottom, relatedBy: .equal, toItem: yellowCard, attribute: .bottom, multiplier: 1, constant: 0)
            let buttonsStackTop = NSLayoutConstraint(item: buttonsStack, attribute: .top, relatedBy: .equal, toItem: messageLabel, attribute: .bottom, multiplier: 1, constant: 35)
            yellowCard.addConstraints([buttonsStackLeft, buttonsStackRight, buttonsStackBottom, buttonsStackTop])
            buttonsStack.addConstraint(buttonsStackHeight)
            
            self.view.layoutIfNeeded()
            
            for (index, eachButton) in buttons.enumerated() {
                
                // Close view
                let closeView = UIView()
                closeView.translatesAutoresizingMaskIntoConstraints = false
                closeView.backgroundColor = Colors.getColor("white0.7orblue1")
                closeView.layer.cornerRadius = 8
                closeView.layer.shadowColor = UIColor.black.cgColor
                closeView.layer.shadowOffset = CGSize(width: 0, height: 7)
                closeView.layer.shadowRadius = 10.0
                closeView.layer.shadowOpacity = 0.1
                closeView.clipsToBounds = false
                buttonsStack.addSubview(closeView)
                let closeViewTop = NSLayoutConstraint(item: closeView, attribute: .top, relatedBy: .equal, toItem: buttonsStack, attribute: .top, multiplier: 1, constant: 0)
                let closeViewBottom = NSLayoutConstraint(item: closeView, attribute: .bottom, relatedBy: .equal, toItem: buttonsStack, attribute: .bottom, multiplier: 1, constant: -10)
                let closeViewHeight = NSLayoutConstraint(item: closeView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
                var leftConstraint:CGFloat = 0
                if buttons.count == 2, index == 1 {
                    leftConstraint = (buttonsStack.bounds.width/2) + 5
                }
                let closeViewLeft = NSLayoutConstraint(item: closeView, attribute: .leading, relatedBy: .equal, toItem: buttonsStack, attribute: .leading, multiplier: 1, constant: leftConstraint)
                var widthConstant:CGFloat = 0
                if buttons.count == 2 {
                    widthConstant = -5
                }
                let closeViewWidth = NSLayoutConstraint(item: closeView, attribute: .width, relatedBy: .equal, toItem: buttonsStack, attribute: .width, multiplier: 1/CGFloat(buttons.count), constant: widthConstant)
                buttonsStack.addConstraints([closeViewTop, closeViewBottom, closeViewLeft, closeViewWidth])
                closeView.addConstraint(closeViewHeight)
                
                // Button label
                let buttonLabel = UILabel()
                buttonLabel.translatesAutoresizingMaskIntoConstraints = false
                buttonLabel.numberOfLines = 1
                buttonLabel.font = UIFont(name: "Gilroy-Bold", size: 16)
                buttonLabel.text = eachButton
                buttonLabel.textColor = Colors.getColor("blackorwhite")
                buttonLabel.textAlignment = .center
                closeView.addSubview(buttonLabel)
                let buttonLabelCenterX = NSLayoutConstraint(item: buttonLabel, attribute: .centerX, relatedBy: .equal, toItem: closeView, attribute: .centerX, multiplier: 1, constant: 0)
                let buttonLabelCenterY = NSLayoutConstraint(item: buttonLabel, attribute: .centerY, relatedBy: .equal, toItem: closeView, attribute: .centerY, multiplier: 1, constant: 1)
                let buttonLabelHeight = NSLayoutConstraint(item: buttonLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                let buttonLabelWidth = NSLayoutConstraint(item: buttonLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                closeView.addConstraints([buttonLabelCenterX, buttonLabelCenterY])
                buttonLabel.addConstraints([buttonLabelHeight, buttonLabelWidth])
                
                // Main button
                let mainButton = UIButton()
                mainButton.translatesAutoresizingMaskIntoConstraints = false
                mainButton.setTitle("", for: .normal)
                mainButton.backgroundColor = .clear
                if actions?[index] == nil {
                    mainButton.addTarget(self, action: #selector(self.hideAlert), for: .touchUpInside)
                } else {
                    mainButton.addTarget(self, action: actions![index]!, for: .touchUpInside)
                }
                buttonsStack.addSubview(mainButton)
                let mainButtonBottom = NSLayoutConstraint(item: mainButton, attribute: .bottom, relatedBy: .equal, toItem: buttonsStack, attribute: .bottom, multiplier: 1, constant: 0)
                let mainButtonLeft = NSLayoutConstraint(item: mainButton, attribute: .leading, relatedBy: .equal, toItem: closeView, attribute: .leading, multiplier: 1, constant: 0)
                let mainButtonRight = NSLayoutConstraint(item: mainButton, attribute: .trailing, relatedBy: .equal, toItem: closeView, attribute: .trailing, multiplier: 1, constant: 0)
                let mainButtonTop = NSLayoutConstraint(item: mainButton, attribute: .top, relatedBy: .equal, toItem: buttonsStack, attribute: .top, multiplier: 1, constant: 0)
                yellowCard.addConstraints([mainButtonTop, mainButtonLeft, mainButtonRight, mainButtonBottom])
            }
            
            self.view.layoutIfNeeded()
        }
    }
    
    @objc func hideAlert() {
        for eachView in self.view.subviews {
            if eachView.accessibilityIdentifier == "alertview" {
                eachView.removeFromSuperview()
            }
        }
    }
}
