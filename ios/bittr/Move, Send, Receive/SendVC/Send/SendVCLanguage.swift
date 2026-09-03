//
//  SendVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension SendViewController {
    
    func setWords() {
        
        self.toLabel.text = Language.getWord(withID: "addressandamount")
        self.toTextField.placeholder = Language.getWord(withID: "enteraddress")
        self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.amountTextField.placeholder = Language.getWord(withID: "enteramount")
        self.nextLabel.text = Language.getWord(withID: "next")
        
        self.stackLabelQR.text = Language.getWord(withID: "sendvcscan")
        self.stackLabelPaste.text = Language.getWord(withID: "sendvcpaste")
        
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
        
        self.labelRegular.textColor = Colors.getColor("blackorwhite")
        self.labelInstant.textColor = Colors.getColor("blackorwhite")
        self.viewRegular.backgroundColor = Colors.getColor("white0.7orblue1")
        self.viewInstant.backgroundColor = Colors.getColor("whiteorblue3")
        self.iconLightning.tintColor = Colors.getColor("blackorwhite")
        self.switchQuestionMark.tintColor = Colors.getColor("blackorwhite")
        
        self.toLabel.textColor = Colors.getColor("blackoryellow")
        self.backgroundQR.backgroundColor = Colors.getColor("whiteorblue3")
        self.backgroundPaste.backgroundColor = Colors.getColor("whiteorblue3")
        self.stackLabelQR.textColor = Colors.getColor("blackorwhite")
        self.stackLabelPaste.textColor = Colors.getColor("blackorwhite")
        self.stackImageQR.tintColor = Colors.getColor("blackorwhite")
        self.stackImagePaste.tintColor = Colors.getColor("blackorwhite")
        self.toView.backgroundColor = Colors.getColor("white0.7orblue1")
        self.toTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteraddress"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.toTextField.textColor = Colors.getColor("blackorwhite")
        
        self.bdkSpinner.color = Colors.getColor("blackorwhite")
        self.availableAmount.textColor = Colors.getColor("blackorwhite")
        self.questionCircle.tintColor = Colors.getColor("blackorwhite")
        self.btcView.backgroundColor = Colors.getColor("whiteorblue3")
        self.btcLabel.textColor = Colors.getColor("blackorwhite")
        self.amountView.backgroundColor = Colors.getColor("white0.7orblue1")
        self.amountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteramount"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.amountTextField.textColor = Colors.getColor("blackorwhite")
    }
    
    func setBasicStyling() {
        
        // Tag the onchain/lightning switch buttons.
        self.regularButton.boundString = "onchain"
        self.instantButton.boundString = "lightning"
        
        // Text fields
        self.toTextField.delegate = self
        self.toTextField.autocorrectionType = .no
        self.toTextField.autocapitalizationType = .none
        self.toTextField.smartQuotesType = .no
        self.toTextField.smartDashesType = .no
        self.amountTextField.delegate = self
        self.amountTextField.inputAccessoryView = createAmountInputAccessoryView()
        
        self.toLabel.accessibilityIdentifier = TestID.Send.toLabel
        self.toTextField.accessibilityIdentifier = TestID.Send.toTextField
        self.amountTextField.accessibilityIdentifier = TestID.Send.amountTextField
        self.pasteButton.accessibilityIdentifier = TestID.Send.pasteButton
        self.qrButton.accessibilityIdentifier = TestID.Send.scanButton
        self.regularButton.accessibilityIdentifier = TestID.Send.regularButton
        self.switchQuestionButton.accessibilityIdentifier = TestID.Send.switchQuestionButton
        self.btcButton.accessibilityIdentifier = TestID.Send.currencyButton
        self.btcLabel.accessibilityIdentifier = TestID.Send.currencyLabel
        self.bdkSpinner.accessibilityIdentifier = TestID.Send.bdkSpinner
        self.availableButton.accessibilityIdentifier = TestID.Send.availableButton
        self.availableAmount.accessibilityIdentifier = TestID.Send.availableLabel
        self.availableQuestionButton.accessibilityIdentifier = TestID.Send.availableQuestionButton
        self.nextButton.accessibilityIdentifier = TestID.Send.nextButton
        
        // Button titles
        self.amountButton.setTitle("", for: .normal)
        self.availableButton.setTitle("", for: .normal)
        self.pasteButton.setTitle("", for: .normal)
        self.backgroundButton.setTitle("", for: .normal)
        self.centerBackgroundButton.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.regularButton.setTitle("", for: .normal)
        self.instantButton.setTitle("", for: .normal)
        self.qrButton.setTitle("", for: .normal)
        self.toButton.setTitle("", for: .normal)
        self.btcButton.setTitle("", for: .normal)
        self.availableQuestionButton.setTitle("", for: .normal)
        self.switchQuestionButton.setTitle("", for: .normal)
        
        // Corner radii
        self.yellowCard.layer.cornerRadius = 13
        self.toView.layer.cornerRadius = 8
        self.amountView.layer.cornerRadius = 8
        self.nextView.layer.cornerRadius = 8
        self.backgroundQR.layer.cornerRadius = 8
        self.backgroundPaste.layer.cornerRadius = 8
        self.btcView.layer.cornerRadius = 8
        self.viewRegular.layer.cornerRadius = 8
        self.viewInstant.layer.cornerRadius = 8
        
        // Shadows
        self.backgroundQR.setShadow()
        self.backgroundPaste.setShadow()
        self.btcView.setShadow()
        self.yellowCard.setShadow()
        
        // Selection view
        self.viewRegular.setShadow()
        self.viewRegular.layer.shadowOpacity = 0
        self.viewInstant.setShadow()
        self.viewInstant.layer.shadowOpacity = 0.1
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    func checkContentViewHeight() {
        let centerViewHeight = self.centerView.bounds.height
        if self.centerView.bounds.height + 60 > self.contentView.bounds.height {
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight + 120)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.view.layoutIfNeeded()
        } else {
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: self.contentView.superview, attribute: .height, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.view.layoutIfNeeded()
        }
    }
    
    @objc func keyboardWillDisappear() {
        
        self.amountButton.alpha = 1
        self.toButton.alpha = 1
        
        self.scrollViewBottom.constant = self.view.safeAreaInsets.bottom
        self.view.layoutIfNeeded()
        self.checkContentViewHeight()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            self.scrollViewBottom.constant = -keyboardHeight + self.view.safeAreaInsets.bottom
            self.view.layoutIfNeeded()
            self.checkContentViewHeight()
            
            // Scroll view up to text field.
            var fieldFrame = self.scrollView.convert(self.amountTextField.bounds, from: self.amountTextField.superview)
            fieldFrame = fieldFrame.insetBy(dx: 0, dy: -25)
            self.scrollView.scrollRectToVisible(fieldFrame, animated: true)
        }
    }
}
