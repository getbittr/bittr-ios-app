//
//  AlertManager.swift
//  bittr
//
//  Created by Tom Melters on 04/03/2025.
//

import UIKit
import ObjectiveC.runtime

private struct AlertManagerAssociatedKeys {
    static var bottomConstraint: UInt8 = 0
    static var loadingBottomConstraint: UInt8 = 0
    static var keyboardObservers: UInt8 = 0
    static var alertPresenter: UInt8 = 0
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

private final class WeakController {
    weak var controller: UIViewController?
    init(_ controller: UIViewController?) { self.controller = controller }
}

private extension UIViewController {
    var alertPresenter: UIViewController? {
        get { (objc_getAssociatedObject(self, &AlertManagerAssociatedKeys.alertPresenter) as? WeakController)?.controller }
        set { objc_setAssociatedObject(self, &AlertManagerAssociatedKeys.alertPresenter, WeakController(newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

protocol OnchainSyncFailureReporting: UIViewController {
    // Adopted by SendVC and SwapVC.
    var bdkSpinner: UIActivityIndicatorView! { get }
}

extension OnchainSyncFailureReporting {
    // Stops the on-chain sync spinner and tells the user the on-chain sync failed.
    func presentOnchainSyncFailedAlert() {
        DispatchQueue.main.async {
            self.bdkSpinner.stopAnimating()
            let timedOut = BitcoinManager.shared.bdkFullScanTimedOut
            // Replace the "syncing" alert (if still visible) with the failure alert.
            self.hideAlert()
            self.showAlert(presentingController: self, title: Language.getWord(withID: "onchainsyncfailedtitle"), message: Language.getWord(withID: timedOut ? "onchainsynctimedout" : "onchainsyncfailed"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
}

// MARK: - Shared chrome

// The dimming background and the card that slides up inside it.
private struct AlertChrome {
    let background: UIView
    let card: UIView
    let cardTop: NSLayoutConstraint
    let cardBottom: NSLayoutConstraint
    let backgroundBottom: NSLayoutConstraint
}

private extension UIViewController {
    
    // Builds the background + card and pins them, with the card parked off-screen below.
    func makeAlertChrome(on host: UIViewController, marker: String, cardColor: UIColor) -> AlertChrome {
        
        let background = UIView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
        background.boundString = marker
        host.view.addSubview(background)
        
        let backgroundBottom = background.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: host.view.topAnchor),
            background.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            backgroundBottom
        ])
        
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = cardColor
        card.layer.cornerRadius = 13
        card.setShadow()
        card.clipsToBounds = false
        background.addSubview(card)
        
        let cardTop = card.topAnchor.constraint(equalTo: background.bottomAnchor)
        let cardBottom = card.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            card.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            card.heightAnchor.constraint(lessThanOrEqualToConstant: host.view.bounds.height),
            cardTop
        ])
        
        return AlertChrome(background: background, card: card, cardTop: cardTop, cardBottom: cardBottom, backgroundBottom: backgroundBottom)
    }
    
    // The bell icon + lowercased title row.
    @discardableResult
    func addAlertHeader(to card: UIView, title: String, trailingLimit: UIView?) -> UIImageView {
        
        let alertIcon = UIImageView()
        alertIcon.translatesAutoresizingMaskIntoConstraints = false
        alertIcon.contentMode = .scaleAspectFit
        alertIcon.image = UIImage(named: CacheManager.darkModeIsOn() ? "iconbellyellow" : "iconbellwhite")
        card.addSubview(alertIcon)
        
        let headerLabel = UILabel()
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.numberOfLines = 1
        headerLabel.font = UIFont(name: "Gilroy-Bold", size: 18)
        headerLabel.text = title.lowercased()
        headerLabel.textColor = Colors.getColor("whiteoryellow")
        card.addSubview(headerLabel)
        
        NSLayoutConstraint.activate([
            alertIcon.topAnchor.constraint(equalTo: card.topAnchor, constant: 19),
            alertIcon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            alertIcon.heightAnchor.constraint(equalToConstant: 17),
            alertIcon.widthAnchor.constraint(equalToConstant: 17),
            headerLabel.centerYAnchor.constraint(equalTo: alertIcon.centerYAnchor),
            headerLabel.leadingAnchor.constraint(equalTo: alertIcon.trailingAnchor, constant: 10)
        ])
        if let trailingLimit = trailingLimit {
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingLimit.trailingAnchor, constant: -20).isActive = true
        }
        return alertIcon
    }
    
    // One alert button: the rounded, shadowed plate with its centred label.
    func makeAlertButton(title: String, index: Int, handler: @escaping () -> Void) -> UIButton {
        
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = Colors.getColor("white0.7orblue1")
        button.layer.cornerRadius = 8
        button.setShadow()
        button.clipsToBounds = false
        button.accessibilityLabel = title
        button.accessibilityIdentifier = "alert.button.\(index)"
        button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        
        let buttonLabel = UILabel()
        buttonLabel.translatesAutoresizingMaskIntoConstraints = false
        buttonLabel.numberOfLines = 1
        buttonLabel.font = UIFont(name: "Gilroy-Bold", size: 16)
        buttonLabel.text = title
        buttonLabel.textColor = Colors.getColor("blackorwhite")
        buttonLabel.textAlignment = .center
        buttonLabel.isAccessibilityElement = false
        button.addSubview(buttonLabel)
        
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 40),
            buttonLabel.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            buttonLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: 1)
        ])
        return button
    }
    
