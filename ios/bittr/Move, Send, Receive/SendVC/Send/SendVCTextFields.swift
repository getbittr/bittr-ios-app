//
//  SendVCTextFields.swift
//  bittr
//
//  Created by Tom Melters on 9/15/25.
//

import UIKit
import LightningDevKit

extension SendViewController {
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Reset didTapAvailable boolean upon manual changes.
        if textField == self.amountTextField { self.didTapAvailable = false }
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Same logic as doneButtonTapped for return key
        if textField == self.toTextField {
            let enteredText = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check whether this is an invoice or LNURL.
            let lightningInvoice = enteredText.extractLightningInvoice()
            let lnurl = enteredText.extractLNURL()
            if lightningInvoice != nil || lnurl != nil {
                self.view.endEditing(true)
                self.onchainOrLightning = .lightning
                self.updateLabels()
                if let lnurl {
                    self.handleLNURL(code: lnurl)
                    return true
                } else if let lightningInvoice, lightningInvoice.bolt11Invoice()?.amountMilliSatoshis() != nil {
                    self.checkSendLightning()
                    return true
                }
            }
            
            // Otherwise, move to amount field
            self.amountTextField.becomeFirstResponder()
            return true
            
        } else if textField == self.amountTextField {
            self.nextButtonTapped(self.nextButton)
            return true
        }
        return false
    }
    
    func createAmountInputAccessoryView() -> UIView {
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        containerView.backgroundColor = Colors.getColor("whiteorblue3")
        
        let toolbar = UIToolbar(frame: containerView.bounds)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = .clear
        
        // Currency selection buttons
        let btcButton = UIBarButtonItem(title: "BTC", style: .plain, target: self, action: #selector(selectBTCCurrency))
        let satsButton = UIBarButtonItem(title: "Sats", style: .plain, target: self, action: #selector(selectSatsCurrency))
        let currencyButton = UIBarButtonItem(title: CacheStore.value(for: CacheKeys.currency) ?? "EUR", style: .plain, target: self, action: #selector(selectFiatCurrency))
        
        // Style the buttons with better contrast for dark mode
        // Force black color for better visibility in dark mode
        let buttonColor = UIColor.black
        btcButton.tintColor = buttonColor
        satsButton.tintColor = buttonColor
        currencyButton.tintColor = buttonColor
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: Language.getWord(withID: "done"), style: .done, target: self, action: #selector(doneButtonTapped))
        doneButton.tintColor = buttonColor
        
        toolbar.items = [btcButton, satsButton, currencyButton, flexSpace, doneButton]
        
        containerView.addSubview(toolbar)
        
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: containerView.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
}
