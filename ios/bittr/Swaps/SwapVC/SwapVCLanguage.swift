//
//  SwapVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 9/4/25.
//

import UIKit

extension SwapViewController {
    
    func setLanguage() {
        self.subtitleLabel.text = Language.getWord(withID: "swapsubtitle")
        self.moveLabel.text = Language.getWord(withID: "move")
        self.nextLabel.text = Language.getWord(withID: "next")
        self.fromLabel.text = Language.getWord(withID: "lightningtoonchain")
        self.poweredByLabel.text = Language.getWord(withID: "poweredbyboltz")
    }
    
    @objc func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.subtitleLabel.textColor = Colors.getColor("blackorwhite")
        self.moveLabel.textColor = Colors.getColor("blackoryellow")
        self.centerCard.backgroundColor = Colors.getColor("yelloworblue2")
        self.availableAmountLabel.textColor = Colors.getColor("blackorwhite")
        self.questionMark.tintColor = Colors.getColor("blackorwhite")
        self.bdkSpinner.color = Colors.getColor("blackorwhite")
        self.amountTextField.backgroundColor = Colors.getColor("white0.7orblue3")
        self.fromView.backgroundColor = Colors.getColor("whiteorblue3")
        self.fromLabel.textColor = Colors.getColor("blackorwhite")
        self.poweredByLabel.textColor = Colors.getColor("blackorwhite")
        self.boltzLogo.image = UIImage(named: (CacheManager.darkModeIsOn() ? "boltzwhite" : "boltzblack"))
        
        self.amountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteramountofsatoshis"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.amountTextField.textColor = Colors.getColor("blackorwhite")
    }
    
    func setBasicStyling() {
        
        // Accessibility identifiers
        self.subtitleLabel.accessibilityIdentifier = TestID.Swap.subtitleLabel
        self.amountTextField.accessibilityIdentifier = TestID.Swap.amountTextField
        self.nextButton.accessibilityIdentifier = TestID.Swap.nextButton
        self.nextButton.accessibilityLabel = Language.getWord(withID: "next")
        self.fromLabel.accessibilityIdentifier = TestID.Swap.fromLabel
        self.fromButton.accessibilityIdentifier = TestID.Swap.fromButton
        self.fromButton.accessibilityLabel = "Swap direction"
        
        // Button titles
        self.centerBackground.setTitle("", for: .normal)
        self.contentBackground.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.availableButton.setTitle("", for: .normal)
        self.fromButton.setTitle("", for: .normal)
        self.boltzButton.setTitle("", for: .normal)
        
        // Corner radii
        self.centerCard.layer.cornerRadius = 13
        self.amountTextField.layer.cornerRadius = 8
        self.fromView.layer.cornerRadius = 8
        self.nextView.layer.cornerRadius = 8
        
        // Shadows
        self.centerCard.setShadow()
        self.fromView.setShadow()
        self.amountTextField.setShadow()
        
        // Amount text field
        self.amountTextField.delegate = self
        self.amountTextField.inputAccessoryView = self.createInputAccessoryView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        self.handlePendingSwaps()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
        
        // Clear swap state when leaving the swap screen
        // This ensures that if user swipes away the page, swap data is cleared
        Log.info("Leaving SwapViewController, clearing swap state")
        self.clearPendingSwapData()
    }
    
    @objc func keyboardWillDisappear() {
        
        NSLayoutConstraint.deactivate([self.mainContentViewBottom])
        self.mainContentViewBottom = NSLayoutConstraint(item: self.mainContentView!, attribute: .bottom, relatedBy: .equal, toItem: self.mainScrollView, attribute: .bottom, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.mainContentViewBottom])
        self.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            NSLayoutConstraint.deactivate([self.mainContentViewBottom])
            self.mainContentViewBottom = NSLayoutConstraint(item: self.mainContentView!, attribute: .bottom, relatedBy: .equal, toItem: self.mainScrollView, attribute: .bottom, multiplier: 1, constant: -keyboardHeight)
            NSLayoutConstraint.activate([self.mainContentViewBottom])
            
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Input Accessory View
    func createInputAccessoryView() -> UIView {
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        containerView.backgroundColor = Colors.getColor("whiteorblue3")
        
        let toolbar = UIToolbar(frame: containerView.bounds)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = .clear
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: Language.getWord(withID: "done"), style: .done, target: self, action: #selector(backgroundTapped))
        
        toolbar.items = [flexSpace, doneButton]
        toolbar.tintColor = Colors.getColor("blackorwhite")
        
        containerView.addSubview(toolbar)
        
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: containerView.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.view.endEditing(true)
        return false
    }
    
}
