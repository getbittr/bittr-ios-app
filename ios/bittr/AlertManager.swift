//
//  AlertManager.swift
//  bittr
//
//  Created by Tom Melters on 04/03/2025.
//

import UIKit
import ObjectiveC.runtime

private var thisVC:UIViewController?

private struct AlertManagerAssociatedKeys {
    static var bottomConstraint: UInt8 = 0
    static var loadingBottomConstraint: UInt8 = 0
    static var keyboardObservers: UInt8 = 0
}

private extension UIView {
    var alertBottomConstraint: NSLayoutConstraint? {
        get { objc_getAssociatedObject(self, &AlertManagerAssociatedKeys.bottomConstraint) as? NSLayoutConstraint }
        set { objc_setAssociatedObject(self, &AlertManagerAssociatedKeys.bottomConstraint, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    // Stashes the loading overlay's bottom constraint so hideLoading() can
    // animate the card back down (same technique as the alert above).
    var loadingBottomConstraint: NSLayoutConstraint? {
        get { objc_getAssociatedObject(self, &AlertManagerAssociatedKeys.loadingBottomConstraint) as? NSLayoutConstraint }
        set { objc_setAssociatedObject(self, &AlertManagerAssociatedKeys.loadingBottomConstraint, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    // Holds the keyboard-notification tokens for a text-field alert so they can
    // be torn down when the alert is dismissed (see showTextFieldAlert/hideAlert).
    var keyboardObserverTokens: [NSObjectProtocol]? {
        get { objc_getAssociatedObject(self, &AlertManagerAssociatedKeys.keyboardObservers) as? [NSObjectProtocol] }
        set { objc_setAssociatedObject(self, &AlertManagerAssociatedKeys.keyboardObservers, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

/// Adopted by the send/swap screens, which both show the on-chain (BDK) sync
/// spinner and surface the same alert when that sync can't complete. Constrained
/// to UIViewController so the default implementation can use showAlert/hideAlert.
protocol OnchainSyncFailureReporting: UIViewController {
    var bdkSpinner: UIActivityIndicatorView! { get }
}

extension OnchainSyncFailureReporting {
    /// Stops the on-chain sync spinner and tells the user the on-chain sync
    /// failed and to retry later. Safe to call from any thread — BDK completions
    /// fire off the main thread.
    func presentOnchainSyncFailedAlert() {
        DispatchQueue.main.async {
            self.bdkSpinner.stopAnimating()
            // Replace the "syncing" alert (if still visible) with the failure alert.
            self.hideAlert()
            self.showAlert(
                presentingController: self,
                title: Language.getWord(withID: "onchainsyncfailedtitle"),
                message: Language.getWord(withID: "onchainsyncfailed"),
                buttons: [Language.getWord(withID: "okay")],
                actions: nil
            )
        }
    }
}

extension UIViewController {

    func showAlert(presentingController:UIViewController, title:String, message:String, buttons:[String], actions:[Selector?]?) {
        
        thisVC = presentingController
        
        DispatchQueue.main.async {
            
            // Background
            let darkBackground = UIView()
            darkBackground.translatesAutoresizingMaskIntoConstraints = false
            darkBackground.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
            darkBackground.boundString = "alertview"
            presentingController.view.addSubview(darkBackground)
            let darkBackgroundTop = NSLayoutConstraint(item: darkBackground, attribute: .top, relatedBy: .equal, toItem: presentingController.view, attribute: .top, multiplier: 1, constant: 0)
            let darkBackgroundBottom = NSLayoutConstraint(item: darkBackground, attribute: .bottom, relatedBy: .equal, toItem: presentingController.view, attribute: .bottom, multiplier: 1, constant: 0)
            let darkBackgroundLeft = NSLayoutConstraint(item: darkBackground, attribute: .leading, relatedBy: .equal, toItem: presentingController.view, attribute: .leading, multiplier: 1, constant: 0)
            let darkBackgroundRight = NSLayoutConstraint(item: darkBackground, attribute: .trailing, relatedBy: .equal, toItem: presentingController.view, attribute: .trailing, multiplier: 1, constant: 0)
            presentingController.view.addConstraints([darkBackgroundTop, darkBackgroundLeft, darkBackgroundRight, darkBackgroundBottom])
            darkBackground.alertBottomConstraint = darkBackgroundBottom
            
            // Card
            let yellowCard = UIView()
            yellowCard.translatesAutoresizingMaskIntoConstraints = false
            yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
            yellowCard.layer.cornerRadius = 13
            yellowCard.setShadow()
            yellowCard.clipsToBounds = false
            darkBackground.addSubview(yellowCard)
            let yellowCardTop = NSLayoutConstraint(item: yellowCard, attribute: .top, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: 0)
            var yellowCardBottom = NSLayoutConstraint()
            let yellowCardLeft = NSLayoutConstraint(item: yellowCard, attribute: .leading, relatedBy: .equal, toItem: darkBackground, attribute: .leading, multiplier: 1, constant: 10)
            let yellowCardRight = NSLayoutConstraint(item: yellowCard, attribute: .trailing, relatedBy: .equal, toItem: darkBackground, attribute: .trailing, multiplier: 1, constant: -10)
            let yellowCardHeight = NSLayoutConstraint(item: yellowCard, attribute: .height, relatedBy: .lessThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: presentingController.view.bounds.height)
            darkBackground.addConstraints([yellowCardTop, yellowCardLeft, yellowCardRight, yellowCardBottom])
            yellowCard.addConstraint(yellowCardHeight)
            
            // Icon
            let alertIcon = UIImageView()
            alertIcon.translatesAutoresizingMaskIntoConstraints = false
            alertIcon.contentMode = .scaleAspectFit
            if CacheManager.darkModeIsOn() {
                alertIcon.image = UIImage(named: "iconbellyellow")
            } else {
                alertIcon.image = UIImage(named: "iconbellwhite")
            }
            yellowCard.addSubview(alertIcon)
            let alertIconTop = NSLayoutConstraint(item: alertIcon, attribute: .top, relatedBy: .equal, toItem: yellowCard, attribute: .top, multiplier: 1, constant: 19)
            let alertIconLeft = NSLayoutConstraint(item: alertIcon, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 20)
            let alertIconHeight = NSLayoutConstraint(item: alertIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 17)
            let alertIconWidth = NSLayoutConstraint(item: alertIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 17)
            yellowCard.addConstraints([alertIconTop, alertIconLeft])
            alertIcon.addConstraints([alertIconHeight, alertIconWidth])
            
            // Header
            let headerLabel = UILabel()
            headerLabel.translatesAutoresizingMaskIntoConstraints = false
            headerLabel.numberOfLines = 1
            headerLabel.font = UIFont(name: "Gilroy-Bold", size: 18)
            headerLabel.text = title.lowercased()
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
            let closeIconHeight = NSLayoutConstraint(item: closeIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 14)
            let closeIconWidth = NSLayoutConstraint(item: closeIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 14)
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
            
            // Message
            let messageLabel = UILabel()
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            messageLabel.numberOfLines = 0
            messageLabel.attributedText = message.attributed()
            yellowCard.addSubview(messageLabel)
            let messageLabelTop = NSLayoutConstraint(item: messageLabel, attribute: .top, relatedBy: .equal, toItem: alertIcon, attribute: .bottom, multiplier: 1, constant: 25)
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
            let buttonsStackHeight:NSLayoutConstraint = {
                if buttons.count < 3 {
                    return NSLayoutConstraint(item: buttonsStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 50)
                } else {
                    return NSLayoutConstraint(item: buttonsStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 50*CGFloat(buttons.count))
                }
            }()
            let buttonsStackLeft = NSLayoutConstraint(item: buttonsStack, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 15)
            let buttonsStackRight = NSLayoutConstraint(item: buttonsStack, attribute: .trailing, relatedBy: .equal, toItem: yellowCard, attribute: .trailing, multiplier: 1, constant: -15)
            let buttonsStackBottom = NSLayoutConstraint(item: buttonsStack, attribute: .bottom, relatedBy: .equal, toItem: yellowCard, attribute: .bottom, multiplier: 1, constant: -5)
            let buttonsStackTop = NSLayoutConstraint(item: buttonsStack, attribute: .top, relatedBy: .equal, toItem: messageLabel, attribute: .bottom, multiplier: 1, constant: 25)
            yellowCard.addConstraints([buttonsStackLeft, buttonsStackRight, buttonsStackBottom, buttonsStackTop])
            buttonsStack.addConstraint(buttonsStackHeight)
            
            presentingController.view.layoutIfNeeded()
            
            for (index, eachButton) in buttons.enumerated() {
                
                // Close view
                let closeView = UIView()
                closeView.translatesAutoresizingMaskIntoConstraints = false
                closeView.backgroundColor = Colors.getColor("white0.7orblue1")
                closeView.layer.cornerRadius = 8
                closeView.setShadow()
                closeView.clipsToBounds = false
                buttonsStack.addSubview(closeView)
                
                let closeViewHeight = NSLayoutConstraint(item: closeView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
                
                let closeViewWidth:NSLayoutConstraint = {
                    if buttons.count == 2 {
                        return NSLayoutConstraint(item: closeView, attribute: .width, relatedBy: .equal, toItem: buttonsStack, attribute: .width, multiplier: 0.5, constant: -5)
                    } else {
                        return NSLayoutConstraint(item: closeView, attribute: .width, relatedBy: .equal, toItem: buttonsStack, attribute: .width, multiplier: 1, constant: 0)
                    }
                }()
                
                let closeViewLeft:NSLayoutConstraint = {
                    if buttons.count == 2, index == 1 {
                        return NSLayoutConstraint(item: closeView, attribute: .leading, relatedBy: .equal, toItem: buttonsStack, attribute: .leading, multiplier: 1, constant: (buttonsStack.bounds.width/2) + 5)
                    } else {
                        return NSLayoutConstraint(item: closeView, attribute: .leading, relatedBy: .equal, toItem: buttonsStack, attribute: .leading, multiplier: 1, constant: 0)
                    }
                }()
                
                let closeViewBottom:NSLayoutConstraint = {
                    if buttons.count > 2, index > 0 {
                        return NSLayoutConstraint(item: closeView, attribute: .bottom, relatedBy: .equal, toItem: buttonsStack, attribute: .bottom, multiplier: 1, constant: CGFloat(index)*(-50) - 10)
                    } else {
                        return NSLayoutConstraint(item: closeView, attribute: .bottom, relatedBy: .equal, toItem: buttonsStack, attribute: .bottom, multiplier: 1, constant: -10)
                    }
                }()
                
                buttonsStack.addConstraints([closeViewBottom, closeViewLeft, closeViewWidth])
                closeView.addConstraint(closeViewHeight)
                
                // Button label
                let buttonLabel = UILabel()
                buttonLabel.translatesAutoresizingMaskIntoConstraints = false
                buttonLabel.numberOfLines = 1
                buttonLabel.font = UIFont(name: "Gilroy-Bold", size: 16)
                buttonLabel.text = eachButton
                buttonLabel.textColor = Colors.getColor("blackorwhite")
                buttonLabel.textAlignment = .center
                buttonLabel.isAccessibilityElement = false
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
                mainButton.accessibilityLabel = eachButton
                mainButton.accessibilityIdentifier = "alert.button.\(index)"
                if actions?[index] == nil {
                    mainButton.addTarget(self, action: #selector(self.hideAlert), for: .touchUpInside)
                } else {
                    mainButton.addTarget(self, action: actions![index]!, for: .touchUpInside)
                }
                buttonsStack.addSubview(mainButton)
                let mainButtonBottom = NSLayoutConstraint(item: mainButton, attribute: .bottom, relatedBy: .equal, toItem: closeView, attribute: .bottom, multiplier: 1, constant: 0)
                let mainButtonLeft = NSLayoutConstraint(item: mainButton, attribute: .leading, relatedBy: .equal, toItem: closeView, attribute: .leading, multiplier: 1, constant: 0)
                let mainButtonRight = NSLayoutConstraint(item: mainButton, attribute: .trailing, relatedBy: .equal, toItem: closeView, attribute: .trailing, multiplier: 1, constant: 0)
                let mainButtonTop = NSLayoutConstraint(item: mainButton, attribute: .top, relatedBy: .equal, toItem: closeView, attribute: .top, multiplier: 1, constant: 0)
                yellowCard.addConstraints([mainButtonTop, mainButtonLeft, mainButtonRight, mainButtonBottom])
            }
            
            presentingController.view.layoutIfNeeded()
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                darkBackground.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
                NSLayoutConstraint.deactivate([yellowCardTop])
                yellowCardBottom = NSLayoutConstraint(item: yellowCard, attribute: .bottom, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: -presentingController.view.safeAreaInsets.bottom - 15)
                NSLayoutConstraint.activate([yellowCardBottom])
                presentingController.view.layoutIfNeeded()
            }) { _ in
                UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                    NSLayoutConstraint.deactivate([yellowCardBottom])
                    yellowCardBottom = NSLayoutConstraint(item: yellowCard, attribute: .bottom, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: -presentingController.view.safeAreaInsets.bottom)
                    NSLayoutConstraint.activate([yellowCardBottom])
                    presentingController.view.layoutIfNeeded()
                }
            }
        }
    }
    
    @objc func hideAlert() {
        if thisVC != nil {
            for eachView in thisVC!.view.subviews {
                if eachView.boundString == "alertview" {
                    // Tear down any keyboard observers a text-field alert registered.
                    if let tokens = eachView.keyboardObserverTokens {
                        tokens.forEach { NotificationCenter.default.removeObserver($0) }
                        eachView.keyboardObserverTokens = nil
                    }
                    if eachView.subviews.count == 1, let yellowCard = eachView.subviews.first, var darkBackgroundBottom = eachView.alertBottomConstraint {
                        
                        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                            eachView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
                            
                            NSLayoutConstraint.deactivate([darkBackgroundBottom])
                            darkBackgroundBottom = NSLayoutConstraint(item: eachView, attribute: .bottom, relatedBy: .equal, toItem: thisVC!.view, attribute: .bottom, multiplier: 1, constant: yellowCard.frame.height + thisVC!.view.safeAreaInsets.bottom)
                            NSLayoutConstraint.activate([darkBackgroundBottom])
                            thisVC!.view.layoutIfNeeded()
                        }) { _ in
                            eachView.removeFromSuperview()
                        }
                    } else {
                        eachView.removeFromSuperview()
                    }
                }
            }
        } else {
            thisVC = self
            self.hideAlert()
        }
    }

    /// A custom input alert with the same card + slide-up look as `showAlert`,
    /// but containing a single text field styled like the Transfer2 OTP field
    /// (white rounded container, Gilroy-Regular black text) and Cancel/Save
    /// buttons. The card lifts above the keyboard while editing. The entered
    /// text is handed back via `onSave` (the caller decides what to do with it);
    /// dismissal reuses `hideAlert`. Buttons carry the same `alert.button.<index>`
    /// identifiers as `showAlert` (0 = cancel, 1 = save) and the field is
    /// addressable as `alert.textField`.
    func showTextFieldAlert(presentingController: UIViewController,
                            title: String,
                            initialText: String,
                            placeholder: String,
                            cancelTitle: String,
                            saveTitle: String,
                            onSave: @escaping (String) -> Void) {

        thisVC = presentingController

        DispatchQueue.main.async {

            // Background — same "alertview" marker so hideAlert can dismiss it.
            let darkBackground = UIView()
            darkBackground.translatesAutoresizingMaskIntoConstraints = false
            darkBackground.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
            darkBackground.boundString = "alertview"
            presentingController.view.addSubview(darkBackground)
            let darkBackgroundTop = NSLayoutConstraint(item: darkBackground, attribute: .top, relatedBy: .equal, toItem: presentingController.view, attribute: .top, multiplier: 1, constant: 0)
            let darkBackgroundBottom = NSLayoutConstraint(item: darkBackground, attribute: .bottom, relatedBy: .equal, toItem: presentingController.view, attribute: .bottom, multiplier: 1, constant: 0)
            let darkBackgroundLeft = NSLayoutConstraint(item: darkBackground, attribute: .leading, relatedBy: .equal, toItem: presentingController.view, attribute: .leading, multiplier: 1, constant: 0)
            let darkBackgroundRight = NSLayoutConstraint(item: darkBackground, attribute: .trailing, relatedBy: .equal, toItem: presentingController.view, attribute: .trailing, multiplier: 1, constant: 0)
            presentingController.view.addConstraints([darkBackgroundTop, darkBackgroundLeft, darkBackgroundRight, darkBackgroundBottom])
            darkBackground.alertBottomConstraint = darkBackgroundBottom

            // Card
            let yellowCard = UIView()
            yellowCard.translatesAutoresizingMaskIntoConstraints = false
            yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
            yellowCard.layer.cornerRadius = 13
            yellowCard.setShadow()
            yellowCard.clipsToBounds = false
            darkBackground.addSubview(yellowCard)
            let yellowCardTop = NSLayoutConstraint(item: yellowCard, attribute: .top, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: 0)
            var yellowCardBottom = NSLayoutConstraint()
            let yellowCardLeft = NSLayoutConstraint(item: yellowCard, attribute: .leading, relatedBy: .equal, toItem: darkBackground, attribute: .leading, multiplier: 1, constant: 10)
            let yellowCardRight = NSLayoutConstraint(item: yellowCard, attribute: .trailing, relatedBy: .equal, toItem: darkBackground, attribute: .trailing, multiplier: 1, constant: -10)
            darkBackground.addConstraints([yellowCardTop, yellowCardLeft, yellowCardRight])

            // Icon
            let alertIcon = UIImageView()
            alertIcon.translatesAutoresizingMaskIntoConstraints = false
            alertIcon.contentMode = .scaleAspectFit
            alertIcon.image = UIImage(named: CacheManager.darkModeIsOn() ? "iconbellyellow" : "iconbellwhite")
            yellowCard.addSubview(alertIcon)
            let alertIconTop = NSLayoutConstraint(item: alertIcon, attribute: .top, relatedBy: .equal, toItem: yellowCard, attribute: .top, multiplier: 1, constant: 19)
            let alertIconLeft = NSLayoutConstraint(item: alertIcon, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 20)
            let alertIconHeight = NSLayoutConstraint(item: alertIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 17)
            let alertIconWidth = NSLayoutConstraint(item: alertIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 17)
            yellowCard.addConstraints([alertIconTop, alertIconLeft])
            alertIcon.addConstraints([alertIconHeight, alertIconWidth])

            // Header
            let headerLabel = UILabel()
            headerLabel.translatesAutoresizingMaskIntoConstraints = false
            headerLabel.numberOfLines = 1
            headerLabel.font = UIFont(name: "Gilroy-Bold", size: 18)
            headerLabel.text = title.lowercased()
            headerLabel.textColor = Colors.getColor("whiteoryellow")
            yellowCard.addSubview(headerLabel)
            let headerLabelCenterY = NSLayoutConstraint(item: headerLabel, attribute: .centerY, relatedBy: .equal, toItem: alertIcon, attribute: .centerY, multiplier: 1, constant: 0)
            let headerLabelLeft = NSLayoutConstraint(item: headerLabel, attribute: .leading, relatedBy: .equal, toItem: alertIcon, attribute: .trailing, multiplier: 1, constant: 10)
            let headerLabelRight = NSLayoutConstraint(item: headerLabel, attribute: .trailing, relatedBy: .lessThanOrEqual, toItem: yellowCard, attribute: .trailing, multiplier: 1, constant: -20)
            yellowCard.addConstraints([headerLabelCenterY, headerLabelLeft, headerLabelRight])

            // Text field container — matches the Transfer2 OTP field: white,
            // rounded (corner radius 8), 45pt tall.
            let fieldView = UIView()
            fieldView.translatesAutoresizingMaskIntoConstraints = false
            fieldView.backgroundColor = .white
            fieldView.layer.cornerRadius = 8
            fieldView.clipsToBounds = true
            yellowCard.addSubview(fieldView)
            let fieldViewTop = NSLayoutConstraint(item: fieldView, attribute: .top, relatedBy: .equal, toItem: alertIcon, attribute: .bottom, multiplier: 1, constant: 25)
            let fieldViewLeft = NSLayoutConstraint(item: fieldView, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 20)
            let fieldViewRight = NSLayoutConstraint(item: fieldView, attribute: .trailing, relatedBy: .equal, toItem: yellowCard, attribute: .trailing, multiplier: 1, constant: -20)
            let fieldViewHeight = NSLayoutConstraint(item: fieldView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 45)
            yellowCard.addConstraints([fieldViewTop, fieldViewLeft, fieldViewRight])
            fieldView.addConstraint(fieldViewHeight)

            // Text field — Gilroy-Regular 16, black, 15pt side padding (as OTP).
            let textField = UITextField()
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = UIFont(name: "Gilroy-Regular", size: 16)
            textField.textColor = .black
            textField.text = initialText
            textField.placeholder = placeholder
            textField.textAlignment = .left
            textField.autocapitalizationType = .sentences
            textField.returnKeyType = .done
            textField.accessibilityIdentifier = "alert.textField"
            fieldView.addSubview(textField)
            let textFieldLeft = NSLayoutConstraint(item: textField, attribute: .leading, relatedBy: .equal, toItem: fieldView, attribute: .leading, multiplier: 1, constant: 15)
            let textFieldRight = NSLayoutConstraint(item: textField, attribute: .trailing, relatedBy: .equal, toItem: fieldView, attribute: .trailing, multiplier: 1, constant: -15)
            let textFieldCenterY = NSLayoutConstraint(item: textField, attribute: .centerY, relatedBy: .equal, toItem: fieldView, attribute: .centerY, multiplier: 1, constant: 0)
            fieldView.addConstraints([textFieldLeft, textFieldRight, textFieldCenterY])

            // Buttons stack (cancel + save, side by side).
            let buttonsStack = UIView()
            buttonsStack.translatesAutoresizingMaskIntoConstraints = false
            buttonsStack.clipsToBounds = false
            buttonsStack.backgroundColor = .clear
            yellowCard.addSubview(buttonsStack)
            let buttonsStackHeight = NSLayoutConstraint(item: buttonsStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 50)
            let buttonsStackLeft = NSLayoutConstraint(item: buttonsStack, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 15)
            let buttonsStackRight = NSLayoutConstraint(item: buttonsStack, attribute: .trailing, relatedBy: .equal, toItem: yellowCard, attribute: .trailing, multiplier: 1, constant: -15)
            let buttonsStackBottom = NSLayoutConstraint(item: buttonsStack, attribute: .bottom, relatedBy: .equal, toItem: yellowCard, attribute: .bottom, multiplier: 1, constant: -5)
            let buttonsStackTop = NSLayoutConstraint(item: buttonsStack, attribute: .top, relatedBy: .equal, toItem: fieldView, attribute: .bottom, multiplier: 1, constant: 20)
            yellowCard.addConstraints([buttonsStackLeft, buttonsStackRight, buttonsStackBottom, buttonsStackTop])
            buttonsStack.addConstraint(buttonsStackHeight)

            // Dismissal helper. Stop observing the keyboard first (so its
            // will-hide handler doesn't also move the card), then dismiss the
            // keyboard and let the card settle to its resting position in step
            // with it, and only once that's done slide the alert out. Sliding
            // the alert out while the keyboard is still lowering looks bumpy —
            // and hideAlert's off-screen math assumes the card is at rest, so a
            // keyboard-lifted card wouldn't fully dismiss.
            let dismiss: () -> Void = {
                if let tokens = darkBackground.keyboardObserverTokens {
                    tokens.forEach { NotificationCenter.default.removeObserver($0) }
                    darkBackground.keyboardObserverTokens = nil
                }
                // No keyboard up (e.g. it was dismissed via Done) — just exit.
                guard presentingController.view.endEditing(true) else {
                    self.hideAlert()
                    return
                }
                NSLayoutConstraint.deactivate([yellowCardBottom])
                yellowCardBottom = NSLayoutConstraint(item: yellowCard, attribute: .bottom, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: -presentingController.view.safeAreaInsets.bottom)
                NSLayoutConstraint.activate([yellowCardBottom])
                UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: {
                    presentingController.view.layoutIfNeeded()
                }) { _ in
                    self.hideAlert()
                }
            }

            for (index, eachButton) in [cancelTitle, saveTitle].enumerated() {

                let closeView = UIView()
                closeView.translatesAutoresizingMaskIntoConstraints = false
                closeView.backgroundColor = Colors.getColor("white0.7orblue1")
                closeView.layer.cornerRadius = 8
                closeView.setShadow()
                closeView.clipsToBounds = false
                buttonsStack.addSubview(closeView)
                let closeViewHeight = NSLayoutConstraint(item: closeView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
                let closeViewWidth = NSLayoutConstraint(item: closeView, attribute: .width, relatedBy: .equal, toItem: buttonsStack, attribute: .width, multiplier: 0.5, constant: -5)
                let closeViewLeft: NSLayoutConstraint = {
                    if index == 1 {
                        return NSLayoutConstraint(item: closeView, attribute: .leading, relatedBy: .equal, toItem: buttonsStack, attribute: .centerX, multiplier: 1, constant: 5)
                    } else {
                        return NSLayoutConstraint(item: closeView, attribute: .leading, relatedBy: .equal, toItem: buttonsStack, attribute: .leading, multiplier: 1, constant: 0)
                    }
                }()
                let closeViewBottom = NSLayoutConstraint(item: closeView, attribute: .bottom, relatedBy: .equal, toItem: buttonsStack, attribute: .bottom, multiplier: 1, constant: -10)
                buttonsStack.addConstraints([closeViewLeft, closeViewBottom, closeViewWidth])
                closeView.addConstraint(closeViewHeight)

                let buttonLabel = UILabel()
                buttonLabel.translatesAutoresizingMaskIntoConstraints = false
                buttonLabel.numberOfLines = 1
                buttonLabel.font = UIFont(name: "Gilroy-Bold", size: 16)
                buttonLabel.text = eachButton
                buttonLabel.textColor = Colors.getColor("blackorwhite")
                buttonLabel.textAlignment = .center
                buttonLabel.isAccessibilityElement = false
                closeView.addSubview(buttonLabel)
                let buttonLabelCenterX = NSLayoutConstraint(item: buttonLabel, attribute: .centerX, relatedBy: .equal, toItem: closeView, attribute: .centerX, multiplier: 1, constant: 0)
                let buttonLabelCenterY = NSLayoutConstraint(item: buttonLabel, attribute: .centerY, relatedBy: .equal, toItem: closeView, attribute: .centerY, multiplier: 1, constant: 1)
                closeView.addConstraints([buttonLabelCenterX, buttonLabelCenterY])

                let mainButton = UIButton()
                mainButton.translatesAutoresizingMaskIntoConstraints = false
                mainButton.setTitle("", for: .normal)
                mainButton.backgroundColor = .clear
                mainButton.accessibilityLabel = eachButton
                mainButton.accessibilityIdentifier = "alert.button.\(index)"
                if index == 1 {
                    mainButton.addAction(UIAction { _ in
                        let noteText = textField.text ?? ""
                        dismiss()
                        onSave(noteText)
                    }, for: .touchUpInside)
                } else {
                    mainButton.addAction(UIAction { _ in dismiss() }, for: .touchUpInside)
                }
                closeView.addSubview(mainButton)
                let mainButtonTop = NSLayoutConstraint(item: mainButton, attribute: .top, relatedBy: .equal, toItem: closeView, attribute: .top, multiplier: 1, constant: 0)
                let mainButtonBottom = NSLayoutConstraint(item: mainButton, attribute: .bottom, relatedBy: .equal, toItem: closeView, attribute: .bottom, multiplier: 1, constant: 0)
                let mainButtonLeft = NSLayoutConstraint(item: mainButton, attribute: .leading, relatedBy: .equal, toItem: closeView, attribute: .leading, multiplier: 1, constant: 0)
                let mainButtonRight = NSLayoutConstraint(item: mainButton, attribute: .trailing, relatedBy: .equal, toItem: closeView, attribute: .trailing, multiplier: 1, constant: 0)
                closeView.addConstraints([mainButtonTop, mainButtonBottom, mainButtonLeft, mainButtonRight])
            }

            presentingController.view.layoutIfNeeded()

            // Slide the card up while the background dims (same motion as showAlert),
            // then auto-focus the field once it has settled.
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                darkBackground.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
                NSLayoutConstraint.deactivate([yellowCardTop])
                yellowCardBottom = NSLayoutConstraint(item: yellowCard, attribute: .bottom, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: -presentingController.view.safeAreaInsets.bottom - 15)
                NSLayoutConstraint.activate([yellowCardBottom])
                presentingController.view.layoutIfNeeded()
            }) { _ in
                UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut, animations: {
                    NSLayoutConstraint.deactivate([yellowCardBottom])
                    yellowCardBottom = NSLayoutConstraint(item: yellowCard, attribute: .bottom, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: -presentingController.view.safeAreaInsets.bottom)
                    NSLayoutConstraint.activate([yellowCardBottom])
                    presentingController.view.layoutIfNeeded()
                }) { _ in
                    textField.becomeFirstResponder()
                }
            }

            // Keyboard avoidance: lift the card so its bottom sits just above the
            // keyboard while editing, and drop it back when the keyboard hides.
            let notificationCenter = NotificationCenter.default
            var tokens: [NSObjectProtocol] = []
            tokens.append(notificationCenter.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { note in
                guard let keyboardFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
                NSLayoutConstraint.deactivate([yellowCardBottom])
                yellowCardBottom = NSLayoutConstraint(item: yellowCard, attribute: .bottom, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: -keyboardFrame.height - 10)
                NSLayoutConstraint.activate([yellowCardBottom])
                UIView.animate(withDuration: 0.25) { presentingController.view.layoutIfNeeded() }
            })
            tokens.append(notificationCenter.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                NSLayoutConstraint.deactivate([yellowCardBottom])
                yellowCardBottom = NSLayoutConstraint(item: yellowCard, attribute: .bottom, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: -presentingController.view.safeAreaInsets.bottom)
                NSLayoutConstraint.activate([yellowCardBottom])
                UIView.animate(withDuration: 0.25) { presentingController.view.layoutIfNeeded() }
            })
            darkBackground.keyboardObserverTokens = tokens
        }
    }

    // MARK: - Loading overlay

    /// Shows a non-dismissable loading overlay over this view controller: a
    /// full-screen transparent-black background (blocking all touches) with a
    /// card sliding up from the bottom, containing a spinner and `message`. It
    /// mirrors showAlert's look and motion but has no buttons and can't be
    /// dismissed by the user — call `hideLoading()` when the work is done.
    /// Calling it again while one is showing just updates the label in place
    /// (e.g. "syncing wallet" → "receiving payment"). Colours follow light/dark
    /// mode automatically (Colors + attributed()).
    func showLoading(message: String) {
        DispatchQueue.main.async {

            // Already showing → just swap the message, don't stack a second overlay.
            if let existing = self.view.subviews.first(where: { $0.boundString == "loadingview" }) {
                for card in existing.subviews {
                    for row in card.subviews {
                        for sub in row.subviews where sub.boundString == "loadinglabel" {
                            (sub as? UILabel)?.text = message
                        }
                    }
                }
                return
            }

            // Background — a plain view over everything absorbs all touches, so
            // nothing behind it is tappable and there's no gesture to dismiss it.
            let darkBackground = UIView()
            darkBackground.translatesAutoresizingMaskIntoConstraints = false
            darkBackground.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
            darkBackground.boundString = "loadingview"
            self.view.addSubview(darkBackground)
            let bgTop = NSLayoutConstraint(item: darkBackground, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
            let bgLeft = NSLayoutConstraint(item: darkBackground, attribute: .leading, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
            let bgRight = NSLayoutConstraint(item: darkBackground, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
            let bgBottom = NSLayoutConstraint(item: darkBackground, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            self.view.addConstraints([bgTop, bgLeft, bgRight, bgBottom])
            darkBackground.loadingBottomConstraint = bgBottom

            // Card — same corner radius, shadow and side padding as the alert.
            let card = UIView()
            card.translatesAutoresizingMaskIntoConstraints = false
            card.backgroundColor = Colors.getColor("whiteorblue3")
            card.layer.cornerRadius = 13
            card.setShadow()
            card.clipsToBounds = false
            darkBackground.addSubview(card)
            let cardTop = NSLayoutConstraint(item: card, attribute: .top, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: 0)
            var cardBottom = NSLayoutConstraint()
            let cardLeft = NSLayoutConstraint(item: card, attribute: .leading, relatedBy: .equal, toItem: darkBackground, attribute: .leading, multiplier: 1, constant: 10)
            let cardRight = NSLayoutConstraint(item: card, attribute: .trailing, relatedBy: .equal, toItem: darkBackground, attribute: .trailing, multiplier: 1, constant: -10)
            let cardMaxHeight = NSLayoutConstraint(item: card, attribute: .height, relatedBy: .lessThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: self.view.bounds.height)
            darkBackground.addConstraints([cardTop, cardLeft, cardRight])
            card.addConstraint(cardMaxHeight)

            // Spinner
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.color = Colors.getColor("blackorwhite")
            spinner.startAnimating()

            // Message (bold, sitting to the right of the spinner).
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = UIFont(name: "Gilroy-Bold", size: 16)
            label.textColor = Colors.getColor("blackorwhite")
            label.text = message
            label.boundString = "loadinglabel"

            // Lay the spinner and message out as a horizontal row centred in the
            // card. The row's top/bottom padding drives the card height.
            let row = UIStackView(arrangedSubviews: [spinner, label])
            row.translatesAutoresizingMaskIntoConstraints = false
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 11
            card.addSubview(row)
            let rowTop = NSLayoutConstraint(item: row, attribute: .top, relatedBy: .equal, toItem: card, attribute: .top, multiplier: 1, constant: 25)
            let rowBottom = NSLayoutConstraint(item: row, attribute: .bottom, relatedBy: .equal, toItem: card, attribute: .bottom, multiplier: 1, constant: -25)
            let rowCenterX = NSLayoutConstraint(item: row, attribute: .centerX, relatedBy: .equal, toItem: card, attribute: .centerX, multiplier: 1, constant: 0)
            let rowLeading = NSLayoutConstraint(item: row, attribute: .leading, relatedBy: .greaterThanOrEqual, toItem: card, attribute: .leading, multiplier: 1, constant: 25)
            card.addConstraints([rowTop, rowBottom, rowCenterX, rowLeading])

            self.view.layoutIfNeeded()

            // Slide up with a small overshoot while the background fades in —
            // the same motion as showAlert.
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                darkBackground.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
                NSLayoutConstraint.deactivate([cardTop])
                cardBottom = NSLayoutConstraint(item: card, attribute: .bottom, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: -self.view.safeAreaInsets.bottom - 15)
                NSLayoutConstraint.activate([cardBottom])
                self.view.layoutIfNeeded()
            }) { _ in
                UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                    NSLayoutConstraint.deactivate([cardBottom])
                    cardBottom = NSLayoutConstraint(item: card, attribute: .bottom, relatedBy: .equal, toItem: darkBackground, attribute: .bottom, multiplier: 1, constant: -self.view.safeAreaInsets.bottom)
                    NSLayoutConstraint.activate([cardBottom])
                    self.view.layoutIfNeeded()
                }
            }
        }
    }

    /// Slides the loading overlay back down and removes it. Safe to call when
    /// none is showing.
    func hideLoading() {
        DispatchQueue.main.async {
            for eachView in self.view.subviews where eachView.boundString == "loadingview" {
                if let card = eachView.subviews.first, var bgBottom = eachView.loadingBottomConstraint {
                    UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                        eachView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
                        NSLayoutConstraint.deactivate([bgBottom])
                        bgBottom = NSLayoutConstraint(item: eachView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: card.frame.height + self.view.safeAreaInsets.bottom)
                        NSLayoutConstraint.activate([bgBottom])
                        self.view.layoutIfNeeded()
                    }) { _ in
                        eachView.removeFromSuperview()
                    }
                } else {
                    eachView.removeFromSuperview()
                }
            }
        }
    }
}
