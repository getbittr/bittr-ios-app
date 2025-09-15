//
//  SendVCTextFields.swift
//  bittr
//
//  Created by Tom Melters on 9/15/25.
//

import UIKit
import LightningDevKit

extension SendViewController {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Same logic as doneButtonTapped for return key
        if textField == self.toTextField {
            // If it's a lightning invoice with amount, go straight to confirmation
            if (textField.text ?? "").prefix(2) == "ln" {
                if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: textField.text!).getValue() {
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        // Invoice has amount, go straight to confirmation
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        self.amountTextField.text = "\(invoiceAmount)"
                        self.btcLabel.text = "Sats"
                        self.selectedCurrency = .satoshis
                        self.confirmLightningTransaction(lnurlinvoice: nil, sendVC: self, receiveVC: nil, lnurlNote: nil)
                        return true
                    }
                }
            } else if (textField.text ?? "").contains("@") {
                self.view.endEditing(true)
                self.onchainOrLightning = .lightning
                self.hideScannerView(forView: .lightning)
                self.handleLNURL(code: textField.text!, sendVC: self, receiveVC: nil)
                return true
            }
            
            // Otherwise, move to amount field
            self.amountTextField.becomeFirstResponder()
            return true
        } else if textField == amountTextField {
            // Move to next step
            self.nextButtonTapped(nextButton)
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
        let currencyButton = UIBarButtonItem(title: UserDefaults.standard.value(forKey: "currency") as? String ?? "EUR", style: .plain, target: self, action: #selector(selectFiatCurrency))
        
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
