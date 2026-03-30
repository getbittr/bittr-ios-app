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
            
            self.viewRegular.layer.shadowOpacity = 0.1
            self.viewInstant.layer.shadowOpacity = 0
            self.viewRegular.backgroundColor = Colors.getColor("whiteorblue3")
            self.viewInstant.backgroundColor = Colors.getColor("white0.7orblue1")
        } else {
            self.toLabel.text = Language.getWord(withID: "invoiceandamount")
            self.toTextField.placeholder = Language.getWord(withID: "enterinvoice")
            
            self.viewRegular.layer.shadowOpacity = 0
            self.viewInstant.layer.shadowOpacity = 0.1
            self.viewRegular.backgroundColor = Colors.getColor("white0.7orblue1")
            self.viewInstant.backgroundColor = Colors.getColor("whiteorblue3")
        }
    }
}
