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
        self.titleAmount.text = Language.getWord(withID: "amount")
        self.titleType.text = Language.getWord(withID: "type")
        self.titleSwapId.text = Language.getWord(withID: "swapid")
        self.titleSwapStatus.text = Language.getWord(withID: "swapstatus")
        self.titleFees.text = Language.getWord(withID: "feespaid")
        self.titleConfirmations.text = Language.getWord(withID: "confirmations")
        self.titleDescription.text = Language.getWord(withID: "description")
        self.titleCurrentValue.text = Language.getWord(withID: "currentvalue")
        self.titlePurchaseValue.text = Language.getWord(withID: "purchasevalue")
        self.titleProfit.text = Language.getWord(withID: "profit")
        self.titleNote.text = Language.getWord(withID: "note")
        self.titleAddANote.text = Language.getWord(withID: "addanote")
        
    }
    
    func changeColors() {
        
        // Card
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue1")
        
        // Date
        self.labelDate.textColor = Colors.getColor("blackorwhite")
        
        // Amount
        self.cardAmount.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelAmount.textColor = Colors.getColor("blackorwhite")
        
        // Type
        self.cardType.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelType.textColor = Colors.getColor("blackorwhite")
        self.typeBoltImage.tintColor = Colors.getColor("blackorwhite")
        
        // Swap ID and status
        self.cardSwapId.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelSwapId.textColor = Colors.getColor("blackorwhite")
        self.labelSwapStatus.textColor = Colors.getColor("blackorwhite")
        self.swapArrowImage.tintColor = Colors.getColor("blackorwhite")
        
        // Fees
        self.cardFees.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelFees.textColor = Colors.getColor("blackorwhite")
        self.feesQuestionImage.tintColor = Colors.getColor("blackorwhite")
        
        // Confirmations
        self.cardConfirmations.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelConfirmations.textColor = Colors.getColor("blackorwhite")
        
        // Description
        self.cardDescription.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelDescription.textColor = Colors.getColor("blackorwhite")
        
        // IDs
        self.cardTopId.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelTopId.textColor = Colors.getColor("blackorwhite")
        self.labelBottomId.textColor = Colors.getColor("blackorwhite")
        self.urlImageTopId.tintColor = Colors.getColor("blackorwhite")
        self.urlImageBottomId.tintColor = Colors.getColor("blackorwhite")
        
        // Value
        self.cardValue.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelCurrentValue.textColor = Colors.getColor("blackorwhite")
        self.labelPurchaseValue.textColor = Colors.getColor("blackorwhite")
        
        // Note
        self.cardNote.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelNote.textColor = Colors.getColor("blackorwhite")
        
        // Add a note
        self.titleAddANote.textColor = Colors.getColor("blackorwhite")
        self.imageAddANote.tintColor = Colors.getColor("blackorwhite")
    }
}
