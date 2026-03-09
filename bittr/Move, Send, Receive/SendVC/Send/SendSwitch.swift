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
    
    func updateLabels() {
        
        // Update available amount
        self.setSendAllLabel()
        
        if self.onchainOrLightning == .onchain {
            self.toLabel.text = Language.getWord(withID: "addressandamount")
            self.toTextField.placeholder = Language.getWord(withID: "enteraddress")
        } else {
            self.toLabel.text = Language.getWord(withID: "invoiceandamount")
            self.toTextField.placeholder = Language.getWord(withID: "enterinvoice")
        }
        
        var leadingConstraint = self.labelRegular
        var leadingConstant:CGFloat = -15
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            if self.onchainOrLightning == .onchain {
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
                self.labelRegularLeading.constant = 20
                self.labelInstantTrailing.constant = 15
                leadingConstraint = self.labelRegular
                leadingConstant = -15
            } else {
                self.availableAmountCenterX.constant = -10
                self.questionCircle.alpha = 1
                self.labelRegularLeading.constant = 15
                self.labelInstantTrailing.constant = 20
                leadingConstraint = self.labelInstant
                leadingConstant = -30
            }
            
            NSLayoutConstraint.deactivate([self.selectionLeading, self.selectionTrailing])
            self.selectionLeading = NSLayoutConstraint(item: self.switchSelectionView, attribute: .leading, relatedBy: .equal, toItem: leadingConstraint, attribute: .leading, multiplier: 1, constant: leadingConstant)
            self.selectionTrailing = NSLayoutConstraint(item: self.switchSelectionView, attribute: .trailing, relatedBy: .equal, toItem: leadingConstraint, attribute: .trailing, multiplier: 1, constant: 15)
            NSLayoutConstraint.activate([self.selectionLeading, self.selectionTrailing])
            
            self.view.layoutIfNeeded()
        }
    }
}
