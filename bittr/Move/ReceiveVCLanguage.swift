//
//  ReceiveVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 10/10/2024.
//

import UIKit

extension ReceiveViewController {
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "receivebitcoin")
        self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.subtitleRegular.text = Language.getWord(withID: "thisisanaddress")
        self.subtitleInstant.text = Language.getWord(withID: "createaninvoice")
        self.amountLabel.text = Language.getWord(withID: "amountinsatoshis")
        self.descriptionLabel.text = Language.getWord(withID: "description")
        self.amountTextField.placeholder = Language.getWord(withID: "enteramount")
        self.descriptionTextField.placeholder = Language.getWord(withID: "enterdescription")
        self.createInvoiceLabel.text = Language.getWord(withID: "createinvoice")
        self.lnHeaderLabel.text = Language.getWord(withID: "lightninginvoice")
        self.lnConfirmationLabel.text = Language.getWord(withID: "thisisyourinvoice")
        self.lnDoneLabel.text = Language.getWord(withID: "done")
        
    }
}
