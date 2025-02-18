//
//  TransactionVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension TransactionViewController {
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "transaction")
        self.amountTitle.text = Language.getWord(withID: "amount")
        self.typeTitle.text = Language.getWord(withID: "type")
        self.idTitle.text = Language.getWord(withID: "id")
        self.confirmationsTitle.text = Language.getWord(withID: "confirmations")
        self.feesTitle.text = Language.getWord(withID: "feespaid")
        self.descriptionTitle.text = Language.getWord(withID: "description")
        self.valueNowTitle.text = Language.getWord(withID: "currentvalue")
        self.valueThenTitle.text = Language.getWord(withID: "purchasevalue")
        self.profitTitle.text = Language.getWord(withID: "profit")
        self.noteTitle.text = Language.getWord(withID: "addanote")
        
    }
}