    // The slide-up.
    func slideIn(_ chrome: AlertChrome, on host: UIViewController, completion: (() -> Void)? = nil) {
        
        host.view.layoutIfNeeded()
        
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [], animations: {
            chrome.background.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
            chrome.cardTop.isActive = false
            chrome.cardBottom.constant = -host.view.safeAreaInsets.bottom
            chrome.cardBottom.isActive = true
            host.view.layoutIfNeeded()
        }) { _ in
            completion?()
        }
    }
    
    // Slides a chrome view back down and removes it.
    func slideOut(_ overlay: UIView, from host: UIViewController, bottom: NSLayoutConstraint?) {
        
        guard let card = overlay.subviews.first, let bottom = bottom else {
            overlay.removeFromSuperview()
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
            overlay.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
            bottom.constant = card.frame.height + host.view.safeAreaInsets.bottom
            host.view.layoutIfNeeded()
        }) { _ in
            overlay.removeFromSuperview()
        }
    }
}

// MARK: - Alerts

extension UIViewController {
    
    func showAlert(presentingController:UIViewController, title:String, message:String, buttons:[String], actions:[(() -> Void)?]?) {
        
        self.alertPresenter = presentingController
        
        // Pad to the button count.
        let resolvedActions: [(() -> Void)?] = buttons.indices.map { index in
            guard let actions = actions, index < actions.count else { return nil }
            return actions[index]
        }
        let isDismissable = actions == nil || resolvedActions.contains { $0 == nil }
        
        DispatchQueue.main.async {
            
            let chrome = self.makeAlertChrome(on: presentingController, marker: "alertview", cardColor: Colors.getColor("yelloworblue2"))
            let card = chrome.card
            chrome.background.alertBottomConstraint = chrome.backgroundBottom
            
            let alertIcon = self.addAlertHeader(to: card, title: title, trailingLimit: nil)
            
            // Close image
            let closeIcon = UIImageView()
            closeIcon.translatesAutoresizingMaskIntoConstraints = false
            closeIcon.contentMode = .scaleAspectFit
            closeIcon.image = UIImage(named: CacheManager.darkModeIsOn() ? "iconcloseyellow" : "iconclosewhite")
            closeIcon.alpha = isDismissable ? 1 : 0
            card.addSubview(closeIcon)
            
            // Close button
            let closeButton = UIButton(type: .custom)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            closeButton.backgroundColor = .clear
            closeButton.alpha = isDismissable ? 1 : 0
            closeButton.addAction(UIAction { [weak self] _ in self?.hideAlert() }, for: .touchUpInside)
            card.addSubview(closeButton)
            
            // Message
            let messageLabel = UILabel()
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            messageLabel.numberOfLines = 0
            messageLabel.attributedText = message.attributed()
            card.addSubview(messageLabel)
            
            // Check whether to stack buttons vertically or horizontally.
            let titlesFitSideBySide = buttons.allSatisfy { eachButton in eachButton.count < 16 }
            let stackButtonsVertically = buttons.count > 2 || (buttons.count == 2 && !titlesFitSideBySide)

            let buttonViews = buttons.enumerated().map { index, eachButton in
                self.makeAlertButton(title: eachButton, index: index) { [weak self] in
                    if let action = resolvedActions[index] {
                        action()
                    } else {
                        self?.hideAlert()
                    }
                }
            }

            let buttonsStack = UIStackView(arrangedSubviews: stackButtonsVertically ? buttonViews.reversed() : buttonViews)
            buttonsStack.translatesAutoresizingMaskIntoConstraints = false
            buttonsStack.axis = stackButtonsVertically ? .vertical : .horizontal
            buttonsStack.distribution = .fillEqually
            buttonsStack.spacing = 10
            buttonsStack.clipsToBounds = false
            card.addSubview(buttonsStack)

            NSLayoutConstraint.activate([
                closeIcon.centerYAnchor.constraint(equalTo: alertIcon.centerYAnchor),
                closeIcon.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
                closeIcon.heightAnchor.constraint(equalToConstant: 14),
                closeIcon.widthAnchor.constraint(equalToConstant: 14),

                closeButton.centerXAnchor.constraint(equalTo: closeIcon.centerXAnchor),
                closeButton.centerYAnchor.constraint(equalTo: closeIcon.centerYAnchor),
                closeButton.heightAnchor.constraint(equalToConstant: 40),
                closeButton.widthAnchor.constraint(equalToConstant: 40),

                messageLabel.topAnchor.constraint(equalTo: alertIcon.bottomAnchor, constant: 25),
                messageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 40),
                messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -40),

                buttonsStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 25),
                buttonsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
                buttonsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
                buttonsStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15)
            ])

            self.slideIn(chrome, on: presentingController)
        }
    }
    
    func hideAlert() {
        let host = self.alertPresenter ?? self
        DispatchQueue.main.async {
            for eachView in host.view.subviews where eachView.boundString == "alertview" {
                // Tear down any keyboard observers a text-field alert registered.
                if let tokens = eachView.keyboardObserverTokens {
                    tokens.forEach { NotificationCenter.default.removeObserver($0) }
                    eachView.keyboardObserverTokens = nil
                }
                self.slideOut(eachView, from: host, bottom: eachView.alertBottomConstraint)
            }
        }
    }
    
    func showTextFieldAlert(presentingController: UIViewController, title: String, initialText: String, placeholder: String, cancelTitle: String, saveTitle: String, onSave: @escaping (String) -> Void) {
        
        self.alertPresenter = presentingController
        
        DispatchQueue.main.async {
            let chrome = self.makeAlertChrome(on: presentingController, marker: "alertview", cardColor: Colors.getColor("yelloworblue2"))
            let card = chrome.card
            chrome.background.alertBottomConstraint = chrome.backgroundBottom
            
            let alertIcon = self.addAlertHeader(to: card, title: title, trailingLimit: card)
            
            // Text field container.
            let fieldView = UIView()
            fieldView.translatesAutoresizingMaskIntoConstraints = false
            fieldView.backgroundColor = .white
            fieldView.layer.cornerRadius = 8
            fieldView.clipsToBounds = true
            card.addSubview(fieldView)

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
            
            // Dismissal helper.
            let dismiss: () -> Void = { [weak self] in
                if let tokens = chrome.background.keyboardObserverTokens {
                    tokens.forEach { NotificationCenter.default.removeObserver($0) }
                    chrome.background.keyboardObserverTokens = nil
                }
                // No keyboard up (e.g. it was dismissed via Done) — just exit.
                guard presentingController.view.endEditing(true) else {
                    self?.hideAlert()
                    return
                }
                chrome.cardBottom.constant = -presentingController.view.safeAreaInsets.bottom
                UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: {
                    presentingController.view.layoutIfNeeded()
                }) { _ in
                    self?.hideAlert()
                }
            }
            
            let cancelButton = self.makeAlertButton(title: cancelTitle, index: 0) { dismiss() }
            let saveButton = self.makeAlertButton(title: saveTitle, index: 1) {
                let noteText = textField.text ?? ""
                dismiss()
                onSave(noteText)
            }
            
            let buttonsStack = UIStackView(arrangedSubviews: [cancelButton, saveButton])
            buttonsStack.translatesAutoresizingMaskIntoConstraints = false
            buttonsStack.axis = .horizontal
            buttonsStack.distribution = .fillEqually
            buttonsStack.spacing = 10
            buttonsStack.clipsToBounds = false
            card.addSubview(buttonsStack)
            
            NSLayoutConstraint.activate([
                fieldView.topAnchor.constraint(equalTo: alertIcon.bottomAnchor, constant: 25),
                fieldView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
                fieldView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
                fieldView.heightAnchor.constraint(equalToConstant: 45),

                textField.leadingAnchor.constraint(equalTo: fieldView.leadingAnchor, constant: 15),
                textField.trailingAnchor.constraint(equalTo: fieldView.trailingAnchor, constant: -15),
                textField.centerYAnchor.constraint(equalTo: fieldView.centerYAnchor),

                buttonsStack.topAnchor.constraint(equalTo: fieldView.bottomAnchor, constant: 20),
                buttonsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
                buttonsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
                buttonsStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15)
            ])
            
            // Slide the card up.
            self.slideIn(chrome, on: presentingController) {
                textField.becomeFirstResponder()
            }
            
            // Keyboard avoidance: lift the card so its bottom sits just above the
            // keyboard while editing, and drop it back when the keyboard hides.
            let notificationCenter = NotificationCenter.default
            var tokens: [NSObjectProtocol] = []
            tokens.append(notificationCenter.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { note in
                guard let keyboardFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
                chrome.cardBottom.constant = -keyboardFrame.height - 10
                UIView.animate(withDuration: 0.25) { presentingController.view.layoutIfNeeded() }
            })
            tokens.append(notificationCenter.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                chrome.cardBottom.constant = -presentingController.view.safeAreaInsets.bottom
                UIView.animate(withDuration: 0.25) { presentingController.view.layoutIfNeeded() }
            })
            chrome.background.keyboardObserverTokens = tokens
        }
    }

    // MARK: - Loading overlay

    // Shows a non-dismissable loading overlay over this view controller.
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
            
            // A plain view over everything absorbs all touches, so nothing
            // behind it is tappable and there's no gesture to dismiss it.
            let chrome = self.makeAlertChrome(on: self, marker: "loadingview", cardColor: Colors.getColor("whiteorblue3"))
            let card = chrome.card
            chrome.background.loadingBottomConstraint = chrome.backgroundBottom
            
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
            
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: card.topAnchor, constant: 25),
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -25),
                row.centerXAnchor.constraint(equalTo: card.centerXAnchor),
                row.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 25)
            ])
            
            self.slideIn(chrome, on: self)
        }
    }
    
    /// Slides the loading overlay back down and removes it. Safe to call when
    /// none is showing.
    func hideLoading() {
        DispatchQueue.main.async {
            for eachView in self.view.subviews where eachView.boundString == "loadingview" {
                self.slideOut(eachView, from: self, bottom: eachView.loadingBottomConstraint)
            }
        }
    }
}
