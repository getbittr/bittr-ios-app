//
//  SendSwitch.swift
//  bittr
//
//  Created by Tom Melters on 02/07/2024.
//

import UIKit

extension SendViewController {
    
    func resetFields() {
        self.invoiceLabel.text = nil
        self.toTextFieldHeight.constant = 0
        self.toTextField.text = nil
        self.amountTextField.text = nil
        self.toTextFieldTop.constant = 5
        self.invoiceLabelTop.constant = 10
    }
    
    func hideScannerView(forView:String) {
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }
        
        self.scannerView.alpha = 0
        self.toLabel.alpha = 1
        self.toView.alpha = 1
        self.pasteButton.alpha = 1
        self.availableButton.alpha = 1
        self.nextLabel.text = "Next"
        self.setSendAllLabel(forView: forView)
        self.availableAmount.alpha = 1
        
        if forView == "onchain" {
            self.regularView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.instantView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.topLabel.text = "Send bitcoin from your bitcoin wallet to another bitcoin wallet. Scan a QR code or input manually."
            self.toLabel.text = "Address"
            self.toTextField.placeholder = "Enter address"
        } else {
            self.regularView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.instantView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.topLabel.text = "Send bitcoin from your bitcoin lightning wallet to another bitcoin lightning wallet."
            self.toLabel.text = "Invoice"
            self.toTextField.placeholder = "Enter invoice"
        }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            if forView == "onchain" {
                self.amountView.alpha = 1
                self.amountLabel.alpha = 1
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
            } else {
                self.amountView.alpha = 0
                self.amountLabel.alpha = 0
                self.availableAmountTop.constant = -75
                self.availableButtonTop.constant = -85
                self.availableAmountCenterX.constant = -10
                self.questionCircle.alpha = 1
            }
            
            NSLayoutConstraint.deactivate([self.nextViewTop])
            self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
            NSLayoutConstraint.activate([self.nextViewTop])
            
            self.view.layoutIfNeeded()
        }
    }
}
