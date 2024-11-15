//
//  SendSwitch.swift
//  bittr
//
//  Created by Tom Melters on 02/07/2024.
//

import UIKit

extension SendViewController {
    
    func resetFields() {
        self.toTextField.text = nil
        self.amountTextField.text = nil
    }
    
    func hideScannerView(forView:String) {
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }
        
        self.scannerView.alpha = 0
        self.addressStack.alpha = 1
        self.toLabel.alpha = 1
        self.toView.alpha = 1
        self.pasteButton.alpha = 1
        self.availableButton.alpha = 1
        self.nextLabel.text = Language.getWord(withID: "next")
        self.setSendAllLabel(forView: forView)
        self.availableAmount.alpha = 1
        
        if forView == "onchain" {
            self.regularView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.instantView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.topLabel.text = Language.getWord(withID: "sendtoplabel")
            self.toLabel.text = Language.getWord(withID: "address")
            self.toTextField.placeholder = Language.getWord(withID: "enteraddress")
        } else {
            self.regularView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.instantView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.topLabel.text = Language.getWord(withID: "sendtoplabellightning")
            self.toLabel.text = Language.getWord(withID: "invoice")
            self.toTextField.placeholder = Language.getWord(withID: "enterinvoice")
        }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            if forView == "onchain" {
                self.amountStack.alpha = 1
                self.amountLabel.alpha = 1
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
            } else {
                self.amountStack.alpha = 0
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
