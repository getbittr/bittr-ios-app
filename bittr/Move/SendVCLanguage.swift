//
//  SendVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension SendViewController {
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "sendbitcoin")
        self.topLabel.text = Language.getWord(withID: "sendtoplabel")
        self.toLabel.text = Language.getWord(withID: "address")
        self.toTextField.placeholder = Language.getWord(withID: "enteraddress")
        self.amountLabel.text = Language.getWord(withID: "amount")
        self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.amountTextField.placeholder = Language.getWord(withID: "enteramount")
        self.nextLabel.text = Language.getWord(withID: "next")
        self.confirmHeaderLabel.text = Language.getWord(withID: "confirmtransaction")
        self.confirmTopLabel.text = Language.getWord(withID: "checkdetails")
        self.labelAddress.text = Language.getWord(withID: "address")
        self.labelAmount.text = Language.getWord(withID: "amount")
        self.feesTopLabel.text = Language.getWord(withID: "feerate")
        self.labelEdit.text = "<   " + Language.getWord(withID: "edit")
        self.sendLabel.text = Language.getWord(withID: "send")
        
    }
}
